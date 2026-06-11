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
New-CCCFNStackFromDirectory -StackName MyStack -VerifyOnly
#>
function New-CCCFNStackFromDirectory {
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
# Verify-CCCFNStackFromDirectory Function
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
Test-CCCFNStackFromDirectory -StackName "MyStack"
#>
function Test-CCCFNStackFromDirectory {
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
Out-CCCFNStackInfo -StackName 'MyStack'
#>
function Out-CCCFNStackInfo {
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
# Update-CCCFNStackFromDirectory Function
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
    Update-CCCFNStackFromDirectory -StackName client-vpn
    Creates a change set for the client-vpn stack that can be reviewed and executed later.

.EXAMPLE
    Update-CCCFNStackFromDirectory -StackName client-vpn -ExecuteChangeSet
    Creates and immediately executes a change set for the client-vpn stack.

.EXAMPLE
    Update-CCCFNStackFromDirectory -StackName client-vpn -VerifyOnly
    Verifies the template and shows what would be updated without creating a change set.
#>
function Update-CCCFNStackFromDirectory {
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
                    throw "Stack $StackName does not exist in region $Region. Use New-CCCFNStackFromDirectory to create a new stack."
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
# New-CCCFNStackDirectory Function
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
    New-CCCFNStackDirectory -StackName "MyStack" -TemplateBody $templateContent
    Creates a new directory structure for MyStack with the provided template content.

.NOTES
    This function creates the directory structure and calls Test-CCCFNStackFromDirectory to validate the template.
#>
function New-CCCFNStackDirectory {
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

            # call Test-CCCFNStackFromDirectory to validate the template
            Test-CCCFNStackFromDirectory -StackName $StackName -RootPath $Path @awsParams
        }
    }
}

# ================================================================================================
# Edit-CCCFTTEbsVolume Function
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
Edit-CCCFTTEbsVolume -StackName "MyStack" -OldVolumeType "gp2" -NewVolumeType "gp3"
Changes all gp2 volumes to gp3 in the MyStack CloudFormation stack

.NOTES
This function creates a change set to preview changes before applying them.
#>
function Edit-CCCFTTEbsVolume {
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
    'New-CCCFNStackFromDirectory',
    'Test-CCCFNStackFromDirectory',
    'Out-CCCFNStackInfo',
    'Update-CCCFNStackFromDirectory',
    'New-CCCFNStackDirectory',
    'Edit-CCCFTTEbsVolume'
)
# SIG # Begin signature block
# MIIr0AYJKoZIhvcNAQcCoIIrwTCCK70CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBNu5BAeO3Sarz4
# VDU+5FxHI/q3gQYLFgWmA1I6zxMUIaCCJOUwggVvMIIEV6ADAgECAhBI/JO0YFWU
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
# +9/DUp/mBlXpnYzyOmJRvOwkDynUWICE5EV7WtgwggYUMIID/KADAgECAhB6I67a
# U2mWD5HIPlz0x+M/MA0GCSqGSIb3DQEBDAUAMFcxCzAJBgNVBAYTAkdCMRgwFgYD
# VQQKEw9TZWN0aWdvIExpbWl0ZWQxLjAsBgNVBAMTJVNlY3RpZ28gUHVibGljIFRp
# bWUgU3RhbXBpbmcgUm9vdCBSNDYwHhcNMjEwMzIyMDAwMDAwWhcNMzYwMzIxMjM1
# OTU5WjBVMQswCQYDVQQGEwJHQjEYMBYGA1UEChMPU2VjdGlnbyBMaW1pdGVkMSww
# KgYDVQQDEyNTZWN0aWdvIFB1YmxpYyBUaW1lIFN0YW1waW5nIENBIFIzNjCCAaIw
# DQYJKoZIhvcNAQEBBQADggGPADCCAYoCggGBAM2Y2ENBq26CK+z2M34mNOSJjNPv
# IhKAVD7vJq+MDoGD46IiM+b83+3ecLvBhStSVjeYXIjfa3ajoW3cS3ElcJzkyZlB
# nwDEJuHlzpbN4kMH2qRBVrjrGJgSlzzUqcGQBaCxpectRGhhnOSwcjPMI3G0hedv
# 2eNmGiUbD12OeORN0ADzdpsQ4dDi6M4YhoGE9cbY11XxM2AVZn0GiOUC9+XE0wI7
# CQKfOUfigLDn7i/WeyxZ43XLj5GVo7LDBExSLnh+va8WxTlA+uBvq1KO8RSHUQLg
# zb1gbL9Ihgzxmkdp2ZWNuLc+XyEmJNbD2OIIq/fWlwBp6KNL19zpHsODLIsgZ+WZ
# 1AzCs1HEK6VWrxmnKyJJg2Lv23DlEdZlQSGdF+z+Gyn9/CRezKe7WNyxRf4e4bwU
# trYE2F5Q+05yDD68clwnweckKtxRaF0VzN/w76kOLIaFVhf5sMM/caEZLtOYqYad
# tn034ykSFaZuIBU9uCSrKRKTPJhWvXk4CllgrwIDAQABo4IBXDCCAVgwHwYDVR0j
# BBgwFoAU9ndq3T/9ARP/FqFsggIv0Ao9FCUwHQYDVR0OBBYEFF9Y7UwxeqJhQo1S
# gLqzYZcZojKbMA4GA1UdDwEB/wQEAwIBhjASBgNVHRMBAf8ECDAGAQH/AgEAMBMG
# A1UdJQQMMAoGCCsGAQUFBwMIMBEGA1UdIAQKMAgwBgYEVR0gADBMBgNVHR8ERTBD
# MEGgP6A9hjtodHRwOi8vY3JsLnNlY3RpZ28uY29tL1NlY3RpZ29QdWJsaWNUaW1l
# U3RhbXBpbmdSb290UjQ2LmNybDB8BggrBgEFBQcBAQRwMG4wRwYIKwYBBQUHMAKG
# O2h0dHA6Ly9jcnQuc2VjdGlnby5jb20vU2VjdGlnb1B1YmxpY1RpbWVTdGFtcGlu
# Z1Jvb3RSNDYucDdjMCMGCCsGAQUFBzABhhdodHRwOi8vb2NzcC5zZWN0aWdvLmNv
# bTANBgkqhkiG9w0BAQwFAAOCAgEAEtd7IK0ONVgMnoEdJVj9TC1ndK/HYiYh9lVU
# acahRoZ2W2hfiEOyQExnHk1jkvpIJzAMxmEc6ZvIyHI5UkPCbXKspioYMdbOnBWQ
# Un733qMooBfIghpR/klUqNxx6/fDXqY0hSU1OSkkSivt51UlmJElUICZYBodzD3M
# /SFjeCP59anwxs6hwj1mfvzG+b1coYGnqsSz2wSKr+nDO+Db8qNcTbJZRAiSazr7
# KyUJGo1c+MScGfG5QHV+bps8BX5Oyv9Ct36Y4Il6ajTqV2ifikkVtB3RNBUgwu/m
# SiSUice/Jp/q8BMk/gN8+0rNIE+QqU63JoVMCMPY2752LmESsRVVoypJVt8/N3qQ
# 1c6FibbcRabo3azZkcIdWGVSAdoLgAIxEKBeNh9AQO1gQrnh1TA8ldXuJzPSuALO
# z1Ujb0PCyNVkWk7hkhVHfcvBfI8NtgWQupiaAeNHe0pWSGH2opXZYKYG4Lbukg7H
# pNi/KqJhue2Keak6qH9A8CeEOB7Eob0Zf+fU+CCQaL0cJqlmnx9HCDxF+3BLbUuf
# rV64EbTI40zqegPZdA+sXCmbcZy6okx/SjwsusWRItFA3DE8MORZeFb6BmzBtqKJ
# 7l939bbKBy2jvxcJI98Va95Q5JnlKor3m0E7xpMeYRriWklUPsetMSf2NvUQa/E5
# vVyefQIwggYaMIIEAqADAgECAhBiHW0MUgGeO5B5FSCJIRwKMA0GCSqGSIb3DQEB
# DAUAMFYxCzAJBgNVBAYTAkdCMRgwFgYDVQQKEw9TZWN0aWdvIExpbWl0ZWQxLTAr
# BgNVBAMTJFNlY3RpZ28gUHVibGljIENvZGUgU2lnbmluZyBSb290IFI0NjAeFw0y
# MTAzMjIwMDAwMDBaFw0zNjAzMjEyMzU5NTlaMFQxCzAJBgNVBAYTAkdCMRgwFgYD
# VQQKEw9TZWN0aWdvIExpbWl0ZWQxKzApBgNVBAMTIlNlY3RpZ28gUHVibGljIENv
# ZGUgU2lnbmluZyBDQSBSMzYwggGiMA0GCSqGSIb3DQEBAQUAA4IBjwAwggGKAoIB
# gQCbK51T+jU/jmAGQ2rAz/V/9shTUxjIztNsfvxYB5UXeWUzCxEeAEZGbEN4QMgC
# sJLZUKhWThj/yPqy0iSZhXkZ6Pg2A2NVDgFigOMYzB2OKhdqfWGVoYW3haT29PST
# ahYkwmMv0b/83nbeECbiMXhSOtbam+/36F09fy1tsB8je/RV0mIk8XL/tfCK6cPu
# YHE215wzrK0h1SWHTxPbPuYkRdkP05ZwmRmTnAO5/arnY83jeNzhP06ShdnRqtZl
# V59+8yv+KIhE5ILMqgOZYAENHNX9SJDm+qxp4VqpB3MV/h53yl41aHU5pledi9lC
# BbH9JeIkNFICiVHNkRmq4TpxtwfvjsUedyz8rNyfQJy/aOs5b4s+ac7IH60B+Ja7
# TVM+EKv1WuTGwcLmoU3FpOFMbmPj8pz44MPZ1f9+YEQIQty/NQd/2yGgW+ufflcZ
# /ZE9o1M7a5Jnqf2i2/uMSWymR8r2oQBMdlyh2n5HirY4jKnFH/9gRvd+QOfdRrJZ
# b1sCAwEAAaOCAWQwggFgMB8GA1UdIwQYMBaAFDLrkpr/NZZILyhAQnAgNpFcF4Xm
# MB0GA1UdDgQWBBQPKssghyi47G9IritUpimqF6TNDDAOBgNVHQ8BAf8EBAMCAYYw
# EgYDVR0TAQH/BAgwBgEB/wIBADATBgNVHSUEDDAKBggrBgEFBQcDAzAbBgNVHSAE
# FDASMAYGBFUdIAAwCAYGZ4EMAQQBMEsGA1UdHwREMEIwQKA+oDyGOmh0dHA6Ly9j
# cmwuc2VjdGlnby5jb20vU2VjdGlnb1B1YmxpY0NvZGVTaWduaW5nUm9vdFI0Ni5j
# cmwwewYIKwYBBQUHAQEEbzBtMEYGCCsGAQUFBzAChjpodHRwOi8vY3J0LnNlY3Rp
# Z28uY29tL1NlY3RpZ29QdWJsaWNDb2RlU2lnbmluZ1Jvb3RSNDYucDdjMCMGCCsG
# AQUFBzABhhdodHRwOi8vb2NzcC5zZWN0aWdvLmNvbTANBgkqhkiG9w0BAQwFAAOC
# AgEABv+C4XdjNm57oRUgmxP/BP6YdURhw1aVcdGRP4Wh60BAscjW4HL9hcpkOTz5
# jUug2oeunbYAowbFC2AKK+cMcXIBD0ZdOaWTsyNyBBsMLHqafvIhrCymlaS98+Qp
# oBCyKppP0OcxYEdU0hpsaqBBIZOtBajjcw5+w/KeFvPYfLF/ldYpmlG+vd0xqlqd
# 099iChnyIMvY5HexjO2AmtsbpVn0OhNcWbWDRF/3sBp6fWXhz7DcML4iTAWS+MVX
# eNLj1lJziVKEoroGs9Mlizg0bUMbOalOhOfCipnx8CaLZeVme5yELg09Jlo8BMe8
# 0jO37PU8ejfkP9/uPak7VLwELKxAMcJszkyeiaerlphwoKx1uHRzNyE6bxuSKcut
# isqmKL5OTunAvtONEoteSiabkPVSZ2z76mKnzAfZxCl/3dq3dUNw4rg3sTCggkHS
# RqTqlLMS7gjrhTqBmzu1L90Y1KWN/Y5JKdGvspbOrTfOXyXvmPL6E52z1NZJ6ctu
# MFBQZH3pwWvqURR8AgQdULUvrxjUYbHHj95Ejza63zdrEcxWLDX6xWls/GDnVNue
# KjWUH3fTv1Y8Wdho698YADR7TNx8X8z2Bev6SivBBOHY+uqiirZtg0y9ShQoPzmC
# cn63Syatatvx157YK9hlcPmVoa1oDE5/L9Uo2bC5a4CH2RwwggZMMIIEtKADAgEC
# AhAVVO/doV4MRRGuXmkecKnEMA0GCSqGSIb3DQEBDAUAMFQxCzAJBgNVBAYTAkdC
# MRgwFgYDVQQKEw9TZWN0aWdvIExpbWl0ZWQxKzApBgNVBAMTIlNlY3RpZ28gUHVi
# bGljIENvZGUgU2lnbmluZyBDQSBSMzYwHhcNMjMwODA5MDAwMDAwWhcNMjYwODA4
# MjM1OTU5WjBjMQswCQYDVQQGEwJVUzEWMBQGA1UECAwNTmV3IEhhbXBzaGlyZTEd
# MBsGA1UECgwUQ2hyaXN0b3BoZXIgQ2hhcmxhbmQxHTAbBgNVBAMMFENocmlzdG9w
# aGVyIENoYXJsYW5kMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAwLQA
# cUKQzYs2WJY+W2fl+/1PzX3vsFwK/W9sj1RXRLBsQjsTCYRu+jRPEZSVzL/K4L87
# 7Wxb69/ye88/RrWS0d6LUyohl0OgJwgRBXBsDIcpt3hTv7GRLAFvjzcCOvK6qk+k
# jf+bxqYSUOxfl/XDK0QvM3KgWbq2IeNHoMwvAXVFBcZnRPXp1FkcHGKf+nNwxP6V
# GWtiRrhIj99q0R4iwOQaQLRY8pe8m1wn/gwFRai1F1f/Q2EMSyvbgf7kYpFNHJK1
# 7LZR9J/G7P8h4QFQZJdMU6C4lRT+Lk2jEDF4elKF5c7DFjfMv2zd0jf3/2vOhayc
# Gna9puKwQUvtwtrmcCwOI5EXBIVBcFVS8xD6eeREvzjZXiuS83quzwxVVjNBQ2f/
# nuK54huEBbNQQeNjSkMdjyr5S0Xwf8Pic5NA4ggLUWuv2XYqTTMtXHQPZ41noEJM
# +LSBulBatGT98Tu0kib3MH7e1vREcTG7gZDnicmY0RfrWM59txft97gXP7Vj99ed
# 9t2/9niQleiT+YXy3ZpNoqGFB3XC13mM44xEff49vRSLN/B0IonG5vDpMgtFoKpq
# PtUx/oKQWtYbmoWFZkvEBRUeJOmkEmIUQonzE7aqgk/uGtyjxsBHtJzIHojA+8fG
# eD0NXjlOM1bbT0OcpSMkhRXPqiOELViMQwHrAiUCAwEAAaOCAYkwggGFMB8GA1Ud
# IwQYMBaAFA8qyyCHKLjsb0iuK1SmKaoXpM0MMB0GA1UdDgQWBBSO6WwZWwCa6iKw
# s6LE4InGvJQl3zAOBgNVHQ8BAf8EBAMCB4AwDAYDVR0TAQH/BAIwADATBgNVHSUE
# DDAKBggrBgEFBQcDAzBKBgNVHSAEQzBBMDUGDCsGAQQBsjEBAgEDAjAlMCMGCCsG
# AQUFBwIBFhdodHRwczovL3NlY3RpZ28uY29tL0NQUzAIBgZngQwBBAEwSQYDVR0f
# BEIwQDA+oDygOoY4aHR0cDovL2NybC5zZWN0aWdvLmNvbS9TZWN0aWdvUHVibGlj
# Q29kZVNpZ25pbmdDQVIzNi5jcmwweQYIKwYBBQUHAQEEbTBrMEQGCCsGAQUFBzAC
# hjhodHRwOi8vY3J0LnNlY3RpZ28uY29tL1NlY3RpZ29QdWJsaWNDb2RlU2lnbmlu
# Z0NBUjM2LmNydDAjBggrBgEFBQcwAYYXaHR0cDovL29jc3Auc2VjdGlnby5jb20w
# DQYJKoZIhvcNAQEMBQADggGBAENPYZO6JkhXuprRcjFErvAggFDfB4bJmvHwydUU
# q8EEdDkvVvS+SnqpaL+Nw5FY/X5GnIXfWKYvQJFY1o/bskqLBSH96jOk+wMWZ2Lq
# fuyEuW4OZUvBtpho2E2QwcpCQQzG47c+qtENC6lITctyoOUi5481cm9VXRL0E1g/
# MSDOqpYcd32oKt6rbqLQZD89HFgkNrfh3a4wq2O8ljai9gvQJnYV4588DGI4quzv
# 81b6mGDx9ku9zHhtvI19C1L+oQddqFFUViSwUUiNrBO7aA5iFwr1vQPkiP40Zd6f
# SSQAjrRnUI/kbK9oD2l1i/Vi9hfQ8SLarLPhW0M0qaut175+RJKlwuusUZADtgYV
# WcrmMxy20RMCUZA2bnTWXjb4pVfHUyKPU7dpM+8gG/tUPBZegMWrzWqctSPQhdRE
# pkLTMCm5E/o4ZUGNE0uo+twbGMGEyPPmjsFnIKLAqN2rHMI1Fz9pR+qMdixl+/mG
# /ElSJqGSDVArmZLn1IYhr4vQ8DCCBmIwggTKoAMCAQICEQCkKTtuHt3XpzQIh616
# TrckMA0GCSqGSIb3DQEBDAUAMFUxCzAJBgNVBAYTAkdCMRgwFgYDVQQKEw9TZWN0
# aWdvIExpbWl0ZWQxLDAqBgNVBAMTI1NlY3RpZ28gUHVibGljIFRpbWUgU3RhbXBp
# bmcgQ0EgUjM2MB4XDTI1MDMyNzAwMDAwMFoXDTM2MDMyMTIzNTk1OVowcjELMAkG
# A1UEBhMCR0IxFzAVBgNVBAgTDldlc3QgWW9ya3NoaXJlMRgwFgYDVQQKEw9TZWN0
# aWdvIExpbWl0ZWQxMDAuBgNVBAMTJ1NlY3RpZ28gUHVibGljIFRpbWUgU3RhbXBp
# bmcgU2lnbmVyIFIzNjCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBANOE
# lfRupFN48j0QS3gSBzzclIFTZ2Gsn7BjsmBF659/kpA2Ey7NXK3MP6JdrMBNU8wd
# mkf+SSIyjX++UAYWtg3Y/uDRDyg8RxHeHRJ+0U1jHEyH5uPdk1ttiPC3x/gOxIc9
# P7Gn3OgW7DQc4x07exZ4DX4XyaGDq5LoEmk/BdCM1IelVMKB3WA6YpZ/XYdJ9Jue
# OXeQObSQ/dohQCGyh0FhmwkDWKZaqQBWrBwZ++zqlt+z/QYTgEnZo6dyIo2IhXXA
# NFkCHutL8765NBxvolXMFWY8/reTnFxk3MajgM5NX6wzWdWsPJxYRhLxtJLSUJJ5
# yWRNw+NBqH1ezvFs4GgJ2ZqFJ+Dwqbx9+rw+F2gBdgo4j7CVomP49sS7Cbqsdybb
# iOGpB9DJhs5QVMpYV73TVV3IwLiBHBECrTgUfZVOMF0KSEq2zk/LsfvehswavE3W
# 4aBXJmGjgWSpcDz+6TqeTM8f1DIcgQPdz0IYgnT3yFTgiDbFGOFNt6eCidxdR6j9
# x+kpcN5RwApy4pRhE10YOV/xafBvKpRuWPjOPWRBlKdm53kS2aMh08spx7xSEqXn
# 4QQldCnUWRz3Lki+TgBlpwYwJUbR77DAayNwAANE7taBrz2v+MnnogMrvvct0iwv
# fIA1W8kp155Lo44SIfqGmrbJP6Mn+Udr3MR2oWozAgMBAAGjggGOMIIBijAfBgNV
# HSMEGDAWgBRfWO1MMXqiYUKNUoC6s2GXGaIymzAdBgNVHQ4EFgQUiGGMoSo3ZIEo
# YKGbMdCM/SwCzk8wDgYDVR0PAQH/BAQDAgbAMAwGA1UdEwEB/wQCMAAwFgYDVR0l
# AQH/BAwwCgYIKwYBBQUHAwgwSgYDVR0gBEMwQTA1BgwrBgEEAbIxAQIBAwgwJTAj
# BggrBgEFBQcCARYXaHR0cHM6Ly9zZWN0aWdvLmNvbS9DUFMwCAYGZ4EMAQQCMEoG
# A1UdHwRDMEEwP6A9oDuGOWh0dHA6Ly9jcmwuc2VjdGlnby5jb20vU2VjdGlnb1B1
# YmxpY1RpbWVTdGFtcGluZ0NBUjM2LmNybDB6BggrBgEFBQcBAQRuMGwwRQYIKwYB
# BQUHMAKGOWh0dHA6Ly9jcnQuc2VjdGlnby5jb20vU2VjdGlnb1B1YmxpY1RpbWVT
# dGFtcGluZ0NBUjM2LmNydDAjBggrBgEFBQcwAYYXaHR0cDovL29jc3Auc2VjdGln
# by5jb20wDQYJKoZIhvcNAQEMBQADggGBAAKBPqSGclEh+WWpLj1SiuHlm8xLE0ST
# hI2yLuq+75s11y6SceBchpnKpxWaGtXc8dya1Aq3RuW//y3wMThsvT4fSba2AoSW
# lR67rA4fTYGMIhgzocsids0ct/pHaocLVJSwnTYxY2pE0hPoZAvRebctbsTqENmZ
# HyOVjOFlwN2R3DRweFeNs4uyZN5LRJ5EnVYlcTOq3bl1tI5poru9WaQRWQ4eynXp
# 7Pj0Fz4DKr86HYECRJMWiDjeV0QqAcQMFsIjJtrYTw7mU81qf4FBc4u4swphLeKR
# Nyn9DDrd3HIMJ+CpdhSHEGleeZ5I79YDg3B3A/fmVY2GaMik1Vm+FajEMv4/EN2m
# mHf4zkOuhYZNzVm4NrWJeY4UAriLBOeVYODdA1GxFr1ycbcUEGlUecc4RCPgYySs
# 4d00NNuicR4a9n7idJlevAJbha/arIYMEuUqTeRRbWkhJwMKmb9yEvppRudKyu1t
# 6l21sIuIZqcpVH8oLWCxHS0LpDRF9Y4jijCCBoIwggRqoAMCAQICEDbCsL18Gzrn
# o7PdNsvJdWgwDQYJKoZIhvcNAQEMBQAwgYgxCzAJBgNVBAYTAlVTMRMwEQYDVQQI
# EwpOZXcgSmVyc2V5MRQwEgYDVQQHEwtKZXJzZXkgQ2l0eTEeMBwGA1UEChMVVGhl
# IFVTRVJUUlVTVCBOZXR3b3JrMS4wLAYDVQQDEyVVU0VSVHJ1c3QgUlNBIENlcnRp
# ZmljYXRpb24gQXV0aG9yaXR5MB4XDTIxMDMyMjAwMDAwMFoXDTM4MDExODIzNTk1
# OVowVzELMAkGA1UEBhMCR0IxGDAWBgNVBAoTD1NlY3RpZ28gTGltaXRlZDEuMCwG
# A1UEAxMlU2VjdGlnbyBQdWJsaWMgVGltZSBTdGFtcGluZyBSb290IFI0NjCCAiIw
# DQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAIid2LlFZ50d3ei5JoGaVFTAfEkF
# m8xaFQ/ZlBBEtEFAgXcUmanU5HYsyAhTXiDQkiUvpVdYqZ1uYoZEMgtHES1l1Cc6
# HaqZzEbOOp6YiTx63ywTon434aXVydmhx7Dx4IBrAou7hNGsKioIBPy5GMN7KmgY
# muu4f92sKKjbxqohUSfjk1mJlAjthgF7Hjx4vvyVDQGsd5KarLW5d73E3ThobSko
# b2SL48LpUR/O627pDchxll+bTSv1gASn/hp6IuHJorEu6EopoB1CNFp/+HpTXeNA
# RXUmdRMKbnXWflq+/g36NJXB35ZvxQw6zid61qmrlD/IbKJA6COw/8lFSPQwBP1i
# tyZdwuCysCKZ9ZjczMqbUcLFyq6KdOpuzVDR3ZUwxDKL1wCAxgL2Mpz7eZbrb/JW
# XiOcNzDpQsmwGQ6Stw8tTCqPumhLRPb7YkzM8/6NnWH3T9ClmcGSF22LEyJYNWCH
# rQqYubNeKolzqUbCqhSqmr/UdUeb49zYHr7ALL8bAJyPDmubNqMtuaobKASBqP84
# uhqcRY/pjnYd+V5/dcu9ieERjiRKKsxCG1t6tG9oj7liwPddXEcYGOUiWLm742st
# 50jGwTzxbMpepmOP1mLnJskvZaN5e45NuzAHteORlsSuDt5t4BBRCJL+5EZnnw0e
# zntk9R8QJyAkL6/bAgMBAAGjggEWMIIBEjAfBgNVHSMEGDAWgBRTeb9aqitKz1SA
# 4dibwJ3ysgNmyzAdBgNVHQ4EFgQU9ndq3T/9ARP/FqFsggIv0Ao9FCUwDgYDVR0P
# AQH/BAQDAgGGMA8GA1UdEwEB/wQFMAMBAf8wEwYDVR0lBAwwCgYIKwYBBQUHAwgw
# EQYDVR0gBAowCDAGBgRVHSAAMFAGA1UdHwRJMEcwRaBDoEGGP2h0dHA6Ly9jcmwu
# dXNlcnRydXN0LmNvbS9VU0VSVHJ1c3RSU0FDZXJ0aWZpY2F0aW9uQXV0aG9yaXR5
# LmNybDA1BggrBgEFBQcBAQQpMCcwJQYIKwYBBQUHMAGGGWh0dHA6Ly9vY3NwLnVz
# ZXJ0cnVzdC5jb20wDQYJKoZIhvcNAQEMBQADggIBAA6+ZUHtaES45aHF1BGH5Lc7
# JYzrftrIF5Ht2PFDxKKFOct/awAEWgHQMVHol9ZLSyd/pYMbaC0IZ+XBW9xhdkkm
# UV/KbUOiL7g98M/yzRyqUOZ1/IY7Ay0YbMniIibJrPcgFp73WDnRDKtVutShPSZQ
# ZAdtFwXnuiWl8eFARK3PmLqEm9UsVX+55DbVIz33Mbhba0HUTEYv3yJ1fwKGxPBs
# P/MgTECimh7eXomvMm0/GPxX2uhwCcs/YLxDnBdVVlxvDjHjO1cuwbOpkiJGHmLX
# XVNbsdXUC2xBrq9fLrfe8IBsA4hopwsCj8hTuwKXJlSTrZcPRVSccP5i9U28gZ7O
# MzoJGlxZ5384OKm0r568Mo9TYrqzKeKZgFo0fj2/0iHbj55hc20jfxvK3mQi+H7x
# pbzxZOFGm/yVQkpo+ffv5gdhp+hv1GDsvJOtJinJmgGbBFZIThbqI+MHvAmMmkfb
# 3fTxmSkop2mSJL1Y2x/955S29Gu0gSJIkc3z30vU/iXrMpWx2tS7UVfVP+5tKuzG
# tgkP7d/doqDrLF1u6Ci3TpjAZdeLLlRQZm867eVeXED58LXd1Dk6UvaAhvmWYXoi
# Lz4JA5gPBcz7J311uahxCweNxE+xxxR3kT0WKzASo5G/PyDez6NHdIUKBeE3jDPs
# 2ACc6CkJ1Sji4PKWVT0/MYIGQTCCBj0CAQEwaDBUMQswCQYDVQQGEwJHQjEYMBYG
# A1UEChMPU2VjdGlnbyBMaW1pdGVkMSswKQYDVQQDEyJTZWN0aWdvIFB1YmxpYyBD
# b2RlIFNpZ25pbmcgQ0EgUjM2AhAVVO/doV4MRRGuXmkecKnEMA0GCWCGSAFlAwQC
# AQUAoIGEMBgGCisGAQQBgjcCAQwxCjAIoAKAAKECgAAwGQYJKoZIhvcNAQkDMQwG
# CisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZI
# hvcNAQkEMSIEILTinFBkMf3RmtHB1uYOAYM4/uxSnGqN3HxQmszwzUhgMA0GCSqG
# SIb3DQEBAQUABIICACzKOdX9NTsVUW10F1188/OWj4ORJVztIa7ICqqwcwVgKORS
# SZb6geKEFj0jtZhZf58UC5zRsME4je4dYInG8LSysTBIr9ZVRilO7NVzQGRjnuYc
# WAVqPBwTI8wqkp/gXlto+3ubrJDIY2iYltl8BDELl8vKKFKrsPXdLpNdmdQFtIIc
# PmF/zskXDnj0Vss/dDwHRR6dZOjUsIRedaRTsZRac0MplllvYCVuDgqX5FxFXAI+
# K8y9cVrW6trBdXdMqnWWGqvLtfzPPkfjkOhXc004XZbEqIsQhJ07XzuPTGe8iRf4
# NOyPUG/YeXvVC9wxoQXkVH9iMmXTN25kujwQ/kQgHPhj1zomQxQRZj6FW/fP3iUW
# tGGbN1QVyur8ysRb+vYwC4qn1abhjXLv2dkrq0J6lS2XlM8+oJAlQRmYAHQwuD/1
# pZnYi9g5zr73ytvQIevBFgYRj3Xc8nhXjmoYO91osVH6BaoGBp9CkZb9hLbtXc7C
# qZHOPXj7zgxbQ2FhwzwuJdYCoCVX6RYzwFI/RvNniDIWQBgCuaVHptqjWS67N9UJ
# SdERGHSsHpmy2y3NGZXLazy6MeicK9fb3eYXMD/PvpsPW1N1ZDLX2diel/lsS9xg
# T8hxORks+OpK8EWcz/viSWneZK7UGoG4Rw8zL53fdAZxYe9f/p3MRQmW2hwwoYID
# IzCCAx8GCSqGSIb3DQEJBjGCAxAwggMMAgEBMGowVTELMAkGA1UEBhMCR0IxGDAW
# BgNVBAoTD1NlY3RpZ28gTGltaXRlZDEsMCoGA1UEAxMjU2VjdGlnbyBQdWJsaWMg
# VGltZSBTdGFtcGluZyBDQSBSMzYCEQCkKTtuHt3XpzQIh616TrckMA0GCWCGSAFl
# AwQCAgUAoHkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjYwNjA2MDIwNjAyWjA/BgkqhkiG9w0BCQQxMgQw+0BA9zacV1PRtFgYzSXf
# MTA6k55PRCRZWDDj2wxpCjST/k1dfCgirW1905ZmA3uXMA0GCSqGSIb3DQEBAQUA
# BIICAHBGjxXPQqnj7PDRe6e5y3I3xWmTlo8GuAiafX56bB4A1RLuo2iJk4H0jHzM
# bQ9hhiMN1GZBCdi2hLpaqXm+AtSU94AHzxSd4MRAvA6xr1h4WwX/1Ja5IWsIvZ0L
# GioZ/R+Ws/W4BskYtNNFPbxJBlxGhgLavVw3yQ++O0evrUKGQYGH+vRh1dZZIGQb
# B4ybnd7ZF5SONIR+QYWlxBsZFVwZWfnSoG5u5Sar204EgMJzE+7f5qp+9//na1Ty
# txWDtEtiyYL2n8yDF4nY4GhUSc6GBh0FmXrmCRWxYmLYOqsYvlU68T4xuLtR941x
# YKAe9FwVJM1qS1znhoZwa/T4r+I4uzigEsw+NGQqK+GjKwiCJioJoWNy6BLXSxCK
# 9XHrURMYJTMpmMV9E/r9sfkkA0R4CJJcjxipMAnafEwAUB7l+lAgSYJ7O2z9tf3Y
# huzxJLNcWSp3zfBDzdHIlCFFPIJ4KEef2q9oI5XQ7Tt2g4a0sxQn3TFuhPk/Taa9
# DKFQ/iLWFiQVYF14jUnyS+L/hY6K8u78UZk8/v6WJoWsmlg4gkcD6dJiWAcsUKd8
# vZz0BJWdIV+jY9Cc6p3yq6dn5VDT9abWJKXNGZ2JivxaUIydyMBF3c/y8nzGclcm
# sovfT/ySe4h6plMIg3vXDDwwAS+Q1e9dP+EAQiIkz0fymWtW
# SIG # End signature block
