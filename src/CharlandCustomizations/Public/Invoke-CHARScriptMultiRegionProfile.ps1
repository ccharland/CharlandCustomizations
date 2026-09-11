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

    When no -ProfileName is specified and no stored profile is found, the function
    checks for ambient credentials (AWS CloudShell, EC2 instance roles, ECS task
    roles, or environment variables). If ambient credentials are detected via a
    successful Get-STSCallerIdentity call, execution proceeds without a named profile.

    Error Handling:
    - If a ScriptBlock throws (e.g., SCP denial, access denied, service unavailable),
      the error is caught and a result object with the Error property populated is
      emitted for that profile/region combination. Processing continues with the
      next region or profile.
    - If a ScriptBlock returns no data, an empty tracking object is emitted so
      every profile/region combination produces at least one output row. Use
      -SuppressEmptyResult to skip these placeholders when you only want real data.
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

.PARAMETER SuppressEmptyResult
    When specified, does not emit an object to the pipeline for profile/region
    combinations where the ScriptBlock returned no data. By default an empty
    tracking object is emitted so every iteration produces at least one output row;
    this switch suppresses that placeholder when you only want real results.

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
    [switch]$SuppressEmptyResult,

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
    $null = Test-CHARAWSCmdlet -Name 'Get-STSCallerIdentity'

    # When -OutputSubTemplate is specified, emit a function stub for use as a ScriptBlock
    if ($OutputSubTemplate) {
      Write-Verbose 'Emitting sub-template for ScriptBlock'
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
    # Build base AWS splat from credential parameters then remove ProfileName/Region
    # since those are arrays used for iteration in this function, not single-value
    # credential params to pass to AWS cmdlets directly.
    $awsParams = New-AWSParamSplat -BoundParameters $PSBoundParameters
    $awsParams.Remove('ProfileName') | Out-Null
    $awsParams.Remove('Region') | Out-Null
    if (-not $ProfileName) {
      # Try the shell's current stored credential profile name
      Write-Debug 'ProfileName not specified'
      $currentProfile = $null
      if ($StoredAWSCredentials) {
        Write-Debug "Found StoredAWSCredentials: $StoredAWSCredentials"
        $currentProfile = $StoredAWSCredentials
      }
      if (-not $currentProfile) {
        Write-Debug 'Checking for default profile'
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
      } else {
        # No named profile found — check if ambient credentials are available
        # (e.g., CloudShell, EC2 instance role, ECS task role, environment variables).
        # Only attempt this when no explicit credential parameters were provided;
        # if the user passed -AccessKey/-SecretKey/-Credential they expect a profile
        # to pair them with, so ambient fallback would be incorrect.
        $hasExplicitCreds = $PSBoundParameters.ContainsKey('AccessKey') -or
          $PSBoundParameters.ContainsKey('SecretKey') -or
          $PSBoundParameters.ContainsKey('SessionToken') -or
          $PSBoundParameters.ContainsKey('Credential')

        if (-not $hasExplicitCreds) {
          Write-Debug 'No named profile found, checking for ambient credentials'
          try {
            $ambientIdentity = Get-STSCallerIdentity -ErrorAction Stop
            if ($ambientIdentity) {
              Write-Verbose "Using ambient credentials (no named profile): $($ambientIdentity.Arn)"
              $ProfileName = @('__ambient__')
            }
          } catch {
            Write-Debug "Ambient credential check failed: $_"
          }
        }

        if (-not $ProfileName) {
          Write-Error 'No ProfileName specified and no current AWS profile or ambient credentials found. Use -ProfileName or Set-AWSCredential.'
          return
        }
      }

    }
    Write-Debug "Region checks : $Region"

    if ($Region.count -eq 0) {
      Write-Verbose 'Region not specified - trying default region'
      $defaultRegion = (Get-DefaultAWSRegion).Region
      if ($defaultRegion) {
        Write-Verbose "Using current/default region: $defaultRegion"
        $Region = @($defaultRegion)
      } else {
        Write-Error 'No region specified and no default AWS region set. Use -Region or Set-DefaultAWSRegion.'
        return
      }
    } else {
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
  }

  process {
    foreach ($prof in $ProfileName) {
      Write-Verbose "Processing profile: $prof"
      $profileCount++
      if (-not $NoProgress) {
        Write-Progress -Id 1 -Activity 'Processing AWS Profiles' `
          -Status "Profile: $prof (#$profileCount)" `
          -CurrentOperation 'Authenticating...'
      }

      # Validate credentials before doing any work for this profile
      # Override ProfileName per iteration; base awsParams carries other credential params
      # Use the first region from the list for validation since Region was removed from awsParams
      $iterParams = $awsParams.Clone()
      $isAmbient = ($prof -eq '__ambient__')
      if (-not $isAmbient) {
        $iterParams['ProfileName'] = $prof
      }
      if ($Region -and $Region.Count -gt 0) {
        $iterParams['Region'] = $Region[0]
      } else {
        Write-Error "Region array is empty or null for profile '$prof'"
        continue
      }
      $displayProfile = if ($isAmbient) { '(ambient credentials)' } else { $prof }
      Write-Verbose "Validating profile '$displayProfile' with region '$($iterParams.Region)'"
      try {
        $identity = Get-STSCallerIdentity @iterParams -ErrorAction Stop
        $accountId = $identity.Account
        Write-Verbose "Profile '$displayProfile' resolved to AccountId: $accountId"
      } catch {
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
      # For ambient credentials (CloudShell, instance roles), skip resolution entirely.
      $resolvedCreds = $null
      if (-not $isAmbient) {
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
        } catch {
          Write-Verbose "Could not resolve credentials for profile '$prof': $_"
        }
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

        # Save current AWS session state
        $origStoredRegion = $global:StoredAWSRegion
        $origStoredCreds = $global:StoredAWSCredentials
        $origEnvRegion = $env:AWS_DEFAULT_REGION
        $origEnvAccessKey = $env:AWS_ACCESS_KEY_ID
        $origEnvSecretKey = $env:AWS_SECRET_ACCESS_KEY
        $origEnvSessionToken = $env:AWS_SESSION_TOKEN

        try {

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
            } else {
              $env:AWS_SESSION_TOKEN = $null
            }
          } elseif (-not $isAmbient) {
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
            # Inject Region and ProfileName as automatic variables so simple
            # ScriptBlocks can reference them directly (e.g. -Region $Region).
            # Also inject $PSDefaultParameterValues so any cmdlet or wrapper
            # accepting -Region/-ProfileName picks them up implicitly during
            # parameter binding — this avoids requiring users to thread the
            # values through every wrapper call.
            $iterationDefaults = @{
              '*:Region' = $r
            }
            if (-not $isAmbient) {
              $iterationDefaults['*:ProfileName'] = $prof
            }
            $vars = [System.Collections.Generic.List[psvariable]]::new()
            $vars.Add([psvariable]::new('Region', $r))
            $vars.Add([psvariable]::new('ProfileName', $(if ($isAmbient) { $null } else { $prof })))
            $vars.Add([psvariable]::new('PSDefaultParameterValues', $iterationDefaults))
            $results = @($ScriptBlock.InvokeWithContext($null, $vars))

            if ($results.Count -eq 0) {
              Write-Verbose "No results returned for Profile='$prof', Region='$r'"
              if ($SuppressEmptyResult) {
                Write-Verbose "SuppressEmptyResult: skipping empty result for Profile='$prof', Region='$r'"
                $results = $null
              } else {
                $results = [PSCustomObject]@{}
              }
            }
          } catch {
            # script failed to execute, record error and continue
            Write-Warning "ScriptBlock failed for Profile='${prof}', Region='${r}': $_"
            $results = [PSCustomObject]@{
              Error = $_.Exception.Message
            }
          } finally {
            $ErrorActionPreference = $origErrorAction
          }
          # Results should NEVER be empty unless intentionally suppressed
          if ($results) {
            foreach ($item in $results) {
              Write-Debug "Returning result for Profile='$prof', Region='$r': $item"
              $props = [ordered]@{}

              # If the item is a simple type (string, number, etc.), wrap it so enrichment works
              if ($item -is [string]) {
                Write-Debug 'item: string'
                $props['Value'] = $item
              } elseif ($item.GetType().IsPrimitive -or $item -is [decimal]) {
                Write-Debug 'item: primitive'
                $props['Value'] = $item
              } else {
                Write-Debug 'item: psobject'
                foreach ($p in $item.PSObject.Properties) {
                  $props[$p.Name] = $p.Value
                }
              }
              # if error not present, insert a placeholder for it
              if (-not $props.Contains('Error')) { $props['Error'] = $null }
              if ($IncludeAccountId) { $props['AccountId'] = $accountId }
              if ($IncludeRegion) { $props['Region'] = $r }
              if ($IncludeProfileName) { $props['ProfileName'] = if ($isAmbient) { '(ambient)' } else { $prof } }

              $enriched = [PSCustomObject]$props

              $propNames = [string[]]$props.Keys
              $propSet = [System.Management.Automation.PSPropertySet]::new(
                'DefaultDisplayPropertySet', $propNames
              )
              $enriched | Add-Member -MemberType MemberSet -Name PSStandardMembers -Value $propSet -Force

              $enriched
            }
          } elseif (-not $SuppressEmptyResult) {
            throw 'Error- Results empty, aborting'
          }
        } catch {
          Write-Warning "Error executing ScriptBlock for Profile='${prof}', Region='${r}': $_"
        } finally {
          # Restore original AWS session state by directly reassigning the globals.
          # $StoredAWSCredentials may hold a profile name string OR a credential object
          # (e.g., BasicAWSCredentials from SSO), so we cannot assume Set-AWSCredential
          # -ProfileName will work. Direct assignment is the safe restore path.
          $global:StoredAWSCredentials = $origStoredCreds
          if ($origStoredRegion) {
            Set-DefaultAWSRegion -Region $origStoredRegion
          } else {
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
      Write-Progress -Id 1 -Activity 'Processing AWS Profiles' -Completed
    }
  }
}

# SIG # Begin signature block
# MIIgygYJKoZIhvcNAQcCoIIguzCCILcCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDYUPjag37DxLdy
# nERmTiJ2NondzYtoJ9eU5GueTjP9dKCCG1gwggN5MIIC/qADAgECAhAcz51nzeIZ
# /xLZmv82guWnMAoGCCqGSM49BAMDMHwxCzAJBgNVBAYTAlVTMQ4wDAYDVQQIDAVU
# ZXhhczEQMA4GA1UEBwwHSG91c3RvbjEYMBYGA1UECgwPU1NMIENvcnBvcmF0aW9u
# MTEwLwYDVQQDDChTU0wuY29tIFJvb3QgQ2VydGlmaWNhdGlvbiBBdXRob3JpdHkg
# RUNDMB4XDTE5MDMwNzE5MzU0N1oXDTM0MDMwMzE5MzU0N1oweDELMAkGA1UEBhMC
# VVMxDjAMBgNVBAgMBVRleGFzMRAwDgYDVQQHDAdIb3VzdG9uMREwDwYDVQQKDAhT
# U0wgQ29ycDE0MDIGA1UEAwwrU1NMLmNvbSBDb2RlIFNpZ25pbmcgSW50ZXJtZWRp
# YXRlIENBIEVDQyBSMjB2MBAGByqGSM49AgEGBSuBBAAiA2IABOpt7gyJbfdl1TyX
# rJy6JZGueJwq39d2z/FOJTbnNRuYrlS823MWKvLp+ziKPRCumlXWYiCS5X0xZxWv
# 2FIxsD9Tf7tCm8JcqSsa6W8uRyjXT+yEBglVRcOJGZiIjeFxJKOCAUcwggFDMBIG
# A1UdEwEB/wQIMAYBAf8CAQAwHwYDVR0jBBgwFoAUgtGFczDnNQTTjgKS++Wk0cQh
# 6M0weAYIKwYBBQUHAQEEbDBqMEYGCCsGAQUFBzAChjpodHRwOi8vd3d3LnNzbC5j
# b20vcmVwb3NpdG9yeS9TU0xjb20tUm9vdENBLUVDQy0zODQtUjEuY3J0MCAGCCsG
# AQUFBzABhhRodHRwOi8vb2NzcHMuc3NsLmNvbTARBgNVHSAECjAIMAYGBFUdIAAw
# EwYDVR0lBAwwCgYIKwYBBQUHAwMwOwYDVR0fBDQwMjAwoC6gLIYqaHR0cDovL2Ny
# bHMuc3NsLmNvbS9zc2wuY29tLWVjYy1Sb290Q0EuY3JsMB0GA1UdDgQWBBQyeLEO
# kNtGzxrPtmMRbf4w52dUMDAOBgNVHQ8BAf8EBAMCAYYwCgYIKoZIzj0EAwMDaQAw
# ZgIxAIZwNaUUH2Oi1OfK9PES0J4Ay3EIm1mAOjpxEHItL3pSmV+5tJ/iQQqK2Dwg
# evkxFQIxAIHLuf6CWo8Wvxn2XZR/+3do0Q/XjqQSbfhJlqwRUVPlxUz5aK1vpJwv
# LRHaPzhzXTCCA8AwggNHoAMCAQICEFEd7vPtDKtYV7OYcsTNL88wCgYIKoZIzj0E
# AwMweDELMAkGA1UEBhMCVVMxDjAMBgNVBAgMBVRleGFzMRAwDgYDVQQHDAdIb3Vz
# dG9uMREwDwYDVQQKDAhTU0wgQ29ycDE0MDIGA1UEAwwrU1NMLmNvbSBDb2RlIFNp
# Z25pbmcgSW50ZXJtZWRpYXRlIENBIEVDQyBSMjAeFw0yNjA4MDcxOTA3NTdaFw0y
# NzExMDgxOTA3NTdaMHkxCzAJBgNVBAYTAlVTMRYwFAYDVQQIDA1OZXcgSGFtcHNo
# aXJlMRQwEgYDVQQHDAtOZXcgSXBzd2ljaDEdMBsGA1UECgwUQ2hyaXN0b3BoZXIg
# Q2hhcmxhbmQxHTAbBgNVBAMMFENocmlzdG9waGVyIENoYXJsYW5kMHYwEAYHKoZI
# zj0CAQYFK4EEACIDYgAEnBTifag8qbU07/B2aFtw7h3deXWsME/+F18vvlqQOnQg
# 5YNQyYRisw1XkwtXq2m1AMiqAddMEVOkmxIi71eYqVi87p/RQct3k/HuXi/clk4C
# YqaYFCEpq7tFMUDd8cUCo4IBkzCCAY8wDAYDVR0TAQH/BAIwADAfBgNVHSMEGDAW
# gBQyeLEOkNtGzxrPtmMRbf4w52dUMDB5BggrBgEFBQcBAQRtMGswRwYIKwYBBQUH
# MAKGO2h0dHA6Ly9jZXJ0LnNzbC5jb20vU1NMY29tLVN1YkNBLWNvZGVTaWduaW5n
# LUVDQy0zODQtUjIuY2VyMCAGCCsGAQUFBzABhhRodHRwOi8vb2NzcHMuc3NsLmNv
# bTBRBgNVHSAESjBIMAgGBmeBDAEEATA8BgwrBgEEAYKpMAEDAwEwLDAqBggrBgEF
# BQcCARYeaHR0cHM6Ly93d3cuc3NsLmNvbS9yZXBvc2l0b3J5MBMGA1UdJQQMMAoG
# CCsGAQUFBwMDMEwGA1UdHwRFMEMwQaA/oD2GO2h0dHA6Ly9jcmxzLnNzbC5jb20v
# U1NMY29tLVN1YkNBLWNvZGVTaWduaW5nLUVDQy0zODQtUjIuY3JsMB0GA1UdDgQW
# BBRaKfdK1zqVgfdqPHp69Ump7V7QDjAOBgNVHQ8BAf8EBAMCB4AwCgYIKoZIzj0E
# AwMDZwAwZAIwfyXRtBRHbkmoEP6vHjnUe6Xb6WUcfzZ+r2mFqz3pxpokqXkdYfbn
# ySinlBy2oScEAjAmFdwaA7/yG/M+bPD8UviQ9p13KC3R2X1eXbRlCoRwLwdKSF89
# FQPG4jtmL9FPIawwggaCMIIEaqADAgECAhA2wrC9fBs656Oz3TbLyXVoMA0GCSqG
# SIb3DQEBDAUAMIGIMQswCQYDVQQGEwJVUzETMBEGA1UECBMKTmV3IEplcnNleTEU
# MBIGA1UEBxMLSmVyc2V5IENpdHkxHjAcBgNVBAoTFVRoZSBVU0VSVFJVU1QgTmV0
# d29yazEuMCwGA1UEAxMlVVNFUlRydXN0IFJTQSBDZXJ0aWZpY2F0aW9uIEF1dGhv
# cml0eTAeFw0yMTAzMjIwMDAwMDBaFw0zODAxMTgyMzU5NTlaMFcxCzAJBgNVBAYT
# AkdCMRgwFgYDVQQKEw9TZWN0aWdvIExpbWl0ZWQxLjAsBgNVBAMTJVNlY3RpZ28g
# UHVibGljIFRpbWUgU3RhbXBpbmcgUm9vdCBSNDYwggIiMA0GCSqGSIb3DQEBAQUA
# A4ICDwAwggIKAoICAQCIndi5RWedHd3ouSaBmlRUwHxJBZvMWhUP2ZQQRLRBQIF3
# FJmp1OR2LMgIU14g0JIlL6VXWKmdbmKGRDILRxEtZdQnOh2qmcxGzjqemIk8et8s
# E6J+N+Gl1cnZocew8eCAawKLu4TRrCoqCAT8uRjDeypoGJrruH/drCio28aqIVEn
# 45NZiZQI7YYBex48eL78lQ0BrHeSmqy1uXe9xN04aG0pKG9ki+PC6VEfzutu6Q3I
# cZZfm00r9YAEp/4aeiLhyaKxLuhKKaAdQjRaf/h6U13jQEV1JnUTCm511n5avv4N
# +jSVwd+Wb8UMOs4netapq5Q/yGyiQOgjsP/JRUj0MAT9YrcmXcLgsrAimfWY3MzK
# m1HCxcquinTqbs1Q0d2VMMQyi9cAgMYC9jKc+3mW62/yVl4jnDcw6ULJsBkOkrcP
# LUwqj7poS0T2+2JMzPP+jZ1h90/QpZnBkhdtixMiWDVgh60KmLmzXiqJc6lGwqoU
# qpq/1HVHm+Pc2B6+wCy/GwCcjw5rmzajLbmqGygEgaj/OLoanEWP6Y52Hflef3XL
# vYnhEY4kSirMQhtberRvaI+5YsD3XVxHGBjlIli5u+NrLedIxsE88WzKXqZjj9Zi
# 5ybJL2WjeXuOTbswB7XjkZbErg7ebeAQUQiS/uRGZ58NHs57ZPUfECcgJC+v2wID
# AQABo4IBFjCCARIwHwYDVR0jBBgwFoAUU3m/WqorSs9UgOHYm8Cd8rIDZsswHQYD
# VR0OBBYEFPZ3at0//QET/xahbIICL9AKPRQlMA4GA1UdDwEB/wQEAwIBhjAPBgNV
# HRMBAf8EBTADAQH/MBMGA1UdJQQMMAoGCCsGAQUFBwMIMBEGA1UdIAQKMAgwBgYE
# VR0gADBQBgNVHR8ESTBHMEWgQ6BBhj9odHRwOi8vY3JsLnVzZXJ0cnVzdC5jb20v
# VVNFUlRydXN0UlNBQ2VydGlmaWNhdGlvbkF1dGhvcml0eS5jcmwwNQYIKwYBBQUH
# AQEEKTAnMCUGCCsGAQUFBzABhhlodHRwOi8vb2NzcC51c2VydHJ1c3QuY29tMA0G
# CSqGSIb3DQEBDAUAA4ICAQAOvmVB7WhEuOWhxdQRh+S3OyWM637ayBeR7djxQ8Si
# hTnLf2sABFoB0DFR6JfWS0snf6WDG2gtCGflwVvcYXZJJlFfym1Doi+4PfDP8s0c
# qlDmdfyGOwMtGGzJ4iImyaz3IBae91g50QyrVbrUoT0mUGQHbRcF57olpfHhQESt
# z5i6hJvVLFV/ueQ21SM99zG4W2tB1ExGL98idX8ChsTwbD/zIExAopoe3l6JrzJt
# Pxj8V9rocAnLP2C8Q5wXVVZcbw4x4ztXLsGzqZIiRh5i111TW7HV1AtsQa6vXy63
# 3vCAbAOIaKcLAo/IU7sClyZUk62XD0VUnHD+YvVNvIGezjM6CRpcWed/ODiptK+e
# vDKPU2K6synimYBaNH49v9Ih24+eYXNtI38byt5kIvh+8aW88WThRpv8lUJKaPn3
# 7+YHYafob9Rg7LyTrSYpyZoBmwRWSE4W6iPjB7wJjJpH29308ZkpKKdpkiS9WNsf
# /eeUtvRrtIEiSJHN899L1P4l6zKVsdrUu1FX1T/ubSrsxrYJD+3f3aKg6yxdbugo
# t06YwGXXiy5UUGZvOu3lXlxA+fC13dQ5OlL2gIb5lmF6Ii8+CQOYDwXM+yd9dbmo
# cQsHjcRPsccUd5E9FiswEqORvz8g3s+jR3SFCgXhN4wz7NgAnOgpCdUo4uDyllU9
# PzCCBqcwggSPoAMCAQICEQCQrAhyIP3Fp8RrXMcN9z0GMA0GCSqGSIb3DQEBDAUA
# MFcxCzAJBgNVBAYTAkdCMRgwFgYDVQQKEw9TZWN0aWdvIExpbWl0ZWQxLjAsBgNV
# BAMTJVNlY3RpZ28gUHVibGljIFRpbWUgU3RhbXBpbmcgUm9vdCBSNDYwHhcNMjYw
# MzI1MDAwMDAwWhcNNDEwMzI0MjM1OTU5WjBVMQswCQYDVQQGEwJHQjEYMBYGA1UE
# ChMPU2VjdGlnbyBMaW1pdGVkMSwwKgYDVQQDEyNTZWN0aWdvIFB1YmxpYyBUaW1l
# IFN0YW1waW5nIENBIFI0MTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIB
# AK7kSqIBrYIcYvlmLVuaA8zw1RfBhkn4G1CoemzjcYtML6yNUvKmwGH7y6/5MuSC
# 1UYP/+9KYDSqvMQt/1hEKHYxMAD9oZpBkoaDQFEKbOJHelsKe+BaO0ZcENTKfePc
# raVkA7wrGAW2XHA5gQCQv4IKori/3PNOXxnDMOk8yIMgVrlMeTxqfWJ4XkjT1xc2
# s9DD7URHWWJOFobTPoWs6mrDFlaY9FlAHDYTfbzvxQHVsvRmn3W+5ZmCwyk02I8K
# gGPT/UX4sTz41GiR+ppwUjQXa1+2tEHZbsdAKUtH3OPEVtZvlt7atx4h83IdRR8o
# Yi8wjY3OjFKXFecWpQbzzsPxbUKPwMWiTrzwkrFa8dH/1pDKRJt371W62PfqKPay
# Cr/XbnBOlRn8CALSmHnRtGzuAWtTJpcT3BKw6oy8IIL6wSbu938F6ZIbRNIc1dKb
# IJtr4ULN6R5ZfTdNEhwXctqp3RHDbg4fuOl6LjNoaFwjud92EEDhzxFJzE1jqN4c
# sceZIwxOT1aqfsfh0uFQE/lgTBuBs3i6/WL2W1OceWLy3XEdXRK1f0EWCuea6dNf
# X2RRdjUfk5EltFnJkN2+bWhnK14OPRKcyjOv5hKZ0iV4NRNd1+hjtva1rPyzb5Bs
# 7EvFxqEQhgZbOq7qH3nm0rBwA0dxniBOYCFPdu246JCxAgMBAAGjggFuMIIBajAf
# BgNVHSMEGDAWgBT2d2rdP/0BE/8WoWyCAi/QCj0UJTAdBgNVHQ4EFgQUOnSlDGfG
# QlDC/bX8x7spNIL0erkwDgYDVR0PAQH/BAQDAgGGMBIGA1UdEwEB/wQIMAYBAf8C
# AQAwEwYDVR0lBAwwCgYIKwYBBQUHAwgwIwYDVR0gBBwwGjAIBgZngQwBBAIwDgYM
# KwYBBAGyMQECAQMIMEwGA1UdHwRFMEMwQaA/oD2GO2h0dHA6Ly9jcmwuc2VjdGln
# by5jb20vU2VjdGlnb1B1YmxpY1RpbWVTdGFtcGluZ1Jvb3RSNDYuY3JsMHwGCCsG
# AQUFBwEBBHAwbjBHBggrBgEFBQcwAoY7aHR0cDovL2NydC5zZWN0aWdvLmNvbS9T
# ZWN0aWdvUHVibGljVGltZVN0YW1waW5nUm9vdFI0Ni5wN2MwIwYIKwYBBQUHMAGG
# F2h0dHA6Ly9vY3NwLnNlY3RpZ28uY29tMA0GCSqGSIb3DQEBDAUAA4ICAQAy3lJH
# ZvGeA2b43yhzoarvobHVzbfl+RfuPDwej0wCQkYAN6scTt2GwFe22qbOCv/tllqF
# lLKQZE+E9jVyuPTbyQHwrM7R0oLapAEDC1+CowsqSRf/ptira5Pfd4PoHICnb9co
# PQtyZmHSQp5y9IGvqWf1qNfq7V2fHZ8DvEQrLUzeoGF9BJRYu2OzacW3QQtUum3N
# OVf0gPRwv6I4991uhncJ6VP4lcpUpHZKB7R3hiIUC09mR9KjzPVnXHvL9n2bAwiU
# ECfK5Zezhiw27F2tgi39DETfU8M4n0N6xLgFzsf05M5GURX8C9+IX9V6kpmmKtrU
# zMti4LD66gtmf+mSm934K81NL6YQeMEk1rpYrWPypcW76Mir6wb1AgseLIHqn/Gk
# euQm7zOTDf3f5WoX14qVNjZWNHF3JxkutV6ZnhinfCLfdv5bnwKWUfceqOajCVnt
# I6uCbHxjBg6SCsexc5AfIGno7gVFvwifT4XONPsSUaJ71XsJ+EvciVUVnjOO4qxm
# 0fWJTd8a7jP8mc4ZPqwJvQFtOp7+6G+kUJAF0fnE8YgD8uttBReNTa1YmAeFMiqc
# 38e8fI4eLm0zjM/eeGCHasnoqqrbGwcF41iz9HXzFDwN4iD5z3QShp6HRiU3UpTw
# DJiiXcr0z6pjl7PyzJ3/tmWtGehV7CAfc/WlyzCCBuIwggTKoAMCAQICEQDnTvJV
# sFBP+tum3/f8i6MVMA0GCSqGSIb3DQEBDAUAMFUxCzAJBgNVBAYTAkdCMRgwFgYD
# VQQKEw9TZWN0aWdvIExpbWl0ZWQxLDAqBgNVBAMTI1NlY3RpZ28gUHVibGljIFRp
# bWUgU3RhbXBpbmcgQ0EgUjQxMB4XDTI2MDMyNTAwMDAwMFoXDTM3MDYyNDIzNTk1
# OVowcjELMAkGA1UEBhMCR0IxFzAVBgNVBAgTDkdyZWF0ZXIgTG9uZG9uMRgwFgYD
# VQQKEw9TZWN0aWdvIExpbWl0ZWQxMDAuBgNVBAMTJ1NlY3RpZ28gUHVibGljIFRp
# bWUgU3RhbXBpbmcgU2lnbmVyIFIzNzCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCC
# AgoCggIBALL/w21L3FDZRS0FEXfZuPtUrefibnRSqOT/NNyJLOJhXjQfUspqHT+g
# SSVgbjYThUI/cO+wFQHoOakKQNnSMKdkE8gR69ofXlkk5DAVY/ZlevliOUmlvrw2
# Vuz4SU28rHfb/Vgd17eqpRIvJuO6XE8vPpPzn4c4iorszUF6nwuynKEQ/+rqfDmQ
# bFNKsa+5+Z4f4kXwKdUFxUwUDjQWUhiHRwMlUWGF9N91aAvL+9a4sxCgqR/ez8W8
# HJ/XqvSu1vIeb+J6bDFKKgkv3PJkMMpQ0BsdeXR2FejZXFRXY1w9dZe6gqyMv7px
# +TpWbYMefECUV0WxoEMgXUk6RKcLo94uUHOdmfZu4Xe8ghglyro3/N4VEKTj8dcP
# PvOBGxFEx1QH6uHKTkWhloGPDScurcZnd8KUtTHl6zmlQDHM04MwGfsmQViKnYEA
# YE8RHl5XRE6GTq0ZMb59SIyJX6+CODVic/kW+dhbIS1Z5AP8HaGne/PRG+12QzSn
# eKDJp3Ot+k4GrmmlWT9iy6FNCQ/32K+d4cAZ+Ll7uWbEn6Z6gE+tEu7MyZvzWvPN
# sRKMkcyyflFW1zpRyzutwypALXc9Qg7sFsYERNXa58KZXqU9Onc/tck6+adQJFM9
# tW8xOnE//P5I4eDj84IGGKqzgUD37ihC+WST3DfY0YBKWL0ZaubnAgMBAAGjggGO
# MIIBijAfBgNVHSMEGDAWgBQ6dKUMZ8ZCUML9tfzHuyk0gvR6uTAdBgNVHQ4EFgQU
# YRDpehKvUcSF1PLPpHQPUM0gr/gwDgYDVR0PAQH/BAQDAgbAMAwGA1UdEwEB/wQC
# MAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgwSgYDVR0gBEMwQTAIBgZngQwBBAIw
# NQYMKwYBBAGyMQECAQMIMCUwIwYIKwYBBQUHAgEWF2h0dHBzOi8vc2VjdGlnby5j
# b20vQ1BTMEoGA1UdHwRDMEEwP6A9oDuGOWh0dHA6Ly9jcmwuc2VjdGlnby5jb20v
# U2VjdGlnb1B1YmxpY1RpbWVTdGFtcGluZ0NBUjQxLmNybDB6BggrBgEFBQcBAQRu
# MGwwRQYIKwYBBQUHMAKGOWh0dHA6Ly9jcnQuc2VjdGlnby5jb20vU2VjdGlnb1B1
# YmxpY1RpbWVTdGFtcGluZ0NBUjQxLmNydDAjBggrBgEFBQcwAYYXaHR0cDovL29j
# c3Auc2VjdGlnby5jb20wDQYJKoZIhvcNAQEMBQADggIBAAPqPY3RrM36GXqTpsoH
# n9TpW5I6z3dkFvc9zPL1W0Egq7j3jtnkbAvRoWeAjGX4ZK4sWsmA+u4EJG8okQmy
# buS/4tDUI5UIQb21n4hG2vihxShrneWB0VoQ2VLQ3jCCRmRtAQ+/7H7WVKNiH5Pg
# l4v2ZTOdPsStzpKnl1YuRrmww/+bcZmLqgk909ywIpZqAfubYfbEMYjIckLk90f2
# mG+L8qaGSS2JJVM02pV5XltZ1fbOFETpRN/PQhwygIv33qUUjJ1fE4ITgw0McMzR
# qziWdOJP8ocxxw7qXxz1OdRWCalyL1qvUgAFnZTVdSRiMYZKf0wLcQcM/1Xf1W4F
# W9nff8ERX8RZJGt/TtPuMWmUpf6BCv9Q6o8YyUTtknvZRpSQ0nLttWXdtwsrN2mM
# gfMuR//gxVrVXvDzCoK/lbiA6dEZOW53lQwBFtEzwE/FH8JdhegyYg4PymZOTZrG
# BEvgsbxe25yEhJ0IdGa1pwCYsarldJhJVMdNcAOU7jyIMqHcczav3wtIXp/SwbXZ
# 3xX0mfsLfANSJ47G4qPgx1atb6GIlTaQXzu/p4fTQeAIUVzZXT4K984IyfuO7NLj
# WMtog1wGUpZD98pv+4Mt9Y5bvfPUjaUVjtePy1DVdi0rl5ESNYi0zyOmXVxtA5zz
# xu1H7RdLZOZugT/XjX69rY9bMYIEyDCCBMQCAQEwgYwweDELMAkGA1UEBhMCVVMx
# DjAMBgNVBAgMBVRleGFzMRAwDgYDVQQHDAdIb3VzdG9uMREwDwYDVQQKDAhTU0wg
# Q29ycDE0MDIGA1UEAwwrU1NMLmNvbSBDb2RlIFNpZ25pbmcgSW50ZXJtZWRpYXRl
# IENBIEVDQyBSMgIQUR3u8+0Mq1hXs5hyxM0vzzANBglghkgBZQMEAgEFAKCBhDAY
# BgorBgEEAYI3AgEMMQowCKACgAChAoAAMBkGCSqGSIb3DQEJAzEMBgorBgEEAYI3
# AgEEMBwGCisGAQQBgjcCAQsxDjAMBgorBgEEAYI3AgEVMC8GCSqGSIb3DQEJBDEi
# BCBxqxguxJEGtAvw1QypKLL6Iz1C3oTShn7JX3iL1BkI8zALBgcqhkjOPQIBBQAE
# ZjBkAjBmZtTsgqY2bupCUygcRLSE6RhXc9ncRwyxaUsKLf+r6rEx+v2dASyDxInZ
# jZ4cqAwCMAa1mYIfVlFZf19Q43n3VJIMN6RExTXNDNoFG9JqYObjSN66UTnjTE9l
# aDQDqWQiU6GCAyMwggMfBgkqhkiG9w0BCQYxggMQMIIDDAIBATBqMFUxCzAJBgNV
# BAYTAkdCMRgwFgYDVQQKEw9TZWN0aWdvIExpbWl0ZWQxLDAqBgNVBAMTI1NlY3Rp
# Z28gUHVibGljIFRpbWUgU3RhbXBpbmcgQ0EgUjQxAhEA507yVbBQT/rbpt/3/Iuj
# FTANBglghkgBZQMEAgIFAKB5MBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJ
# KoZIhvcNAQkFMQ8XDTI2MDgyMzIxMTM0N1owPwYJKoZIhvcNAQkEMTIEMJyidWr4
# jUWlYrUPlPi6bBYAx1I3abTyvtIdLzQp3yVeOKeNoIp8wsAqdg7doKUsMjANBgkq
# hkiG9w0BAQEFAASCAgCOi0KSV2A+78EiMEwfGWyJ4txl79KEmBu32T46IUmd9FPp
# KjZujaNwlSegiIt60vgwK2tXm9KI4TvLLcW+w/cZIm8yyJAmmZWkdpbKpXVW0zLB
# 89LRcgpHVFuUF8xSKO2jmKbNBrt9tMb9UQKrZDmdscd6uqrXwtTzL3h0Qlh74cc0
# hFXppkaadV7nhG3AVGtgYtEh0kRH1Vln4b0jJ7NyjJ9rFwA7qv9hE68YxB9lV10e
# ulrsf3weYbSFEKIUMrtuRjcjMiEyfdQAmSzAYXnd1r/N3AKQHRikfOMrPChqhIFN
# /Y21/UgrnyqHvwWqLQHUylTlc1sJoGumRMLAdEr06m8PPTA4Xiua/V1reU8NhlVC
# wv1wCmQj1cM5CJ+J5qatowkw9F9tqhxOrV7I5y+0myeRORgaWU+H5iFLsg45UG8E
# Zj9WkrU88fz4zt5BioJV+lgXhDRos5a0ddzdZ+6+up5pwphAHwKtcawupDVS6qr2
# e5gIbK9gCccjRVFkbRLpf/XlpHR69vSPQlDvkQj8/czV64/yhplNXuVC6oPLItir
# gMpBfXGfDnp10LcPN7nVeF8A/wWrc5YTb1JfO0MEA3ypscm+/IWtxvDSn3qmz/pS
# O0CJkDtc260QLeNwa5ce8z57txyg3CgfPJQQBhz6lv6/VZplGCiE8fUyAkQv9A==
# SIG # End signature block
