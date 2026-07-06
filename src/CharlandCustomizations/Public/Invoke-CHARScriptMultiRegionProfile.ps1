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
    Write-Debug 'Start Begin'
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
        Write-Error 'No ProfileName specified and no current AWS profile found. Use -ProfileName or Set-AWSCredential.'
        return
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
    Write-Debug 'end begin'
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
      $iterParams['ProfileName'] = $prof
      if ($Region -and $Region.Count -gt 0) {
        $iterParams['Region'] = $Region[0]
      } else {
        Write-Error "Region array is empty or null for profile '$prof'"
        continue
      }
      Write-Verbose "Validating profile '$prof' with region '$($iterParams.Region)'"
      try {
        $identity = Get-STSCallerIdentity @iterParams -ErrorAction Stop
        $accountId = $identity.Account
        Write-Verbose "Profile '$prof' resolved to AccountId: $accountId"
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
      } catch {
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
          Write-Verbose 'saving state'

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
          } else {
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
            Write-Verbose "Try to invoke script: Results before script: $results"
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
              Write-Verbose 'emit a single item for tracking'
              $results = [PSCustomObject]@{}
            }
          } catch {
            # script failed to execute, record error and continue
            Write-Warning "ScriptBlock failed for Profile='${prof}', Region='${r}': $_"
            $results = [PSCustomObject]@{
              Error = $_.Exception.Message
            }
          } finally {
            Write-Verbose 'finally block'
            Write-Verbose "Results: $results"
            $ErrorActionPreference = $origErrorAction
          }
          # Results should NEVER be empty
          if ($results) {
            Write-Verbose "Results for Profile='$prof', Region='$r'"
            Write-Verbose "results:  $results"
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
              if ($IncludeProfileName) { $props['ProfileName'] = $prof }

              $enriched = [PSCustomObject]$props

              $propNames = [string[]]$props.Keys
              $propSet = [System.Management.Automation.PSPropertySet]::new(
                'DefaultDisplayPropertySet', $propNames
              )
              $enriched | Add-Member -MemberType MemberSet -Name PSStandardMembers -Value $propSet -Force

              $enriched
            }
          } else {
            throw 'Error- Results empty, aborting'
          }
        } catch {
          Write-Warning "Error executing ScriptBlock for Profile='${prof}', Region='${r}': $_"
        } finally {
          # Restore original AWS session state
          if ($origStoredCreds) {
            Set-AWSCredential -ProfileName $origStoredCreds
          } else {
            Clear-AWSCredential
          }
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
# MIIs4wYJKoZIhvcNAQcCoIIs1DCCLNACAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCB2jLJIuYp2Jvv6
# W00px2YI7IX66M02lPP2skkd5tl0haCCJfgwggVvMIIEV6ADAgECAhBI/JO0YFWU
# jTanyYqJ1pQWMA0GCSqGSIb3DQEBDAUAMHsxCzAJBgNVBAYTAkdCMRswGQYDVQQI
# DBJHcmVhdGVyIE1hbmNoZXN0ZXIxEDAOBgNVBAcMB1NhbGZvcmQxGjAYBgNVBAoM
# EUNvbW9kbyBDQSBMaW1pdGVkMSEwHwYDVQQDDBhBQUEgQ2VydGlmaWNhdGUgU2Vy
# dmljZXMwHhcNMjEwNTI1MDAwMDAwWhcNMjgxMjMxMjM1OTU5WjBWMQswCQYDVQQG
# EwJHQjEYMBYGA1UEChMPU2VjdGlnbyBMaW1pdGVkMS0wKwYDVQQDEyRTZWN0aWdv
# IFB1YmxpYyBDb2RlIFNpZ25pbmcgUm9vdCBSNDYwggIiMA0GCSqGSIb3DQEBAQUA
# A4ICDwAwggIKAoICAQCN55QSIgQkdC7/FiMCkoq2rjaFrEfUI5ErPtx94jGgUW+s
# hJHjUoq14pbe0IdjJImK/+8Skzt9u7aKvb0Ffyeba2XTpQxpsbxJOZrxbW6q5KCD
# J9qaDStQ6Utbs7hkNqR+Sj2pcaths3OzPAsM79szV+W+NDfjlxtd/R8SPYIDdub7
# P2bSlDFp+m2zNKzBenjcklDyZMeqLQSrw2rq4C+np9xu1+j/2iGrQL+57g2extme
# me/G3h+pDHazJyCh1rr9gOcB0u/rgimVcI3/uxXP/tEPNqIuTzKQdEZrRzUTdwUz
# T2MuuC3hv2WnBGsY2HH6zAjybYmZELGt2z4s5KoYsMYHAXVn3m3pY2MeNn9pib6q
# RT5uWl+PoVvLnTCGMOgDs0DGDQ84zWeoU4j6uDBl+m/H5x2xg3RpPqzEaDux5mcz
# mrYI4IAFSEDu9oJkRqj1c7AGlfJsZZ+/VVscnFcax3hGfHCqlBuCF6yH6bbJDoEc
# QNYWFyn8XJwYK+pF9e+91WdPKF4F7pBMeufG9ND8+s0+MkYTIDaKBOq3qgdGnA2T
# OglmmVhcKaO5DKYwODzQRjY1fJy67sPV+Qp2+n4FG0DKkjXp1XrRtX8ArqmQqsV/
# AZwQsRb8zG4Y3G9i/qZQp7h7uJ0VP/4gDHXIIloTlRmQAOka1cKG8eOO7F/05QID
# AQABo4IBEjCCAQ4wHwYDVR0jBBgwFoAUoBEKIz6W8Qfs4q8p74Klf9AwpLQwHQYD
# VR0OBBYEFDLrkpr/NZZILyhAQnAgNpFcF4XmMA4GA1UdDwEB/wQEAwIBhjAPBgNV
# HRMBAf8EBTADAQH/MBMGA1UdJQQMMAoGCCsGAQUFBwMDMBsGA1UdIAQUMBIwBgYE
# VR0gADAIBgZngQwBBAEwQwYDVR0fBDwwOjA4oDagNIYyaHR0cDovL2NybC5jb21v
# ZG9jYS5jb20vQUFBQ2VydGlmaWNhdGVTZXJ2aWNlcy5jcmwwNAYIKwYBBQUHAQEE
# KDAmMCQGCCsGAQUFBzABhhhodHRwOi8vb2NzcC5jb21vZG9jYS5jb20wDQYJKoZI
# hvcNAQEMBQADggEBABK/oe+LdJqYRLhpRrWrJAoMpIpnuDqBv0WKfVIHqI0fTiGF
# OaNrXi0ghr8QuK55O1PNtPvYRL4G2VxjZ9RAFodEhnIq1jIV9RKDwvnhXRFAZ/ZC
# J3LFI+ICOBpMIOLbAffNRk8monxmwFE2tokCVMf8WPtsAO7+mKYulaEMUykfb9gZ
# pk+e96wJ6l2CxouvgKe9gUhShDHaMuwV5KZMPWw5c9QLhTkg4IUaaOGnSDip0TYl
# d8GNGRbFiExmfS9jzpjoad+sPKhdnckcW67Y8y90z7h+9teDnRGWYpquRRPaf9xH
# +9/DUp/mBlXpnYzyOmJRvOwkDynUWICE5EV7WtgwggYaMIIEAqADAgECAhBiHW0M
# UgGeO5B5FSCJIRwKMA0GCSqGSIb3DQEBDAUAMFYxCzAJBgNVBAYTAkdCMRgwFgYD
# VQQKEw9TZWN0aWdvIExpbWl0ZWQxLTArBgNVBAMTJFNlY3RpZ28gUHVibGljIENv
# ZGUgU2lnbmluZyBSb290IFI0NjAeFw0yMTAzMjIwMDAwMDBaFw0zNjAzMjEyMzU5
# NTlaMFQxCzAJBgNVBAYTAkdCMRgwFgYDVQQKEw9TZWN0aWdvIExpbWl0ZWQxKzAp
# BgNVBAMTIlNlY3RpZ28gUHVibGljIENvZGUgU2lnbmluZyBDQSBSMzYwggGiMA0G
# CSqGSIb3DQEBAQUAA4IBjwAwggGKAoIBgQCbK51T+jU/jmAGQ2rAz/V/9shTUxjI
# ztNsfvxYB5UXeWUzCxEeAEZGbEN4QMgCsJLZUKhWThj/yPqy0iSZhXkZ6Pg2A2NV
# DgFigOMYzB2OKhdqfWGVoYW3haT29PSTahYkwmMv0b/83nbeECbiMXhSOtbam+/3
# 6F09fy1tsB8je/RV0mIk8XL/tfCK6cPuYHE215wzrK0h1SWHTxPbPuYkRdkP05Zw
# mRmTnAO5/arnY83jeNzhP06ShdnRqtZlV59+8yv+KIhE5ILMqgOZYAENHNX9SJDm
# +qxp4VqpB3MV/h53yl41aHU5pledi9lCBbH9JeIkNFICiVHNkRmq4TpxtwfvjsUe
# dyz8rNyfQJy/aOs5b4s+ac7IH60B+Ja7TVM+EKv1WuTGwcLmoU3FpOFMbmPj8pz4
# 4MPZ1f9+YEQIQty/NQd/2yGgW+ufflcZ/ZE9o1M7a5Jnqf2i2/uMSWymR8r2oQBM
# dlyh2n5HirY4jKnFH/9gRvd+QOfdRrJZb1sCAwEAAaOCAWQwggFgMB8GA1UdIwQY
# MBaAFDLrkpr/NZZILyhAQnAgNpFcF4XmMB0GA1UdDgQWBBQPKssghyi47G9IritU
# pimqF6TNDDAOBgNVHQ8BAf8EBAMCAYYwEgYDVR0TAQH/BAgwBgEB/wIBADATBgNV
# HSUEDDAKBggrBgEFBQcDAzAbBgNVHSAEFDASMAYGBFUdIAAwCAYGZ4EMAQQBMEsG
# A1UdHwREMEIwQKA+oDyGOmh0dHA6Ly9jcmwuc2VjdGlnby5jb20vU2VjdGlnb1B1
# YmxpY0NvZGVTaWduaW5nUm9vdFI0Ni5jcmwwewYIKwYBBQUHAQEEbzBtMEYGCCsG
# AQUFBzAChjpodHRwOi8vY3J0LnNlY3RpZ28uY29tL1NlY3RpZ29QdWJsaWNDb2Rl
# U2lnbmluZ1Jvb3RSNDYucDdjMCMGCCsGAQUFBzABhhdodHRwOi8vb2NzcC5zZWN0
# aWdvLmNvbTANBgkqhkiG9w0BAQwFAAOCAgEABv+C4XdjNm57oRUgmxP/BP6YdURh
# w1aVcdGRP4Wh60BAscjW4HL9hcpkOTz5jUug2oeunbYAowbFC2AKK+cMcXIBD0Zd
# OaWTsyNyBBsMLHqafvIhrCymlaS98+QpoBCyKppP0OcxYEdU0hpsaqBBIZOtBajj
# cw5+w/KeFvPYfLF/ldYpmlG+vd0xqlqd099iChnyIMvY5HexjO2AmtsbpVn0OhNc
# WbWDRF/3sBp6fWXhz7DcML4iTAWS+MVXeNLj1lJziVKEoroGs9Mlizg0bUMbOalO
# hOfCipnx8CaLZeVme5yELg09Jlo8BMe80jO37PU8ejfkP9/uPak7VLwELKxAMcJs
# zkyeiaerlphwoKx1uHRzNyE6bxuSKcutisqmKL5OTunAvtONEoteSiabkPVSZ2z7
# 6mKnzAfZxCl/3dq3dUNw4rg3sTCggkHSRqTqlLMS7gjrhTqBmzu1L90Y1KWN/Y5J
# KdGvspbOrTfOXyXvmPL6E52z1NZJ6ctuMFBQZH3pwWvqURR8AgQdULUvrxjUYbHH
# j95Ejza63zdrEcxWLDX6xWls/GDnVNueKjWUH3fTv1Y8Wdho698YADR7TNx8X8z2
# Bev6SivBBOHY+uqiirZtg0y9ShQoPzmCcn63Syatatvx157YK9hlcPmVoa1oDE5/
# L9Uo2bC5a4CH2RwwggZMMIIEtKADAgECAhAVVO/doV4MRRGuXmkecKnEMA0GCSqG
# SIb3DQEBDAUAMFQxCzAJBgNVBAYTAkdCMRgwFgYDVQQKEw9TZWN0aWdvIExpbWl0
# ZWQxKzApBgNVBAMTIlNlY3RpZ28gUHVibGljIENvZGUgU2lnbmluZyBDQSBSMzYw
# HhcNMjMwODA5MDAwMDAwWhcNMjYwODA4MjM1OTU5WjBjMQswCQYDVQQGEwJVUzEW
# MBQGA1UECAwNTmV3IEhhbXBzaGlyZTEdMBsGA1UECgwUQ2hyaXN0b3BoZXIgQ2hh
# cmxhbmQxHTAbBgNVBAMMFENocmlzdG9waGVyIENoYXJsYW5kMIICIjANBgkqhkiG
# 9w0BAQEFAAOCAg8AMIICCgKCAgEAwLQAcUKQzYs2WJY+W2fl+/1PzX3vsFwK/W9s
# j1RXRLBsQjsTCYRu+jRPEZSVzL/K4L877Wxb69/ye88/RrWS0d6LUyohl0OgJwgR
# BXBsDIcpt3hTv7GRLAFvjzcCOvK6qk+kjf+bxqYSUOxfl/XDK0QvM3KgWbq2IeNH
# oMwvAXVFBcZnRPXp1FkcHGKf+nNwxP6VGWtiRrhIj99q0R4iwOQaQLRY8pe8m1wn
# /gwFRai1F1f/Q2EMSyvbgf7kYpFNHJK17LZR9J/G7P8h4QFQZJdMU6C4lRT+Lk2j
# EDF4elKF5c7DFjfMv2zd0jf3/2vOhaycGna9puKwQUvtwtrmcCwOI5EXBIVBcFVS
# 8xD6eeREvzjZXiuS83quzwxVVjNBQ2f/nuK54huEBbNQQeNjSkMdjyr5S0Xwf8Pi
# c5NA4ggLUWuv2XYqTTMtXHQPZ41noEJM+LSBulBatGT98Tu0kib3MH7e1vREcTG7
# gZDnicmY0RfrWM59txft97gXP7Vj99ed9t2/9niQleiT+YXy3ZpNoqGFB3XC13mM
# 44xEff49vRSLN/B0IonG5vDpMgtFoKpqPtUx/oKQWtYbmoWFZkvEBRUeJOmkEmIU
# QonzE7aqgk/uGtyjxsBHtJzIHojA+8fGeD0NXjlOM1bbT0OcpSMkhRXPqiOELViM
# QwHrAiUCAwEAAaOCAYkwggGFMB8GA1UdIwQYMBaAFA8qyyCHKLjsb0iuK1SmKaoX
# pM0MMB0GA1UdDgQWBBSO6WwZWwCa6iKws6LE4InGvJQl3zAOBgNVHQ8BAf8EBAMC
# B4AwDAYDVR0TAQH/BAIwADATBgNVHSUEDDAKBggrBgEFBQcDAzBKBgNVHSAEQzBB
# MDUGDCsGAQQBsjEBAgEDAjAlMCMGCCsGAQUFBwIBFhdodHRwczovL3NlY3RpZ28u
# Y29tL0NQUzAIBgZngQwBBAEwSQYDVR0fBEIwQDA+oDygOoY4aHR0cDovL2NybC5z
# ZWN0aWdvLmNvbS9TZWN0aWdvUHVibGljQ29kZVNpZ25pbmdDQVIzNi5jcmwweQYI
# KwYBBQUHAQEEbTBrMEQGCCsGAQUFBzAChjhodHRwOi8vY3J0LnNlY3RpZ28uY29t
# L1NlY3RpZ29QdWJsaWNDb2RlU2lnbmluZ0NBUjM2LmNydDAjBggrBgEFBQcwAYYX
# aHR0cDovL29jc3Auc2VjdGlnby5jb20wDQYJKoZIhvcNAQEMBQADggGBAENPYZO6
# JkhXuprRcjFErvAggFDfB4bJmvHwydUUq8EEdDkvVvS+SnqpaL+Nw5FY/X5GnIXf
# WKYvQJFY1o/bskqLBSH96jOk+wMWZ2LqfuyEuW4OZUvBtpho2E2QwcpCQQzG47c+
# qtENC6lITctyoOUi5481cm9VXRL0E1g/MSDOqpYcd32oKt6rbqLQZD89HFgkNrfh
# 3a4wq2O8ljai9gvQJnYV4588DGI4quzv81b6mGDx9ku9zHhtvI19C1L+oQddqFFU
# ViSwUUiNrBO7aA5iFwr1vQPkiP40Zd6fSSQAjrRnUI/kbK9oD2l1i/Vi9hfQ8SLa
# rLPhW0M0qaut175+RJKlwuusUZADtgYVWcrmMxy20RMCUZA2bnTWXjb4pVfHUyKP
# U7dpM+8gG/tUPBZegMWrzWqctSPQhdREpkLTMCm5E/o4ZUGNE0uo+twbGMGEyPPm
# jsFnIKLAqN2rHMI1Fz9pR+qMdixl+/mG/ElSJqGSDVArmZLn1IYhr4vQ8DCCBoIw
# ggRqoAMCAQICEDbCsL18Gzrno7PdNsvJdWgwDQYJKoZIhvcNAQEMBQAwgYgxCzAJ
# BgNVBAYTAlVTMRMwEQYDVQQIEwpOZXcgSmVyc2V5MRQwEgYDVQQHEwtKZXJzZXkg
# Q2l0eTEeMBwGA1UEChMVVGhlIFVTRVJUUlVTVCBOZXR3b3JrMS4wLAYDVQQDEyVV
# U0VSVHJ1c3QgUlNBIENlcnRpZmljYXRpb24gQXV0aG9yaXR5MB4XDTIxMDMyMjAw
# MDAwMFoXDTM4MDExODIzNTk1OVowVzELMAkGA1UEBhMCR0IxGDAWBgNVBAoTD1Nl
# Y3RpZ28gTGltaXRlZDEuMCwGA1UEAxMlU2VjdGlnbyBQdWJsaWMgVGltZSBTdGFt
# cGluZyBSb290IFI0NjCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAIid
# 2LlFZ50d3ei5JoGaVFTAfEkFm8xaFQ/ZlBBEtEFAgXcUmanU5HYsyAhTXiDQkiUv
# pVdYqZ1uYoZEMgtHES1l1Cc6HaqZzEbOOp6YiTx63ywTon434aXVydmhx7Dx4IBr
# Aou7hNGsKioIBPy5GMN7KmgYmuu4f92sKKjbxqohUSfjk1mJlAjthgF7Hjx4vvyV
# DQGsd5KarLW5d73E3ThobSkob2SL48LpUR/O627pDchxll+bTSv1gASn/hp6IuHJ
# orEu6EopoB1CNFp/+HpTXeNARXUmdRMKbnXWflq+/g36NJXB35ZvxQw6zid61qmr
# lD/IbKJA6COw/8lFSPQwBP1ityZdwuCysCKZ9ZjczMqbUcLFyq6KdOpuzVDR3ZUw
# xDKL1wCAxgL2Mpz7eZbrb/JWXiOcNzDpQsmwGQ6Stw8tTCqPumhLRPb7YkzM8/6N
# nWH3T9ClmcGSF22LEyJYNWCHrQqYubNeKolzqUbCqhSqmr/UdUeb49zYHr7ALL8b
# AJyPDmubNqMtuaobKASBqP84uhqcRY/pjnYd+V5/dcu9ieERjiRKKsxCG1t6tG9o
# j7liwPddXEcYGOUiWLm742st50jGwTzxbMpepmOP1mLnJskvZaN5e45NuzAHteOR
# lsSuDt5t4BBRCJL+5EZnnw0ezntk9R8QJyAkL6/bAgMBAAGjggEWMIIBEjAfBgNV
# HSMEGDAWgBRTeb9aqitKz1SA4dibwJ3ysgNmyzAdBgNVHQ4EFgQU9ndq3T/9ARP/
# FqFsggIv0Ao9FCUwDgYDVR0PAQH/BAQDAgGGMA8GA1UdEwEB/wQFMAMBAf8wEwYD
# VR0lBAwwCgYIKwYBBQUHAwgwEQYDVR0gBAowCDAGBgRVHSAAMFAGA1UdHwRJMEcw
# RaBDoEGGP2h0dHA6Ly9jcmwudXNlcnRydXN0LmNvbS9VU0VSVHJ1c3RSU0FDZXJ0
# aWZpY2F0aW9uQXV0aG9yaXR5LmNybDA1BggrBgEFBQcBAQQpMCcwJQYIKwYBBQUH
# MAGGGWh0dHA6Ly9vY3NwLnVzZXJ0cnVzdC5jb20wDQYJKoZIhvcNAQEMBQADggIB
# AA6+ZUHtaES45aHF1BGH5Lc7JYzrftrIF5Ht2PFDxKKFOct/awAEWgHQMVHol9ZL
# Syd/pYMbaC0IZ+XBW9xhdkkmUV/KbUOiL7g98M/yzRyqUOZ1/IY7Ay0YbMniIibJ
# rPcgFp73WDnRDKtVutShPSZQZAdtFwXnuiWl8eFARK3PmLqEm9UsVX+55DbVIz33
# Mbhba0HUTEYv3yJ1fwKGxPBsP/MgTECimh7eXomvMm0/GPxX2uhwCcs/YLxDnBdV
# VlxvDjHjO1cuwbOpkiJGHmLXXVNbsdXUC2xBrq9fLrfe8IBsA4hopwsCj8hTuwKX
# JlSTrZcPRVSccP5i9U28gZ7OMzoJGlxZ5384OKm0r568Mo9TYrqzKeKZgFo0fj2/
# 0iHbj55hc20jfxvK3mQi+H7xpbzxZOFGm/yVQkpo+ffv5gdhp+hv1GDsvJOtJinJ
# mgGbBFZIThbqI+MHvAmMmkfb3fTxmSkop2mSJL1Y2x/955S29Gu0gSJIkc3z30vU
# /iXrMpWx2tS7UVfVP+5tKuzGtgkP7d/doqDrLF1u6Ci3TpjAZdeLLlRQZm867eVe
# XED58LXd1Dk6UvaAhvmWYXoiLz4JA5gPBcz7J311uahxCweNxE+xxxR3kT0WKzAS
# o5G/PyDez6NHdIUKBeE3jDPs2ACc6CkJ1Sji4PKWVT0/MIIGpzCCBI+gAwIBAgIR
# AJCsCHIg/cWnxGtcxw33PQYwDQYJKoZIhvcNAQEMBQAwVzELMAkGA1UEBhMCR0Ix
# GDAWBgNVBAoTD1NlY3RpZ28gTGltaXRlZDEuMCwGA1UEAxMlU2VjdGlnbyBQdWJs
# aWMgVGltZSBTdGFtcGluZyBSb290IFI0NjAeFw0yNjAzMjUwMDAwMDBaFw00MTAz
# MjQyMzU5NTlaMFUxCzAJBgNVBAYTAkdCMRgwFgYDVQQKEw9TZWN0aWdvIExpbWl0
# ZWQxLDAqBgNVBAMTI1NlY3RpZ28gUHVibGljIFRpbWUgU3RhbXBpbmcgQ0EgUjQx
# MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAruRKogGtghxi+WYtW5oD
# zPDVF8GGSfgbUKh6bONxi0wvrI1S8qbAYfvLr/ky5ILVRg//70pgNKq8xC3/WEQo
# djEwAP2hmkGShoNAUQps4kd6Wwp74Fo7RlwQ1Mp949ytpWQDvCsYBbZccDmBAJC/
# ggqiuL/c805fGcMw6TzIgyBWuUx5PGp9YnheSNPXFzaz0MPtREdZYk4WhtM+hazq
# asMWVpj0WUAcNhN9vO/FAdWy9Gafdb7lmYLDKTTYjwqAY9P9RfixPPjUaJH6mnBS
# NBdrX7a0Qdlux0ApS0fc48RW1m+W3tq3HiHzch1FHyhiLzCNjc6MUpcV5xalBvPO
# w/FtQo/AxaJOvPCSsVrx0f/WkMpEm3fvVbrY9+oo9rIKv9ducE6VGfwIAtKYedG0
# bO4Ba1MmlxPcErDqjLwggvrBJu73fwXpkhtE0hzV0psgm2vhQs3pHll9N00SHBdy
# 2qndEcNuDh+46XouM2hoXCO533YQQOHPEUnMTWOo3hyxx5kjDE5PVqp+x+HS4VAT
# +WBMG4GzeLr9YvZbU5x5YvLdcR1dErV/QRYK55rp019fZFF2NR+TkSW0WcmQ3b5t
# aGcrXg49EpzKM6/mEpnSJXg1E13X6GO29rWs/LNvkGzsS8XGoRCGBls6ruofeebS
# sHADR3GeIE5gIU927bjokLECAwEAAaOCAW4wggFqMB8GA1UdIwQYMBaAFPZ3at0/
# /QET/xahbIICL9AKPRQlMB0GA1UdDgQWBBQ6dKUMZ8ZCUML9tfzHuyk0gvR6uTAO
# BgNVHQ8BAf8EBAMCAYYwEgYDVR0TAQH/BAgwBgEB/wIBADATBgNVHSUEDDAKBggr
# BgEFBQcDCDAjBgNVHSAEHDAaMAgGBmeBDAEEAjAOBgwrBgEEAbIxAQIBAwgwTAYD
# VR0fBEUwQzBBoD+gPYY7aHR0cDovL2NybC5zZWN0aWdvLmNvbS9TZWN0aWdvUHVi
# bGljVGltZVN0YW1waW5nUm9vdFI0Ni5jcmwwfAYIKwYBBQUHAQEEcDBuMEcGCCsG
# AQUFBzAChjtodHRwOi8vY3J0LnNlY3RpZ28uY29tL1NlY3RpZ29QdWJsaWNUaW1l
# U3RhbXBpbmdSb290UjQ2LnA3YzAjBggrBgEFBQcwAYYXaHR0cDovL29jc3Auc2Vj
# dGlnby5jb20wDQYJKoZIhvcNAQEMBQADggIBADLeUkdm8Z4DZvjfKHOhqu+hsdXN
# t+X5F+48PB6PTAJCRgA3qxxO3YbAV7baps4K/+2WWoWUspBkT4T2NXK49NvJAfCs
# ztHSgtqkAQMLX4KjCypJF/+m2Ktrk993g+gcgKdv1yg9C3JmYdJCnnL0ga+pZ/Wo
# 1+rtXZ8dnwO8RCstTN6gYX0ElFi7Y7NpxbdBC1S6bc05V/SA9HC/ojj33W6Gdwnp
# U/iVylSkdkoHtHeGIhQLT2ZH0qPM9Wdce8v2fZsDCJQQJ8rll7OGLDbsXa2CLf0M
# RN9TwzifQ3rEuAXOx/TkzkZRFfwL34hf1XqSmaYq2tTMy2LgsPrqC2Z/6ZKb3fgr
# zU0vphB4wSTWulitY/KlxbvoyKvrBvUCCx4sgeqf8aR65CbvM5MN/d/lahfXipU2
# NlY0cXcnGS61XpmeGKd8It92/lufApZR9x6o5qMJWe0jq4JsfGMGDpIKx7FzkB8g
# aejuBUW/CJ9Phc40+xJRonvVewn4S9yJVRWeM47irGbR9YlN3xruM/yZzhk+rAm9
# AW06nv7ob6RQkAXR+cTxiAPy620FF41NrViYB4UyKpzfx7x8jh4ubTOMz954YIdq
# yeiqqtsbBwXjWLP0dfMUPA3iIPnPdBKGnodGJTdSlPAMmKJdyvTPqmOXs/LMnf+2
# Za0Z6FXsIB9z9aXLMIIG4jCCBMqgAwIBAgIRAOdO8lWwUE/626bf9/yLoxUwDQYJ
# KoZIhvcNAQEMBQAwVTELMAkGA1UEBhMCR0IxGDAWBgNVBAoTD1NlY3RpZ28gTGlt
# aXRlZDEsMCoGA1UEAxMjU2VjdGlnbyBQdWJsaWMgVGltZSBTdGFtcGluZyBDQSBS
# NDEwHhcNMjYwMzI1MDAwMDAwWhcNMzcwNjI0MjM1OTU5WjByMQswCQYDVQQGEwJH
# QjEXMBUGA1UECBMOR3JlYXRlciBMb25kb24xGDAWBgNVBAoTD1NlY3RpZ28gTGlt
# aXRlZDEwMC4GA1UEAxMnU2VjdGlnbyBQdWJsaWMgVGltZSBTdGFtcGluZyBTaWdu
# ZXIgUjM3MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAsv/DbUvcUNlF
# LQURd9m4+1St5+JudFKo5P803Iks4mFeNB9SymodP6BJJWBuNhOFQj9w77AVAeg5
# qQpA2dIwp2QTyBHr2h9eWSTkMBVj9mV6+WI5SaW+vDZW7PhJTbysd9v9WB3Xt6ql
# Ei8m47pcTy8+k/OfhziKiuzNQXqfC7KcoRD/6up8OZBsU0qxr7n5nh/iRfAp1QXF
# TBQONBZSGIdHAyVRYYX033VoC8v71rizEKCpH97Pxbwcn9eq9K7W8h5v4npsMUoq
# CS/c8mQwylDQGx15dHYV6NlcVFdjXD11l7qCrIy/unH5OlZtgx58QJRXRbGgQyBd
# STpEpwuj3i5Qc52Z9m7hd7yCGCXKujf83hUQpOPx1w8+84EbEUTHVAfq4cpORaGW
# gY8NJy6txmd3wpS1MeXrOaVAMczTgzAZ+yZBWIqdgQBgTxEeXldEToZOrRkxvn1I
# jIlfr4I4NWJz+Rb52FshLVnkA/wdoad789Eb7XZDNKd4oMmnc636TgauaaVZP2LL
# oU0JD/fYr53hwBn4uXu5ZsSfpnqAT60S7szJm/Na882xEoyRzLJ+UVbXOlHLO63D
# KkAtdz1CDuwWxgRE1drnwplepT06dz+1yTr5p1AkUz21bzE6cT/8/kjh4OPzggYY
# qrOBQPfuKEL5ZJPcN9jRgEpYvRlq5ucCAwEAAaOCAY4wggGKMB8GA1UdIwQYMBaA
# FDp0pQxnxkJQwv21/Me7KTSC9Hq5MB0GA1UdDgQWBBRhEOl6Eq9RxIXU8s+kdA9Q
# zSCv+DAOBgNVHQ8BAf8EBAMCBsAwDAYDVR0TAQH/BAIwADAWBgNVHSUBAf8EDDAK
# BggrBgEFBQcDCDBKBgNVHSAEQzBBMAgGBmeBDAEEAjA1BgwrBgEEAbIxAQIBAwgw
# JTAjBggrBgEFBQcCARYXaHR0cHM6Ly9zZWN0aWdvLmNvbS9DUFMwSgYDVR0fBEMw
# QTA/oD2gO4Y5aHR0cDovL2NybC5zZWN0aWdvLmNvbS9TZWN0aWdvUHVibGljVGlt
# ZVN0YW1waW5nQ0FSNDEuY3JsMHoGCCsGAQUFBwEBBG4wbDBFBggrBgEFBQcwAoY5
# aHR0cDovL2NydC5zZWN0aWdvLmNvbS9TZWN0aWdvUHVibGljVGltZVN0YW1waW5n
# Q0FSNDEuY3J0MCMGCCsGAQUFBzABhhdodHRwOi8vb2NzcC5zZWN0aWdvLmNvbTAN
# BgkqhkiG9w0BAQwFAAOCAgEAA+o9jdGszfoZepOmygef1OlbkjrPd2QW9z3M8vVb
# QSCruPeO2eRsC9GhZ4CMZfhkrixayYD67gQkbyiRCbJu5L/i0NQjlQhBvbWfiEba
# +KHFKGud5YHRWhDZUtDeMIJGZG0BD7/sftZUo2Ifk+CXi/ZlM50+xK3OkqeXVi5G
# ubDD/5txmYuqCT3T3LAilmoB+5th9sQxiMhyQuT3R/aYb4vypoZJLYklUzTalXle
# W1nV9s4UROlE389CHDKAi/fepRSMnV8TghODDQxwzNGrOJZ04k/yhzHHDupfHPU5
# 1FYJqXIvWq9SAAWdlNV1JGIxhkp/TAtxBwz/Vd/VbgVb2d9/wRFfxFkka39O0+4x
# aZSl/oEK/1DqjxjJRO2Se9lGlJDScu21Zd23Cys3aYyB8y5H/+DFWtVe8PMKgr+V
# uIDp0Rk5bneVDAEW0TPAT8Ufwl2F6DJiDg/KZk5NmsYES+CxvF7bnISEnQh0ZrWn
# AJixquV0mElUx01wA5TuPIgyodxzNq/fC0hen9LBtdnfFfSZ+wt8A1Injsbio+DH
# Vq1voYiVNpBfO7+nh9NB4AhRXNldPgr3zgjJ+47s0uNYy2iDXAZSlkP3ym/7gy31
# jlu989SNpRWO14/LUNV2LSuXkRI1iLTPI6ZdXG0DnPPG7UftF0tk5m6BP9eNfr2t
# j1sxggZBMIIGPQIBATBoMFQxCzAJBgNVBAYTAkdCMRgwFgYDVQQKEw9TZWN0aWdv
# IExpbWl0ZWQxKzApBgNVBAMTIlNlY3RpZ28gUHVibGljIENvZGUgU2lnbmluZyBD
# QSBSMzYCEBVU792hXgxFEa5eaR5wqcQwDQYJYIZIAWUDBAIBBQCggYQwGAYKKwYB
# BAGCNwIBDDEKMAigAoAAoQKAADAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAc
# BgorBgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQg9WQb
# s7cWrI64q9FEaPdXqygA+77aUNDqI+bU360RPLgwDQYJKoZIhvcNAQEBBQAEggIA
# U4R/jTS1ItbX8KDce2vQFTe+QqO13LUa4BPJCjjCFnR2O+cuuzr8M7T7ulSPYz9u
# fkL775JH5Z1QshS95qBXsur4eCXLVPMcOu4gi4cZGdm4e6KGy9105g+kt/esy/Of
# SYnHfD5TSHvcTuVLomHQU59iixn+HsllUAgNa5HXIIwZlGdUvFMF4HfrxLp8wTtd
# 7QztVohuFrUafApXzO68IBUBZKnh9jvgp2R0nZ4VnMsVUGFEkDALPp8hJftb1L2K
# jip5DNIUCaBOGgKl9i+jBINh4qDVbGSIa88x6gmjqRUzxnBDXrJaQVv72veSTrDN
# b50UfITvfz9OHFwS7oZgp/0Vh0Im26uFduJRdPLyfO9HM9VdI6hIrYixo4rNg8Xo
# kDo1dlWvfUUrAf1dicENO3qyD0OSs0UZRABjmWVtZJ6M39RTpIE7teBoxzHCo23W
# FjAXOanSxg0k0wQySsfoCNdLNc2HrB9SP/RKKoMeqsR84v3esPt8a557z6zipBw7
# 7/fmyZGX+7S7c4zFXPVRMuzrRgrhY/L+TdLAx7mZXNZIY9dRfTx3LYtiblgBgnUY
# tMVINjN5Imrk+I5KpmH56ntFvBdsHDprzqpCwDf94CsNnzQ0KTj0pI1lVqTaMcJa
# Cv7BaiVnTcM3V7uvKgGq9+H75TrbBUC3ng8LlVMdpUihggMjMIIDHwYJKoZIhvcN
# AQkGMYIDEDCCAwwCAQEwajBVMQswCQYDVQQGEwJHQjEYMBYGA1UEChMPU2VjdGln
# byBMaW1pdGVkMSwwKgYDVQQDEyNTZWN0aWdvIFB1YmxpYyBUaW1lIFN0YW1waW5n
# IENBIFI0MQIRAOdO8lWwUE/626bf9/yLoxUwDQYJYIZIAWUDBAICBQCgeTAYBgkq
# hkiG9w0BCQMxCwYJKoZIhvcNAQcBMBwGCSqGSIb3DQEJBTEPFw0yNjA3MDUyMzU3
# NDdaMD8GCSqGSIb3DQEJBDEyBDAxQ/exjv533WlyzalgEvTRXct191Fge3LtVoCD
# otl/cYl0KLJQsZxewQzxJCxyKMYwDQYJKoZIhvcNAQEBBQAEggIAUnlQbViduGuk
# F5oT14bG5S23DAwfHPOsnSFNNVYZ0jAjwWYc6vYheKZ9j5rBQbE8k7Qm+zopc5US
# /NIJWBrMRtHglYUusZlyAAGYE6v8aJBOOW4jYDSMcn/u0DA+X7NEKdnTFZhsKWt/
# jCi/xBGCK+Hu7HDI0ZkDIsMqA7uniQzfezkxsrObCi7R6zuuCikdelsmAZtk3tpM
# Z0RAnCQjGyjGeCLrJs1zagHc+g+h58SgNY5wyDF7+9xYQl3RUts+FOQLcAHB49ti
# R4RMUTG2ODrBgWsQfVYSAG4ofw8keD+ozaI8kPJAsmrK2AMBhX4Elu1JKeXqYgAb
# qtcfRrZ8+CJM+6oisKz345NSscEL/Mg0k71Zsump+4+BRXc4kZkUzzJxIGWwJE/D
# M7eakaLHeon2Yv6FE8Ga4hT0XaP802UERICT1AVj1VMdLPtDbPd2i0GENMbNVBWr
# rPHsAVSeEN2WWsJnPO7tLM+hyY7JYuvVK3CFg6ASTsC0qOzw1cqVBG7K4EBkkLoY
# P/ZStp33vnRpuPYGOnLJ6umHZ421Y+qdjziQlk2F8Q5rDlgSMRUHS5bnOY4xKwiy
# GD84n+KxZXwziZINp1qFHHWw/rSkNBwaAIE9U7g4Gz1+VWPOXiHaw09Bd+XzSrpS
# QKD7zdq4KPEqnrjP76hVgHG2reQIJso=
# SIG # End signature block
