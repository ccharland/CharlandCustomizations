<#
.SYNOPSIS
    Validates branch/path separation for repository changes.
.DESCRIPTION
    Blocks workflow and editor configuration changes on normal code branches, and blocks
    source or test changes on workflow/infrastructure branches.

    Test paths are separated by concern:
    - tests/src/   mirrors the source module and is owned by code branches
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
    ./Scripts/Test-BranchPathPolicy.ps1 -BranchName 'my-branch-no-slash' -ChangedPath @('src/CharlandCustomizations/Public/Get-Something.ps1')
    # Fails: branch name must contain a forward slash
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

$approvedBranchPrefixes = @(
    'feature',
    'bugfix',
    'hotfix',
    'workflow',
    'workflows',
    'infrastructure',
    'infra',
    'ci',
    'architecture',
    'breaking',
    'docs',
    'chore',
    'codex-code',
    'copilot-code',
    'kiro-code',
    'codex-infra',
    'copilot-infra',
    'kiro-infra'
)

# Branch names must contain a forward slash (e.g., feature/thing, ci/updates)
if ($BranchName -notmatch '/') {
    Write-Error @"
Branch path policy failed.

Branch '$BranchName' does not contain a forward slash.
Branch names must follow the format 'type/description' (e.g., feature/add-audit, ci/update-workflows).

All changes are blocked until the branch is renamed.
"@
    return
}

$branchPrefix = ($BranchName -split '/', 2)[0].ToLowerInvariant()
if ($approvedBranchPrefixes -notcontains $branchPrefix) {
    $approvedPrefixText = ($approvedBranchPrefixes | ForEach-Object { "'$_/*'" }) -join ', '
    Write-Error @"
Branch path policy failed.

Branch '$BranchName' has unrecognized prefix '$branchPrefix/'.
Allowed branch prefixes are: $approvedPrefixText.

All changes are blocked until the branch is renamed to an approved prefix.
"@
    return
}

function Test-WorkflowInfrastructureBranch {
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    return $Name -match '(workflow|workflows|infra|infrastructure)' -or
        $Name -match '(^|[\/_-])ci($|[\/_-])'
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

$isWorkflowInfrastructureBranch = Test-WorkflowInfrastructureBranch -Name $BranchName

if ($isWorkflowInfrastructureBranch) {
    # Infrastructure/CI branches own Scripts/ and tests/scripts/.
    # They must not touch source code (src/) or the source-mirrored tests (tests/src/).
    $blockedPrefixes = @('src', 'tests/src')
    $branchType = 'workflow/infrastructure branch'
}
else {
    # Normal code branches own src/ and tests/src/.
    # They must not touch workflow config, build tooling, or the scripts-mirrored tests (tests/scripts/).
    $blockedPrefixes = @('.github', '.kiro', '.vscode', 'Scripts', 'tests/scripts')
    $branchType = 'normal code branch'
}

$blockedPaths = @(
    foreach ($path in $ChangedPath) {
        if (Test-PathPrefix -Path $path -Prefix $blockedPrefixes) {
            $path
        }
    }
)

if ($blockedPaths.Count -gt 0) {
    $blockedPrefixText = ($blockedPrefixes | ForEach-Object { "$_/" }) -join ', '
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

