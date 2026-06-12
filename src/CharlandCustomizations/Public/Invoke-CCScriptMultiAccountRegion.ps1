function Invoke-CCScriptMultiAccountRegion {
  <#
.SYNOPSIS
    Invokes AWS commands across multiple accounts and regions to gather data.

.DESCRIPTION
    Executes a ScriptBlock against multiple AWS accounts (via profiles) and regions,
    collecting the output from each invocation. Each output object is optionally
    enriched with the AccountId and Region it came from, making it easy to aggregate
    and compare data across your AWS estate.

    Designed for read-only data gathering (e.g., Get-EC2SecurityGroup, Get-S3Bucket,
    Get-IAMUser). The ScriptBlock runs with AWS environment variables
    (AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY/AWS_SESSION_TOKEN or AWS_PROFILE, plus
    AWS_DEFAULT_REGION) set for each account/region iteration.

.PARAMETER ProfileName
    One or more AWS profile names to iterate over. Accepts pipeline input.
    If not specified, uses the current default AWS profile.

.PARAMETER Region
    One or more AWS regions to query per profile. Defaults to the current default region.

.PARAMETER ScriptBlock
    The ScriptBlock to execute for each account/region combination.

.PARAMETER IncludeAccountId
    When specified, adds an AccountId property to each output object.

.PARAMETER IncludeRegion
    When specified, adds a Region property to each output object.

.PARAMETER IncludeProfileName
    When specified, adds a ProfileName property to each output object.

.PARAMETER ThrottleLimit
    Seconds to wait between calls to avoid throttling. Defaults to 0.

.PARAMETER NoProgress
    Suppress progress bar output.

.PARAMETER AccessKey
    AWS access key for explicit credentials. Optional.

.PARAMETER SecretKey
    AWS secret key for explicit credentials. Optional.

.PARAMETER SessionToken
    AWS session token for temporary credentials. Optional.

.PARAMETER Credential
    Pre-built AWS credential object. Optional.

.PARAMETER ProfileLocation
    Custom credential file path. Optional.

.PARAMETER EndpointUrl
    Custom AWS service endpoint URL. Optional.

.EXAMPLE
    Invoke-CCScriptMultiAccountRegion -ProfileName 'dev','prod' -Region 'us-east-1' `
        -ScriptBlock { Get-STSCallerIdentity } -IncludeRegion -IncludeProfileName

.EXAMPLE
    Get-AWSCredential -ListProfileDetail | Select-Object -ExpandProperty ProfileName |
        Invoke-CCScriptMultiAccountRegion -Region 'us-east-1' `
            -ScriptBlock { Get-S3Bucket } -IncludeAccountId -IncludeProfileName
#>
  [CmdletBinding()]
  param(
    [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
    [string[]]$ProfileName,

    [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
    [string[]]$Region,

    [Parameter(Mandatory)]
    [scriptblock]$ScriptBlock,

    [Parameter()]
    [switch]$IncludeAccountId,

    [Parameter()]
    [switch]$IncludeRegion,

    [Parameter()]
    [switch]$IncludeProfileName,

    [Parameter()]
    [ValidateRange(0, 60)]
    [int]$ThrottleLimit = 0,

    [Parameter()]
    [switch]$NoProgress,

    # AWS common parameters (credential passthrough for Get-STSCallerIdentity validation)
    [Parameter()]
    [string]$AccessKey,

    [Parameter()]
    [string]$SecretKey,

    [Parameter()]
    [string]$SessionToken,

    [Parameter()]
    [SecureString] $Credential,

    [Parameter()]
    [string]$ProfileLocation,

    [Parameter()]
    [string]$EndpointUrl
  )

  begin {
    # Build base AWS splat from credential parameters then remove ProfileName/Region
    # since those are arrays used for iteration in this function, not single-value
    # credential params to pass to AWS cmdlets directly.
    $awsParams = New-AWSParamSplat -BoundParameters $PSBoundParameters
    $awsParams.Remove('ProfileName') | Out-Null
    $awsParams.Remove('Region') | Out-Null
    if (-not $ProfileName) {
      # Try the shell's current stored credential profile name
      $currentProfile = $null
      if ($StoredAWSCredentials) {
        $currentProfile = $StoredAWSCredentials
      }
      if (-not $currentProfile) {
        # Fall back: check if there's a default profile in the credential store
        $defaultProfile = (Get-AWSCredential -ListProfileDetail |
          Where-Object { $_.ProfileName -eq 'default' } |
          Select-Object -First 1 -ExpandProperty ProfileName)
        if ($defaultProfile) {
          $currentProfile = $defaultProfile
        }
      }
      if ($currentProfile) {
        $ProfileName = @($currentProfile)
      }
      else {
        Write-Error "No ProfileName specified and no current AWS profile found. Use -ProfileName or Set-AWSCredential."
        return
      }
    }

    if (-not $Region) {
      $defaultRegion = (Get-DefaultAWSRegion).Region
      if ($defaultRegion) {
        $Region = @($defaultRegion)
      }
      else {
        Write-Error "No region specified and no default AWS region set. Use -Region or Set-DefaultAWSRegion."
        return
      }
    }
    $profileCount = 0
    $regionTotal = $Region.Count
  }

  process {
    foreach ($prof in $ProfileName) {
      $profileCount++
      if (-not $NoProgress) {
        Write-Progress -Id 1 -Activity "Processing AWS Profiles" `
          -Status "Profile: $prof (#$profileCount)" `
          -CurrentOperation "Authenticating..."
      }

      # Validate credentials before doing any work for this profile
      # Override ProfileName per iteration; base awsParams carries other credential params
      $iterParams = $awsParams.Clone()
      $iterParams['ProfileName'] = $prof
      try {
        $identity = Get-STSCallerIdentity @iterParams -ErrorAction Stop
        $accountId = $identity.Account
        Write-Verbose "Profile '$prof' resolved to AccountId: $accountId"
      }
      catch {
        Write-Warning "Skipping profile '${prof}': unable to authenticate - $_"
        continue
      }

      # Resolve the profile into concrete AccessKey/SecretKey/SessionToken.
      # For profiles stored in the credentials file (e.g., from Update-CCSSOCredentialList),
      # read the keys directly. This avoids SSO token re-resolution and SDK caching issues.
      $resolvedCreds = $null
      try {
        # Get-AWSCredential -ProfileName with the profile's location resolves correctly
        # because it reads directly from the ini file, not from the SSO token cache.
        $profileDetail = Get-AWSCredential -ListProfileDetail |
          Where-Object { $_.ProfileName -eq $prof } | Select-Object -First 1

        if ($profileDetail -and $profileDetail.ProfileLocation) {
          $credObj = Get-AWSCredential -ProfileName $prof -ProfileLocation $profileDetail.ProfileLocation
          if ($credObj -and $credObj.GetCredentials) {
            $resolvedCreds = $credObj.GetCredentials()
          }
        }

        if (-not $resolvedCreds) {
          # Fall back: try without explicit ProfileLocation
          $credObj = Get-AWSCredential -ProfileName $prof
          if ($credObj -and $credObj.GetCredentials) {
            $resolvedCreds = $credObj.GetCredentials()
          }
        }
      }
      catch {
        Write-Verbose "Could not resolve credentials for profile '$prof': $_"
      }

      $regionIndex = 0
      foreach ($r in $Region) {
        $regionIndex++
        $regionPercent = [int](($regionIndex / $regionTotal) * 100)
        if (-not $NoProgress) {
          Write-Progress -Id 2 -ParentId 1 -Activity "Processing Regions for '$prof'" `
            -Status "Region: $r ($regionIndex of $regionTotal)" `
            -PercentComplete $regionPercent
        }

        Write-Verbose "Executing against Profile='$prof', Region='$r'"

        try {
          # Save current environment variables
          $origAK = $env:AWS_ACCESS_KEY_ID
          $origSK = $env:AWS_SECRET_ACCESS_KEY
          $origST = $env:AWS_SESSION_TOKEN
          $origRegion = $env:AWS_DEFAULT_REGION
          $origProfile = $env:AWS_PROFILE

          if ($resolvedCreds -and $resolvedCreds.AccessKey) {
            # Set environment variables that the AWS SDK always respects
            $env:AWS_ACCESS_KEY_ID = $resolvedCreds.AccessKey
            $env:AWS_SECRET_ACCESS_KEY = $resolvedCreds.SecretKey
            $env:AWS_SESSION_TOKEN = $resolvedCreds.Token
            $env:AWS_DEFAULT_REGION = $r
            $env:AWS_PROFILE = $null
          }
          else {
            $env:AWS_ACCESS_KEY_ID = $null
            $env:AWS_SECRET_ACCESS_KEY = $null
            $env:AWS_SESSION_TOKEN = $null
            $env:AWS_DEFAULT_REGION = $r
            $env:AWS_PROFILE = $prof
          }

          Write-Verbose "Invoking scriptblock for Profile='$prof', Region='$r'"
          $results = & $ScriptBlock

          if ($results) {
            foreach ($item in $results) {
              $props = [ordered]@{}
              foreach ($p in $item.PSObject.Properties) {
                $props[$p.Name] = $p.Value
              }

              if ($IncludeAccountId) { $props['AccountId'] = $accountId }
              if ($IncludeRegion) { $props['Region'] = $r }
              if ($IncludeProfileName) { $props['ProfileName'] = $prof }

              $enriched = [PSCustomObject]$props

              $propNames = [string[]]$props.Keys
              $propSet = [System.Management.Automation.PSPropertySet]::new(
                'DefaultDisplayPropertySet', $propNames
              )
              $enriched | Add-Member -MemberType MemberSet -Name PSStandardMembers -Value $propSet -Force

              $enriched
            }
          }
          else {
            Write-Verbose "No results returned for Profile='$prof', Region='$r'"
          }
        }
        catch {
          Write-Warning "Error executing ScriptBlock for Profile='${prof}', Region='${r}': $_"
        }
        finally {
          # Restore original environment variables
          $env:AWS_ACCESS_KEY_ID = $origAK
          $env:AWS_SECRET_ACCESS_KEY = $origSK
          $env:AWS_SESSION_TOKEN = $origST
          $env:AWS_DEFAULT_REGION = $origRegion
          $env:AWS_PROFILE = $origProfile
        }

        if ($ThrottleLimit -gt 0) {
          Write-Verbose "Throttling: waiting $ThrottleLimit second(s)"
          Start-Sleep -Seconds $ThrottleLimit
        }
      }
      if (-not $NoProgress) {
        Write-Progress -Id 2 -ParentId 1 -Activity "Processing Regions for '$prof'" -Completed
      }
    }
  }

  end {
    if (-not $NoProgress) {
      Write-Progress -Id 1 -Activity "Processing AWS Profiles" -Completed
    }
  }
}