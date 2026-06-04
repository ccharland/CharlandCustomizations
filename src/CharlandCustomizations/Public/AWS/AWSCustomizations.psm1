<#
.SYNOPSIS
    AWS PowerShell Customizations and scripts.
#>
Write-Verbose  "Loading AWSCustomizations.psm1"

# Load private helper functions needed by this nested module (added by Kiro, aws-common-params spec)
. "$PSScriptRoot/../../Private/New-AWSParamSplat.ps1"

# Module-level cache for SSO tokens to avoid repeated authentication
$script:SSOTokenCache = @{}
function  Get-CCAWSMFASession {
  <#
  .SYNOPSIS
    Changes your active AWS connection to a temporary session using MFA Authentiation.
  .DESCRIPTION
    Retrieves temporary STS session credentials by authenticating with a one-time MFA token code.
    Returns credentials that can be passed to Set-AWSCredential.
  .EXAMPLE
    PS C:\> Set-AWSCredential -Credential (Get-CCAWSMFASession -TokenCode <OTP>)

    Changes your active AWS session to one authenticated with MFA.
  #>
  param(
    [Parameter(mandatory = $true)]
    [string]$TokenCode
  )
  return Get-STSSessionToken -SerialNumber (Get-IAMMFADevice).SerialNumber -TokenCode $TokenCode
}


function Find-CCCFNStackError {
  <#
.SYNOPSIS
   Finds Stacks and resources in an "error state".
.DESCRIPTION
    Script reports any stack or resource where "StatusReason" has a non-null value
.EXAMPLE
    PS C:\> Find-CCCFNStackError

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


function Set-CCAWSProfileWithMFA {
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
    PS C:\> Set-AWSCredential -Credential (Set-CCAWSProfileWithMFA -ProfileName myprofile -TokenCode 123456)

    Authenticates with MFA and sets the returned credentials as the active session.

.EXAMPLE
    PS C:\> Set-CCAWSProfileWithMFA -ProfileName myprofile -TokenCode 123456 -Region us-east-1

    Retrieves MFA session credentials for a specific region.
#>
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

function Set-CCAWSEnv {
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
  PS> Set-CCAWSEnv
  Sets AWS environment variables from current credential

.EXAMPLE
  PS> Set-CCAWSEnv -WhatIf
  Shows what environment variables would be set without actually setting them

.EXAMPLE
  PS> Set-CCAWSEnv -Confirm:$false
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
function Remove-CCExpiredAWSProfile {
  <#
  .SYNOPSIS
    Removes expired temporary credentials stored in local credential stores.
  .DESCRIPTION
    Tests all AWS Profiles by calling Get-STSCallerIdentity. If the call fails with an
    ExpiredToken error, the profile is removed from the credential store.
  .EXAMPLE
    Remove-CCExpiredAWSProfile
    Scans all profiles with a credential file location and removes any with expired tokens.
  .EXAMPLE
    Remove-CCExpiredAWSProfile -WhatIf
    Shows which profiles would be removed without performing any deletion.
  .PARAMETER Force
    Passes Force to Remove-AWSCredentialProfile to suppress downstream confirmation prompts.
  #>
  [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
  param(
    [switch]$Force
  )
  $MessageList = @("The security token included in the request is invalid")

  # $ignored_messages= @("No access" "not allowed to assume the role?" )


  Get-AWSCredential -ListProfileDetail | Where-Object ProfileLocation | ForEach-Object {
    $profileItem = $_
    try {
      # Set-AWSCredential -ProfileName $profileItem.ProfileName
      Get-STSCallerIdentity -ProfileName $profileItem.ProfileName | Out-Null
    }
    catch {
      if ($_.Exception.Message -in $MessageList) {
        Write-Output "Removing profile: $($profileItem.ProfileName) Message: $($_.Exception.Message)"
        if ($PSCmdlet.ShouldProcess($profileItem.ProfileName, 'Remove expired AWS credential profile')) {
          $removeProfileSplat = @{ ProfileName = $profileItem.ProfileName }
          if ($Force) {
            $removeProfileSplat.Force = $true
          }

          if (Remove-AWSCredentialProfile @removeProfileSplat) {
            Write-Verbose "Profile '$($profileItem.ProfileName)' removed successfully."
          }
          else {
            Write-Error "Failed to remove profile '$($profileItem.ProfileName)'."
          }
        }
      }
      else {
        Write-Verbose "Profile '$($profileItem.ProfileName)' not removed. Message: $($_.Exception.Message)"
      }
    }
  }
}

function Get-CCAccountListFromProfile {
  <#
  .SYNOPSIS
    Lists  AWS ProfileName, Account, and AccountAlias
  .DESCRIPTION
    Enumerates all locally stored AWS credential profiles and retrieves the associated
    account ID and account alias for each by calling Get-STSCallerIdentity and Get-IAMAccountAlias.
  .EXAMPLE
    PS C:\> Get-CCAccountListFromProfile

    ProfileName  Account       AccountAlias
    -----------  -------       ------------
    default      123456789012  my-account
  #>
  Get-AWSCredential -ListProfileDetail  | ForEach-Object { Select-Object -InputObject $_   Profilename, @{Name = "Account"; Expression = { (Get-STSCallerIdentity -ProfileName  $_.ProfileName).Account } }, @{Name = "AccountAlias"; Expression = { Get-IAMAccountAlias -ProfileName  $_.ProfileName } } }
}

function Start-CCMultiStackDriftDetection {
  <#
.SYNOPSIS
  Detects drift on all stacks passed into the function
.DESCRIPTION
  Start-CCMultiStackDriftDetection  will detect Stack drift on all stack names passed into it,
  and will bypass the stacks that it doesn't make sense to do the drift detection on.

.EXAMPLE
  PS C:\> (Get-CFNstack).StackName |Select-Object -first 5  |Start-CCMultiStackDriftDetection
  Starts a drift detection of the first 5 stacks listed.

.EXAMPLE
PS C:\> Start-CCMultiStackDriftDetection

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

function Get-CCAWSAccountListOfDriftedResource {
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
    Get-CCAWSAccountListOfDriftedResource -Region us-east-1 -ProfileName myprofile

.EXAMPLE
    Get-CCAWSAccountListOfDriftedResource -StackRootARN 'arn:aws:cloudformation:us-east-1:123456789012:stack/root/guid'
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

function Get-CCAWSObjectCount {
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
    PS C:\> .\Get-CCAWSObjectCount.ps1 |Format-Table



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
PS C:\> .\Get-CCAWSObjectCount.ps1 -Region us-east-1


Region      : us-east-1
StackCount  : 53
VPCCount    : 3
EC2Count    : 0
BucketCount : 13
LambdaCount : 36
ScanOk      : True

.EXAMPLE
.\Get-CCAWSObjectCount.ps1 -Region @('us-east-1','us-east-2') |Format-Table


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
	PS C:\> Use-CCAssumedRole -Role MyAdminRole

	Assumes the specified role and stores the temporary credentials in ~/.aws/credentials.
#>
function Use-CCAssumedRole($Role) {
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
# Update-CCSSOCredentialList Function
# ================================================================================================

function Update-CCSSOCredentialList {
  <#
.SYNOPSIS
    Retrieves SSO credentials for all accounts/roles and updates ~/.aws/credentials.

.DESCRIPTION
    Authenticates via AWS IAM Identity Center (SSO), enumerates all accounts and roles
    the user has access to, retrieves short-term credentials for each, and writes them
    as named profiles to ~/.aws/credentials.

.PARAMETER StartUrl
    The AWS SSO start URL (e.g., https://d-1234567890.awsapps.com/start).

.PARAMETER Region
    The AWS region where IAM Identity Center is configured.

.PARAMETER ProfileName
    AWS profile name. Optional.

.PARAMETER ProfilePrefix
    Optional prefix for generated profile names.

.PARAMETER RoleFilter
    Optional filter for specific role names. Accepts wildcards.

.PARAMETER AccountFilter
    Optional filter for specific account IDs or names. Accepts wildcards.

.PARAMETER CredentialFile
    Path to the AWS credentials file. Defaults to ~/.aws/credentials.

.PARAMETER Force
    Skip confirmation and overwrite existing profiles without prompting.

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
    Update-CCSSOCredentialList -StartUrl 'https://d-1234567890.awsapps.com/start' -Region 'us-east-1'

.EXAMPLE
    Update-CCSSOCredentialList -StartUrl 'https://mycompany.awsapps.com/start' -Region 'us-east-1' `
        -RoleFilter 'Admin*' -ProfilePrefix 'sso-'
#>
  [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'CredentialFile',
    Justification = 'CredentialFile is a file path, not a password')]
  param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$StartUrl,

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
    [string]$CredentialFile = (Join-Path $HOME '.aws' 'credentials'),

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
    # Build a subset splat for SSO-specific cmdlets
    $SsoParams = @{}
    if ($awsParams.ContainsKey('Region')) { $SsoParams['Region'] = $awsParams['Region'] }
    if ($awsParams.ContainsKey('ProfileName')) { $SsoParams['ProfileName'] = $awsParams['ProfileName'] }
  }

  process {
  # Pseudo credentials required by the SSO OIDC API
  $pseudoCreds = @{
    AccessKey = 'AKAEXAMPLE123ACCESS'
    SecretKey = 'PseudoS3cret4cceSSKey123PseudoS3cretKey'
  }

  # Ensure credentials directory exists
  $credDir = Split-Path $CredentialFile -Parent
  if (-not (Test-Path $credDir)) {
    New-Item -ItemType Directory -Path $credDir -Force | Out-Null
    Write-Verbose "Created directory: $credDir"
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
      $accountPart = if ($account.AccountName) {
        ($account.AccountName -replace '[^a-zA-Z0-9\-]', '-').ToLower().Trim('-')
      }
      else {
        $account.AccountId
      }
      $generatedProfileName = "$ProfilePrefix$accountPart-$($role.RoleName)"

      $target = "Profile '$generatedProfileName' (Account: $($account.AccountId), Role: $($role.RoleName))"

      if ($Force -or $PSCmdlet.ShouldProcess($target, "Update credentials")) {
        try {
          Write-Verbose "Retrieving credentials for $target"

          $creds = Get-SSORoleCredential -AccessToken $ssoToken.AccessToken `
            -AccountId $account.AccountId `
            -RoleName $role.RoleName `
            @SsoParams @pseudoCreds

          [PSCustomObject]@{
            AccessKey    = $creds.AccessKeyId
            SecretKey    = $creds.SecretAccessKey
            SessionToken = $creds.SessionToken
          } | Set-AWSCredential -StoreAs $generatedProfileName -ProfileLocation $CredentialFile

          $profilesUpdated++
          Write-Verbose "Updated profile: $generatedProfileName"
        }
        catch {
          $profilesFailed++
          Write-Warning "Failed to get credentials for $target : $_"
        }
      }
    }
  }

  # Summary
  $remaining = $tokenExpire - (Get-Date)
  Write-Verbose "Credential update complete. Token expires in: $($remaining.ToString('hh\:mm\:ss'))"

  [PSCustomObject]@{
    ProfilesUpdated = $profilesUpdated
    ProfilesFailed  = $profilesFailed
    CredentialFile  = $CredentialFile
    TokenExpires    = $tokenExpire
  }
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
# MIImXQYJKoZIhvcNAQcCoIImTjCCJkoCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDZrruOccsPs6rh
# Jf3eXQBb4mU+lx9rxgTmSCaPu+AnEKCCH3IwggYUMIID/KADAgECAhB6I67aU2mW
# D5HIPlz0x+M/MA0GCSqGSIb3DQEBDAUAMFcxCzAJBgNVBAYTAkdCMRgwFgYDVQQK
# Ew9TZWN0aWdvIExpbWl0ZWQxLjAsBgNVBAMTJVNlY3RpZ28gUHVibGljIFRpbWUg
# U3RhbXBpbmcgUm9vdCBSNDYwHhcNMjEwMzIyMDAwMDAwWhcNMzYwMzIxMjM1OTU5
# WjBVMQswCQYDVQQGEwJHQjEYMBYGA1UEChMPU2VjdGlnbyBMaW1pdGVkMSwwKgYD
# VQQDEyNTZWN0aWdvIFB1YmxpYyBUaW1lIFN0YW1waW5nIENBIFIzNjCCAaIwDQYJ
# KoZIhvcNAQEBBQADggGPADCCAYoCggGBAM2Y2ENBq26CK+z2M34mNOSJjNPvIhKA
# VD7vJq+MDoGD46IiM+b83+3ecLvBhStSVjeYXIjfa3ajoW3cS3ElcJzkyZlBnwDE
# JuHlzpbN4kMH2qRBVrjrGJgSlzzUqcGQBaCxpectRGhhnOSwcjPMI3G0hedv2eNm
# GiUbD12OeORN0ADzdpsQ4dDi6M4YhoGE9cbY11XxM2AVZn0GiOUC9+XE0wI7CQKf
# OUfigLDn7i/WeyxZ43XLj5GVo7LDBExSLnh+va8WxTlA+uBvq1KO8RSHUQLgzb1g
# bL9Ihgzxmkdp2ZWNuLc+XyEmJNbD2OIIq/fWlwBp6KNL19zpHsODLIsgZ+WZ1AzC
# s1HEK6VWrxmnKyJJg2Lv23DlEdZlQSGdF+z+Gyn9/CRezKe7WNyxRf4e4bwUtrYE
# 2F5Q+05yDD68clwnweckKtxRaF0VzN/w76kOLIaFVhf5sMM/caEZLtOYqYadtn03
# 4ykSFaZuIBU9uCSrKRKTPJhWvXk4CllgrwIDAQABo4IBXDCCAVgwHwYDVR0jBBgw
# FoAU9ndq3T/9ARP/FqFsggIv0Ao9FCUwHQYDVR0OBBYEFF9Y7UwxeqJhQo1SgLqz
# YZcZojKbMA4GA1UdDwEB/wQEAwIBhjASBgNVHRMBAf8ECDAGAQH/AgEAMBMGA1Ud
# JQQMMAoGCCsGAQUFBwMIMBEGA1UdIAQKMAgwBgYEVR0gADBMBgNVHR8ERTBDMEGg
# P6A9hjtodHRwOi8vY3JsLnNlY3RpZ28uY29tL1NlY3RpZ29QdWJsaWNUaW1lU3Rh
# bXBpbmdSb290UjQ2LmNybDB8BggrBgEFBQcBAQRwMG4wRwYIKwYBBQUHMAKGO2h0
# dHA6Ly9jcnQuc2VjdGlnby5jb20vU2VjdGlnb1B1YmxpY1RpbWVTdGFtcGluZ1Jv
# b3RSNDYucDdjMCMGCCsGAQUFBzABhhdodHRwOi8vb2NzcC5zZWN0aWdvLmNvbTAN
# BgkqhkiG9w0BAQwFAAOCAgEAEtd7IK0ONVgMnoEdJVj9TC1ndK/HYiYh9lVUacah
# RoZ2W2hfiEOyQExnHk1jkvpIJzAMxmEc6ZvIyHI5UkPCbXKspioYMdbOnBWQUn73
# 3qMooBfIghpR/klUqNxx6/fDXqY0hSU1OSkkSivt51UlmJElUICZYBodzD3M/SFj
# eCP59anwxs6hwj1mfvzG+b1coYGnqsSz2wSKr+nDO+Db8qNcTbJZRAiSazr7KyUJ
# Go1c+MScGfG5QHV+bps8BX5Oyv9Ct36Y4Il6ajTqV2ifikkVtB3RNBUgwu/mSiSU
# ice/Jp/q8BMk/gN8+0rNIE+QqU63JoVMCMPY2752LmESsRVVoypJVt8/N3qQ1c6F
# ibbcRabo3azZkcIdWGVSAdoLgAIxEKBeNh9AQO1gQrnh1TA8ldXuJzPSuALOz1Uj
# b0PCyNVkWk7hkhVHfcvBfI8NtgWQupiaAeNHe0pWSGH2opXZYKYG4Lbukg7HpNi/
# KqJhue2Keak6qH9A8CeEOB7Eob0Zf+fU+CCQaL0cJqlmnx9HCDxF+3BLbUufrV64
# EbTI40zqegPZdA+sXCmbcZy6okx/SjwsusWRItFA3DE8MORZeFb6BmzBtqKJ7l93
# 9bbKBy2jvxcJI98Va95Q5JnlKor3m0E7xpMeYRriWklUPsetMSf2NvUQa/E5vVye
# fQIwggYaMIIEAqADAgECAhBiHW0MUgGeO5B5FSCJIRwKMA0GCSqGSIb3DQEBDAUA
# MFYxCzAJBgNVBAYTAkdCMRgwFgYDVQQKEw9TZWN0aWdvIExpbWl0ZWQxLTArBgNV
# BAMTJFNlY3RpZ28gUHVibGljIENvZGUgU2lnbmluZyBSb290IFI0NjAeFw0yMTAz
# MjIwMDAwMDBaFw0zNjAzMjEyMzU5NTlaMFQxCzAJBgNVBAYTAkdCMRgwFgYDVQQK
# Ew9TZWN0aWdvIExpbWl0ZWQxKzApBgNVBAMTIlNlY3RpZ28gUHVibGljIENvZGUg
# U2lnbmluZyBDQSBSMzYwggGiMA0GCSqGSIb3DQEBAQUAA4IBjwAwggGKAoIBgQCb
# K51T+jU/jmAGQ2rAz/V/9shTUxjIztNsfvxYB5UXeWUzCxEeAEZGbEN4QMgCsJLZ
# UKhWThj/yPqy0iSZhXkZ6Pg2A2NVDgFigOMYzB2OKhdqfWGVoYW3haT29PSTahYk
# wmMv0b/83nbeECbiMXhSOtbam+/36F09fy1tsB8je/RV0mIk8XL/tfCK6cPuYHE2
# 15wzrK0h1SWHTxPbPuYkRdkP05ZwmRmTnAO5/arnY83jeNzhP06ShdnRqtZlV59+
# 8yv+KIhE5ILMqgOZYAENHNX9SJDm+qxp4VqpB3MV/h53yl41aHU5pledi9lCBbH9
# JeIkNFICiVHNkRmq4TpxtwfvjsUedyz8rNyfQJy/aOs5b4s+ac7IH60B+Ja7TVM+
# EKv1WuTGwcLmoU3FpOFMbmPj8pz44MPZ1f9+YEQIQty/NQd/2yGgW+ufflcZ/ZE9
# o1M7a5Jnqf2i2/uMSWymR8r2oQBMdlyh2n5HirY4jKnFH/9gRvd+QOfdRrJZb1sC
# AwEAAaOCAWQwggFgMB8GA1UdIwQYMBaAFDLrkpr/NZZILyhAQnAgNpFcF4XmMB0G
# A1UdDgQWBBQPKssghyi47G9IritUpimqF6TNDDAOBgNVHQ8BAf8EBAMCAYYwEgYD
# VR0TAQH/BAgwBgEB/wIBADATBgNVHSUEDDAKBggrBgEFBQcDAzAbBgNVHSAEFDAS
# MAYGBFUdIAAwCAYGZ4EMAQQBMEsGA1UdHwREMEIwQKA+oDyGOmh0dHA6Ly9jcmwu
# c2VjdGlnby5jb20vU2VjdGlnb1B1YmxpY0NvZGVTaWduaW5nUm9vdFI0Ni5jcmww
# ewYIKwYBBQUHAQEEbzBtMEYGCCsGAQUFBzAChjpodHRwOi8vY3J0LnNlY3RpZ28u
# Y29tL1NlY3RpZ29QdWJsaWNDb2RlU2lnbmluZ1Jvb3RSNDYucDdjMCMGCCsGAQUF
# BzABhhdodHRwOi8vb2NzcC5zZWN0aWdvLmNvbTANBgkqhkiG9w0BAQwFAAOCAgEA
# Bv+C4XdjNm57oRUgmxP/BP6YdURhw1aVcdGRP4Wh60BAscjW4HL9hcpkOTz5jUug
# 2oeunbYAowbFC2AKK+cMcXIBD0ZdOaWTsyNyBBsMLHqafvIhrCymlaS98+QpoBCy
# KppP0OcxYEdU0hpsaqBBIZOtBajjcw5+w/KeFvPYfLF/ldYpmlG+vd0xqlqd099i
# ChnyIMvY5HexjO2AmtsbpVn0OhNcWbWDRF/3sBp6fWXhz7DcML4iTAWS+MVXeNLj
# 1lJziVKEoroGs9Mlizg0bUMbOalOhOfCipnx8CaLZeVme5yELg09Jlo8BMe80jO3
# 7PU8ejfkP9/uPak7VLwELKxAMcJszkyeiaerlphwoKx1uHRzNyE6bxuSKcutisqm
# KL5OTunAvtONEoteSiabkPVSZ2z76mKnzAfZxCl/3dq3dUNw4rg3sTCggkHSRqTq
# lLMS7gjrhTqBmzu1L90Y1KWN/Y5JKdGvspbOrTfOXyXvmPL6E52z1NZJ6ctuMFBQ
# ZH3pwWvqURR8AgQdULUvrxjUYbHHj95Ejza63zdrEcxWLDX6xWls/GDnVNueKjWU
# H3fTv1Y8Wdho698YADR7TNx8X8z2Bev6SivBBOHY+uqiirZtg0y9ShQoPzmCcn63
# Syatatvx157YK9hlcPmVoa1oDE5/L9Uo2bC5a4CH2RwwggZMMIIEtKADAgECAhAV
# VO/doV4MRRGuXmkecKnEMA0GCSqGSIb3DQEBDAUAMFQxCzAJBgNVBAYTAkdCMRgw
# FgYDVQQKEw9TZWN0aWdvIExpbWl0ZWQxKzApBgNVBAMTIlNlY3RpZ28gUHVibGlj
# IENvZGUgU2lnbmluZyBDQSBSMzYwHhcNMjMwODA5MDAwMDAwWhcNMjYwODA4MjM1
# OTU5WjBjMQswCQYDVQQGEwJVUzEWMBQGA1UECAwNTmV3IEhhbXBzaGlyZTEdMBsG
# A1UECgwUQ2hyaXN0b3BoZXIgQ2hhcmxhbmQxHTAbBgNVBAMMFENocmlzdG9waGVy
# IENoYXJsYW5kMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAwLQAcUKQ
# zYs2WJY+W2fl+/1PzX3vsFwK/W9sj1RXRLBsQjsTCYRu+jRPEZSVzL/K4L877Wxb
# 69/ye88/RrWS0d6LUyohl0OgJwgRBXBsDIcpt3hTv7GRLAFvjzcCOvK6qk+kjf+b
# xqYSUOxfl/XDK0QvM3KgWbq2IeNHoMwvAXVFBcZnRPXp1FkcHGKf+nNwxP6VGWti
# RrhIj99q0R4iwOQaQLRY8pe8m1wn/gwFRai1F1f/Q2EMSyvbgf7kYpFNHJK17LZR
# 9J/G7P8h4QFQZJdMU6C4lRT+Lk2jEDF4elKF5c7DFjfMv2zd0jf3/2vOhaycGna9
# puKwQUvtwtrmcCwOI5EXBIVBcFVS8xD6eeREvzjZXiuS83quzwxVVjNBQ2f/nuK5
# 4huEBbNQQeNjSkMdjyr5S0Xwf8Pic5NA4ggLUWuv2XYqTTMtXHQPZ41noEJM+LSB
# ulBatGT98Tu0kib3MH7e1vREcTG7gZDnicmY0RfrWM59txft97gXP7Vj99ed9t2/
# 9niQleiT+YXy3ZpNoqGFB3XC13mM44xEff49vRSLN/B0IonG5vDpMgtFoKpqPtUx
# /oKQWtYbmoWFZkvEBRUeJOmkEmIUQonzE7aqgk/uGtyjxsBHtJzIHojA+8fGeD0N
# XjlOM1bbT0OcpSMkhRXPqiOELViMQwHrAiUCAwEAAaOCAYkwggGFMB8GA1UdIwQY
# MBaAFA8qyyCHKLjsb0iuK1SmKaoXpM0MMB0GA1UdDgQWBBSO6WwZWwCa6iKws6LE
# 4InGvJQl3zAOBgNVHQ8BAf8EBAMCB4AwDAYDVR0TAQH/BAIwADATBgNVHSUEDDAK
# BggrBgEFBQcDAzBKBgNVHSAEQzBBMDUGDCsGAQQBsjEBAgEDAjAlMCMGCCsGAQUF
# BwIBFhdodHRwczovL3NlY3RpZ28uY29tL0NQUzAIBgZngQwBBAEwSQYDVR0fBEIw
# QDA+oDygOoY4aHR0cDovL2NybC5zZWN0aWdvLmNvbS9TZWN0aWdvUHVibGljQ29k
# ZVNpZ25pbmdDQVIzNi5jcmwweQYIKwYBBQUHAQEEbTBrMEQGCCsGAQUFBzAChjho
# dHRwOi8vY3J0LnNlY3RpZ28uY29tL1NlY3RpZ29QdWJsaWNDb2RlU2lnbmluZ0NB
# UjM2LmNydDAjBggrBgEFBQcwAYYXaHR0cDovL29jc3Auc2VjdGlnby5jb20wDQYJ
# KoZIhvcNAQEMBQADggGBAENPYZO6JkhXuprRcjFErvAggFDfB4bJmvHwydUUq8EE
# dDkvVvS+SnqpaL+Nw5FY/X5GnIXfWKYvQJFY1o/bskqLBSH96jOk+wMWZ2LqfuyE
# uW4OZUvBtpho2E2QwcpCQQzG47c+qtENC6lITctyoOUi5481cm9VXRL0E1g/MSDO
# qpYcd32oKt6rbqLQZD89HFgkNrfh3a4wq2O8ljai9gvQJnYV4588DGI4quzv81b6
# mGDx9ku9zHhtvI19C1L+oQddqFFUViSwUUiNrBO7aA5iFwr1vQPkiP40Zd6fSSQA
# jrRnUI/kbK9oD2l1i/Vi9hfQ8SLarLPhW0M0qaut175+RJKlwuusUZADtgYVWcrm
# Mxy20RMCUZA2bnTWXjb4pVfHUyKPU7dpM+8gG/tUPBZegMWrzWqctSPQhdREpkLT
# MCm5E/o4ZUGNE0uo+twbGMGEyPPmjsFnIKLAqN2rHMI1Fz9pR+qMdixl+/mG/ElS
# JqGSDVArmZLn1IYhr4vQ8DCCBmIwggTKoAMCAQICEQCkKTtuHt3XpzQIh616Trck
# MA0GCSqGSIb3DQEBDAUAMFUxCzAJBgNVBAYTAkdCMRgwFgYDVQQKEw9TZWN0aWdv
# IExpbWl0ZWQxLDAqBgNVBAMTI1NlY3RpZ28gUHVibGljIFRpbWUgU3RhbXBpbmcg
# Q0EgUjM2MB4XDTI1MDMyNzAwMDAwMFoXDTM2MDMyMTIzNTk1OVowcjELMAkGA1UE
# BhMCR0IxFzAVBgNVBAgTDldlc3QgWW9ya3NoaXJlMRgwFgYDVQQKEw9TZWN0aWdv
# IExpbWl0ZWQxMDAuBgNVBAMTJ1NlY3RpZ28gUHVibGljIFRpbWUgU3RhbXBpbmcg
# U2lnbmVyIFIzNjCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBANOElfRu
# pFN48j0QS3gSBzzclIFTZ2Gsn7BjsmBF659/kpA2Ey7NXK3MP6JdrMBNU8wdmkf+
# SSIyjX++UAYWtg3Y/uDRDyg8RxHeHRJ+0U1jHEyH5uPdk1ttiPC3x/gOxIc9P7Gn
# 3OgW7DQc4x07exZ4DX4XyaGDq5LoEmk/BdCM1IelVMKB3WA6YpZ/XYdJ9JueOXeQ
# ObSQ/dohQCGyh0FhmwkDWKZaqQBWrBwZ++zqlt+z/QYTgEnZo6dyIo2IhXXANFkC
# HutL8765NBxvolXMFWY8/reTnFxk3MajgM5NX6wzWdWsPJxYRhLxtJLSUJJ5yWRN
# w+NBqH1ezvFs4GgJ2ZqFJ+Dwqbx9+rw+F2gBdgo4j7CVomP49sS7CbqsdybbiOGp
# B9DJhs5QVMpYV73TVV3IwLiBHBECrTgUfZVOMF0KSEq2zk/LsfvehswavE3W4aBX
# JmGjgWSpcDz+6TqeTM8f1DIcgQPdz0IYgnT3yFTgiDbFGOFNt6eCidxdR6j9x+kp
# cN5RwApy4pRhE10YOV/xafBvKpRuWPjOPWRBlKdm53kS2aMh08spx7xSEqXn4QQl
# dCnUWRz3Lki+TgBlpwYwJUbR77DAayNwAANE7taBrz2v+MnnogMrvvct0iwvfIA1
# W8kp155Lo44SIfqGmrbJP6Mn+Udr3MR2oWozAgMBAAGjggGOMIIBijAfBgNVHSME
# GDAWgBRfWO1MMXqiYUKNUoC6s2GXGaIymzAdBgNVHQ4EFgQUiGGMoSo3ZIEoYKGb
# MdCM/SwCzk8wDgYDVR0PAQH/BAQDAgbAMAwGA1UdEwEB/wQCMAAwFgYDVR0lAQH/
# BAwwCgYIKwYBBQUHAwgwSgYDVR0gBEMwQTA1BgwrBgEEAbIxAQIBAwgwJTAjBggr
# BgEFBQcCARYXaHR0cHM6Ly9zZWN0aWdvLmNvbS9DUFMwCAYGZ4EMAQQCMEoGA1Ud
# HwRDMEEwP6A9oDuGOWh0dHA6Ly9jcmwuc2VjdGlnby5jb20vU2VjdGlnb1B1Ymxp
# Y1RpbWVTdGFtcGluZ0NBUjM2LmNybDB6BggrBgEFBQcBAQRuMGwwRQYIKwYBBQUH
# MAKGOWh0dHA6Ly9jcnQuc2VjdGlnby5jb20vU2VjdGlnb1B1YmxpY1RpbWVTdGFt
# cGluZ0NBUjM2LmNydDAjBggrBgEFBQcwAYYXaHR0cDovL29jc3Auc2VjdGlnby5j
# b20wDQYJKoZIhvcNAQEMBQADggGBAAKBPqSGclEh+WWpLj1SiuHlm8xLE0SThI2y
# Luq+75s11y6SceBchpnKpxWaGtXc8dya1Aq3RuW//y3wMThsvT4fSba2AoSWlR67
# rA4fTYGMIhgzocsids0ct/pHaocLVJSwnTYxY2pE0hPoZAvRebctbsTqENmZHyOV
# jOFlwN2R3DRweFeNs4uyZN5LRJ5EnVYlcTOq3bl1tI5poru9WaQRWQ4eynXp7Pj0
# Fz4DKr86HYECRJMWiDjeV0QqAcQMFsIjJtrYTw7mU81qf4FBc4u4swphLeKRNyn9
# DDrd3HIMJ+CpdhSHEGleeZ5I79YDg3B3A/fmVY2GaMik1Vm+FajEMv4/EN2mmHf4
# zkOuhYZNzVm4NrWJeY4UAriLBOeVYODdA1GxFr1ycbcUEGlUecc4RCPgYySs4d00
# NNuicR4a9n7idJlevAJbha/arIYMEuUqTeRRbWkhJwMKmb9yEvppRudKyu1t6l21
# sIuIZqcpVH8oLWCxHS0LpDRF9Y4jijCCBoIwggRqoAMCAQICEDbCsL18Gzrno7Pd
# NsvJdWgwDQYJKoZIhvcNAQEMBQAwgYgxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpO
# ZXcgSmVyc2V5MRQwEgYDVQQHEwtKZXJzZXkgQ2l0eTEeMBwGA1UEChMVVGhlIFVT
# RVJUUlVTVCBOZXR3b3JrMS4wLAYDVQQDEyVVU0VSVHJ1c3QgUlNBIENlcnRpZmlj
# YXRpb24gQXV0aG9yaXR5MB4XDTIxMDMyMjAwMDAwMFoXDTM4MDExODIzNTk1OVow
# VzELMAkGA1UEBhMCR0IxGDAWBgNVBAoTD1NlY3RpZ28gTGltaXRlZDEuMCwGA1UE
# AxMlU2VjdGlnbyBQdWJsaWMgVGltZSBTdGFtcGluZyBSb290IFI0NjCCAiIwDQYJ
# KoZIhvcNAQEBBQADggIPADCCAgoCggIBAIid2LlFZ50d3ei5JoGaVFTAfEkFm8xa
# FQ/ZlBBEtEFAgXcUmanU5HYsyAhTXiDQkiUvpVdYqZ1uYoZEMgtHES1l1Cc6HaqZ
# zEbOOp6YiTx63ywTon434aXVydmhx7Dx4IBrAou7hNGsKioIBPy5GMN7KmgYmuu4
# f92sKKjbxqohUSfjk1mJlAjthgF7Hjx4vvyVDQGsd5KarLW5d73E3ThobSkob2SL
# 48LpUR/O627pDchxll+bTSv1gASn/hp6IuHJorEu6EopoB1CNFp/+HpTXeNARXUm
# dRMKbnXWflq+/g36NJXB35ZvxQw6zid61qmrlD/IbKJA6COw/8lFSPQwBP1ityZd
# wuCysCKZ9ZjczMqbUcLFyq6KdOpuzVDR3ZUwxDKL1wCAxgL2Mpz7eZbrb/JWXiOc
# NzDpQsmwGQ6Stw8tTCqPumhLRPb7YkzM8/6NnWH3T9ClmcGSF22LEyJYNWCHrQqY
# ubNeKolzqUbCqhSqmr/UdUeb49zYHr7ALL8bAJyPDmubNqMtuaobKASBqP84uhqc
# RY/pjnYd+V5/dcu9ieERjiRKKsxCG1t6tG9oj7liwPddXEcYGOUiWLm742st50jG
# wTzxbMpepmOP1mLnJskvZaN5e45NuzAHteORlsSuDt5t4BBRCJL+5EZnnw0ezntk
# 9R8QJyAkL6/bAgMBAAGjggEWMIIBEjAfBgNVHSMEGDAWgBRTeb9aqitKz1SA4dib
# wJ3ysgNmyzAdBgNVHQ4EFgQU9ndq3T/9ARP/FqFsggIv0Ao9FCUwDgYDVR0PAQH/
# BAQDAgGGMA8GA1UdEwEB/wQFMAMBAf8wEwYDVR0lBAwwCgYIKwYBBQUHAwgwEQYD
# VR0gBAowCDAGBgRVHSAAMFAGA1UdHwRJMEcwRaBDoEGGP2h0dHA6Ly9jcmwudXNl
# cnRydXN0LmNvbS9VU0VSVHJ1c3RSU0FDZXJ0aWZpY2F0aW9uQXV0aG9yaXR5LmNy
# bDA1BggrBgEFBQcBAQQpMCcwJQYIKwYBBQUHMAGGGWh0dHA6Ly9vY3NwLnVzZXJ0
# cnVzdC5jb20wDQYJKoZIhvcNAQEMBQADggIBAA6+ZUHtaES45aHF1BGH5Lc7JYzr
# ftrIF5Ht2PFDxKKFOct/awAEWgHQMVHol9ZLSyd/pYMbaC0IZ+XBW9xhdkkmUV/K
# bUOiL7g98M/yzRyqUOZ1/IY7Ay0YbMniIibJrPcgFp73WDnRDKtVutShPSZQZAdt
# FwXnuiWl8eFARK3PmLqEm9UsVX+55DbVIz33Mbhba0HUTEYv3yJ1fwKGxPBsP/Mg
# TECimh7eXomvMm0/GPxX2uhwCcs/YLxDnBdVVlxvDjHjO1cuwbOpkiJGHmLXXVNb
# sdXUC2xBrq9fLrfe8IBsA4hopwsCj8hTuwKXJlSTrZcPRVSccP5i9U28gZ7OMzoJ
# GlxZ5384OKm0r568Mo9TYrqzKeKZgFo0fj2/0iHbj55hc20jfxvK3mQi+H7xpbzx
# ZOFGm/yVQkpo+ffv5gdhp+hv1GDsvJOtJinJmgGbBFZIThbqI+MHvAmMmkfb3fTx
# mSkop2mSJL1Y2x/955S29Gu0gSJIkc3z30vU/iXrMpWx2tS7UVfVP+5tKuzGtgkP
# 7d/doqDrLF1u6Ci3TpjAZdeLLlRQZm867eVeXED58LXd1Dk6UvaAhvmWYXoiLz4J
# A5gPBcz7J311uahxCweNxE+xxxR3kT0WKzASo5G/PyDez6NHdIUKBeE3jDPs2ACc
# 6CkJ1Sji4PKWVT0/MYIGQTCCBj0CAQEwaDBUMQswCQYDVQQGEwJHQjEYMBYGA1UE
# ChMPU2VjdGlnbyBMaW1pdGVkMSswKQYDVQQDEyJTZWN0aWdvIFB1YmxpYyBDb2Rl
# IFNpZ25pbmcgQ0EgUjM2AhAVVO/doV4MRRGuXmkecKnEMA0GCWCGSAFlAwQCAQUA
# oIGEMBgGCisGAQQBgjcCAQwxCjAIoAKAAKECgAAwGQYJKoZIhvcNAQkDMQwGCisG
# AQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcN
# AQkEMSIEIMxzL32c7HrSt0mP2/dIoexsgnL3H3kRRKHr+LuyyWHKMA0GCSqGSIb3
# DQEBAQUABIICAI2eP3XAf8QfEeP9FGuxVmrk9y7fBBdLaENRREQR2nEY4Aa/PJAV
# xDrCAlVU7Gvt+ucFLm5Do0T4NzLqdLU6m6KsSkHzQt7cHicWqbHk/e6T3hEmFCpQ
# 4CDA0BaE81qg6LHupqFR1pTDOI/ANGW1Sv1O8yx3I3EZjGaLaU2JmTMJAVIjc/jE
# 3/NmhJIBZwg7P+Gi5cxLyEOyvVB900yOFLYaq6/VprCcIdWF8Jc6hHtb14417pe0
# Tw9yOdL8D1qtg+881IfCk6i8T5mY49F7gAjhKLtogd8YgKUtYMQNsd5PDtrO2w09
# ueZF5l6AL4HtP5XXsHe7Vdu6myNUwZMauZnby3Y2JBUrT+GT/ZWZmNwxg3bcVnjc
# Qzu3joyUYdEEj0P2DGMzC6fRxXlWA9ugsbNwQHPa4QhcVSz8UuDQlwLnIUMvWeZf
# AVFVyCIUMvySrMRR27fkbTIoedWaL2eR2w0IJijTpImC4HfEWb52VzAmpMC4IoQy
# pbIxZyqQkh/4eND8nn0e3OyBy5icb9RE2+S77EVbyLXN3+9kjA+z76ucWWqDMKNK
# BqepOYoGtx4oOXqZm3StUzvCQG5FYV7TKCajkuWsVBML/1R33RIQlYfWiCFRfvAy
# hDDbPOyxr0+MvTTpjz9m/IlrQrY0UnmJckwHL9HYoFkRCORjxn1lI/o0oYIDIzCC
# Ax8GCSqGSIb3DQEJBjGCAxAwggMMAgEBMGowVTELMAkGA1UEBhMCR0IxGDAWBgNV
# BAoTD1NlY3RpZ28gTGltaXRlZDEsMCoGA1UEAxMjU2VjdGlnbyBQdWJsaWMgVGlt
# ZSBTdGFtcGluZyBDQSBSMzYCEQCkKTtuHt3XpzQIh616TrckMA0GCWCGSAFlAwQC
# AgUAoHkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUxDxcN
# MjYwNjAzMjAzMDI4WjA/BgkqhkiG9w0BCQQxMgQwlyUfwTkSmYvXS8vYJCNUUS16
# OUF2OXlDcp/O5w6x52JHclMno6qDZZtqcVys3o6YMA0GCSqGSIb3DQEBAQUABIIC
# ADZ7kXC3DF8Ocvv8dLDQsN/j9b177Xp4fZuRi0QkVEklbh+uxE6qxSOEiUiOaiaj
# r6w93QevdBL1x2biLSzRct0QCT08PrK99AfXffaf7+lGHOBVEPfPcTKgKJWu+dlU
# RdWA+9rmlvMJHeZnKfPlTPiDAxme3XSSjyE0Bx81mRyiaJra0xSpfxmyTozdE74y
# nPLNL7xr+dn6Cdw0Iv7ww4XspTT3Wf4xJLZjEDfjchrlzxr8zA2fkHFvj11Zsouq
# 9rDrolDM27S+k/rNcnLNbaeMalHR1P2501x+P6i8BHDe3COdWqbQe6BZw+SJupMH
# 79gGDwrQAVfpTIPpvhEX8iI+QhfpdHniN5ZEDCZCFtD6qXTJ2pzFMSkkF2fb7HWF
# It/uNOZKKII3sr9Hb3aw4h/SW1tL5SnPlp2yjFR6+MUVHFpAT7LYqTxarBe5bP8n
# TmFrgsEja7UI6XF3uAaEuIJ/8xgLKftcKy5tdIK9VlJfqtVZcrTOWiQszs5duK7t
# eSwJbuWxDXKo9Z/o7tzpToClX93fbTXfzWerKgpUvBl8I4OsKcIMQBDjZjYW1pFl
# qkos/AIi7wjpPSH7UELURphhV4gwtnIqscOker0rnAo4Zb9QDrBoqbIdqDEhpWQE
# 4mCr+KaZHoH1rRfTNPSzxP9mTB5RsfhJfAhvSoW2Mu6P
# SIG # End signature block
