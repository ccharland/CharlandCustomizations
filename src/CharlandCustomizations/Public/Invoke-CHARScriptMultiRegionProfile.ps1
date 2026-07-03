function Invoke-CHARScriptMultiRegionProfile {
  <#
.SYNOPSIS
    Invokes AWS commands across multiple AWS Profiles and regions to gather data.

.DESCRIPTION
    Executes a ScriptBlock against multiple AWS accounts (via profiles) and regions,
    collecting the output from each invocation. Each output object is optionally
    enriched with the AccountId and Region it came from, making it easy to aggregate
    and compare data across your AWS estate.

    Designed for read-only data gathering (e.g., Get-EC2SecurityGroup, Get-S3Bucket,
    Get-IAMUser). The ScriptBlock runs with AWS environment variables
    (AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY/AWS_SESSION_TOKEN or AWS_PROFILE, plus
    AWS_DEFAULT_REGION) set for each account/region iteration.

    The function injects $Region, $ProfileName, and $PSDefaultParameterValues into
    the ScriptBlock scope automatically. This means any AWS cmdlet or wrapper function
    accepting -Region or -ProfileName picks up the current iteration values without
    requiring the user to pass them explicitly.

    Error Handling:
    - If a ScriptBlock throws (e.g., SCP denial, access denied, service unavailable),
      the error is caught and a result object with the Error property populated is
      emitted for that profile/region combination. Processing continues with the
      next region or profile.
    - If a ScriptBlock returns no data, an empty tracking object is emitted so
      every profile/region combination produces at least one output row.
    - Every output object includes an Error property (null on success) so that
      Format-Table and other formatters display columns consistently regardless
      of whether some iterations failed.
    - Authentication failures (invalid profile credentials) skip the entire profile
      with a warning and continue processing subsequent profiles.

    Use -OutputSubTemplate to emit a starter script template that calls this function,
    which you can customize for your specific data-gathering scenario.

.PARAMETER ProfileName
    One or more AWS profile names to iterate over. Accepts pipeline input.
    If not specified, uses the current default AWS profile.

.PARAMETER Region
    One or more AWS regions to query per profile. Defaults to the current default region.

.PARAMETER ScriptBlock
    The ScriptBlock to execute for each account/region combination.
    $Region and $ProfileName variables are automatically available inside the block.
    $PSDefaultParameterValues is injected so cmdlets with -Region/-ProfileName parameters
    receive the correct values without explicit passing.

.PARAMETER IncludeAccountId
    When specified, adds an AccountId property to each output object.

.PARAMETER IncludeRegion
    When specified, adds a Region property to each output object.

.PARAMETER IncludeProfileName
    When specified, adds a ProfileName property to each output object.

.PARAMETER NoProgress
    Suppress progress bar output.

.PARAMETER OutputSubTemplate
    When specified, outputs a string containing a ScriptBlock function stub with CmdletBinding,
    param block, and begin/process/end structure. Assign the output to a variable and
    convert it to a ScriptBlock (e.g. `[scriptblock]::Create($output)`) before passing to -ScriptBlock.

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
    Invoke-CHARScriptMultiRegionProfile -ProfileName 'dev','prod' -Region 'us-east-1' `
        -ScriptBlock { Get-STSCallerIdentity } -IncludeRegion -IncludeProfileName

    Calls Get-STSCallerIdentity for each profile in us-east-1, adding Region and
    ProfileName columns to the output.

.EXAMPLE
    Invoke-CHARScriptMultiRegionProfile -ProfileName 'prod' `
        -Region 'us-east-1','eu-west-1','ap-southeast-1' `
        -ScriptBlock { Get-LMFunctionList | Select-Object FunctionName, Runtime } `
        -IncludeRegion -IncludeAccountId | Format-Table

    Lists Lambda functions across three regions. Regions blocked by SCP will show
    an Error value instead of function data, while allowed regions return normally.

.EXAMPLE
    Invoke-CHARScriptMultiRegionProfile -ProfileName 'dev','staging','prod' `
        -Region 'us-east-1' `
        -ScriptBlock { Get-CHARDeprecatedLMFunctionList } `
        -IncludeProfileName -IncludeAccountId | Where-Object { -not $_.Error }

    Calls a wrapper function across three accounts. The wrapper receives -Region
    and -ProfileName automatically via $PSDefaultParameterValues injection. Results
    are filtered to exclude any accounts where the call failed.

.EXAMPLE
    $results = Invoke-CHARScriptMultiRegionProfile -ProfileName 'prod' `
        -Region 'us-east-1','eu-west-1' `
        -ScriptBlock { Get-S3Bucket } `
        -IncludeRegion -IncludeProfileName

    $results | Where-Object { $_.Error } | Format-Table Region, ProfileName, Error
    $results | Where-Object { -not $_.Error } | Format-Table BucketName, Region

    Separates successful results from failures for independent processing.
    Regions denied by SCP produce rows with Error populated; allowed regions
    produce rows with bucket data and Error set to null.

.EXAMPLE
    Invoke-CHARScriptMultiRegionProfile -OutputSubTemplate

    Outputs a ScriptBlock function stub with param/begin/process/end blocks
    that you can assign to a variable and pass to -ScriptBlock.

.NOTES
    Generated by Kiro using Auto, reviewed by ccharland
#>
  [CmdletBinding(DefaultParameterSetName = 'Execute')]
  # Suppress: StoredAWSCredentials is a well-known AWS.Tools global variable used to detect the current session profile
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '',
    Justification = 'AWS.Tools uses global:StoredAWSCredentials and global:StoredAWSRegion for session state; must read/write them to set context for ScriptBlock execution')]
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUsePSCredentialType', '',
    Justification = 'Credential parameter accepts an AWSCredentials object from AWS.Tools, not a PSCredential')]
  param(
    [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName, ParameterSetName = 'Execute')]
    [string[]]$ProfileName,

    [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName, ParameterSetName = 'Execute')]
    [string[]]$Region,

    [Parameter(Mandatory, ParameterSetName = 'Execute')]
    [scriptblock]$ScriptBlock,

    [Parameter(ParameterSetName = 'Execute')]
    [switch]$IncludeAccountId,

    [Parameter(ParameterSetName = 'Execute')]
    [switch]$IncludeRegion,

    [Parameter(ParameterSetName = 'Execute')]
    [switch]$IncludeProfileName,

    [Parameter(ParameterSetName = 'Execute')]
    [switch]$NoProgress,

    [Parameter(Mandatory, ParameterSetName = 'SubTemplate')]
    [switch]$OutputSubTemplate,

    # AWS common parameters (credential passthrough for Get-STSCallerIdentity validation)
    [Parameter(ParameterSetName = 'Execute')]
    [string]$AccessKey,

    [Parameter(ParameterSetName = 'Execute')]
    [string]$SecretKey,

    [Parameter(ParameterSetName = 'Execute')]
    [string]$SessionToken,

    [Parameter(ParameterSetName = 'Execute')]
    [SecureString] $Credential,

    [Parameter(ParameterSetName = 'Execute')]
    [string]$ProfileLocation,

    [Parameter(ParameterSetName = 'Execute')]
    [string]$EndpointUrl
  )

  begin {
    # When -OutputSubTemplate is specified, emit a function stub for use as a ScriptBlock
    if ($OutputSubTemplate) {
      Write-Verbose "Emitting sub-template for ScriptBlock"
      $subTemplate = @'
{
    <#
    .SYNOPSIS
        ScriptBlock stub for Invoke-CHARScriptMultiRegionProfile.

    .DESCRIPTION
        This function runs once per profile/region iteration. AWS context
        (credentials and region) is already set by the caller. Add your
        data-gathering logic in the process block.

    .NOTES
        Generated by Invoke-CHARScriptMultiRegionProfile -OutputSubTemplate
    #>
    [CmdletBinding()]
    param(
        # Add parameters your ScriptBlock needs here, e.g.:
        # [string]$ResourceTag = 'Environment'
    )

    begin {
        # One-time setup per iteration (initialize collections, set filters, etc.)
        $results = [System.Collections.Generic.List[object]]::new()
    }

    process {
        # Data-gathering logic — AWS credentials and region are already in scope.
        # Replace the example below with your cmdlet(s):
        # $instances = Get-EC2Instance
        # $buckets = Get-S3Bucket
        $identity = Get-STSCallerIdentity
        $results.Add($identity)
    }

    end {
        # Return collected results to the pipeline
        $results
    }
}
'@
      Write-Output $subTemplate
      return
    }
    Write-Debug "Start Begin"
    # Build base AWS splat from credential parameters then remove ProfileName/Region
    # since those are arrays used for iteration in this function, not single-value
    # credential params to pass to AWS cmdlets directly.
    $awsParams = New-AWSParamSplat -BoundParameters $PSBoundParameters
    $awsParams.Remove('ProfileName') | Out-Null
    $awsParams.Remove('Region') | Out-Null
    if (-not $ProfileName) {
      # Try the shell's current stored credential profile name
      Write-Debug "ProfileName not specified"
      $currentProfile = $null
      if ($StoredAWSCredentials) {
        Write-Debug "Found StoredAWSCredentials: $StoredAWSCredentials"
        $currentProfile = $StoredAWSCredentials
      }
      if (-not $currentProfile) {
        Write-Debug "Checking for default profile"
        # Fall back: check if there's a default profile in the credential store
        $defaultProfile = (Get-AWSCredential -ListProfileDetail |
          Where-Object { $_.ProfileName -eq 'default' } |
          Select-Object -First 1 -ExpandProperty ProfileName)
        if ($defaultProfile) {
          Write-Debug "Default profile found: $defaultProfile"
          $currentProfile = $defaultProfile
        }
      }
      if ($currentProfile) {
        Write-Verbose "Using current profile: $currentProfile"
        $ProfileName = @($currentProfile)
      }
      else {
        Write-Error "No ProfileName specified and no current AWS profile found. Use -ProfileName or Set-AWSCredential."
        return
      }

    }
  Write-Debug "aRegion checks : $Region"

    if ($Region -eq "") {
      Write-Debug "Region not specified"
      $defaultRegion = (Get-DefaultAWSRegion).Region
      if ($defaultRegion) {
        Write-Verbose "Using current/default region: $defaultRegion"
        $Region = @($defaultRegion)
      }
      else {
        Write-Error "No region specified and no default AWS region set. Use -Region or Set-DefaultAWSRegion."
        return
      }
    }
    else {
      Write-Verbose "region specified: $Region"
    }
    $profileCount = 0
    $regionTotal = $Region.Count
    Write-Verbose "Executing against $($ProfileName.Count) profile(s) across $regionTotal region(s) each"
    # Match common AWS.Tools missing-region failures:
    # - "No region..." text
    # - "RegionEndpoint" / "ServiceURL" configuration errors
    # - Explicit "DefaultAWSRegion is not configured"/"no default region" failures.
    $missingRegionPatternAlternatives = @(
      'no\s+region(?:\s*endpoint)?\b'
      '\bregionendpoint\b'
      'serviceurl\s+configured'
      'defaultawsregion.*(not\s+configured|not\s+set)'
      'no\s+default\s+aws\s+region'
      'region.*not.*(configured|specified|set)'
    )
    $missingRegionPattern = '(?i)(' + ($missingRegionPatternAlternatives -join '|') + ')'
    Write-Debug "end begin"
}

  process {
    foreach ($prof in $ProfileName) {
      Write-Verbose "Processing profile: $prof"
      $profileCount++
      if (-not $NoProgress) {
        Write-Progress -Id 1 -Activity "Processing AWS Profiles" `
          -Status "Profile: $prof (#$profileCount)" `
          -CurrentOperation "Authenticating..."
      }

      # Validate credentials before doing any work for this profile
      # Override ProfileName per iteration; base awsParams carries other credential params
      # Use the first region from the list for validation since Region was removed from awsParams
      $iterParams = $awsParams.Clone()
      $iterParams['ProfileName'] = $prof
      if ($Region -and $Region.Count -gt 0) {
        $iterParams['Region'] = $Region[0]
      }
      else {
        Write-Error "Region array is empty or null for profile '$prof'"
        continue
      }
      Write-Verbose "Validating profile '$prof' with region '$($iterParams.Region)'"
      try {
        $identity = Get-STSCallerIdentity @iterParams -ErrorAction Stop
        $accountId = $identity.Account
        Write-Verbose "Profile '$prof' resolved to AccountId: $accountId"
      }
      catch {
        if ($_.Exception.Message -match $missingRegionPattern) {
          $missingRegionError = [System.Management.Automation.ErrorRecord]::new(
            $_.Exception,
            'InvokeCHARScriptMultiRegionProfile.MissingRegion',
            [System.Management.Automation.ErrorCategory]::InvalidOperation,
            $prof
          )
          $PSCmdlet.ThrowTerminatingError($missingRegionError)
        }
        Write-Warning "Skipping profile '${prof}': unable to authenticate - $_"
        continue
      }

      # Resolve the profile into concrete AccessKey/SecretKey/SessionToken.
      # For profiles stored in the credentials file (e.g., from Update-CHARSSOCredentialList),
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
        # Save current AWS session state
        $origStoredRegion = $global:StoredAWSRegion
        $origStoredCreds = $global:StoredAWSCredentials
        $origEnvRegion = $env:AWS_DEFAULT_REGION
        $origEnvAccessKey = $env:AWS_ACCESS_KEY_ID
        $origEnvSecretKey = $env:AWS_SECRET_ACCESS_KEY
        $origEnvSessionToken = $env:AWS_SESSION_TOKEN

        try {
          write-verbose "saving state"

          if ($resolvedCreds -and $resolvedCreds.AccessKey) {
            # Use Set-AWSCredential to properly register credentials in the SDK session cache
            $setCmdParams = @{
              AccessKey = $resolvedCreds.AccessKey
              SecretKey = $resolvedCreds.SecretKey
            }
            if ($resolvedCreds.Token) {
              $setCmdParams['SessionToken'] = $resolvedCreds.Token
            }
            Set-AWSCredential @setCmdParams

            # Also set environment variables so the SDK resolves region/creds
            # consistently even when module-level globals are not picked up
            $env:AWS_ACCESS_KEY_ID = $resolvedCreds.AccessKey
            $env:AWS_SECRET_ACCESS_KEY = $resolvedCreds.SecretKey
            if ($resolvedCreds.Token) {
              $env:AWS_SESSION_TOKEN = $resolvedCreds.Token
            }
            else {
              $env:AWS_SESSION_TOKEN = $null
            }
          }
          else {
            Set-AWSCredential -ProfileName $prof
          }
          Set-DefaultAWSRegion -Region $r
          # Set env var as a fallback for SDK region resolution
          $env:AWS_DEFAULT_REGION = $r

          Write-Verbose "Invoking scriptblock for Profile='$prof', Region='$r'"
          # Force non-terminating errors (e.g., SCP access denied) to become
          # terminating so they hit the catch block and don't return results
          # from a fallback region
          $origErrorAction = $ErrorActionPreference
          $ErrorActionPreference = 'Stop'
          try {
            $results = $NULL
            write-verbose "Try to invoke script: Results before script: $results"
            Write-Verbose "Region:  $r"
            # $results = & $ScriptBlock
            # $results = & $ScriptBlock -Region $r -ProfileName $prof
            # Inject Region and ProfileName as automatic variables so simple
            # ScriptBlocks can reference them directly (e.g. -Region $Region).
            # Also inject $PSDefaultParameterValues so any cmdlet or wrapper
            # accepting -Region/-ProfileName picks them up implicitly during
            # parameter binding — this avoids requiring users to thread the
            # values through every wrapper call.
            $iterationDefaults = @{
              '*:Region'      = $r
              '*:ProfileName' = $prof
            }
            $vars = [System.Collections.Generic.List[psvariable]]::new()
            $vars.Add([psvariable]::new('Region', $r))
            $vars.Add([psvariable]::new('ProfileName', $prof))
            $vars.Add([psvariable]::new('PSDefaultParameterValues', $iterationDefaults))
            $results = @($ScriptBlock.InvokeWithContext($null, $vars))

            if ($results.Count -eq 0) {
              Write-Verbose "No results returned for Profile='$prof', Region='$r'"
              Write-Verbose "emit a single item for tracking"
              $results = [PSCustomObject]@{}
            }
          }
          catch {
            # script failed to execute, record error and continue
            Write-Warning "ScriptBlock failed for Profile='${prof}', Region='${r}': $_"
            $results= [PSCustomObject]@{
              Error = $_.Exception.Message
           }
          }
          finally {
            write-verbose "finally block"
            write-verbose "Results: $results"
            $ErrorActionPreference = $origErrorAction
          }
          # Results should NEVER be empty
          if ($results) {
            Write-Verbose "Results for Profile='$prof', Region='$r'"
            write-verbose "results:  $results"
            foreach ($item in $results) {
              Write-Debug "Returning result for Profile='$prof', Region='$r': $item"
              $props = [ordered]@{}

              # If the item is a simple type (string, number, etc.), wrap it so enrichment works
              if ($item -is [string]) {
                Write-Debug "item: string"
                $props['Value'] = $item
              }
              elseif ($item.GetType().IsPrimitive -or $item -is [decimal]) {
                Write-Debug "item: primitive"
                $props['Value'] = $item
              }
              else {
                write-debug "item: psobject"
                foreach ($p in $item.PSObject.Properties) {
                  $props[$p.Name] = $p.Value
                }
              }
              # if error not present, insert a placeholder for it
              if (-not $props.Contains('Error')) { $props['Error'] = $null }
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
            throw "Error- Results empty, aborting"
          }
        }
        catch {
          Write-Warning "Error executing ScriptBlock for Profile='${prof}', Region='${r}': $_"
        }
        finally {
          # Restore original AWS session state
          if ($origStoredCreds) {
            Set-AWSCredential -ProfileName $origStoredCreds
          }
          else {
            Clear-AWSCredential
          }
          if ($origStoredRegion) {
            Set-DefaultAWSRegion -Region $origStoredRegion
          }
          else {
            Clear-DefaultAWSRegion
          }
          # Restore environment variables
          $env:AWS_DEFAULT_REGION = $origEnvRegion
          $env:AWS_ACCESS_KEY_ID = $origEnvAccessKey
          $env:AWS_SECRET_ACCESS_KEY = $origEnvSecretKey
          $env:AWS_SESSION_TOKEN = $origEnvSessionToken
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
