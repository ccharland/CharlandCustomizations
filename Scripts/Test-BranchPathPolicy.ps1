<#
.SYNOPSIS
    Validates branch/path separation for repository changes.
.DESCRIPTION
    Blocks workflow and editor configuration changes on normal code branches, and blocks
    source or test changes on workflow/infrastructure branches.
.PARAMETER BranchName
    Branch name to classify.
.PARAMETER ChangedPath
    Changed repository-relative paths to validate.
.EXAMPLE
    ./Scripts/Test-BranchPathPolicy.ps1 -BranchName 'feature/add-audit' -ChangedPath @('src/CharlandCustomizations/Public/AWS/Audit/Audit-AWSAccount.psm1')
    # Passes: source changes are allowed on a normal code branch
.EXAMPLE
    ./Scripts/Test-BranchPathPolicy.ps1 -BranchName 'feature/add-audit' -ChangedPath @('.github/workflows/publish.yml')
    # Fails: workflow changes are not allowed on a normal code branch
.EXAMPLE
    ./Scripts/Test-BranchPathPolicy.ps1 -BranchName 'ci/update-workflows' -ChangedPath @('.github/workflows/publish.yml', '.kiro/settings/mcp.json')
    # Passes: workflow/infra changes are allowed on a CI branch
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
    $blockedPrefixes = @('src', 'tests')
    $branchType = 'workflow/infrastructure branch'
}
else {
    $blockedPrefixes = @('.github', '.kiro', '.vscode', 'Scripts')
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
