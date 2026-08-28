<#
.SYNOPSIS
    Validates branch/path separation for repository changes.
.DESCRIPTION
    Blocks workflow and editor configuration changes on normal code branches, except for
    the repository cSpell configuration, and blocks source and tests/src changes on
    workflow/infrastructure branches.

    Used in workflows:
        - .github/workflows/pr-quality-gate.yml
        - .github/workflows/publish.yml
    to enforce branch/path separation policy.

    Test paths are separated by concern:
    - tests/src/  mirrors the source module and is owned by code branches
    - tests/scripts/ mirrors Scripts/ and is owned by infrastructure branches
.PARAMETER BranchName
    Branch name to classify.
.PARAMETER ChangedPath
    Changed repository-relative paths to validate.
.EXAMPLE
    ./Scripts/Test-BranchPathPolicy.ps1 -BranchName 'feature/add-audit' -ChangedPath @('src/CharlandCustomizations/Public/AWS/Audit/Audit-AWSAccount.psm1')
    # Passes: source changes are allowed on a normal code branch
.EXAMPLE
    ./Scripts/Test-BranchPathPolicy.ps1 -BranchName 'feature/add-audit' -ChangedPath @('tests/src/CharlandCustomizations/Public/AWS/Audit/Audit-AWSAccount/Audit-Functions.Tests.ps1')
    # Passes: tests/src changes are allowed on a normal code branch
.EXAMPLE
    ./Scripts/Test-BranchPathPolicy.ps1 -BranchName 'feature/add-audit' -ChangedPath @('.github/workflows/publish.yml')
    # Fails: workflow changes are not allowed on a normal code branch
.EXAMPLE
    ./Scripts/Test-BranchPathPolicy.ps1 -BranchName 'feature/add-audit' -ChangedPath @('tests/scripts/Build-Module.Tests.ps1')
    # Fails: tests/scripts changes are not allowed on a normal code branch
.EXAMPLE
    ./Scripts/Test-BranchPathPolicy.ps1 -BranchName 'ci/update-workflows' -ChangedPath @('.github/workflows/publish.yml', '.kiro/settings/mcp.json')
    # Passes: workflow/infra changes are allowed on a CI branch
.EXAMPLE
    ./Scripts/Test-BranchPathPolicy.ps1 -BranchName 'ci/update-workflows' -ChangedPath @('tests/scripts/Build-Module.Tests.ps1')
    # Passes: tests/scripts changes are allowed on a CI branch
.EXAMPLE
    ./Scripts/Test-BranchPathPolicy.ps1 -BranchName 'ci/update-workflows' -ChangedPath @('tests/src/CharlandCustomizations/Public/Test-Thing.Tests.ps1')
    # Fails: tests/src changes are not allowed on an infrastructure branch
.EXAMPLE
    ./Scripts/Test-BranchPathPolicy.ps1 -BranchName 'infra/pipeline-fixes' -ChangedPath @('src/CharlandCustomizations/Public/Get-Something.ps1')
    # Fails: source changes are not allowed on an infrastructure branch
.EXAMPLE
    ./Scripts/Test-BranchPathPolicy.ps1 -BranchName 'experiment/new-policy' -ChangedPath @('src/CharlandCustomizations/Public/Get-Something.ps1')
    # Fails: branch prefix is not approved
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$BranchName,

    [Parameter(Mandatory)]
    [AllowEmptyCollection()]
    [string[]]$ChangedPath
)
Set-StrictMode -Version 3
$ErrorActionPreference = 'Stop'

$script:SuccessExitCode = 0
$script:PolicyViolationExitCode = 1

Set-Variable -Name NormalCodeBranchBlockedPath -Option Constant -Value @(
    'Scripts'
)

Set-Variable -Name NormalCodeBranchAllowedPath -Option Constant -Value @(
    '.vscode/cspell.json'
)

Set-Variable -Name WorkflowInfrastructureBranchBlockedPath -Option Constant -Value @(
    'src'
    'tests/src'
)

Set-Variable -Name PublishBranchBlockedPath -Option Constant -Value @(
    'Scripts'
)

# Bare AI-tool prefixes block ALL paths — forces rename to -code/ or -infra/ before merge
Set-Variable -Name AIRootBranchBlockedPath -Option Constant -Value @(
    'src'
    'tests/src'
    'Scripts'
)

$approvedBranchPrefixes = @(
    [pscustomobject]@{
        BranchPrefix = 'feature/'
        BlockedPath = $NormalCodeBranchBlockedPath
        AllowedPath = $NormalCodeBranchAllowedPath
        BranchType = 'normal code branch'
    },
    [pscustomobject]@{
        BranchPrefix = 'bugfix/'
        BlockedPath = $NormalCodeBranchBlockedPath
        AllowedPath = $NormalCodeBranchAllowedPath
        BranchType = 'normal code branch'
    },
    [pscustomobject]@{
        BranchPrefix = 'hotfix/'
        BlockedPath = $NormalCodeBranchBlockedPath
        AllowedPath = $NormalCodeBranchAllowedPath
        BranchType = 'normal code branch'
    },
    [pscustomobject]@{
        BranchPrefix = 'workflow/'
        BlockedPath = $WorkflowInfrastructureBranchBlockedPath
        BranchType = 'workflow/infrastructure branch'
    },
    [pscustomobject]@{
        BranchPrefix = 'workflows/'
        BlockedPath = $WorkflowInfrastructureBranchBlockedPath
        BranchType = 'workflow/infrastructure branch'
    },
    [pscustomobject]@{
        BranchPrefix = 'infrastructure/'
        BlockedPath = $WorkflowInfrastructureBranchBlockedPath
        BranchType = 'workflow/infrastructure branch'
    },
    [pscustomobject]@{
        BranchPrefix = 'infra/'
        BlockedPath = $WorkflowInfrastructureBranchBlockedPath
        BranchType = 'workflow/infrastructure branch'
    },
    [pscustomobject]@{
        BranchPrefix = 'ci/'
        BlockedPath = $WorkflowInfrastructureBranchBlockedPath
        BranchType = 'workflow/infrastructure branch'
    },
    [pscustomobject]@{
        BranchPrefix = 'architecture/'
        BlockedPath = $NormalCodeBranchBlockedPath
        AllowedPath = $NormalCodeBranchAllowedPath
        BranchType = 'normal code branch'
    },
    [pscustomobject]@{
        BranchPrefix = 'breaking/'
        BlockedPath = $NormalCodeBranchBlockedPath
        AllowedPath = $NormalCodeBranchAllowedPath
        BranchType = 'normal code branch'
    },
    [pscustomobject]@{
        BranchPrefix = 'docs/'
        BlockedPath = $NormalCodeBranchBlockedPath
        AllowedPath = $NormalCodeBranchAllowedPath
        BranchType = 'normal code branch'
    },
    [pscustomobject]@{
        BranchPrefix = 'chore/'
        BlockedPath = $NormalCodeBranchBlockedPath
        AllowedPath = $NormalCodeBranchAllowedPath
        BranchType = 'normal code branch'
    },
    [pscustomobject]@{
        BranchPrefix = 'codex-code/'
        BlockedPath = $NormalCodeBranchBlockedPath
        AllowedPath = $NormalCodeBranchAllowedPath
        BranchType = 'normal code branch'
    },
    [pscustomobject]@{
        BranchPrefix = 'copilot-code/'
        BlockedPath = $NormalCodeBranchBlockedPath
        AllowedPath = $NormalCodeBranchAllowedPath
        BranchType = 'normal code branch'
    },
    [pscustomobject]@{
        BranchPrefix = 'kiro-code/'
        BlockedPath = $NormalCodeBranchBlockedPath
        AllowedPath = $NormalCodeBranchAllowedPath
        BranchType = 'normal code branch'
    },
    [pscustomobject]@{
        BranchPrefix = 'codex-infra/'
        BlockedPath = $WorkflowInfrastructureBranchBlockedPath
        BranchType = 'workflow/infrastructure branch'
    },
    [pscustomobject]@{
        BranchPrefix = 'copilot-infra/'
        BlockedPath = $WorkflowInfrastructureBranchBlockedPath
        BranchType = 'workflow/infrastructure branch'
    },
    [pscustomobject]@{
        BranchPrefix = 'kiro-infra/'
        BlockedPath = $WorkflowInfrastructureBranchBlockedPath
        BranchType = 'workflow/infrastructure branch'
    },
    [pscustomobject]@{
        BranchPrefix = 'codex/'
        BlockedPath = $AIRootBranchBlockedPath
        BranchType = 'AI root branch (rename to -code/ or -infra/ before merge)'
    },
    [pscustomobject]@{
        BranchPrefix = 'copilot/'
        BlockedPath = $AIRootBranchBlockedPath
        BranchType = 'AI root branch (rename to -code/ or -infra/ before merge)'
    },
    [pscustomobject]@{
        BranchPrefix = 'kiro/'
        BlockedPath = $AIRootBranchBlockedPath
        BranchType = 'AI root branch (rename to -code/ or -infra/ before merge)'
    },
    [pscustomobject]@{
        BranchPrefix = 'publish/'
        BlockedPath = $PublishBranchBlockedPath
        BranchType = 'publish/release branch'
    }
)


$normalizedBranchName = $BranchName.ToLowerInvariant()
$matchingBranchPolicy = $approvedBranchPrefixes | Where-Object {
    $normalizedBranchName.StartsWith($_.BranchPrefix)
} | Select-Object -First 1

if (-not $matchingBranchPolicy) {
    $branchPrefix = ($BranchName -split '/', 2)[0].ToLowerInvariant()
    $approvedPrefixText = ($approvedBranchPrefixes | ForEach-Object { "'$($_.BranchPrefix)*'" }) -join ', '
    Write-Error -ErrorAction Continue @"
Branch path policy failed.

Branch '$BranchName' has unrecognized prefix '$branchPrefix/'.
Allowed branch prefixes are: $approvedPrefixText.

All changes are blocked until the branch is renamed to an approved prefix.
"@
    exit $script:PolicyViolationExitCode
}

function Test-PathPrefix {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string[]]$Prefix
    )

    $normalizedPath = $Path -replace '\\', '/'

    foreach ($item in $Prefix) {
        $normalizedPrefix = $item.TrimEnd('/')
        if ($normalizedPath -eq $normalizedPrefix -or $normalizedPath.StartsWith("$normalizedPrefix/")) {
            return $true
        }
    }

    return $false
}

function Test-ExactPath {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$ExactPath
    )

    $normalizedPath = $Path -replace '\\', '/'

    foreach ($item in $ExactPath) {
        $normalizedExactPath = $item -replace '\\', '/'
        if ($normalizedPath -eq $normalizedExactPath) {
            return $true
        }
    }

    return $false
}

$blockedPrefixes = $matchingBranchPolicy.BlockedPath
$allowedPaths = @(
    if ($matchingBranchPolicy.PSObject.Properties.Name -contains 'AllowedPath') {
        $matchingBranchPolicy.AllowedPath | Where-Object { $_ }
    }
)
$branchType = $matchingBranchPolicy.BranchType

$blockedPaths = @(
    foreach ($path in $ChangedPath) {
        $isAllowedPath = $allowedPaths.Count -gt 0 -and
            (Test-ExactPath -Path $path -ExactPath $allowedPaths)

        if (
            (Test-PathPrefix -Path $path -Prefix $blockedPrefixes) -and
            -not $isAllowedPath
        ) {
            $path
        }
    }
)

if ($blockedPaths.Count -gt 0) {
    $blockedPrefixText = ($blockedPrefixes | ForEach-Object { "$($_.TrimEnd('/'))/" }) -join ', '
    Write-Error -ErrorAction Continue @"
Branch path policy failed.

Branch '$BranchName' is treated as a $branchType.
Do not include changes under $blockedPrefixText on this branch type.

Blocked changed paths:
$($blockedPaths -join [Environment]::NewLine)

Split this work into a branch whose name matches the kind of change being made.
"@
    exit $script:PolicyViolationExitCode
}

Write-Output "Branch path policy passed for '$BranchName'."
exit $script:SuccessExitCode

#