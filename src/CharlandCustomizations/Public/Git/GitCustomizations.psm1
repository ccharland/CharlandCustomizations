# Git-related customizations and utilities

# Import the validation script as a function
. $PSScriptRoot/Test-CommitSignatures.ps1
. $PSScriptRoot/Install-GitHooks.ps1

# Export functions
Export-ModuleMember -Function @(
    'Test-CommitSignatures',
    'Install-GitHooks'
)