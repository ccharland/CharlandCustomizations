@{
    ExcludeFunction = @{
        'Clear-CHARAuthenticodeSignature' = 'Authenticode helper; does not call AWS cmdlets.'
        'Export-CHARPfxCertificatePem' = 'Certificate helper; does not call AWS cmdlets.'
        'Get-CFNContext' = 'Private CloudFormation path/context helper invoked by validated AWS commands.'
        'Get-CHARAWSRegionFromIp' = 'Region lookup helper; does not call AWS cmdlets.'
        'Get-DefaultAWSRegionName' = 'Private CloudFormation default-region helper invoked by validated AWS commands.'
        'Get-StackFile' = 'Private CloudFormation file helper invoked by validated AWS commands.'
        'Install-CHARGitHook' = 'Git helper; does not call AWS cmdlets.'
        'Install-CHARProfilesFromSource' = 'Profile bootstrap helper; does not call AWS cmdlets.'
        'New-AWSParamSplat' = 'AWS parameter helper; does not call AWS cmdlets itself.'
        'New-CHARCFNStackDirectory' = 'Local directory scaffolding helper; does not call AWS cmdlets.'
        'New-TemplateS3Upload' = 'Private upload helper called only by validated CloudFormation commands.'
        'Set-CHARAuthenticodeSignature' = 'Authenticode helper; does not call AWS cmdlets.'
        'Start-CHAREC2RetryLoop' = 'Retry-loop helper invoked by validated AWS commands.'
        'Test-CHARAuthenticodeSignature' = 'Authenticode helper; does not call AWS cmdlets.'
        'Test-CHARAWSCmdlet' = 'Rule subject; cannot validate itself with a recursive call.'
        'Test-CHARCommitSignature' = 'Git signature helper; does not call AWS cmdlets.'
        'Test-CHARIsWindows' = 'Platform helper; does not call AWS cmdlets.'
        'Test-CHARPfxCertificate' = 'Certificate helper; does not call AWS cmdlets.'
        'Update-CHARPfxCertificateInACM' = 'Certificate orchestrator that delegates AWS validation to nested ACM commands.'
        'Update-CHARPowershell7' = 'PowerShell installer helper; does not call AWS cmdlets.'
    }
}
