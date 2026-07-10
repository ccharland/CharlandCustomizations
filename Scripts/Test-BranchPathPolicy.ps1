<#
.SYNOPSIS
    Validates branch/path separation for repository changes.
.DESCRIPTION
    Blocks workflow and editor configuration changes on normal code branches, and blocks
    source and tests/src changes on workflow/infrastructure branches.

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

$ErrorActionPreference = 'Stop'

Set-Variable -Name NormalCodeBranchBlockedPath -Option Constant -Value @(
    '.github'
    '.githooks'
    '.kiro/settings'
    '.vscode'
    'Scripts'
    'tests/scripts'
)

Set-Variable -Name WorkflowInfrastructureBranchBlockedPath -Option Constant -Value @(
    'src'
    'tests/src'
)

Set-Variable -Name PublishBranchBlockedPath -Option Constant -Value @(
    '.github'
    '.githooks'
    '.kiro'
    '.vscode'
    'Scripts'
    'tests'
)

$approvedBranchPrefixes = @(
    [pscustomobject]@{
        BranchPrefix = 'feature/'
        BlockedPath = $NormalCodeBranchBlockedPath
        BranchType = 'normal code branch'
    },
    [pscustomobject]@{
        BranchPrefix = 'bugfix/'
        BlockedPath = $NormalCodeBranchBlockedPath
        BranchType = 'normal code branch'
    },
    [pscustomobject]@{
        BranchPrefix = 'hotfix/'
        BlockedPath = $NormalCodeBranchBlockedPath
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
        BranchType = 'normal code branch'
    },
    [pscustomobject]@{
        BranchPrefix = 'breaking/'
        BlockedPath = $NormalCodeBranchBlockedPath
        BranchType = 'normal code branch'
    },
    [pscustomobject]@{
        BranchPrefix = 'docs/'
        BlockedPath = $NormalCodeBranchBlockedPath
        BranchType = 'normal code branch'
    },
    [pscustomobject]@{
        BranchPrefix = 'chore/'
        BlockedPath = $NormalCodeBranchBlockedPath
        BranchType = 'normal code branch'
    },
    [pscustomobject]@{
        BranchPrefix = 'codex-code/'
        BlockedPath = $NormalCodeBranchBlockedPath
        BranchType = 'normal code branch'
    },
    [pscustomobject]@{
        BranchPrefix = 'copilot-code/'
        BlockedPath = $NormalCodeBranchBlockedPath
        BranchType = 'normal code branch'
    },
    [pscustomobject]@{
        BranchPrefix = 'kiro-code/'
        BlockedPath = $NormalCodeBranchBlockedPath
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
    Write-Error @"
Branch path policy failed.

Branch '$BranchName' has unrecognized prefix '$branchPrefix/'.
Allowed branch prefixes are: $approvedPrefixText.

All changes are blocked until the branch is renamed to an approved prefix.
"@
    return
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

$blockedPrefixes = $matchingBranchPolicy.BlockedPath
$branchType = $matchingBranchPolicy.BranchType

$blockedPaths = @(
    foreach ($path in $ChangedPath) {
        if (Test-PathPrefix -Path $path -Prefix $blockedPrefixes) {
            $path
        }
    }
)

if ($blockedPaths.Count -gt 0) {
    $blockedPrefixText = ($blockedPrefixes | ForEach-Object { "$($_.TrimEnd('/'))/" }) -join ', '
    Write-Error @"
Branch path policy failed.

Branch '$BranchName' is treated as a $branchType.
Do not include changes under $blockedPrefixText on this branch type.

Blocked changed paths:
$($blockedPaths -join [Environment]::NewLine)

Split this work into a branch whose name matches the kind of change being made.
"@
}

Write-Output "Branch path policy passed for '$BranchName'."