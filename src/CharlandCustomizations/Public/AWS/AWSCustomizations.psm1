<#
.SYNOPSIS
    AWS PowerShell Customizations and scripts.
#>
Write-Verbose  "Loading AWSCustomizations.psm1"

# Load private helper functions needed by this nested module
. "$PSScriptRoot/../../Private/New-AWSParamSplat.ps1"

# Module-level cache for SSO tokens to avoid repeated authentication
$script:SSOTokenCache = @{}
function  Get-AWSMFASession {
  <#
  .SYNOPSIS
    Changes your active AWS connection to a temporary session using MFA Authentiation.
  .EXAMPLE
    PS C:\> Set-AWSCredential -Credential (Get-AWSMFASession -TokenCode <OTP>)

    Changes your active AWS sessio
  #>
  param(
    [Parameter(mandatory = $true)]
    [string]$TokenCode
  )
  return Get-STSSessionToken -SerialNumber (Get-IAMMFADevice).SerialNumber -TokenCode $TokenCode
}

function MFAHOW {
  <# reminders for me on how to gete session credentials witha  MFA token #>
  Write-Output  "HowToMFA:  Set-AWSCredential -Credential (Get-AWSMFASession -TokenCode <OTP>)"
  Write-Output "HowtoMFA:  Set-AWSCredential -Credential (Set-AWSProfleWithMFA -Profile <profilename> -TokenCode <OTP> -Region <Region>"
}
function Find-CFNStackErrors {
  <#
.SYNOPSIS
   Finds Stacks and resources in an "error state".
.DESCRIPTION
    Script reports any stack or resource where "StatusReason" has a non-null value
.EXAMPLE
    PS C:\> Find-CFNSTackErrors

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
    $Credential,

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


function Set-AWSProfileWithMFA {
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
    PS C:\> Set-AWSCredential -Credential (Set-AWSProfileWithMFA -ProfileName myprofile -TokenCode 123456)

    Authenticates with MFA and sets the returned credentials as the active session.

.EXAMPLE
    PS C:\> Set-AWSProfileWithMFA -ProfileName myprofile -TokenCode 123456 -Region us-east-1

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
    $Credential,

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

function Set-AWSEnv {
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
  PS> Set-AWSEnv
  Sets AWS environment variables from current credential
  
.EXAMPLE
  PS> Set-AWSEnv -WhatIf
  Shows what environment variables would be set without actually setting them
  
.EXAMPLE
  PS> Set-AWSEnv -Confirm:$false
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
function Remove-ExpiredAWSProfiles {
  <#
  .SYNOPSIS
    Removes expired temporary credentials stored in local credential stores.
  .DESCRIPTION
    Tests all AWS Profiles by calling Get-STSCallerIdentity. If the call fails with an
    ExpiredToken error, the profile is removed from the credential store.
  .EXAMPLE
    Remove-ExpiredAWSProfiles
    Scans all profiles with a credential file location and removes any with expired tokens.
  #>
  [CmdletBinding()]
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
        Remove-AWSCredentialProfile -ProfileName $profileItem.ProfileName
      }
      else {
        Write-Verbose "Profile '$($profileItem.ProfileName)' failed with non-expired error: $_"
      }
    }
  }
}
function Get-AccountListFromProfiles {
  <#
  .SYNOPSIS
    Lists  AWS ProfileName, Account, and AccountAlias
  #>
  Get-AWSCredential -ListProfileDetail  | ForEach-Object { Select-Object -InputObject $_   Profilename, @{Name = "Account"; Expression = { (Get-STSCallerIdentity -ProfileName  $_.ProfileName).Account } }, @{Name = "AccountAlias"; Expression = { Get-IAMAccountAlias -ProfileName  $_.ProfileName } } }
}

function Test-CFNTemplateFromFile {
  <#
  .SYNOPSIS
    Validates a CloudFormation template from a local file.
  .DESCRIPTION
    Reads a CloudFormation template file and validates it using the AWS CFN API.
  .PARAMETER Path
    Path to the CloudFormation template file.
  .EXAMPLE
    Test-CFNTemplateFromFile -Path ./templates/my-stack.yaml
  #>
  param (
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ })]
    [string]$Path
  )
  Test-CFNTemplate -TemplateBody (Get-Content -Raw -Path $Path)
}

function Start-MultiStackDriftDetection {
  <#
.SYNOPSIS
  Detects drift on all stacks passed into the function
.DESCRIPTION
  Start-MultiStackDriftDetection  will detect Stack drift on all stack names passed into it,
  and will bypass the stacks that it doesn't make sense to do the drift detection on.

.EXAMPLE
  PS C:\> (Get-CFNstack).StackName |Select-Object -first 5  |Start-MultiStackDriftDetection
  Starts a drift detection of the first 5 stacks listed.

.EXAMPLE
PS C:\> Start-MultiStackDriftDetection

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
    $Credential,

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

function Get-AWSAccountListOfDriftedResources {
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
    Get-AWSAccountListOfDriftedResources -Region us-east-1 -ProfileName myprofile

.EXAMPLE
    Get-AWSAccountListOfDriftedResources -StackRootARN 'arn:aws:cloudformation:us-east-1:123456789012:stack/root/guid'
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
    $Credential,

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

function Get-AWSObjectCount {
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
    PS C:\> .\Get-AWSObjectCount.ps1 |Format-Table



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
PS C:\> .\Get-AWSObjectCount.ps1 -Region us-east-1


Region      : us-east-1
StackCount  : 53
VPCCount    : 3
EC2Count    : 0
BucketCount : 13
LambdaCount : 36
ScanOk      : True

.EXAMPLE
.\Get-AWSObjectCount.ps1 -Region @('us-east-1','us-east-2') |Format-Table


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
    $Credential,

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
#>
function Use-AssumedRole($Role) {
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
# Update-SSOCredentialList Function
# ================================================================================================

function Update-SSOCredentialList {
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
    Update-SSOCredentialList -StartUrl 'https://d-1234567890.awsapps.com/start' -Region 'us-east-1'

.EXAMPLE
    Update-SSOCredentialList -StartUrl 'https://mycompany.awsapps.com/start' -Region 'us-east-1' `
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
    $Credential,

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