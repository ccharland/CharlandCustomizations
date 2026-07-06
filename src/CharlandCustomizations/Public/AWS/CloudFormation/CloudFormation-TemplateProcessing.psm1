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
# MIIs4wYJKoZIhvcNAQcCoIIs1DCCLNACAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDakB6HxODuFaFt
# FpJEaAPpTQv9R1RD9xkFAmjIb7yDI6CCJfgwggVvMIIEV6ADAgECAhBI/JO0YFWU
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
# BgorBgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQgHnFP
# QlDlseTlIGt6WVo0OinvyQNLtIOMbk1USDa1ZHgwDQYJKoZIhvcNAQEBBQAEggIA
# ghbKXWTtg8W2SwTCo9AAAO9p7IpR+M5fjVoRsGXiw1RSSDzgu7TVtpfGsvxN5DOH
# CCS8fwBkGFqSWDH7p37AmuJWuAjVW875GV+yDl10W5qS434KnmrSdVlrZhYUNIsh
# zMAjkjCvg/SwyQqNATQ9E54U76DOYex2fp86uWsKjywxXEP+g4pgu2fnEHgWjamx
# qveC8YKZbFiRZCD1jKyA40Uwp1eSfMu+iX45xJ6ordPifq7dg39HzUbnqnWZni3g
# 06296Fxz8elTdqDcbnOQ5FhLNn0G0EHzbpfjZvnN+zLdFFHn4uLIWQJqVhutsu3X
# 85x9dJIzX+V4/ANtBrzvYCoWa0tfVrDXmh6r7KnJAP+xVHYMcPo7PeMGH+P3Nfwt
# aIP35ILU9DfwMGjHb9whl/FjbHd6Eki5XUWNvQyyG41dMYVdYJ15iB7oZr0daIKM
# W3OAxZOLV3qbLjE5Q5LcE2kh/5FURMroXWYpv3S6KxYErPi9dQI/ocStA7zCv7Ty
# aug8rQRFdgt/Bt3x0Ost9CbB/tDfKjrlgrXWiEEitFuZVuaHNvMEOihc5BwtN2Vn
# g68Q9WAUkQ9GBUz43UqGT+WAVhtpBXD23wQEDOmijX5TfU3G18yyjZihFx8CcmSP
# HTx2jCnmn8Bug9AU3MueaSEidvcqBEBeLf5q1J/hLXKhggMjMIIDHwYJKoZIhvcN
# AQkGMYIDEDCCAwwCAQEwajBVMQswCQYDVQQGEwJHQjEYMBYGA1UEChMPU2VjdGln
# byBMaW1pdGVkMSwwKgYDVQQDEyNTZWN0aWdvIFB1YmxpYyBUaW1lIFN0YW1waW5n
# IENBIFI0MQIRAOdO8lWwUE/626bf9/yLoxUwDQYJYIZIAWUDBAICBQCgeTAYBgkq
# hkiG9w0BCQMxCwYJKoZIhvcNAQcBMBwGCSqGSIb3DQEJBTEPFw0yNjA3MDUyMzU4
# MTBaMD8GCSqGSIb3DQEJBDEyBDCbg6G6hekFlu5WiRUe8d21m+derhycbrSYqvQ7
# fMojj/q8acWBXdlmiQZ5HEl3Py8wDQYJKoZIhvcNAQEBBQAEggIAIk+lbUNd+uj4
# e6JZNVHZjiEB+AFwinpUJMsR2X50LnNHNe/Z/QC4zAqvVL4szJng/MJspB0tK4NR
# Fog0AgwoWWcsFzhoCS6xL0x2eKBLDCNMCq1qViPujDZUCfHM8ZyPwyEY96GbdL3l
# VzptSLqKY5+2c+wjUjz1ytuaYdRiTxOO7heADgax+3LiVLdBe/cpOABWSK8xRLWB
# 2jkbmBtG5X2KX+iLvB4pij0lzCdeAT6HI/moTRN+gSaxDDkn0trzh5q+Nf0N563v
# dIyOwjz3fZ8YoKb+8Q1od2Euk46LUKNxE+BXyXAxvisSB0ecGHGEg39W1vbrav5K
# kSWdFeVhv8onu6gCenXkCaXuHiSGnpHBtm7lzB50yeYxEoM8o+WZplPKDXHLgE+m
# syjJ38QfCgcFXNbq9UvdZoNAG/cKu/EPuc4zSXdEZKkujJgRn2Js74MJMbEN6bHg
# 9/DQt1tKD3xulS0k1VDjz9G3sQEHT++9je99fl0vK+C7xMhWkDIaQyb/Z0IORqAT
# fIbnIVnwqv3apbKa0sMVxSlkHUw4iBAdAZvqWWDGtih9FIROFPunCJ9JLCprqZ84
# vI5UFEyzkvtCwkMeN57wtCFzS1FEIIQ6xWVDb4InqkXek9XkgktwvF1YvSwMV0mw
# C/0K+VSaAaPWCbZ2BOLe7pDVJx1ZAus=
# SIG # End signature block
