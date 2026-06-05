function Test-CCCommitSignature {

    <#
    .SYNOPSIS
        Tests that commits are signed (GPG or SSH)
        
    .DESCRIPTION
        Checks git commits to ensure they are properly signed with GPG or SSH.
        Can check recent commits or a specific range.
        
    .PARAMETER Count
        Number of recent commits to check (default: 1)
        
    .PARAMETER Range
        Git commit range to check (e.g., "HEAD~5..HEAD", "main..feature")
        
    .PARAMETER Branch
        Branch to check (default: current branch)
        
    .EXAMPLE
        Test-CCCommitSignatures
        Checks the last commit
        
    .EXAMPLE
        Test-CCCommitSignatures -Count 10
        Checks the last 10 commits
        
    .EXAMPLE
        Test-CCCommitSignatures -Range "HEAD~5..HEAD"
        Checks specific commit range
        
    .EXAMPLE
        Test-CCCommitSignatures -Branch main
        Checks commits on main branch
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [int]$Count = 1,
        
        [Parameter()]
        [string]$Range,
        
        [Parameter()]
        [string]$Branch
    )

    $ErrorActionPreference = 'Stop'

    # Check if we're in a git repository
    try {
        git rev-parse --git-dir 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Not in a git repository"
        }
    }
    catch {
        Write-Error "Not in a git repository"
        return $false
    }

    Write-Host "Validating commit signatures..." -ForegroundColor Cyan

    # Check if commit signing is configured
    $commitSignEnabled = git config --get commit.gpgsign
    $signingKey = git config --get user.signingkey
    $gpgFormat = git config --get gpg.format

    # Detect signing method
    $signingMethod = if ($gpgFormat -eq 'ssh') { 'SSH' } 
                     elseif ($signingKey -like 'ssh-*') { 'SSH' }
                     else { 'GPG' }

    if ($commitSignEnabled -ne 'true') {
        Write-Warning "Commit signing is not enabled!"
        Write-Host "Enable with: git config --global commit.gpgsign true" -ForegroundColor Yellow
    }

    if (-not $signingKey) {
        Write-Warning "No signing key configured!"
        Write-Host "Configure with: git config --global user.signingkey <YOUR_KEY_ID>" -ForegroundColor Yellow
    }

    if ($signingMethod -eq 'SSH') {
        $allowedSigners = git config --get gpg.ssh.allowedSignersFile
        if (-not $allowedSigners) {
            Write-Warning "SSH signing is configured but gpg.ssh.allowedSignersFile is not set"
            Write-Host "For verification, configure with:" -ForegroundColor Yellow
            Write-Host "  git config --global gpg.ssh.allowedSignersFile ~/.ssh/allowed_signers" -ForegroundColor Gray
            Write-Host "Then add your public key:" -ForegroundColor Yellow
            Write-Host "  echo `"`$(git config user.email) `$(cat ~/.ssh/id_ed25519.pub)`" >> ~/.ssh/allowed_signers" -ForegroundColor Gray
        }
    }

    # Build git log command
    $gitArgs = @('log', '--pretty=format:%H|%G?|%GS|%s')

    if ($Range) {
        $gitArgs += $Range
    }
    elseif ($Branch) {
        $gitArgs += $Branch
    }
    else {
        $gitArgs += "-$Count"
    }

    # Get commits
    $commits = git @gitArgs | ForEach-Object {
        $parts = $_ -split '\|', 4
        [PSCustomObject]@{
            Hash = $parts[0].Substring(0, 7)
            SignatureStatus = $parts[1]
            Signer = $parts[2]
            Subject = $parts[3]
        }
    }

    if (-not $commits) {
        Write-Host "No commits found to check" -ForegroundColor Yellow
        return $true
    }

    # Analyze results
    $results = foreach ($commit in $commits) {
        $status = switch ($commit.SignatureStatus) {
            'G' { 'Valid'; $true }      # Good signature
            'B' { 'Bad'; $false }        # Bad signature
            'U' { 'Unknown'; $false }    # Unknown validity
            'X' { 'Expired'; $false }    # Expired signature
            'Y' { 'Expired Key'; $false } # Expired key
            'R' { 'Revoked'; $false }    # Revoked key
            'E' { 'Error'; $false }      # Error checking
            'N' { 'Not Signed'; $false } # No signature
            default { 'Unknown'; $false }
        }
        
        $color = if ($status -eq 'Valid') { 'Green' } else { 'Red' }
        
        [PSCustomObject]@{
            Commit = $commit.Hash
            Status = $status
            Signer = $commit.Signer
            Subject = $commit.Subject
            Valid = $status -eq 'Valid'
            Color = $color
        }
    }

    # Display results
    Write-Host "`nCommit Signature Status:" -ForegroundColor Cyan
    $results | ForEach-Object {
        $statusText = "[$($_.Status)]".PadRight(15)
        Write-Host "  $($_.Commit) " -NoNewline
        Write-Host $statusText -ForegroundColor $_.Color -NoNewline
        Write-Host " $($_.Subject)"
        if ($_.Signer) {
            Write-Host "    Signer: $($_.Signer)" -ForegroundColor Gray
        }
    }

    # Summary
    $validCount = ($results | Where-Object Valid).Count
    $totalCount = $results.Count
    $invalidCount = $totalCount - $validCount

    Write-Host "`nSummary:" -ForegroundColor Cyan
    Write-Host "  Total commits checked: $totalCount"
    Write-Host "  Valid signatures: $validCount" -ForegroundColor Green
    if ($invalidCount -gt 0) {
        Write-Host "  Invalid/Missing signatures: $invalidCount" -ForegroundColor Red
    }

    # Return false if any commits are not properly signed
    if ($invalidCount -gt 0) {
        Write-Host "`nValidation FAILED: Not all commits are properly signed" -ForegroundColor Red
        Write-Host "All commits must be signed" -ForegroundColor Yellow
        Write-Host "`nTo fix:" -ForegroundColor Yellow
        
        if ($signingMethod -eq 'SSH') {
            Write-Host "  1. Ensure SSH signing is configured:"
            Write-Host "     git config --global gpg.format ssh"
            Write-Host "     git config --global commit.gpgsign true"
            Write-Host "     git config --global user.signingkey ~/.ssh/id_ed25519.pub"
            Write-Host "  2. Configure allowed signers (for verification):"
            Write-Host "     git config --global gpg.ssh.allowedSignersFile ~/.ssh/allowed_signers"
            Write-Host "     echo `"`$(git config user.email) `$(cat ~/.ssh/id_ed25519.pub)`" >> ~/.ssh/allowed_signers"
            Write-Host "  3. Amend unsigned commits: git commit --amend --no-edit -S"
        }
        else {
            Write-Host "  1. Configure GPG signing: git config --global commit.gpgsign true"
            Write-Host "  2. Set your signing key: git config --global user.signingkey <KEY_ID>"
            Write-Host "  3. Amend unsigned commits: git commit --amend --no-edit -S"
        }
        return $false
    }

    Write-Host "`nValidation PASSED: All commits are properly signed" -ForegroundColor Green
    return $true
}