# Git-related customizations and utilities

# Import the validation script as a function
. $PSScriptRoot/Test-CHARCommitSignature.ps1
. $PSScriptRoot/Install-CHARGitHook.ps1

# Export functions
Export-ModuleMember -Function @(
    'Install-CHARGitHook',
    'Test-CHARCommitSignature'
)
