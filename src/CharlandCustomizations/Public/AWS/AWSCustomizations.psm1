<#
.SYNOPSIS
    AWS PowerShell Customizations and scripts.
#>
Write-Verbose  "Loading AWSCustomizations.psm1"

# Load private helper functions needed by this nested module (added by Kiro, aws-common-params spec)
. "$PSScriptRoot/../../Private/New-AWSParamSplat.ps1"

# Module-level cache for SSO tokens to avoid repeated authentication
$script:SSOTokenCache = @{}
function  Get-CHARAWSMFASession {
  <#
  .SYNOPSIS
    Changes your active AWS connection to a temporary session using MFA Authentiation.
  .DESCRIPTION
    Retrieves temporary STS session credentials by authenticating with a one-time MFA token code.
    Returns credentials that can be passed to Set-AWSCredential.
  .EXAMPLE
    PS C:\> Set-AWSCredential -Credential (Get-CHARAWSMFASession -TokenCode <OTP>)

    Changes your active AWS session to one authenticated with MFA.
  #>
  param(
    [Parameter(mandatory = $true)]
    [string]$TokenCode
  )
  return Get-STSSessionToken -SerialNumber (Get-IAMMFADevice).SerialNumber -TokenCode $TokenCode
}


function Find-CHARCFNStackError {
  <#
.SYNOPSIS
   Finds Stacks and resources in an "error state".
.DESCRIPTION
    Script reports any stack or resource where "StatusReason" has a non-null value
.EXAMPLE
    PS C:\> Find-CHARCFNStackError

StackName  StackStatus              StackStatusReason
---------  -----------              -----------------
Stack1     UPDATE_ROLLBACK_COMPLETE Update successful. One or more resources could not be deleted.
Stack2     UPDATE_ROLLBACK_COMPLETE Update successful. One or more resources could not be deleted.
Stack3     UPDATE_ROLLBACK_COMPLETE Update successful. One or more resources could not be deleted.

Resources causing StackErrors

StackName ResourceStatus  LogicalResourceId ResourceStatusReason
--------- --------------  ----------------- --------------------
Stack4    UPDATE_COMPLETE ALambdaFunction   Resource skipped during UpdateRollback

.PARAMETER Region
    AWS region. If not specified, will use your default Region.

.PARAMETER ProfileName
    AWS profile name. Optional.

.PARAMETER AccessKey
    AWS access key. Optional.

.PARAMETER SecretKey
    AWS secret key. Optional.

.PARAMETER SessionToken
    AWS session token for temporary credentials. Optional.

.PARAMETER Credential
    Pre-built AWS credential object. Optional.

.PARAMETER ProfileLocation
    Custom credential file path. Optional.

.PARAMETER EndpointUrl
    Custom AWS service endpoint URL. Optional.
#>

  [CmdletBinding()]
  param (
    [Parameter()]
    [string]$RootStackName = $Null,

    # AWS common parameters
    [Parameter()]
    [string]$Region,

    [Parameter()]
    [string]$ProfileName,

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
    $awsParams = New-AWSParamSplat -BoundParameters $PSBoundParameters
  }

  process {
    Write-Output "Checking Stacks in:  $($Region) for account $($(Get-STSCallerIdentity @awsParams).Account)"

    if ([string]::IsNullOrEmpty($RootStackName) ) {
      Write-Verbose  "looking at all stacks"
      $StackList = Get-CFNStack @awsParams

    }
    else {
      Write-Verbose "looking for child stacks"
      $StackList = Get-CFNStack @awsParams | Where-Object RootId -eq (Get-CFNStack @awsParams -StackName $RootStackName).StackId
      $StackList += Get-CFNStack @awsParams -StackName $RootStackName

    }

    Write-Verbose  "stacklist.count $(($Stacklist).count)"

    $StacksWithErrors = $Stacklist | Where-Object StackStatusReason

    if ($stackswithErrors.count -gt 0) {
      Write-Output "Stacks in error state"
      $StacksWithErrors | Select-Object StackName, StackStatus, StackStatusReason | Format-Table  -AutoSize
    }
    else {
      Write-Output "No stacks in error state"
    }

    Write-Output "Resources with Errors:"
    foreach ($Stack in $StacksWithErrors.StackName) {
      Get-CFNStackResourceSummary @awsParams -StackName $Stack | Where-Object ResourceStatusReason | `
        Select-Object @{Name = "StackName"; Expression = { $Stack } }, ResourceStatus, LogicalResourceId, ResourceStatusReason | Format-Table -Autosize
    }
  }
}


function Set-CHARAWSProfileWithMFA {
  <#
.SYNOPSIS
    Retrieves temporary STS session credentials using MFA authentication.

.DESCRIPTION
    Authenticates against an AWS profile using a one-time MFA token code and returns
    temporary STS session credentials. The returned credentials can be used with
    Set-AWSCredential to establish a session.

.PARAMETER ProfileName
    The AWS credential profile to authenticate with MFA.

.PARAMETER TokenCode
    The one-time password (OTP) from your MFA device.

.PARAMETER Region
    AWS region. If not specified, uses the session default from Get-DefaultAWSRegion.

.PARAMETER AccessKey
    AWS access key. Optional.

.PARAMETER SecretKey
    AWS secret key. Optional.

.PARAMETER SessionToken
    AWS session token for temporary credentials. Optional.

.PARAMETER Credential
    Pre-built AWS credential object. Optional.

.PARAMETER ProfileLocation
    Custom credential file path. Optional.

.PARAMETER EndpointUrl
    Custom AWS service endpoint URL. Optional.

.EXAMPLE
    PS C:\> Set-AWSCredential -Credential (Set-CHARAWSProfileWithMFA -ProfileName myprofile -TokenCode 123456)

    Authenticates with MFA and sets the returned credentials as the active session.

.EXAMPLE
    PS C:\> Set-CHARAWSProfileWithMFA -ProfileName myprofile -TokenCode 123456 -Region us-east-1

    Retrieves MFA session credentials for a specific region.
#>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This function returns temporary credentials and sets AWS profile context only as an AWS.Tools prerequisite.')]
  [CmdletBinding()]
  param (
    [Parameter(Mandatory)]
    [string]$ProfileName,

    [Parameter(Mandatory)]
    [string]$TokenCode,

    # AWS common parameters
    [Parameter()]
    [string]$Region,

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
    # If Region not specified, fall back to session default
    if (-not $Region) {
      $Region = (Get-DefaultAWSRegion).Region
      if ($Region) {
        $PSBoundParameters['Region'] = $Region
      }
    }

    $awsParams = New-AWSParamSplat -BoundParameters $PSBoundParameters
  }

  process {
    # Set-AWSCredential to call Get-IAMMFADevice (AWS bug - see https://github.com/aws/aws-tools-for-powershell/issues/106)
    Set-AWSCredential -ProfileName $ProfileName
    # Set-AWSCredential -Credential (Get-STSSessionToken @awsParams -SerialNumber (Get-IAMMFADevice @awsParams).SerialNumber -TokenCode $TokenCode)
    # above goal.. but you have to run set-AWSCredential manually

    return Get-STSSessionToken @awsParams -SerialNumber (Get-IAMMFADevice @awsParams).SerialNumber -TokenCode $TokenCode
  }
}

function Set-CHARAWSEnv {
  <#
.SYNOPSIS
  Sets AWS Credential variables for use with command line tools
.DESCRIPTION
  Sets environment variables for Access key, secret key, token,
  default region based on the results of Get-AWSCredential and Get-DefaultAWSRegion.

  This function modifies environment variables and supports -WhatIf and -Confirm.

.PARAMETER Force
  Skip confirmation prompts

.EXAMPLE
  PS> Set-CHARAWSEnv
  Sets AWS environment variables from current credential

.EXAMPLE
  PS> Set-CHARAWSEnv -WhatIf
  Shows what environment variables would be set without actually setting them

.EXAMPLE
  PS> Set-CHARAWSEnv -Confirm:$false
  Sets environment variables without confirmation

.NOTES
  Requires an active AWS credential to be set via Set-AWSCredential
#>
  [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
  param(
    [switch]$Force
  )

  try {
    $creds = (Get-AWSCredential -ErrorAction Stop).GetCredentials()
  }
  catch {
    Write-Error -Message "AWSCredential not set. Run Set-AWSCredential first." -Category InvalidOperation
    return
  }

  if (-not $creds) {
    Write-Error -Message "AWSCredential not set. Run Set-AWSCredential first." -Category InvalidOperation
    return
  }

  # Get caller identity for display
  try {
    $identity = Get-STSCallerIdentity -ErrorAction Stop
    $identityInfo = "Account: $($identity.Account), User: $($identity.Arn)"
  }
  catch {
    $identityInfo = "Unable to retrieve caller identity"
  }

  # Get region
  $region = (Get-DefaultAWSRegion).Region

  # Prepare the changes
  $changes = @(
    "AWS_ACCESS_KEY_ID = $($creds.AccessKey.Substring(0, 4))..."
    "AWS_DEFAULT_REGION = $region"
    "AWS_SECRET_ACCESS_KEY = [REDACTED]"
  )

  if ($creds.UseToken) {
    $changes += "AWS_SESSION_TOKEN = [REDACTED]"
  }
  else {
    $changes += "AWS_SESSION_TOKEN = [CLEARED]"
  }

  $changeDescription = "Setting AWS environment variables for: $identityInfo"

  if ($Force -or $PSCmdlet.ShouldProcess($changeDescription, "Set environment variables")) {
    Write-Verbose "Setting AWS environment variables"

    $env:AWS_ACCESS_KEY_ID = $creds.AccessKey
    $env:AWS_DEFAULT_REGION = $region
    $env:AWS_SECRET_ACCESS_KEY = $creds.SecretKey

    if ($creds.UseToken) {
      $env:AWS_SESSION_TOKEN = $creds.Token
    }
    else {
      $env:AWS_SESSION_TOKEN = $null
    }

    Write-Host "AWS environment variables set successfully" -ForegroundColor Green
    Write-Host "  Account: $($identity.Account)" -ForegroundColor Cyan
    Write-Host "  Region: $region" -ForegroundColor Cyan
    Write-Host "  Access Key: $($creds.AccessKey.Substring(0, 4))..." -ForegroundColor Cyan

    if ($creds.UseToken) {
      Write-Host "  Session Token: Set (temporary credentials)" -ForegroundColor Cyan
    }
  }
  else {
    Write-Verbose "Operation cancelled by user"
  }
}
function Remove-CHARExpiredAWSProfile {
  <#
  .SYNOPSIS
    Removes expired temporary credentials stored in local credential stores.
  .DESCRIPTION
    Tests all AWS Profiles by calling Get-STSCallerIdentity. If the call fails with an
    ExpiredToken error, the profile is removed from the credential store.
  .EXAMPLE
    Remove-CHARExpiredAWSProfile
    Scans all profiles with a credential file location and removes any with expired tokens.
  #>
  [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
  param()

  Get-AWSCredential -ListProfileDetail | Where-Object ProfileLocation | ForEach-Object {
    $profileItem = $_
    try {
      Set-AWSCredential -ProfileName $profileItem.ProfileName
      Get-STSCallerIdentity -ErrorAction Stop | Out-Null
    }
    catch {
      if ($_.Exception.Message -match 'ExpiredToken') {
        Write-Verbose "Removing expired profile: $($profileItem.ProfileName)"
        if ($PSCmdlet.ShouldProcess("AWS profile '$($profileItem.ProfileName)'", 'Remove expired credential profile')) {
          Remove-AWSCredentialProfile -ProfileName $profileItem.ProfileName
        }
      }
      else {
        Write-Verbose "Profile '$($profileItem.ProfileName)' failed with non-expired error: $_"
      }
    }
  }
}
function Get-CHARAccountListFromProfile {
  <#
  .SYNOPSIS
    Lists  AWS ProfileName, Account, and AccountAlias
  .DESCRIPTION
    Enumerates all locally stored AWS credential profiles and retrieves the associated
    account ID and account alias for each by calling Get-STSCallerIdentity and Get-IAMAccountAlias.
  .EXAMPLE
    PS C:\> Get-CHARAccountListFromProfile

    ProfileName  Account       AccountAlias
    -----------  -------       ------------
    default      123456789012  my-account
  #>
  Get-AWSCredential -ListProfileDetail  | ForEach-Object { Select-Object -InputObject $_   Profilename, @{Name = "Account"; Expression = { (Get-STSCallerIdentity -ProfileName  $_.ProfileName).Account } }, @{Name = "AccountAlias"; Expression = { Get-IAMAccountAlias -ProfileName  $_.ProfileName } } }
}

function Start-CHARMultiStackDriftDetection {
  <#
.SYNOPSIS
  Detects drift on all stacks passed into the function
.DESCRIPTION
  Start-CHARMultiStackDriftDetection  will detect Stack drift on all stack names passed into it,
  and will bypass the stacks that it doesn't make sense to do the drift detection on.

.EXAMPLE
  PS C:\> (Get-CFNstack).StackName |Select-Object -first 5  |Start-CHARMultiStackDriftDetection
  Starts a drift detection of the first 5 stacks listed.

.EXAMPLE
PS C:\> Start-CHARMultiStackDriftDetection

Does stack drift detection on all stacks within a region.

.PARAMETER StackName
Stackname or list of stackNames to start

.PARAMETER Region
    AWS region. If not specified, will use your default Region.

.PARAMETER ProfileName
    AWS profile name. Optional.

.PARAMETER AccessKey
    AWS access key. Optional.

.PARAMETER SecretKey
    AWS secret key. Optional.

.PARAMETER SessionToken
    AWS session token for temporary credentials. Optional.

.PARAMETER Credential
    Pre-built AWS credential object. Optional.

.PARAMETER ProfileLocation
    Custom credential file path. Optional.

.PARAMETER EndpointUrl
    Custom AWS service endpoint URL. Optional.
#>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This orchestrator intentionally starts drift detection operations across stacks.')]
  [CmdletBinding()]
  param (
    [Parameter(valueFromPipeline = $true, ValueFromRemainingArguments)]
    [string[]]$StackName = $null,

    # AWS common parameters
    [Parameter()]
    [string]$Region,

    [Parameter()]
    [string]$ProfileName,

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
    $awsParams = New-AWSParamSplat -BoundParameters $PSBoundParameters

    if ($NULL -eq $stackname) {
      #call Get-CFNstack not Get-CFNstacksummary -- don't care about deleted stacks
      $stackname = (Get-CFNstack @awsParams).StackName
    }
    # nothing but debug messages
    $message = "stackname count " + $StackName.count
    Write-Verbose $message
  }

  process {
    $total = $stackname.count
    $i = 0

    foreach ($Item in $stackname) {
      $i++
      Write-Progress -Activity "Checking Stack" -CurrentOperation "$Item" -PercentComplete ($i / $total * 100)
      $message = "Starting  " + $Item
      Write-Verbose $message

      $StackInfo = Get-CFNstack @awsParams -stackname $Item
      # can't do a drift check if stack is in below states:
      if ($StackInfo.StackStatus -in "ROLLBACK_COMPLETE", "DELETE_FAILED", "ROLLBACK_FAILED") {
        Write-Verbose "$($StackInfo.stackName) in status  $($StackInfo.StackStatus) drift-detection not applicable"
      }
      else {
        $DetectStatus = $NULL
        try {
          $DetectStatus = Start-CFNStackDriftDetection @awsParams -StackName $Item -Select '*' -ErrorAction Stop
        }
        catch {
          Write-Error "Stack drift detection failed for '$Item': $($_.Exception.Message)"
          if ($DebugPreference -ne "SilentlyContinue") {
            $_ | Format-List -Force
            break
          }
          continue
        }
        Write-Verbose "Started drift detection for $($StackInfo.stackName)"
        $SleepTimer = 2
        if ($DetectStatus) {
          do {
            Write-Verbose "Waiting for detection to finish for $($StackInfo.stackName)"
            Start-Sleep -Seconds $SleepTimer
            $SleepTimer += $SleepTimer / 2
            $Status = (Get-CFNstackDriftDetectionStatus @awsParams -StackDriftDetectionId $DetectStatus.StackDriftDetectionId).DetectionStatus
          } until ($Status -ne "DETECTION_IN_PROCESS")
          Write-Verbose "Drift detection completed for $($StackInfo.stackName)"
        }

      }

    }
  }
  end {
    # nothing to do
  }
}

function Get-CHARAWSAccountListOfDriftedResource {
  <#
.SYNOPSIS
    Lists all drifted resources across CloudFormation stacks in an AWS account.

.DESCRIPTION
    Enumerates CloudFormation stacks (optionally filtered by a root stack ARN) and
    reports any resources whose drift status is MODIFIED or DELETED.

.PARAMETER StackRootARN
    Optional. If specified, only stacks whose RootId matches this ARN are checked.

.PARAMETER Region
    AWS region. If not specified, uses the session default.

.PARAMETER ProfileName
    AWS credential profile name. Optional.

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
    Get-CHARAWSAccountListOfDriftedResource -Region us-east-1 -ProfileName myprofile

.EXAMPLE
    Get-CHARAWSAccountListOfDriftedResource -StackRootARN 'arn:aws:cloudformation:us-east-1:123456789012:stack/root/guid'
#>
  [CmdletBinding()]
  param (
    [Parameter()]
    [string]$StackRootARN = $null,

    # AWS common parameters
    [Parameter()]
    [string]$Region,

    [Parameter()]
    [string]$ProfileName,

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
    $awsParams = New-AWSParamSplat -BoundParameters $PSBoundParameters
  }

  process {
    If ($StackRootArn) {
      $stacklist = Get-CFNstack @awsParams | Where-Object RootId -EQ $StackRootArn
    }
    else {
      $stacklist = Get-CFNstack @awsParams
    }
    foreach ($stack in $stacklist) {
      foreach ($resource in Get-CFNstackResourceSummary @awsParams -StackName $stack.Stackname |
        Where-Object { $_.DriftInformation.StackResourceDriftStatus -in @("MODIFIED", "DELETED") } ) {

        Get-CFNstackResourceDrift @awsParams -StackName $stack.Stackname -LogicalResourceId $resource.LogicalResourceId   |
        Select-Object @{Name = "StackId"; Expression = { $stack.Stackname } },
        LogicalResourceId, PhysicalResourceId, ResourceType, StackResourceDriftStatus

      }
    }
  }
}

function Get-CHARAWSObjectCount {
  <#
.SYNOPSIS
    Quick scan to see if a region is in use.

.DESCRIPTION
    Counts number of CloudFormation stacks, VPCs, EC2 Instances, S3 Buckets, and Lambda Functions for a region.

.PARAMETER Region
    Region or list of regions to scan, if not entered, will look at all regions.

.PARAMETER ProfileName
    AWS profile name. Optional.

.PARAMETER AccessKey
    AWS access key. Optional.

.PARAMETER SecretKey
    AWS secret key. Optional.

.PARAMETER SessionToken
    AWS session token for temporary credentials. Optional.

.PARAMETER Credential
    Pre-built AWS credential object. Optional.

.PARAMETER ProfileLocation
    Custom credential file path. Optional.

.PARAMETER EndpointUrl
    Custom AWS service endpoint URL. Optional.

.EXAMPLE
    PS C:\> .\Get-CHARAWSObjectCount.ps1 |Format-Table



Region         StackCount VPCCount EC2Count BucketCount LambdaCount ScanOk
------         ---------- -------- -------- ----------- ----------- ------
eu-north-1              0        1        0           0           0   True
ap-south-1              0        1        0           0           0   True
eu-west-3               0        1        0           0           0   True
eu-west-2               0        1        0           0           0   True
eu-west-1               0        1        0           0           0   True
ap-northeast-2          0        1        0           0           0   True
ap-northeast-1          0        1        0           0           0   True
sa-east-1               0        1        0           0           0   True
ca-central-1            0        1        0           0           0   True
ap-southeast-1          0        1        0           0           0   True
ap-southeast-2          0        1        0           0           0   True
eu-central-1            0        1        0           0           0   True
us-east-1              53        3        0          13          36   True
us-east-2               0        1        1           2           0   True
us-west-1               0        1        0           0           0   True
us-west-2               0        1        0           0           0   True

.EXAMPLE
PS C:\> .\Get-CHARAWSObjectCount.ps1 -Region us-east-1


Region      : us-east-1
StackCount  : 53
VPCCount    : 3
EC2Count    : 0
BucketCount : 13
LambdaCount : 36
ScanOk      : True

.EXAMPLE
.\Get-CHARAWSObjectCount.ps1 -Region @('us-east-1','us-east-2') |Format-Table


Region    StackCount VPCCount EC2Count BucketCount LambdaCount ScanOk
------    ---------- -------- -------- ----------- ----------- ------
us-east-1         53        3        0          13          36   True
us-east-2          0        1        1           2           0   True

#>

  [CmdletBinding()]
  param (
    [Parameter(ValueFromPipeline)]
    $Region = (Get-EC2Region).RegionName,

    # AWS common parameters
    [Parameter()]
    [string]$ProfileName,

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
    $awsParams = New-AWSParamSplat -BoundParameters $PSBoundParameters
  }

  process {
    Write-Verbose "RegionCount: $(($Region).count)"
    $output = @()

    # S3 bucket listing must use us-east-1; override Region in the splat for this call
    $S3Params = $awsParams.Clone()
    $S3Params['Region'] = 'us-east-1'

    #do this in us-east-1 only
    $AllBuckets = ((Get-S3Bucket @S3Params).BucketName | Get-S3BucketLocation @S3Params).Value | Select-Object @{Name = "Region"; Expression = { $_ } } | Group-Object Region -NoElement

    foreach ($R in $Region ) {
      # Override Region for each iteration since we scan multiple regions
      $AwsParams['Region'] = $R

      Write-Verbose "Region: $($R)"
      #  see https://docs.aws.amazon.com/general/latest/gr/s3.html , us-east-1 and eu-west-1 have extra names
      if ($R -eq 'us-east-1') {
        $BucketCount = ($AllBuckets | Where-Object Name -In '', 'us-east-1').Count

      }
      elseif ($R -eq 'eu-west-1') {
        $BucketCount = ($AllBuckets | Where-Object Name -In 'EU', 'eu-west-1' ).Count
      }
      else {
        #if no buckets in region, will return zero
        $BucketCount = ($AllBuckets | Where-Object Name -EQ $R).Count
      }
      Write-Verbose "Bucketcount: $($R)$($BucketCount)"

      try {
        $StackCount = (Get-CFNStack @AwsParams).count
        Write-Verbose "Stackcount: $($stackcount)"
        $EC2Count = (Get-EC2Instance @AwsParams).count
        Write-Verbose "EC2Count: $($EC2Count)"
        $LambdaCount = (Get-LMFunctionList @AwsParams).count
        Write-Verbose "LambdaCount: $($LambdaCount)"
        $VPCCount = (Get-EC2Vpc @AwsParams).count

        $RegionData = New-Object -TypeName PsObject -Property ([ordered]@{
            Region      = $R
            StackCount  = $StackCount
            VPCCount    = $VPCCount
            EC2Count    = $Ec2Count
            BucketCount = $BucketCount
            LambdaCount = $LambdaCount
            ScanOk      = $True
          })
        Write-Verbose "$($RegionData)"
      }

      catch {
        Write-Verbose ("catch: $($Region)")
        $RegionData = New-Object -TypeName PsObject -Property ([ordered]@{
            Region      = $Region
            StackCount  = ""
            EC2Count    = ""
            BucketCount = ""
            LambdaCount = ""
            ScanOk      = $false

          })
      }
      finally {
        Write-Verbose "Completed Region $($R)"
        $output += $RegionData
      }
    }
    return $output
  }
}

<#
.SYNOPSIS
	Get AWSCredentials for a role you can use assume from your current role
.DESCRIPTION
	A wrapper around 'Get-STSRole' that will get the credentials for a role you can use from your current role,
	and save the credentials in $home/.aws/credentials
.PARAMETER Role
	The name of the role you want to assume,
.EXAMPLE
	PS C:\> Use-CHARAssumedRole -Role MyAdminRole

	Assumes the specified role and stores the temporary credentials in ~/.aws/credentials.
#>
function Use-CHARAssumedRole($Role) {
  $RoleSessionName = (Get-STSCallerIdentity).UserId.Split(':')[-1]
  $RoleArnToAssume = (Get-IAMRole -RoleName $Role).Arn
  try {
    $RoleCred = Use-STSRole -RoleArn $RoleArnToAssume -RoleSessionName $RoleSessionName

    Set-AWSCredential -AccessKey $RoleCred.Credentials.AccessKeyId `
      -SecretKey $RoleCred.Credentials.SecretAccessKey `
      -SessionToken $RoleCred.Credentials.SessionToken `
      -ProfileLocation $home/.aws/credentials -StoreAs $RoleArnToAssume
    Write-Output  "Assumed role $RoleArnToAssume, and stored in AWSProfiles"
    Get-STSCallerIdentity

  }
  catch {
    Write-Error "Failed to assume role $RoleArnToAssume"
    throw $_
  }
}






# ================================================================================================
# Update-CHARSSOCredentialList Function
# ================================================================================================

function Update-CHARSSOCredentialList {
  <#
.SYNOPSIS
    Enumerates SSO accounts/roles and writes AWS CLI-compatible SSO profiles to a config file.

.DESCRIPTION
    Authenticates via AWS IAM Identity Center (SSO) using the OIDC device authorization
    flow, enumerates all accounts and roles the caller has access to, and writes
    SSO-style named profiles to the specified config file (default: ~/.aws/config).

    Each generated profile contains sso_session, sso_account_id, sso_role_name, and region.
    A shared [sso-session] block is written once at the top of the config file.

    By default, NO temporary credentials (access key / secret key / session token) are
    persisted. Use -SaveCredentials to opt into saving them to the credentials file.

    Generated profile names follow the pattern:
        [ProfilePrefix-]<RoleName>-<AccountId>

.PARAMETER StartUrl
    The AWS SSO start URL (e.g., https://d-1234567890.awsapps.com/start).

.PARAMETER SSOSessionName
    The sso_session name written into the config file and referenced by each profile.
    If not specified, a sanitized name is derived from the StartUrl host
    (e.g., 'd9067171d80' from https://d-9067171d80.awsapps.com/start).

.PARAMETER Region
    The AWS region where IAM Identity Center is configured (e.g., us-east-1).

.PARAMETER ProfileName
    AWS credential profile used for initial authentication. Optional.

.PARAMETER ProfilePrefix
    Optional prefix prepended to each generated profile name, separated by a hyphen.
    Example: -ProfilePrefix 'CharlandOrg' produces 'CharlandOrg-AWSAdminAccess-123456789012'.

.PARAMETER RoleFilter
    Optional filter for specific role names. Accepts wildcards (e.g., 'Admin*').
    Only matching roles are written as profiles.

.PARAMETER AccountFilter
    Optional filter for specific account IDs or account names. Accepts wildcards.
    Only matching accounts are processed.

.PARAMETER ConfigFile
    Path to the AWS config file where SSO profiles are written.
    Defaults to ~/.aws/config. Supports both absolute and relative paths.

.PARAMETER CredentialFile
    Path to the AWS credentials file. Only used when -SaveCredentials is specified.
    Defaults to ~/.aws/credentials.

.PARAMETER SaveCredentials
    When specified, also retrieves temporary access key, secret key, and session token
    for each role and persists them to the credentials file. By default these are NOT saved.

.PARAMETER Force
    Skip confirmation prompts and overwrite existing profiles without asking.

.PARAMETER AccessKey
    AWS access key. Optional.

.PARAMETER SecretKey
    AWS secret key. Optional.

.PARAMETER SessionToken
    AWS session token for temporary credentials. Optional.

.PARAMETER Credential
    Pre-built AWS credential object. Optional.

.PARAMETER ProfileLocation
    Custom credential file path. When specified, overrides CredentialFile for
    storing temporary credentials (only relevant with -SaveCredentials).

.PARAMETER EndpointUrl
    Custom AWS service endpoint URL. Optional.

.EXAMPLE
    Update-CHARSSOCredentialList -StartUrl 'https://d-9067171d80.awsapps.com/start' `
        -SSOSessionName 'CharlandOrg' -Region 'us-east-1' -Force

    Writes SSO-style profiles to ~/.aws/config using 'CharlandOrg' as the sso_session name.
    Output:
        [sso-session CharlandOrg]
        sso_start_url = https://d-9067171d80.awsapps.com/start
        sso_region = us-east-1
        ...

        [profile AWSAdministratorAccess-217552586751]
        sso_session = CharlandOrg
        sso_account_id = 217552586751
        sso_role_name = AWSAdministratorAccess
        region = us-east-1

.EXAMPLE
    Update-CHARSSOCredentialList -StartUrl 'https://d-9067171d80.awsapps.com/start' `
        -SSOSessionName 'CharlandOrg' -ProfilePrefix 'CharlandOrg' -Region 'us-east-1' -Force

    Produces profiles named 'CharlandOrg-<RoleName>-<AccountId>'.

.EXAMPLE
    Update-CHARSSOCredentialList -StartUrl 'https://d-9067171d80.awsapps.com/start' `
        -SSOSessionName 'CharlandOrg' -Region 'us-east-1' -SaveCredentials

    Writes SSO profiles AND persists temporary access key/secret/token to ~/.aws/credentials.

.EXAMPLE
    Update-CHARSSOCredentialList -StartUrl 'https://d-9067171d80.awsapps.com/start' `
        -SSOSessionName 'CharlandOrg' -Region 'us-east-1' -RoleFilter 'AWSAdministrator*' `
        -AccountFilter '217552586751'

    Only writes profiles matching the specified role and account filters.

.EXAMPLE
    Update-CHARSSOCredentialList -StartUrl 'https://d-9067171d80.awsapps.com/start' `
        -SSOSessionName 'CharlandOrg' -Region 'us-east-1' `
        -ConfigFile '~/custom-aws/config' -Force

    Writes SSO profiles to a custom config file location.

.NOTES
    Generated by Kiro using Claude Sonnet 4, reviewed by ccharland

    The function caches the SSO token in module scope for the session duration,
    so subsequent calls within the same PowerShell session will reuse the token
    until it expires.
#>
  [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'CredentialFile',
    Justification = 'CredentialFile is a file path, not a password')]
  param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$StartUrl,

    [Parameter()]
    [string]$SSOSessionName,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Region,

    [Parameter()]
    [string]$ProfileName,

    [Parameter()]
    [string]$ProfilePrefix = '',

    [Parameter()]
    [string[]]$RoleFilter,

    [Parameter()]
    [string[]]$AccountFilter,

    [Parameter()]
    [string]$ConfigFile = (Join-Path $HOME '.aws' 'config'),

    [Parameter()]
    [string]$CredentialFile = (Join-Path $HOME '.aws' 'credentials'),

    [Parameter()]
    [switch]$SaveCredentials,

    [Parameter()]
    [switch]$Force,

    # AWS common parameters
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
    $awsParams = New-AWSParamSplat -BoundParameters $PSBoundParameters

    # SSO OIDC calls require pseudo credentials and only need Region/ProfileName
    $SsoParams = @{}
    if ($awsParams.ContainsKey('Region')) { $SsoParams['Region'] = $awsParams['Region'] }
    if ($awsParams.ContainsKey('ProfileName')) { $SsoParams['ProfileName'] = $awsParams['ProfileName'] }

    # ProfileLocation overrides CredentialFile when saving temporary credentials
    $effectiveCredentialFile = if ($ProfileLocation) { $ProfileLocation } else { $CredentialFile }

    # Derive SSOSessionName from StartUrl host if not explicitly provided
    if (-not $SSOSessionName) {
      $SSOSessionName = ($StartUrl -replace 'https?://', '' -replace '\.awsapps\.com.*', '' -replace '[^a-zA-Z0-9]', '')
    }
  }

  process {
    # Pseudo credentials required by the SSO OIDC API
    $pseudoCreds = @{
      AccessKey = 'AKAEXAMPLE123ACCESS'
      SecretKey = 'PseudoS3cret4cceSSKey123PseudoS3cretKey'
    }

    # Ensure config directory exists (skip if path has no parent, e.g., relative filename)
    $configDir = Split-Path $ConfigFile -Parent
    if ($configDir -and -not (Test-Path $configDir)) {
      New-Item -ItemType Directory -Path $configDir -Force | Out-Null
      Write-Verbose "Created directory: $configDir"
    }

    # Ensure credentials directory exists when saving credentials
    if ($SaveCredentials) {
      $credDir = Split-Path $effectiveCredentialFile -Parent
      if ($credDir -and -not (Test-Path $credDir)) {
        New-Item -ItemType Directory -Path $credDir -Force | Out-Null
        Write-Verbose "Created credentials directory: $credDir"
      }
    }

    # Check for cached SSO token in session
    $cacheKey = 'SSOToken_' + ($StartUrl -replace '[^a-zA-Z0-9]', '')

    $cachedToken = $null
    $cachedExpire = $null
    if ($script:SSOTokenCache.ContainsKey($cacheKey)) {
      $cachedToken = $script:SSOTokenCache[$cacheKey].Token
      $cachedExpire = $script:SSOTokenCache[$cacheKey].Expires
    }

    $needsAuth = (-not $cachedToken) -or (-not $cachedExpire) -or ($cachedExpire -lt (Get-Date))

    if ($needsAuth) {
      Write-Verbose "SSO token not found or expired. Initiating authentication..."

      $client = Register-SSOOIDCClient -ClientName 'powershell-sso-updater' -ClientType 'public' @SsoParams @pseudoCreds
      $device = $client | Start-SSOOIDCDeviceAuthorization -StartUrl $StartUrl @SsoParams @pseudoCreds

      Write-Verbose "Opening browser for SSO authentication..."
      Write-Output "Opening browser for SSO login. Please authorize the request."
      Start-Process $device.VerificationUriComplete

      $ssoToken = $null
      while (-not $ssoToken) {
        try {
          $ssoToken = $client | New-SSOOIDCToken `
            -DeviceCode $device.DeviceCode `
            -GrantType 'urn:ietf:params:oauth:grant-type:device_code' `
            @SsoParams @pseudoCreds
        }
        catch {
          if ($_.Exception.Message -notlike '*AuthorizationPendingException*') {
            throw $_
          }
          Start-Sleep -Seconds 2
        }
      }

      $tokenExpire = (Get-Date).AddSeconds($ssoToken.ExpiresIn)
      $script:SSOTokenCache[$cacheKey] = @{ Token = $ssoToken; Expires = $tokenExpire }
      Write-Verbose "SSO token obtained. Expires at: $tokenExpire"
    }
    else {
      $ssoToken = $cachedToken
      $tokenExpire = $cachedExpire
      $remaining = $tokenExpire - (Get-Date)
      Write-Verbose "Using cached SSO token. Expires in: $($remaining.ToString('hh\:mm\:ss'))"
    }

    # Enumerate all accounts
    Write-Verbose "Listing SSO accounts..."
    $accounts = Get-SSOAccountList -AccessToken $ssoToken.AccessToken @SsoParams @pseudoCreds

    if (-not $accounts) {
      Write-Warning "No accounts found for this SSO session."
      return
    }

    Write-Verbose "Found $($accounts.Count) account(s)."

    # Apply account filter
    if ($AccountFilter) {
      $accounts = $accounts | Where-Object {
        $acct = $_
        $AccountFilter | Where-Object { $acct.AccountId -like $_ -or $acct.AccountName -like $_ }
      }
      Write-Verbose "After filtering: $($accounts.Count) account(s)."
    }

    # Write sso-session block to config file (only once, at the top if not already present)
    $ssoSessionBlock = @"
[sso-session $SSOSessionName]
sso_start_url = $StartUrl
sso_region = $Region
sso_registration_scopes = sso:account:access
"@

    # Read existing config or start fresh
    $configContent = ''
    if (Test-Path $ConfigFile) {
      $configContent = Get-Content $ConfigFile -Raw
    }

    # Only add sso-session block if not already present
    if ($configContent -notmatch "(?m)^\[sso-session $([regex]::Escape($SSOSessionName))\]") {
      $configContent = "$ssoSessionBlock`n`n$configContent"
      Write-Verbose "Added [sso-session $SSOSessionName] block to config."
    }

    # Process each account
    $profilesUpdated = 0
    $profilesFailed = 0

    foreach ($account in $accounts) {
      Write-Verbose "Processing account: $($account.AccountName) ($($account.AccountId))"

      try {
        $roles = Get-SSOAccountRoleList -AccessToken $ssoToken.AccessToken `
          -AccountId $account.AccountId @SsoParams @pseudoCreds
      }
      catch {
        Write-Warning "Failed to list roles for account $($account.AccountName) ($($account.AccountId)): $_"
        continue
      }

      if (-not $roles) {
        Write-Verbose "No roles found for account $($account.AccountName)."
        continue
      }

      # Apply role filter
      $filteredRoles = $roles
      if ($RoleFilter) {
        $filteredRoles = $roles | Where-Object {
          $roleName = $_.RoleName
          $RoleFilter | Where-Object { $roleName -like $_ }
        }
      }

      foreach ($role in $filteredRoles) {
        $generatedProfileName = if ($ProfilePrefix) {
          "$ProfilePrefix-$($role.RoleName)-$($account.AccountId)"
        } else {
          "$($role.RoleName)-$($account.AccountId)"
        }

        $target = "Profile '$generatedProfileName' (Account: $($account.AccountId), Role: $($role.RoleName))"

        if ($Force -or $PSCmdlet.ShouldProcess($target, "Update SSO profile")) {
          try {
            Write-Verbose "Writing SSO profile for $target"

            # Build SSO-style profile entry for config file
            $profileSection = "[profile $generatedProfileName]"
            $profileBlock = @"
$profileSection
sso_session = $SSOSessionName
sso_account_id = $($account.AccountId)
sso_role_name = $($role.RoleName)
region = $Region
"@

            # Replace existing profile block or append new one
            $escapedSection = [regex]::Escape($profileSection)
            if ($configContent -match "(?m)$escapedSection") {
              $configContent = $configContent -replace "(?ms)$escapedSection.*?(?=\r?\n\[|\z)", "$profileBlock`n"
            }
            else {
              if ($configContent -and -not $configContent.EndsWith("`n")) {
                $configContent += "`n"
              }
              $configContent += "$profileBlock`n`n"
            }

            # Optionally save temporary credentials to credentials file
            if ($SaveCredentials) {
              $creds = Get-SSORoleCredential -AccessToken $ssoToken.AccessToken `
                -AccountId $account.AccountId `
                -RoleName $role.RoleName `
                @SsoParams @pseudoCreds

              [PSCustomObject]@{
                AccessKey    = $creds.AccessKeyId
                SecretKey    = $creds.SecretAccessKey
                SessionToken = $creds.SessionToken
              } | Set-AWSCredential -StoreAs $generatedProfileName -ProfileLocation $effectiveCredentialFile
              Write-Verbose "Saved temporary credentials for: $generatedProfileName"
            }

            $profilesUpdated++
            Write-Verbose "Updated profile: $generatedProfileName"
          }
          catch {
            $profilesFailed++
            Write-Warning "Failed to process $target : $_"
          }
        }
      }
    }

    # Write config file
    if ($Force -or $PSCmdlet.ShouldProcess("AWS config file '$ConfigFile'", 'Write updated SSO configuration')) {
      Set-Content -Path $ConfigFile -Value $configContent.TrimEnd() -Encoding UTF8
      Write-Verbose "Config written to: $ConfigFile"
    }

    # Summary
    $remaining = $tokenExpire - (Get-Date)
    Write-Verbose "Profile update complete. Token expires in: $($remaining.ToString('hh\:mm\:ss'))"

    $result = [PSCustomObject]@{
      ProfilesUpdated  = $profilesUpdated
      ProfilesFailed   = $profilesFailed
      ConfigFile       = $ConfigFile
      SavedCredentials = $SaveCredentials.IsPresent
      TokenExpires     = $tokenExpire
    }

    if ($SaveCredentials) {
      $result | Add-Member -NotePropertyName 'CredentialFile' -NotePropertyValue $effectiveCredentialFile
    }

    $result
  }
}

# Export-ModuleMember -Function *
# # code to run if attempted to dot source file
try {
  Write-Verbose  "atempting to export Module Members for AWSCustomizations"
  Export-ModuleMember -Function *
}
catch {
  Write-Verbose "OK: someone is dot sourcing this script"
}
finally {
  Write-Verbose "Finished Loading AWSCustomizations.psm1"
}
# SIG # Begin signature block
# MIIs4wYJKoZIhvcNAQcCoIIs1DCCLNACAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCnY3wGYnaQbime
# TnuaV/Ce9e3x4HudtOhRjd12sUHVFaCCJfgwggVvMIIEV6ADAgECAhBI/JO0YFWU
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
# BgorBgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQg0l8+
# /9i6d67ZfKxgLz9/dAKAlWd+MSDfYuREnjRXVj8wDQYJKoZIhvcNAQEBBQAEggIA
# qtiZnetduFgqpphiPFnmLjg/UXAQNcPLrryoSjN8tOA3gcejfD1gaPzGcdgBBDiR
# Vu+CdtlQIqTWxKS+iEqFMcohAzdPkM+CA6Au16PAAt1kih+0HTXygBXlKus92ZcI
# +TmQoPL/HK6PnetCnYYu2pLok3EaY+ftIsJKwWteZaA7XSqVHpz047+QU3b6aBHP
# CRl2q5O+ihbmu3MPJ3JC7ZFpsjhuIsDkCdaGghhZ7cnOR3Fbx6eB+cqY2ZJygmuc
# a/LA9pu6V/t4qbH7D0a7fNEwDcdh1qh1SKY9RdUejnYwT/zbhbofBt+t1EZGCCYo
# p6gaeXOtgJ3iHbnOoryDJVQ4kVkSOFGFLW9ze7C5dKSqViNMVI7YN0JsPamRfYM1
# lrQHUKAHq8/iRwIdLwQ8sVCXV0h+lopT1kzghqsZSDrGzAb34wDqhmBUGKMPf4Yc
# +ziPleU3niCfXCh3BLDMG23w5/sKPlKkuAmNgOKKoKK0pYrdrmpj0q5lXQV7IL05
# H+vHvGDC51rkv+tm2OOwDm4ZW+cnXdVfowr+1oNpPUQVyc1JooSL1M/USgPq47+J
# ud5saGAal3pHYhurvhqMF77c3O7PAzwlbr/A+RHRk+V9V5oow5J0q3s2si1HSns1
# 8NLmNc7ULXBZ+loBO4H5OmecbpdUBosWecUlLFjKyFGhggMjMIIDHwYJKoZIhvcN
# AQkGMYIDEDCCAwwCAQEwajBVMQswCQYDVQQGEwJHQjEYMBYGA1UEChMPU2VjdGln
# byBMaW1pdGVkMSwwKgYDVQQDEyNTZWN0aWdvIFB1YmxpYyBUaW1lIFN0YW1waW5n
# IENBIFI0MQIRAOdO8lWwUE/626bf9/yLoxUwDQYJYIZIAWUDBAICBQCgeTAYBgkq
# hkiG9w0BCQMxCwYJKoZIhvcNAQcBMBwGCSqGSIb3DQEJBTEPFw0yNjA3MDUyMzU4
# MDNaMD8GCSqGSIb3DQEJBDEyBDC4axEbIe1CtGEF5BAhhsXaV97DD4Mn2HX/XIjn
# HFMmTrIoXRq6UHrIgUmOsHtpCB8wDQYJKoZIhvcNAQEBBQAEggIAKFRXyJJosWCM
# 7536X4b2dbrqwbiucpSUB0YjMw2FHaHqxaihDbWqOItKSlYS1yJRSAzwFjx4c0UI
# jJ93iVDHWK19A7TxTt6dLDGKYaHskrGsVc5Vfed91BVUwzkOvfxfO5W0I7KXd5+f
# yHD8AreHZmsEDHEpXHfbHY+9Q4nnSDf8BLVkqQGVAzYl4Zeq9n9lSr6yyEyHHBQi
# rpP3rysslwSDdYpE1ALF2eXShR/lSjw4U0SGzBft0ywBcawSi2ru2W8r6wTPiX2l
# RCb59KHvSvX/4B/SZrNATcwHNRskjjt1oweBTywsFtDmb/NVCgAN1O5aMITh0BrV
# TdChQukLCEW1uWBRQj5msVMEiMB568/u4kc/g1KlsJH2KdD6k9YQu7ZJjX5NeV1W
# ueSeSLkJI0wCrBJUYQT0rl+XPZWrdAOu9c8jo6W3iUXc5Wdeas25oWlO8oL+qQEB
# Qu6PUSYqW4+cVT+uV6yfIi9Vt9+FWI4N+iVcNOjfvLHsYVCxRb/UUKZrJpHRhhXw
# jGNz6ysW8wdFeKO88SOXIABTGVj0NzI1G52tvijER0y93Droun6cWUx5VTuZM/lM
# IT1tgrVIgrmLlbN//GoCaslIbfGY7Sif3tCEn4kM04loBE9MJvSunqihebbrXZ2J
# BD9do0CS7vAcB532Z4ocVkRppyW/stE=
# SIG # End signature block
