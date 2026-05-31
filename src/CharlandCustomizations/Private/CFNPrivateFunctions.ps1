<#
.SYNOPSIS
    Private helper functions and classes for CloudFormation stack directory operations.

.DESCRIPTION
    Contains the CFNStackDirectoryInfo class (file/directory naming conventions) and
    private helper functions used internally by CloudFormation-TemplateProcessing.psm1.

    These are NOT exported to end users.

.NOTES
    Used by:
        - New-CCCFNStackFromDirectory
        - Test-CCCFNStackFromDirectory
        - Out-CCCFNStackInfo
        - Update-CCCFNStackFromDirectory
        - New-CCCFNStackDirectory
        - Edit-CCCFTTEbsVolumes
#>

# ================================================================================================
# CFNStackDirectoryInfo Class
# ================================================================================================

class CFNStackDirectoryInfo {
    # --- Standard file names ---
    static [string] $TemplateFile = 'template.template'
    static [string] $ProcessedTemplateFile = 'template-processed.template'
    static [string] $ParametersFile = 'parameters.json'
    static [string] $CapabilitiesFile = 'capabilities.json'
    static [string] $TagsFile = 'tags.json'
    static [string] $OutputsFile = 'outputs.json'
    static [string] $StackInfoFile = 'stack.json'
    static [string] $ChangeSetsFile = 'changesets.json'

    # --- Files required for stack deployment ---
    static [string[]] $RequiredForDeploy = @(
        'template.template',
        'parameters.json'
    )

    # --- All possible files (for documentation / validation) ---
    static [string[]] $AllFiles = @(
        'template.template',
        'template-processed.template',
        'parameters.json',
        'capabilities.json',
        'tags.json',
        'outputs.json',
        'stack.json',
        'changesets.json'
    )

    # Returns the full path for a given file within a stack directory
    static [string] GetFilePath([string]$StackPath, [string]$FileName) {
        return Join-Path -Path $StackPath -ChildPath $FileName
    }

    # Returns the full path to the template file
    static [string] GetTemplatePath([string]$StackPath) {
        return [CFNStackDirectoryInfo]::GetFilePath($StackPath, [CFNStackDirectoryInfo]::TemplateFile)
    }

    # Returns the full path to the processed template file
    static [string] GetProcessedTemplatePath([string]$StackPath) {
        return [CFNStackDirectoryInfo]::GetFilePath($StackPath, [CFNStackDirectoryInfo]::ProcessedTemplateFile)
    }

    # Returns the full path to the parameters file
    static [string] GetParametersPath([string]$StackPath) {
        return [CFNStackDirectoryInfo]::GetFilePath($StackPath, [CFNStackDirectoryInfo]::ParametersFile)
    }

    # Returns the full path to the capabilities file
    static [string] GetCapabilitiesPath([string]$StackPath) {
        return [CFNStackDirectoryInfo]::GetFilePath($StackPath, [CFNStackDirectoryInfo]::CapabilitiesFile)
    }

    # Returns the full path to the tags file
    static [string] GetTagsPath([string]$StackPath) {
        return [CFNStackDirectoryInfo]::GetFilePath($StackPath, [CFNStackDirectoryInfo]::TagsFile)
    }

    # Returns the full path to the outputs file
    static [string] GetOutputsPath([string]$StackPath) {
        return [CFNStackDirectoryInfo]::GetFilePath($StackPath, [CFNStackDirectoryInfo]::OutputsFile)
    }

    # Returns the full path to the stack info file
    static [string] GetStackInfoPath([string]$StackPath) {
        return [CFNStackDirectoryInfo]::GetFilePath($StackPath, [CFNStackDirectoryInfo]::StackInfoFile)
    }

    # Returns the full path to the changesets file
    static [string] GetChangeSetsPath([string]$StackPath) {
        return [CFNStackDirectoryInfo]::GetFilePath($StackPath, [CFNStackDirectoryInfo]::ChangeSetsFile)
    }

    # Validates that required deployment files exist in a stack directory
    # Returns an array of missing file names (empty if all present)
    static [string[]] ValidateForDeploy([string]$StackPath) {
        $missing = @()
        foreach ($file in [CFNStackDirectoryInfo]::RequiredForDeploy) {
            $filePath = [CFNStackDirectoryInfo]::GetFilePath($StackPath, $file)
            if (-not (Test-Path -Path $filePath)) {
                $missing += $file
            }
        }
        return $missing
    }

    # Builds the standard account/region/stack directory path
    static [string] GetStackExportPath([string]$RootPath, [string]$AccountID, [string]$Region, [string]$StackName) {
        return Join-Path -Path $RootPath -ChildPath (
            Join-Path -Path $AccountID -ChildPath (
                Join-Path -Path $Region -ChildPath $StackName
            )
        )
    }

    # Generates a unique S3 key for temporary template uploads
    static [string] NewTemplateS3Key([string]$StackName) {
        $timestamp = Get-Date -Format 'yyyy-MM-ddTHHmmss.fff'
        $random = -join ((97..122) | Get-Random -Count 2 | ForEach-Object { [char]$_ })
        return "$timestamp$random-$StackName"
    }
}

# ================================================================================================
# Private Helper Functions
# ================================================================================================

function Get-DefaultAWSRegionName {
    try {
        (Get-DefaultAWSRegion).Region
    }
    catch {
        $null
    }
}

function Get-CFNContext {
    param($Region)
    $resolvedRegion = if ($Region) { $Region } else { Get-DefaultAWSRegionName }
    @{
        AccountID      = (Get-STSCallerIdentity).Account
        Region         = $resolvedRegion
        TemplateBucket = (Get-S3Bucket | Where-Object BucketName -like "$S3_BUCKET_PATTERN$resolvedRegion").BucketName
    }
}

function Get-StackFiles {
    param($StackPath)
    @{
        Parameters   = if (Test-Path ([CFNStackDirectoryInfo]::GetParametersPath($StackPath))) { Get-Content ([CFNStackDirectoryInfo]::GetParametersPath($StackPath)) -Raw | ConvertFrom-Json } else { @() }
        Tags         = if (Test-Path ([CFNStackDirectoryInfo]::GetTagsPath($StackPath))) { Get-Content ([CFNStackDirectoryInfo]::GetTagsPath($StackPath)) -Raw | ConvertFrom-Json } else { @() }
        Capabilities = if (Test-Path ([CFNStackDirectoryInfo]::GetCapabilitiesPath($StackPath))) { Get-Content ([CFNStackDirectoryInfo]::GetCapabilitiesPath($StackPath)) -Raw | ConvertFrom-Json } else { @() }
    }
}

function New-TemplateS3Upload {
    param($StackPath, $Name, $TemplateBucket, $Region, $ProfileName)

    $awsParams = New-AWSParamSplat -BoundParameters $PSBoundParameters

    $Key = [CFNStackDirectoryInfo]::NewTemplateS3Key($Name)
    Write-S3Object -BucketName $TemplateBucket -Key $Key -File ([CFNStackDirectoryInfo]::GetTemplatePath($StackPath)) @awsParams
    Get-S3PresignedURL -BucketName $TemplateBucket -Key $Key @awsParams -Expires (Get-Date).AddHours(1)
}
