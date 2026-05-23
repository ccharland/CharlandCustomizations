function Invoke-ScriptMultiAccountRegion {
  <#
.SYNOPSIS
    Invokes AWS commands across multiple accounts and regions to gather data.

.DESCRIPTION
    Executes a ScriptBlock against multiple AWS accounts (via profiles) and regions,
    collecting the output from each invocation. Each output object is optionally
    enriched with the AccountId and Region it came from, making it easy to aggregate
    and compare data across your AWS estate.

    Designed for read-only data gathering (e.g., Get-EC2SecurityGroup, Get-S3Bucket,
    Get-IAMUser). The ScriptBlock receives -ProfileName and -Region via
    PSDefaultParameterValues so AWS cmdlets inside the block automatically use them.

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

.EXAMPLE
    Invoke-ScriptMultiAccountRegion -ProfileName 'dev','prod' -Region 'us-east-1' `
        -ScriptBlock { Get-STSCallerIdentity } -IncludeRegion -IncludeProfileName

.EXAMPLE
    Get-AWSCredential -ListProfileDetail | Select-Object -ExpandProperty ProfileName |
        Invoke-ScriptMultiAccountRegion -Region 'us-east-1' `
            -ScriptBlock { Get-S3Bucket } -IncludeAccountId -IncludeProfileName
#>
  [CmdletBinding()]
  param(
    [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
    [string[]]$ProfileName,

    [Parameter()]
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
    [int]$ThrottleLimit = 0
  )

  begin {
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
      Write-Progress -Id 1 -Activity "Processing AWS Profiles" `
        -Status "Profile: $prof (#$profileCount)" `
        -CurrentOperation "Authenticating..."

      # Validate credentials before doing any work for this profile
      try {
        $identity = Get-STSCallerIdentity -ProfileName $prof -ErrorAction Stop
        $accountId = $identity.Account
        Write-Verbose "Profile '$prof' resolved to AccountId: $accountId"
      }
      catch {
        Write-Warning "Skipping profile '${prof}': unable to authenticate - $_"
        continue
      }

      $regionIndex = 0
      foreach ($r in $Region) {
        $regionIndex++
        $regionPercent = [int](($regionIndex / $regionTotal) * 100)
        Write-Progress -Id 2 -ParentId 1 -Activity "Processing Regions for '$prof'" `
          -Status "Region: $r ($regionIndex of $regionTotal)" `
          -PercentComplete $regionPercent

        Write-Verbose "Executing against Profile='$prof', Region='$r'"

        try {
          $originalDefaults = $PSDefaultParameterValues.Clone()
          $PSDefaultParameterValues['*:ProfileName'] = $prof
          $PSDefaultParameterValues['*:Region'] = $r

          # Module-scoped functions cannot modify the caller's $PSDefaultParameterValues.
          # Use [scriptblock]::Create() to build an unbound scriptblock (not tied to any
          # module's session state) that sets $PSDefaultParameterValues and then invokes
          # the user's original ScriptBlock. Unbound scriptblocks execute in the global/
          # caller scope where AWS cmdlets will see the default parameter values.
          $invoker = [scriptblock]::Create(@"
            `$PSDefaultParameterValues['*:ProfileName'] = '$($prof -replace "'", "''")'
            `$PSDefaultParameterValues['*:Region'] = '$($r -replace "'", "''")'
            & `$args[0]
"@)
          $results = & $invoker $ScriptBlock

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
          # Restore module-scoped defaults
          $PSDefaultParameterValues.Clear()
          foreach ($key in $originalDefaults.Keys) {
            $PSDefaultParameterValues[$key] = $originalDefaults[$key]
          }
          # Clean up caller/global scope defaults set by the unbound invoker scriptblock
          $cleanup = [scriptblock]::Create(
            "`$PSDefaultParameterValues.Remove('*:ProfileName'); " +
            "`$PSDefaultParameterValues.Remove('*:Region')"
          )
          & $cleanup
        }

        if ($ThrottleLimit -gt 0) {
          Write-Verbose "Throttling: waiting $ThrottleLimit second(s)"
          Start-Sleep -Seconds $ThrottleLimit
        }
      }
      Write-Progress -Id 2 -ParentId 1 -Activity "Processing Regions for '$prof'" -Completed
    }
  }

  end {
    Write-Progress -Id 1 -Activity "Processing AWS Profiles" -Completed
  }
}
