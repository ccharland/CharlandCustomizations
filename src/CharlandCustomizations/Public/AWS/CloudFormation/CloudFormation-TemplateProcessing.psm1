<#
.SYNOPSIS
CloudFormation Template Processing PowerShell Module

.DESCRIPTION
Provides functions for CloudFormation template and stack management using directory-based structures.

.NOTES
Version: 1.0
Requires: AWS PowerShell module and valid credentials
Author: code written by Amazon Q and Copilot, reviewed  by ccharland
#>

# Constants
# File naming conventions and private helpers are defined in Private/CFNPrivateFunctions.ps1
# Added by Kiro (aws-common-params spec): dot-source New-AWSParamSplat for nested module scope
. "$PSScriptRoot/../../../Private/New-AWSParamSplat.ps1"
. "$PSScriptRoot/../../../Private/CFNPrivateFunctions.ps1"
. "$PSScriptRoot/../../Test-CHARAWSCmdlet.ps1"
Set-Variable -Name S3_BUCKET_PATTERN -Value 'cf-templates-*' -Option ReadOnly -Scope Script

<#
.SYNOPSIS
Creates CloudFormation stacks from directory structure.

.DESCRIPTION
Deploys one or more CloudFormation stacks using a directory-based convention where each
subdirectory contains a template.template, parameters.json, tags.json, and capabilities.json.
Templates are uploaded to S3 and validated before stack creation.

.PARAMETER Path
Directory containing stack subdirectories. Defaults to current location.

.PARAMETER StackName
Specific stack name or all directories if not specified.

.PARAMETER Region
AWS region. Defaults to default region.

.PARAMETER ProfileName
    AWS credential profile name. Optional.

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

.PARAMETER VerifyOnly
Validate only, don't create stack.

.EXAMPLE
New-CHARCFNStackFromDirectory -StackName MyStack -VerifyOnly
#>
function New-CHARCFNStackFromDirectory {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param (
        $Path = (Get-Location).Path,
        $StackName = $null,
        [switch]$VerifyOnly,

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
            'Get-S3Bucket',
            'Test-CFNTemplate'
        ) | Test-CHARAWSCmdlet | Out-Null

        if (-not $Region) {
            $Region = Get-DefaultAWSRegionName
        }
        if ($null -eq $Region) {
            throw "No AWS region specified and no default region configured. Please specify -Region parameter or configure a default region."
        }

        $awsParams = New-AWSParamSplat -BoundParameters $PSBoundParameters

        $AccountID = (Get-STSCallerIdentity @awsParams).Account
        Write-Verbose "AccountId: $AccountId"
        Write-Verbose "Region: $Region"
        Write-Verbose "Path: $Path"
        $TemplateBucket = (Get-S3Bucket @awsParams | Where-Object BucketName -Like "cf-templates-*$Region").BucketName
        if (-not $TemplateBucket) {
            throw "No S3 bucket found for CloudFormation templates in region $Region. Please ensure you have the correct permissions and the bucket exists (cf-templates-<random>-$Region)."
        }

        if ($null -ne $StackName) {
            if (Test-Path -Path (Join-Path -Path $Path $StackName)) {
                Write-Verbose "Path verified for StackName: $StackName"
            }
            else {
                throw "The specified StackName path does not exist: $StackName"
            }
        }
        else {
            $StackName = (Get-ChildItem -Path $Path -Directory).Name
            if ($StackName.Count -gt 1) {
                if ($PSCmdlet.ShouldProcess('CreateStacks', "Deploy $($StackName.Count) stacks in path: $Path")) {
                    Write-Verbose "Multiple stacks found in path: $Path. Deploying all stacks."
                }
                else {
                    Write-Warning "Multiple stacks found in path: $Path. Use -StackName to specify a single stack to deploy."
                    return
                }
            }
            else {
                Write-Verbose "Single stack found in path: $Path. Deploying stack: $($StackName[0])"
            }
            Write-Verbose "Deploying all stacks in path: $Path"
        }
    }

    process {
        foreach ($Name in $StackName) {
            $StackPath = Join-Path -Path $Path -ChildPath $Name
            Write-Verbose "Processing stack: $Name in path: $StackPath"
            if (-not (Test-Path -Path ([CFNStackDirectoryInfo]::GetTemplatePath($StackPath)))) {
                Write-Error "Template file not found in stack directory: $StackPath"
                continue
            }

            $TemplateS3Key = [CFNStackDirectoryInfo]::NewTemplateS3Key($name)

            Write-S3Object -BucketName $TemplateBucket -Key $TemplateS3Key -File ([CFNStackDirectoryInfo]::GetTemplatePath($StackPath)) @awsParams

            $TemplateS3Url = Get-S3PreSignedURL -BucketName $TemplateBucket -Key $TemplateS3Key @awsParams -Expires (Get-Date).AddHours(1)
            Write-Verbose "template S3 URL: $TemplateS3Url"

            if (Test-Path -Path ([CFNStackDirectoryInfo]::GetParametersPath($StackPath))) {
                $TemplateParameters = Get-Content -Path ([CFNStackDirectoryInfo]::GetParametersPath($StackPath)) -Raw | ConvertFrom-Json
            }
            else {
                $TemplateParameters = @()
            }

            if (Test-Path -Path ([CFNStackDirectoryInfo]::GetTagsPath($StackPath))) {
                $Tags = Get-Content -Path ([CFNStackDirectoryInfo]::GetTagsPath($StackPath)) -Raw | ConvertFrom-Json
            }
            else {
                $Tags = @()
            }

            if (Test-Path -Path ([CFNStackDirectoryInfo]::GetCapabilitiesPath($StackPath))) {
                $TemplateCapabilities = Get-Content -Path ([CFNStackDirectoryInfo]::GetCapabilitiesPath($StackPath)) -Raw | ConvertFrom-Json
            }
            else {
                $TemplateCapabilities = @()
            }

            $TemplateTest = Test-CFNTemplate -TemplateURL $TemplateS3Url @awsParams

            if ($TemplateTest.Parameters.Count -ne $templateParameters.Count) {
                throw "Template parameter counts do not match between template parameters and parameters.json for stack $Name"
            }

            try {
                if ($VerifyOnly) {
                    Write-Output "`n$('*'*80)"
                    Write-Output 'Verification mode enabled. No stack will be created.'
                    Write-Output "Template URL: $TemplateS3Url"
                    Write-Output "$('*'*80)`n"
                    continue
                }
                Write-Verbose "Calling New-CFNStack for stack: $Name"
                if ($PSCmdlet.ShouldProcess("$Name in $Region", 'Create CloudFormation stack')) {
                    New-CFNStack -StackName $Name `
                        -TemplateURL $TemplateS3Url `
                        -Parameters $TemplateParameters `
                        -Capabilities $TemplateCapabilities `
                        @awsParams `
                        -Tags $Tags

                    Write-Output "New-CFNStack invoked for stack $Name in region $Region"
                }
                else {
                    Write-Verbose "Skipping stack creation for $Name in region $Region due to ShouldProcess."
                    continue
                }

            }
            catch {
                Write-Error "Failed to create stack $Name in region $Region. Error: $_"
                throw
            }
        }
    }

    end {
        Write-Output "Attempted to Deploy $($StackName.Count) stacks in region $Region"
    }
}

# ================================================================================================
# Verify-CHARCFNStackFromDirectory Function
# ================================================================================================

<#
.SYNOPSIS
Validates CloudFormation templates from directory structure.

.DESCRIPTION
Reads the template body from the stack directory and passes it to Test-CFNTemplate
for validation without creating or modifying any stacks.

.PARAMETER StackName
Stack names to validate.

.PARAMETER Region
AWS region.

.PARAMETER ProfileName
    AWS credential profile name. Optional.

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

.PARAMETER RootPath
Root directory path.

.PARAMETER TemplateName
Template filename. Defaults to the module constant.

.EXAMPLE
Test-CHARCFNStackFromDirectory -StackName "MyStack"
#>
function Test-CHARCFNStackFromDirectory {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string[]]
        $StackName,
        $RootPath = (Get-Location).Path,
        $TemplateName = [CFNStackDirectoryInfo]::TemplateFile,

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
            'Test-CFNTemplate'
        ) | Test-CHARAWSCmdlet | Out-Null

        if (-not $Region) {
            $Region = Get-DefaultAWSRegionName
        }
        if ($null -eq $Region) {
            throw "No AWS region specified and no default region configured. Please specify -Region parameter or configure a default region."
        }
        $awsParams = New-AWSParamSplat -BoundParameters $PSBoundParameters

        $AccountID = (Get-STSCallerIdentity @awsParams).Account
        Write-Verbose "AccountId: $AccountId"
        Write-Verbose "Region: $Region"
    }

    process {
        foreach ($Stack in $StackName) {
            Write-Verbose "Stack: $Stack"
            Write-Verbose "RootPath: $RootPath"
            $InputPath = Join-Path -Path $RootPath -ChildPath $Stack
            Write-Verbose "InputPath: $InputPath"
            $TemplatePath = Join-Path -Path $InputPath -ChildPath $TemplateName
            Write-Verbose "TemplatePath: $TemplatePath"
            if (-not (Test-Path -Path $TemplatePath)) {
                Write-Error "Template file not found: $TemplatePath"
            }
            try {
                $TemplateBody = Get-Content -Path $TemplatePath -Encoding utf8 -Raw
                Write-Debug "TemplateBody = $TemplateBody"

                Test-CFNTemplate -TemplateBody $TemplateBody @awsParams

            }
            catch {
                Write-Error "Error testing template: $TemplatePath"
            }
        }
    }
}

<#
.SYNOPSIS
Exports CloudFormation stack information to directory structure.

.DESCRIPTION
Retrieves a CloudFormation stack's template, parameters, tags, capabilities, outputs,
and metadata, then writes them to a directory structure organized as
{AccountID}/{Region}/{StackName}.

.PARAMETER StackName
Stack names to export.

.PARAMETER Region
AWS region.

.PARAMETER ProfileName
    AWS credential profile name. Optional.

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

.PARAMETER RootPath
Root export path.

.EXAMPLE
Out-CHARCFNStackInfo -StackName 'MyStack'
#>
function Out-CHARCFNStackInfo {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string[]]
        $StackName,
        $RootPath = (Get-Location).Path,

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
            'Get-CFNTemplate'
        ) | Test-CHARAWSCmdlet | Out-Null

        if (-not $Region) {
            $Region = Get-DefaultAWSRegionName
        }
        if ($Null -eq $Region) {
            throw "No AWS region specified and no default region configured. Please specify -Region parameter or configure a default region."
        }
        $awsParams = New-AWSParamSplat -BoundParameters $PSBoundParameters

        $AccountID = (Get-STSCallerIdentity @awsParams).Account
        Write-Verbose "AccountId: $AccountId"
        Write-Verbose "Region: $Region"

        $progressId = Get-Random -Minimum 1000 -Maximum 9999
        $processedCount = 0
    }

    process {
        foreach ($name in $StackName) {
            $processedCount++
            $activity = "Exporting CloudFormation stack info"
            $statusPrefix = "Stack ${processedCount}: $name"

            Write-Progress -Id $progressId -Activity $activity -Status "$statusPrefix (Preparing output path)" -PercentComplete 5
            $StackInfoPath = Join-Path -Path $RootPath -ChildPath (Join-Path -Path $AccountID -ChildPath (Join-Path -Path $Region -ChildPath $name))

            Write-Verbose "Saving stack info to $StackInfoPath"
            try {
                if (-not (Test-Path $StackInfoPath)) {
                    Write-Verbose "Creating $StackInfoPath"
                    New-Item -Path $StackInfoPath -ItemType Directory -Force | Out-Null
                }
                else {
                    Write-Verbose "Path $StackInfoPath already exists"
                }
            }
            catch {
                Write-Progress -Id $progressId -Activity $activity -Status "$statusPrefix (Failed to create output path)" -Completed
                Write-Error "Unable to create $StackInfoPath"
                throw $_
            }

            # save template to file
            Write-Progress -Id $progressId -Activity $activity -Status "$statusPrefix (Exporting templates)" -PercentComplete 35
            Write-Verbose "Saving template to $StackInfoPath"
            $Original = Get-CFNTemplate -StackName $name -TemplateStage Original @awsParams
            $Processed = Get-CFNTemplate -StackName $name -TemplateStage Processed @awsParams
            if ($Original -eq $Processed) {
                Write-Verbose 'No transforms in template'
                $TemplatePath = [CFNStackDirectoryInfo]::GetTemplatePath($StackInfoPath)
                $Original | Out-File -FilePath $TemplatePath
            }
            else {
                Write-Verbose 'Template has transforms'
                $TemplatePath = [CFNStackDirectoryInfo]::GetTemplatePath($StackInfoPath)
                $Original | Out-File -FilePath $TemplatePath
                $TemplatePath = Join-Path -Path $StackInfoPath -ChildPath ([CFNStackDirectoryInfo]::ProcessedTemplateFile)
                $Processed | Out-File -FilePath $TemplatePath
            }

            Write-Progress -Id $progressId -Activity $activity -Status "$statusPrefix (Exporting stack metadata)" -PercentComplete 70
            $StackInfo = Get-CFNStack -StackName $name @awsParams
            # Save items necessary to deploy stacks.
            Write-Verbose "Saving parameters to $([CFNStackDirectoryInfo]::GetParametersPath($StackInfoPath))"
            $StackInfo.Parameters | ConvertTo-Json -Depth 5 | Out-File -FilePath ([CFNStackDirectoryInfo]::GetParametersPath($StackInfoPath))
            Write-Verbose "Saving tags to $([CFNStackDirectoryInfo]::GetTagsPath($StackInfoPath))"
            $StackInfo.Tags | ConvertTo-Json -Depth 5 | Out-File -FilePath ([CFNStackDirectoryInfo]::GetTagsPath($StackInfoPath))
            Write-Verbose "Saving capabilities to $([CFNStackDirectoryInfo]::GetCapabilitiesPath($StackInfoPath))"
            $StackInfo.Capabilities | ConvertTo-Json -Depth 5 | Out-File -FilePath ([CFNStackDirectoryInfo]::GetCapabilitiesPath($StackInfoPath))
            Write-Verbose "Saving outputs to $([CFNStackDirectoryInfo]::GetOutputsPath($StackInfoPath))"
            $StackInfo.Outputs | ConvertTo-Json -Depth 5 | Out-File -FilePath ([CFNStackDirectoryInfo]::GetOutputsPath($StackInfoPath))
            Write-Verbose "Saving stack info to $([CFNStackDirectoryInfo]::GetStackInfoPath($StackInfoPath))"
            $StackInfo | ConvertTo-Json -Depth 5 | Out-File -FilePath ([CFNStackDirectoryInfo]::GetStackInfoPath($StackInfoPath))

            Write-Progress -Id $progressId -Activity $activity -Status "$statusPrefix (Completed)" -PercentComplete 100
        }
    }

    end {
        Write-Progress -Id $progressId -Activity "Exporting CloudFormation stack info" -Completed
    }
}

# ================================================================================================
# Update-CHARCFNStackFromDirectory Function
# ================================================================================================

<#
.SYNOPSIS
    Updates a CloudFormation stack from a directory structure containing the template, parameters, capabilities, and tags files by creating a change set.

.DESCRIPTION
    This function updates a CloudFormation stack using the specified template, parameters, capabilities, and tags files located in a directory structure.
    The directory structure should be organized as follows:
        - StackName
            - template.template
            - parameters.json
            - capabilities.json
            - tags.json

    By default, this function creates a change set that can be reviewed and executed later. The change set shows what changes will be made to the stack without actually applying them.

.PARAMETER Path
    The path to the directory containing the stack directories. Defaults to the current location. The StackName will be the name of the directory.

.PARAMETER StackName
    The name of the subfolder within the Path that contains the CloudFormation stack files. If not specified, it will create change sets for all directories in the specified path.

.PARAMETER Region
    The AWS region where the stack exists. Defaults to the default AWS region.

.PARAMETER ProfileName
    AWS credential profile name. Optional.

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

.PARAMETER ExecuteChangeSet
    If specified, the change set will be executed immediately after creation. By default, only the change set is created.

.PARAMETER VerifyOnly
    If specified, only validates the template and shows what would be updated without creating a change set.

.PARAMETER ChangeSetName
    The name for the change set. If not specified, a timestamp-based name will be generated.

.NOTES
    You need all files in the directory structure to update the stack. The stack must already exist.
    Change sets allow you to preview changes before applying them to your CloudFormation stack.

.EXAMPLE
    Update-CHARCFNStackFromDirectory -StackName client-vpn
    Creates a change set for the client-vpn stack that can be reviewed and executed later.

.EXAMPLE
    Update-CHARCFNStackFromDirectory -StackName client-vpn -ExecuteChangeSet
    Creates and immediately executes a change set for the client-vpn stack.

.EXAMPLE
    Update-CHARCFNStackFromDirectory -StackName client-vpn -VerifyOnly
    Verifies the template and shows what would be updated without creating a change set.
#>
function Update-CHARCFNStackFromDirectory {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param (
        $Path = (Get-Location).Path,
        [Parameter(Mandatory = $true)]
        [string]$StackName,
        [switch]$VerifyOnly,
        [switch]$ExecuteChangeSet,
        $ChangeSetName = $null,

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
            'Get-S3Bucket',
            'Get-CFNStack'
        ) | Test-CHARAWSCmdlet | Out-Null

        if (-not $Region) {
            $Region = Get-DefaultAWSRegionName
        }
        if ($Null -eq $Region) {
            throw "No AWS region specified and no default region configured. Please specify -Region parameter or configure a default region."
        }
        $awsParams = New-AWSParamSplat -BoundParameters $PSBoundParameters

        $AccountID = (Get-STSCallerIdentity @awsParams).Account
        Write-Verbose "AccountId: $AccountId"
        Write-Verbose "Region: $Region"
        Write-Verbose "Path: $Path"

        $TemplateBucket = (Get-S3Bucket @awsParams | Where-Object BucketName -Like "cf-templates-*$Region").BucketName
        if (-not $TemplateBucket) {
            throw "No S3 bucket found for CloudFormation templates in region $Region. Please ensure you have the correct permissions and the bucket exists (cf-templates-<random>-$Region)."
        }

        if ($null -ne $StackName) {
            if (Test-Path -Path (Join-Path -Path $Path $StackName)) {
                Write-Verbose "Path verified for StackName: $StackName"
                # Verify stack exists
                try {
                    Get-CFNStack -StackName $StackName @awsParams | Out-Null
                    Write-Verbose "Stack $StackName exists in region $Region"
                }
                catch {
                    throw "Stack $StackName does not exist in region $Region. Use New-CHARCFNStackFromDirectory to create a new stack."
                }
            }
            else {
                throw "The specified StackName path does not exist: $StackName"
            }
        }
        else {
            Write-Verbose 'No specific stack name provided, processing all directories'
            $StackName = (Get-ChildItem -Path $Path -Directory).Name
            if ($StackName.Count -gt 1) {
                if ($PSCmdlet.ShouldProcess('UpdateStacks', "Create change sets for $($StackName.Count) stacks in path: $Path")) {
                    Write-Verbose "Multiple stacks found in path: $Path. Creating change sets for all stacks."
                }
                else {
                    Write-Warning "Multiple stacks found in path: $Path. Use -StackName to specify a single stack to update."
                    return
                }
            }
            else {
                Write-Verbose "Single stack found in path: $Path. Creating change set for stack: $($StackName[0])"
            }
        }
    }

    process {
        foreach ($Name in $StackName) {
            $StackPath = Join-Path -Path $Path -ChildPath $Name

            Write-Verbose "Processing stack: $Name in path: $StackPath"

            # Verify the stack exists before attempting to update
            try {
                Get-CFNStack -StackName $Name @awsParams | Out-Null
                Write-Verbose "Confirmed stack $Name exists in region $Region"
            }
            catch {
                Write-Error "Stack $Name does not exist in region $Region. Skipping."
                continue
            }

            # Test for required template file
            if (-not (Test-Path -Path ([CFNStackDirectoryInfo]::GetTemplatePath($StackPath)))) {
                Write-Error "Template file not found in stack directory: $StackPath"
                continue
            }

            # Generate unique S3 key for template
            $TemplateS3Key = [CFNStackDirectoryInfo]::NewTemplateS3Key($Name)

            # Upload template to S3
            Write-S3Object -BucketName $TemplateBucket -Key $TemplateS3Key -File ([CFNStackDirectoryInfo]::GetTemplatePath($StackPath)) @awsParams

            $TemplateS3Url = Get-S3PreSignedURL -BucketName $TemplateBucket -Key $TemplateS3Key @awsParams -Expires (Get-Date).AddHours(1)
            Write-Verbose "Template S3 URL: $TemplateS3Url"

            # Load parameters if they exist
            if (Test-Path -Path ([CFNStackDirectoryInfo]::GetParametersPath($StackPath))) {
                $TemplateParameters = Get-Content -Path ([CFNStackDirectoryInfo]::GetParametersPath($StackPath)) -Raw | ConvertFrom-Json
            }
            else {
                $TemplateParameters = @()
            }

            # Load capabilities if they exist
            if (Test-Path -Path ([CFNStackDirectoryInfo]::GetCapabilitiesPath($StackPath))) {
                $TemplateCapabilities = Get-Content -Path ([CFNStackDirectoryInfo]::GetCapabilitiesPath($StackPath)) -Raw | ConvertFrom-Json
            }
            else {
                $TemplateCapabilities = @()
            }

            # Load tags if they exist
            if (Test-Path -Path ([CFNStackDirectoryInfo]::GetTagsPath($StackPath))) {
                $Tags = Get-Content -Path ([CFNStackDirectoryInfo]::GetTagsPath($StackPath)) -Raw | ConvertFrom-Json
            }
            else {
                $Tags = @()
            }

            # Test template
            $TemplateTest = Test-CFNTemplate -TemplateURL $TemplateS3Url @awsParams

            if ($TemplateTest.Parameters.Count -ne $TemplateParameters.Count) {
                Write-Warning "Template parameter counts do not match between template parameters and parameters.json for stack $Name. Template has $($TemplateTest.Parameters.Count) parameters, file has $($TemplateParameters.Count) parameters."
            }

            # Generate change set name if not provided
            if (-not $ChangeSetName) {
                $GeneratedChangeSetName = "changeset-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            }
            else {
                $GeneratedChangeSetName = $ChangeSetName
            }

            try {
                if ($VerifyOnly) {
                    Write-Output "`n$('*'*80)"
                    Write-Output 'Verification mode enabled. No change set will be created.'
                    Write-Output "Stack: $Name"
                    Write-Output "Template URL: $TemplateS3Url"
                    Write-Output "Parameters Count: $($TemplateParameters.Count)"
                    Write-Output "Capabilities Count: $($TemplateCapabilities.Count)"
                    Write-Output "Tags Count: $($Tags.Count)"
                    Write-Output "$('*'*80)`n"
                    continue
                }

                Write-Verbose "Creating change set for stack: $Name"
                if ($PSCmdlet.ShouldProcess("$Name in $Region", 'Create CloudFormation change set')) {

                    $ChangeSetParams = @{
                        StackName     = $Name
                        ChangeSetName = $GeneratedChangeSetName
                        TemplateURL   = $TemplateS3Url
                    }
                    $ChangeSetParams += $awsParams

                    if ($TemplateParameters.Count -gt 0) {
                        $ChangeSetParams.Parameters = $TemplateParameters
                    }
                    if ($TemplateCapabilities.Count -gt 0) {
                        $ChangeSetParams.Capabilities = $TemplateCapabilities
                    }
                    if ($Tags.Count -gt 0) {
                        $ChangeSetParams.Tags = $Tags
                    }

                    $ChangeSet = New-CFNChangeSet @ChangeSetParams

                    Write-Output "Change set '$GeneratedChangeSetName' created for stack $Name in region $Region"
                    Write-Output "Change set ARN: $($ChangeSet.Id)"

                    # Wait for change set to be created
                    Write-Verbose 'Waiting for change set to be created...'
                    do {
                        Start-Sleep -Seconds 2
                        $ChangeSetStatus = Get-CFNChangeSet -ChangeSetName $GeneratedChangeSetName -StackName $Name @awsParams
                        Write-Verbose "Change set status: $($ChangeSetStatus.Status)"
                    } while ($ChangeSetStatus.Status -eq 'CREATE_IN_PROGRESS')

                    if ($ChangeSetStatus.Status -eq 'CREATE_COMPLETE') {
                        Write-Output 'Change set created successfully. Changes:'
                        foreach ($change in $ChangeSetStatus.Changes) {
                            Write-Output "  - $($change.Action): $($change.ResourceChange.ResourceType) ($($change.ResourceChange.LogicalResourceId))"
                        }

                        if ($ExecuteChangeSet) {
                            if ($PSCmdlet.ShouldProcess("$Name in $Region", 'Execute CloudFormation change set')) {
                                Write-Output 'Executing change set...'
                                Start-CFNChangeSet -ChangeSetName $GeneratedChangeSetName -StackName $Name @awsParams
                                Write-Output "Change set execution started for stack $Name"
                            }
                        }
                        else {
                            Write-Output "`nTo execute this change set, run:"
                            Write-Output "Start-CFNChangeSet -ChangeSetName '$GeneratedChangeSetName' -StackName '$Name' -Region '$Region'"
                            Write-Output "`nTo delete this change set without executing, run:"
                            Write-Output "Remove-CFNChangeSet -ChangeSetName '$GeneratedChangeSetName' -StackName '$Name' -Region '$Region'"
                        }
                    }
                    else {
                        Write-Error "Change set creation failed with status: $($ChangeSetStatus.Status)"
                        if ($ChangeSetStatus.StatusReason) {
                            Write-Error "Reason: $($ChangeSetStatus.StatusReason)"
                        }
                    }

                }
                else {
                    Write-Verbose "Skipping change set creation for $Name in region $Region due to ShouldProcess."
                    continue
                }

            }
            catch {
                Write-Error "Failed to create change set for stack $Name in region $Region. Error: $_"
                throw
            }
        }
    }

    end {
        if (-not $VerifyOnly) {
            Write-Output "Attempted to create change sets for $($StackName.Count) stack(s) in region $Region"
        }
    }
}

# ================================================================================================
# New-CHARCFNStackDirectory Function
# ================================================================================================

<#
.SYNOPSIS
    Creates a new directory for a CloudFormation stack from the template body.

.DESCRIPTION
    Creates a new directory structure for CloudFormation stack deployment and validates the template.

.PARAMETER Region
    The AWS region to work in. Defaults to the default region.

.PARAMETER ProfileName
    AWS credential profile name. Optional.

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

.PARAMETER Path
    The path where the stack directory will be created. Defaults to the current location.

.PARAMETER StackName
    The name of the stack directory to create. This is mandatory.

.PARAMETER TemplateBody
    The CloudFormation template body content. This is mandatory.

.EXAMPLE
    New-CHARCFNStackDirectory -StackName "MyStack" -TemplateBody $templateContent
    Creates a new directory structure for MyStack with the provided template content.

.NOTES
    This function creates the directory structure and calls Test-CHARCFNStackFromDirectory to validate the template.
#>
function New-CHARCFNStackDirectory {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param (
        $Path = (Get-Location).Path,
        [String][Parameter(Mandatory = $true)]$StackName,
        [String][Parameter(Mandatory = $true)]$TemplateBody,

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
        $TargetPath = Join-Path -Path $Path -ChildPath $StackName
        if ($PSCmdlet.ShouldProcess("Creating new CloudFormation Stack directory at '$TargetPath'")) {
            if (-not (Test-Path -Path $TargetPath)) {
                New-Item -ItemType Directory -Path $TargetPath | Out-Null
                Write-Output "Created directory: $TargetPath"
            }
            else {
                Write-Warning "Directory already exists: $TargetPath"
            }

            $TemplateFile = [CFNStackDirectoryInfo]::GetTemplatePath($TargetPath)
            Set-Content -Path $TemplateFile -Value $TemplateBody
            Write-Output "Created template file: $TemplateFile"

            # call Test-CHARCFNStackFromDirectory to validate the template
            Test-CHARCFNStackFromDirectory -StackName $StackName -RootPath $Path @awsParams
        }
    }
}

# ================================================================================================
# Edit-CHARCFTTEbsVolume Function
# ================================================================================================

<#
.SYNOPSIS
Replaces EBS volume type with a newer EBS volume type in CloudFormation templates

.DESCRIPTION
Workload stacks define volumes via a "mappings" table, this is designed to change a volume type such as "gp2" to "gp3", or "io1" to "io2"
See https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ebs-volume-types.html

.PARAMETER StackName
Stack to do update on

.PARAMETER ChangeName
Name to use to create Change set.

.PARAMETER Region
AWS Region to work in (will use default region if not specified)

.PARAMETER ProfileName
    AWS credential profile name. Optional.

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

.PARAMETER TemplateBody
String containing template body, instead of using the one created by this script.

.PARAMETER OldVolumeType
Volume type you are looking to change (GP2, GP3, etc)

.PARAMETER NewVolumeType
New EBS Volume type (GP2, GP3)

.PARAMETER NewTemplateFileName
Optional filename to save the modified template

.EXAMPLE
Edit-CHARCFTTEbsVolume -StackName "MyStack" -OldVolumeType "gp2" -NewVolumeType "gp3"
Changes all gp2 volumes to gp3 in the MyStack CloudFormation stack

.NOTES
This function creates a change set to preview changes before applying them.
#>
function Edit-CHARCFTTEbsVolume {
    [CmdletBinding(ConfirmImpact = 'medium', SupportsShouldProcess = $True)]
    param (
        [Parameter(Mandatory = $true)][string]$StackName,
        [string]$ChangeName = 'ChangeEBSVolumeType',
        [string]$TemplateBody,
        [string]$NewTemplateFileName,
        [string]$OldVolumeType = 'gp2',
        [string]$NewVolumeType = 'gp3',

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
        $null = Test-CHARAWSCmdlet -Name 'Get-CFNTemplate'

        if (-not $Region) {
            $Region = (Get-DefaultAWSRegion).region
        }
        if ($null -eq $Region) {
            Throw 'Need a region specified'
        }
        $awsParams = New-AWSParamSplat -BoundParameters $PSBoundParameters
    }

    process {
        if ($TemplateBody -eq '') {
            $OrigTemplate = Get-CFNTemplate -StackName $StackName @awsParams
            $StackInfo = Get-CFNStack -StackName $StackName @awsParams

            $Template = $OrigTemplate.replace($OldVolumeType, $NewVolumeType)

            if ($Template -eq $OrigTemplate) {
                Write-Output "No changes: $($OldVolumeType) not found in template"
                return
            }

            if ($NewTemplateFileName) {
                Write-Output "Saving new template as: $($NewTemplateFileName)"
                $Template | Out-File -FilePath $NewTemplateFileName -Encoding utf8
            }
        }
        else {
            # use item passed into the template.
            $Template = $TemplateBody
            $StackInfo = Get-CFNStack -StackName $StackName @awsParams
        }

        # Validation
        if ($Template -match $OldVolumeType) {
            Throw "$($OldVolumeType) found in template, modification failed."
        }
        if ($Template -notmatch $NewVolumeType) {
            Throw "$($NewVolumeType) not found in template, modification failed."
        }

        if ($PSCmdlet.ShouldProcess("$StackName", "Create change set to change $OldVolumeType to $NewVolumeType")) {

            # Wait for any existing change sets to complete or be deleted
            do {
                $existingChangeSets = Get-CFNChangeSetList -StackName $StackName @awsParams | Where-Object { $_.Status -eq "CREATE_IN_PROGRESS" }
                if ($existingChangeSets) {
                    Write-Verbose "Waiting for existing change sets to complete..."
                    Start-Sleep -Seconds 10
                }
            } while ($existingChangeSets)

            New-CFNChangeSet -StackName $StackName -ChangeSetName $ChangeName -TemplateBody $Template -Parameters $StackInfo.Parameters @awsParams | Out-Null

            # Wait for change set to be created
            do {
                $ChangeSetResponse = Get-CFNChangeSet -ChangeSetName $ChangeName -StackName $StackName @awsParams
                Start-Sleep -Seconds 5
            } while ($ChangeSetResponse.Status -eq "CREATE_IN_PROGRESS")

            $ChangeSetResponse = Get-CFNChangeSet -ChangeSetName $ChangeName -StackName $StackName @awsParams

            if ($ChangeSetResponse.Status -eq "CREATE_COMPLETE") {
                Write-Output "Change set created successfully!"
                Write-Output "Changes to be made:"
                foreach ($change in $ChangeSetResponse.Changes) {
                    $resourceChange = $change.ResourceChange
                    Write-Output "  Action: $($change.Action)"
                    Write-Output "  Resource: $($resourceChange.LogicalResourceId) ($($resourceChange.ResourceType))"
                    if ($resourceChange.Details) {
                        foreach ($detail in $resourceChange.Details) {
                            Write-Output "    $($detail.Target.Attribute): $($detail.Target.Name)"
                        }
                    }
                    Write-Output ""
                }

                $confirmation = Read-Host "Do you want to execute this change set? (y/n)"
                if ($confirmation -eq 'y' -or $confirmation -eq 'Y') {
                    Start-CFNChangeSet -ChangeSetName $ChangeName -StackName $StackName @awsParams
                    Write-Output "Change set execution started."
                }
                else {
                    Write-Output "Change set created but not executed."
                    Write-Output "To execute later: Start-CFNChangeSet -ChangeSetName '$ChangeName' -StackName '$StackName' -Region '$Region'"
                    Write-Output "To delete: Remove-CFNChangeSet -ChangeSetName '$ChangeName' -StackName '$StackName' -Region '$Region'"
                }
            }
            else {
                Write-Error "Change set creation failed: $($ChangeSetResponse.StatusReason)"
                if ($ChangeSetResponse.Status -eq "FAILED") {
                    Remove-CFNChangeSet -ChangeSetName $ChangeName -StackName $StackName @awsParams
                    Write-Output "Failed change set has been cleaned up."
                }
            }
        }
    }
}

# ================================================================================================
# Module Exports
# ================================================================================================

# Export all functions
Export-ModuleMember -Function @(
    'Edit-CHARCFTTEbsVolume',
    'New-CHARCFNStackDirectory',
    'New-CHARCFNStackFromDirectory',
    'Out-CHARCFNStackInfo',
    'Test-CHARCFNStackFromDirectory',
    'Update-CHARCFNStackFromDirectory'
)

# SIG # Begin signature block
# MIIgywYJKoZIhvcNAQcCoIIgvDCCILgCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAJNf4dp4Bg46aq
# vAoqKfV4PWsuuj7N+MAR9f0FVmuDoqCCG1gwggN5MIIC/qADAgECAhAcz51nzeIZ
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
# xu1H7RdLZOZugT/XjX69rY9bMYIEyTCCBMUCAQEwgYwweDELMAkGA1UEBhMCVVMx
# DjAMBgNVBAgMBVRleGFzMRAwDgYDVQQHDAdIb3VzdG9uMREwDwYDVQQKDAhTU0wg
# Q29ycDE0MDIGA1UEAwwrU1NMLmNvbSBDb2RlIFNpZ25pbmcgSW50ZXJtZWRpYXRl
# IENBIEVDQyBSMgIQUR3u8+0Mq1hXs5hyxM0vzzANBglghkgBZQMEAgEFAKCBhDAY
# BgorBgEEAYI3AgEMMQowCKACgAChAoAAMBkGCSqGSIb3DQEJAzEMBgorBgEEAYI3
# AgEEMBwGCisGAQQBgjcCAQsxDjAMBgorBgEEAYI3AgEVMC8GCSqGSIb3DQEJBDEi
# BCD1ainf30HcgBTCZo53ffFTqoDt2sZij5Zfr6FU+JyPVzALBgcqhkjOPQIBBQAE
# ZzBlAjBTr9VBTGaefVx7ULLj8/CZ3ptb03zeDJV0rlQvkTfTrdmEeK+UdUfUdLJp
# U8i4fBYCMQDhq1mnhIw746bfMRTwhEcRyJsVbhwgcbsI+muoVsGFL7ieKZVUEA2M
# EFAfc++MFHShggMjMIIDHwYJKoZIhvcNAQkGMYIDEDCCAwwCAQEwajBVMQswCQYD
# VQQGEwJHQjEYMBYGA1UEChMPU2VjdGlnbyBMaW1pdGVkMSwwKgYDVQQDEyNTZWN0
# aWdvIFB1YmxpYyBUaW1lIFN0YW1waW5nIENBIFI0MQIRAOdO8lWwUE/626bf9/yL
# oxUwDQYJYIZIAWUDBAICBQCgeTAYBgkqhkiG9w0BCQMxCwYJKoZIhvcNAQcBMBwG
# CSqGSIb3DQEJBTEPFw0yNjA4MjMyMTEzMTRaMD8GCSqGSIb3DQEJBDEyBDAY7ExI
# tlC+IohHvWh2REj5f0KZ7hVprA3t9zjiXSJgNpdD0bKF7AJWOXjLl+GWk5swDQYJ
# KoZIhvcNAQEBBQAEggIAolsmOosf6+gcmGSfCxxFg69XRa46TBPcKhz3yqWGAIeH
# 3/watvZZ04/AcfLDhMlxu4j/bpRv0/3Fz8rnZ9ZKI67aGqD8f3bs4WzddDmlhF54
# fuARqjZOUbchAFTWKvJar7XIebXDX8lRf3GHzhsceO8nK1taYN78u/+hpfSGmgnk
# I/xj75imfip0aEAN5jQUUKyngmGi95lvWilj4cY72sP99/vh2M97dl0EobK9V5kU
# 8z3jvNSwScy1qHUL8vLzl1DwxcBeVoQSKm9slBdt6eHSte2mQ7kfAFiLWnNuKzkU
# 0U7Fm6d6kSb/+z2trIFXk1awtfWB+RozRSujUJ+HmCzulY//vw4HFmHgdLJvwaPr
# 0fswdW8wUS9X1bfuPBB1Ku+4zQoFYgx16NCuRvBgAXKfzkH9aiWUnPV1KuTq8DJT
# 1rVrIM0Q9+9OEb0PuPj6w4ugio8eG5pbBus2+FYPPkHFP/p2JRysf2zDBWI5JkJh
# ivJGUnFxTdmPFaLyGh/7KP1F3Y0dwI+gY7weKdKZz0OpquMUphV+altzk1IM0shY
# jicHwHl2tWtXTXUZbfDe7CwYWW5OdWhglqzswaWbIfVmMYJXbevG2UtYlHXE8cgr
# ubdanAmJiFQAAitKXU1OZoA2T1njn4iTdozYBnUFHHAgqiB6zpRvcuILy/NuY1c=
# SIG # End signature block
