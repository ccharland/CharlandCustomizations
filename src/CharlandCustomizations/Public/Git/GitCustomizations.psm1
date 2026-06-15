# Git-related customizations and utilities

# Import the validation script as a function
. $PSScriptRoot/Test-CCCommitSignature.ps1
. $PSScriptRoot/Install-CCGitHook.ps1

# Export functions
Export-ModuleMember -Function @(
    'Install-CCGitHook',
    'Test-CCCommitSignature'
)
