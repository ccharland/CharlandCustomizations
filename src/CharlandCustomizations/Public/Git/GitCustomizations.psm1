# Git-related customizations and utilities

# Import the validation script as a function
. $PSScriptRoot/Test-CCCommitSignatures.ps1
. $PSScriptRoot/Install-CCGitHooks.ps1

# Export functions
Export-ModuleMember -Function @(
    'Test-CCCommitSignatures',
    'Install-CCGitHooks'
)