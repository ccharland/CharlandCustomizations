@{
    RootModule           = 'CharlandCustomizations.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = '1f7e3e80-b770-4587-a1a0-9e45c839b50a'
    Author               = 'Christopher Charland'
    CompanyName          = ''
    Copyright            = '(c) Christopher Charland. All rights reserved.'
    Description          = 'Public PowerShell module and scripts for daily customization and automation tasks.'
    PowerShellVersion    = '7.2'
    CompatiblePSEditions = @('Core')
    DefaultCommandPrefix = 'CC'
    NestedModules        = @(
        'Public/AWS/AWSCustomizations.psm1'
        'Public/AWS/CloudFormation/CloudFormation-TemplateProcessing.psm1'
        'Public/AWS/S3/S3Customizations.psm1'
        'Public/AWS/Audit/Audit-AWSAccount.psm1'
        'Public/Git/GitCustomizations.psm1'
    )
    FunctionsToExport    = @(
        # Root module public functions (Public/*.ps1)
        'Install-ProfilesFromSource'
        'Invoke-ScriptMultiAccountRegion'
        'Set-FileSignature'
        'Update-Powershell7'
        # AWS nested module (AWSCustomizations.psm1)
        'Find-CFNStackErrors'
        'Set-AWSProfileWithMFA'
        'Get-AWSMFASession'
        'Start-MultiStackDriftDetection'
        'Get-AWSAccountListOfDriftedResources'
        'Get-AWSObjectCount'
        'Set-AWSEnv'
        'Update-SSOCredentialList'
        'Remove-ExpiredAWSProfiles'
        'Get-AccountListFromProfiles'
        'Use-AssumedRole'
        # CloudFormation nested module
        'New-CFNStackFromDirectory'
        'Test-CFNStackFromDirectory'
        'Test-CFNTemplateFromFile'
        'Out-CFNStackInfo'
        'Update-CFNStackFromDirectory'
        'New-CFNStackDirectory'
        'Edit-CFTTEbsVolumes'
        # S3 nested module
        'Clear-S3Bucket'
        # Audit nested module
        'Get-EC2SGInUse'
        'Get-EC2Count'
        'Find-EC2DBSG'
        'Out-AWSSupportingInfo'
        'Out-AWSNetworkingComponent'
        'Get-IAMAuditList'
        'Get-GlobalAuditReportItem'
        'Get-EC2KeyTagNameStatus'
        'Get-EC2SnapshotReport'
        'Get-EC2VolumeReport'
        'Start-EC2RetryLoop'
        'Find-OpenSecurityGroup'
        # Git nested module
        'Test-CommitSignatures'
        'Install-GitHooks'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()

    PrivateData = @{
        PSData = @{
            Tags         = @('PowerShell', 'AWS', 'Automation', 'CloudFormation', 'Utilities')
            ProjectUri   = 'https://github.com/ccharland/CharlandCustomizations'
            LicenseUri   = 'https://github.com/ccharland/CharlandCustomizations/blob/main/LICENSE'
            ReleaseNotes = 'Initial public release - module structure and steering files.'
            Prerelease   = 'beta1'
        }
    }
}
