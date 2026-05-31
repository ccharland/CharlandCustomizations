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
        $Credential,

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
        $Credential,

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
        $Credential,

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
        $Credential,

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
# Edit-CCCFTTEbsVolumes Function
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
Edit-CCCFTTEbsVolumes -StackName "MyStack" -OldVolumeType "gp2" -NewVolumeType "gp3"
Changes all gp2 volumes to gp3 in the MyStack CloudFormation stack

.NOTES
This function creates a change set to preview changes before applying them.
#>
function Edit-CCCFTTEbsVolumes {
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
        $Credential,

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
    'Edit-CCCFTTEbsVolumes'
)
