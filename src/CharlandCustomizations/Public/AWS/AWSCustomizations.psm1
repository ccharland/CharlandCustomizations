<#
.SYNOPSIS
    AWS PowerShell Customizations and scripts.
#>
Write-Verbose  "Loading AWSCustomizations.psm1"

# Load private helper functions needed by this nested module (added by Kiro, aws-common-params spec)
. "$PSScriptRoot/../../Private/New-AWSParamSplat.ps1"
. "$PSScriptRoot/../Test-CHARAWSCmdlet.ps1"

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
  @(
      'Get-STSSessionToken',
      'Get-IAMMFADevice'
  ) | Test-CHARAWSCmdlet | Out-Null

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
    @(
        'Get-STSCallerIdentity',
        'Get-CFNStack'
    ) | Test-CHARAWSCmdlet | Out-Null

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
    @(
        'Get-STSSessionToken',
        'Get-IAMMFADevice'
    ) | Test-CHARAWSCmdlet | Out-Null

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
  $null = Test-CHARAWSCmdlet -Name 'Get-STSCallerIdentity'


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
  $null = Test-CHARAWSCmdlet -Name 'Get-STSCallerIdentity'


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
  @(
      'Get-STSCallerIdentity',
      'Get-IAMAccountAlias'
  ) | Test-CHARAWSCmdlet | Out-Null
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
    $null = Test-CHARAWSCmdlet -Name 'Get-CFNstack'

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
    $null = Test-CHARAWSCmdlet -Name 'Get-CFNstack'

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
    $Region,

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
    @(
        'Get-EC2Region',
        'Get-S3Bucket',
        'Get-CFNStack',
        'Get-LMFunctionList'
    ) | Test-CHARAWSCmdlet | Out-Null

if (-not $MyInvocation.ExpectingInput -and -not $Region) {
  $Region = (Get-EC2Region).RegionName
}

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
  @(
      'Get-STSCallerIdentity',
      'Get-IAMRole'
  ) | Test-CHARAWSCmdlet | Out-Null
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
    When -SaveCredentials is used, config-file updates are skipped and only credentials
    are refreshed.

    Generated profile names follow the pattern:
      [ProfilePrefix-]<RoleName>-<AccountIdentifier>

    By default, AccountIdentifier is the AWS account ID. Use -UseAccountName to use
    account name instead.

.PARAMETER StartUrl
    The AWS SSO start URL (e.g., https://d-1234567890.awsapps.com/start).

.PARAMETER SSOSessionName
    The sso_session name written into the config file and referenced by each profile.
    If not specified, a sanitized name is derived from the StartUrl host
    (e.g., 'd1234567890' from https://d-1234567890.awsapps.com/start).

.PARAMETER Region
    The AWS region where IAM Identity Center is configured (e.g., us-east-1).

.PARAMETER ProfileName
    AWS credential profile used for initial authentication. Optional.

.PARAMETER ProfilePrefix
    Optional prefix prepended to each generated profile name, separated by a hyphen.
    Example: -ProfilePrefix 'ExampleOrg' produces 'ExampleOrg-AWSAdminAccess-123456789012'.

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
    When specified, this function does not modify the AWS config file.
.PARAMETER UseAccountName
  When specified, generated profile names use AWS account name instead of account ID.
  Example: AWSAdministratorAccess-dev-account instead of
  AWSAdministratorAccess-123456789012.

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
    Update-CHARSSOCredentialList -StartUrl 'https://d-1234567890.awsapps.com/start' `
        -SSOSessionName 'ExampleOrg' -Region 'us-east-1' -Force

    Writes SSO-style profiles to ~/.aws/config using 'ExampleOrg' as the sso_session name.
    Output:
        [sso-session ExampleOrg]
        sso_start_url = https://d-1234567890.awsapps.com/start
        sso_region = us-east-1
        ...

        [profile AWSAdministratorAccess-123456789012]
        sso_session = ExampleOrg
        sso_account_id = 123456789012
        sso_role_name = AWSAdministratorAccess
        region = us-east-1

.EXAMPLE
    Update-CHARSSOCredentialList -StartUrl 'https://d-1234567890.awsapps.com/start' `
        -SSOSessionName 'ExampleOrg' -ProfilePrefix 'ExampleOrg' -Region 'us-east-1' -Force

    Produces profiles named 'ExampleOrg-<RoleName>-<AccountId>'.

.EXAMPLE
    Update-CHARSSOCredentialList -StartUrl 'https://d-1234567890.awsapps.com/start' `
        -SSOSessionName 'ExampleOrg' -Region 'us-east-1' -SaveCredentials

  Persists temporary access key/secret/token to ~/.aws/credentials.
  Config-file updates are skipped in this mode.

.EXAMPLE
    Update-CHARSSOCredentialList -StartUrl 'https://d-1234567890.awsapps.com/start' `
        -SSOSessionName 'ExampleOrg' -Region 'us-east-1' -RoleFilter 'AWSAdministrator*' `
        -AccountFilter '123456789012'

    Only writes profiles matching the specified role and account filters.

.EXAMPLE
    Update-CHARSSOCredentialList -StartUrl 'https://d-1234567890.awsapps.com/start' `
        -SSOSessionName 'ExampleOrg' -Region 'us-east-1' `
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
    [switch]$UseAccountName,

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
    @(
        'Register-SSOOIDCClient',
        'Get-SSOAccountList'
    ) | Test-CHARAWSCmdlet | Out-Null

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
    if (-not $SaveCredentials) {
      $configDir = Split-Path $ConfigFile -Parent
      if ($configDir -and -not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
        Write-Verbose "Created directory: $configDir"
      }
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

      $verificationCode = if ($device.UserCode) { $device.UserCode } else { $device.DeviceCode }
      Write-Verbose "Opening browser for SSO authentication..."
      Write-Output "SSO verification code: $verificationCode"
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

    $configContent = ''
    if (-not $SaveCredentials) {
      # Read existing config or start fresh
      if (Test-Path $ConfigFile) {
        $configContent = Get-Content $ConfigFile -Raw
      }

      # Only add sso-session block if not already present
      if ($configContent -notmatch "(?m)^\[sso-session $([regex]::Escape($SSOSessionName))\]") {
        $configContent = "$ssoSessionBlock`n`n$configContent"
        Write-Verbose "Added [sso-session $SSOSessionName] block to config."
      }
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
        $accountIdentifier = $account.AccountId
        if ($UseAccountName -and -not [string]::IsNullOrWhiteSpace($account.AccountName)) {
          $sanitizedAccountName = (($account.AccountName -replace '[^a-zA-Z0-9\-]', '-') -replace '-{2,}', '-').Trim('-')
          if ($sanitizedAccountName) { $accountIdentifier = $sanitizedAccountName }
        }

        $generatedProfileName = if ($ProfilePrefix) {
          "$ProfilePrefix-$($role.RoleName)-$accountIdentifier"
        } else {
          "$($role.RoleName)-$accountIdentifier"
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

            if (-not $SaveCredentials) {
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
    if (-not $SaveCredentials) {
      if ($Force -or $PSCmdlet.ShouldProcess("AWS config file '$ConfigFile'", 'Write updated SSO configuration')) {
        Set-Content -Path $ConfigFile -Value $configContent.TrimEnd() -Encoding UTF8
        Write-Verbose "Config written to: $ConfigFile"
      }
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
# MIIgygYJKoZIhvcNAQcCoIIguzCCILcCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCC+9/KbQ5rhG7np
# HtuAud9BVDiPcmSI3lJVx4NbjLBGUqCCG1gwggN5MIIC/qADAgECAhAcz51nzeIZ
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
# BCAJ6bCYrLi/MAp7iJER/sMTFEhjgyynstS2jVhnB8rgVjALBgcqhkjOPQIBBQAE
# ZjBkAjAvDKhKeUmD3IyVF9N+h0iAFB3EpaxP1La3SOQ65hVuY7THSOEgKAWy6pJ7
# SJwZx0QCMC6SBSMPjo0HQy2Esm2IL+KRo3SnGRvGWj+8y1IBQEKZaGmC3G/AYt6A
# 5Ca7qQChwKGCAyMwggMfBgkqhkiG9w0BCQYxggMQMIIDDAIBATBqMFUxCzAJBgNV
# BAYTAkdCMRgwFgYDVQQKEw9TZWN0aWdvIExpbWl0ZWQxLDAqBgNVBAMTI1NlY3Rp
# Z28gUHVibGljIFRpbWUgU3RhbXBpbmcgQ0EgUjQxAhEA507yVbBQT/rbpt/3/Iuj
# FTANBglghkgBZQMEAgIFAKB5MBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJ
# KoZIhvcNAQkFMQ8XDTI2MDgyMzIxMTMyNlowPwYJKoZIhvcNAQkEMTIEMHQ6Wpq5
# APhaJ42jJWRo/rgsloc4+VXqv8yhC0fEKToQrC1ovnrrV3A1u3PDC0XHhjANBgkq
# hkiG9w0BAQEFAASCAgBkhBmhfHWBkGl4BpY8UNYQU3HY2kb6wROgTk2ZblrTEpJ0
# W20nX4ObFSqdUe86MxR6w5kATwWx6hSwxbnu7hB9cwdakWrpUbMuGZJTN7/lQ8Ja
# PpJrZtYPn/oEDY+ZvkqWEDKL1NNFM5Je5Hk70FmKmAKUSyrbhmO9MdmrdcwEscD5
# Qg3wjtd3zkMM+9hCALQnXwobbCnZ30X62b76+sm1qVIWwQFP1ys4rdd1UQK0WZwX
# 1btwDd97Y+8/hPiIFkWGHxlgHDsXtus9pBVzOLzhY7l7juWxe/xsTXInDqtnUGsm
# oAKficQG+lsDKIgUFWS2WbhyRx1iypwwvDZIyC8D+drcTE+yuy9Kms55GGIxGguV
# 90FFs4vEsKzzRcpkjcAISAG6k631NNZlkHlGT6U03sUZe3YhVmR3eJlp5yCGZNb4
# 48JlVJHMkAFDj98mgRZQKtlF61r0g08lc99aqaxHko0yR3LxZwfcOywrwdrRjvnh
# qOtaz6LBIWAxG4Zs8HCZ+LnvUfqMLqhPBYcSlgbKF4tUzUWWshoUpdcy0ixjWPQo
# popehPIEDk+43D3F+O2CpFBePzTo4SLoUZPqPDx2z06EmpI36+D4AA6YAwfK2r54
# kzUlgwUPdaG3SGhS9XuG2RWVr2QNNedAYzTNnySP+7V2ebaFtv+YkbtKso4kBw==
# SIG # End signature block
