function Install-CCGitHook {
    <#
    .SYNOPSIS
        Installs git hooks for the current repository.

    .DESCRIPTION
        Copies the pre-commit hook from .githooks/pre-commit to .git/hooks/pre-commit,
        makes it executable on Unix-like systems, and checks signing configuration.
        The hook blocks workflow/editor configuration changes on normal code branches,
        and blocks source/test changes on workflow or infrastructure branches.

    .PARAMETER Force
        Overwrites an existing pre-commit hook without prompting.

    .EXAMPLE
        PS C:\> Install-CCGitHook

        Installs the pre-commit hook from .githooks/pre-commit to .git/hooks/pre-commit.

    .EXAMPLE
        PS C:\> Install-CCGitHook -Force

        Overwrites an existing pre-commit hook without prompting.

    .NOTES
        For deliberate exceptions, rerun the commit with:
        CC_GIT_HOOK_ALLOW_PATH_POLICY_OVERRIDE=1 git commit ...
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$Force
    )

    $ErrorActionPreference = 'Stop'

    Write-Host 'Installing git hooks...' -ForegroundColor Cyan

    try {
        $gitDir = git rev-parse --git-dir 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw 'Not in a git repository'
        }

        $repoRoot = git rev-parse --show-toplevel 2>&1
        if ($LASTEXITCODE -ne 0 -or -not $repoRoot) {
            throw 'Unable to determine repository root'
        }
    }
    catch {
        Write-Error 'Not in a git repository'
        return
    }

    $hooksDir = Join-Path $gitDir 'hooks'
    $preCommitHook = Join-Path $hooksDir 'pre-commit'
    $sourceHook = Join-Path $repoRoot '.githooks/pre-commit'

    if ((Test-Path $preCommitHook) -and -not $Force) {
        Write-Host 'Pre-commit hook already exists' -ForegroundColor Yellow
        $response = Read-Host 'Overwrite? (y/N)'
        if ($response -ne 'y') {
            Write-Host 'Skipping hook installation' -ForegroundColor Yellow
            return
        }
    }

    if (-not (Test-Path $sourceHook)) {
        Write-Error "Source hook not found at: $sourceHook"
        return
    }

    Copy-Item $sourceHook $preCommitHook -Force
    Write-Host '  Installed pre-commit hook' -ForegroundColor Green

    if ($IsLinux -or $IsMacOS) {
        chmod +x $preCommitHook
        Write-Host '  Made hook executable' -ForegroundColor Green
    }

    Write-Host "`nVerifying commit signing configuration..." -ForegroundColor Cyan

    $commitSign = git config --get commit.gpgsign
    $signingKey = git config --get user.signingkey
    $gpgFormat = git config --get gpg.format

    if ($commitSign -eq 'true') {
        Write-Host '  Commit signing: Enabled' -ForegroundColor Green
    }
    else {
        Write-Host '  Commit signing: Not enabled' -ForegroundColor Red
        Write-Host '    Enable with: git config --global commit.gpgsign true' -ForegroundColor Yellow
    }

    if ($signingKey) {
        Write-Host "  Signing key: $signingKey" -ForegroundColor Green
    }
    else {
        Write-Host '  Signing key: Not configured' -ForegroundColor Red
        Write-Host '    Configure with: git config --global user.signingkey <KEY_ID>' -ForegroundColor Yellow
    }

    $signingMethod = if ($gpgFormat -eq 'ssh') { 'SSH' }
    elseif ($signingKey -like 'ssh-*') { 'SSH' }
    else { 'GPG' }

    Write-Host "  Signing method: $signingMethod" -ForegroundColor Cyan

    if ($signingMethod -eq 'SSH') {
        $allowedSigners = git config --get gpg.ssh.allowedSignersFile
        if ($allowedSigners) {
            Write-Host "  Allowed signers file: $allowedSigners" -ForegroundColor Green
            if (Test-Path $allowedSigners) {
                Write-Host '    File exists' -ForegroundColor Green
            }
            else {
                Write-Host '    File does not exist!' -ForegroundColor Red
            }
        }
        else {
            Write-Host '  Allowed signers file: Not configured' -ForegroundColor Yellow
            Write-Host '    For verification, configure with:' -ForegroundColor Yellow
            Write-Host '      git config --global gpg.ssh.allowedSignersFile ~/.ssh/allowed_signers' -ForegroundColor Gray
        }
    }
    else {
        Write-Host "`nTesting GPG..." -ForegroundColor Cyan
        try {
            $testOutput = 'test' | gpg --clearsign 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host '  GPG is working' -ForegroundColor Green
            }
            else {
                Write-Host '  GPG test failed' -ForegroundColor Red
                Write-Host "  Output: $testOutput" -ForegroundColor Gray
            }
        }
        catch {
            Write-Host '  GPG not found or not working' -ForegroundColor Red
            Write-Host '  Install GPG: https://gnupg.org/download/' -ForegroundColor Yellow
        }
    }

    Write-Host "`nSetup complete!" -ForegroundColor Green
}
