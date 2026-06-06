[CmdletBinding()]
param(
    [Parameter()]
    [string[]]$Path,

    [Parameter()]
    [ValidateSet('.ps1', '.psm1', '.psd1')]
    [string[]]$IncludeExtension = @('.ps1', '.psm1', '.psd1')
)

if (-not (Get-Variable -Name CCIsWindows -Scope Script -ErrorAction SilentlyContinue)) {
    $script:CCIsWindows = $IsWindows
}

function Test-CCAuthenticodeSignature {
    <#
.SYNOPSIS
    Validates Authenticode signatures for release-critical PowerShell files.
.DESCRIPTION
    Scans one or more directories for .ps1, .psm1, and .psd1 files and verifies
    each file has a valid Authenticode signature with a timestamp counter-signature.
    Files signed without a timestamp certificate are treated as non-compliant because
    the signature will expire with the signing certificate.
.PARAMETER Path
    One or more root paths to scan recursively.
    Defaults to Scripts and src/CharlandCustomizations.
.PARAMETER IncludeExtension
    File extensions to validate. Defaults to .ps1, .psm1, .psd1.
.OUTPUTS
    PSCustomObject

    If any files fail signature validation, an object is returned with its AuthentiCode signature status and the file path.
#>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Gate script uses Write-Host for high-visibility pass/fail status in release workflows')]
    param(
        [Parameter()]
        [string[]]$Path,

        [Parameter()]
        [ValidateSet('.ps1', '.psm1', '.psd1')]
        [string[]]$IncludeExtension = @('.ps1', '.psm1', '.psd1')
    )

    if (-not $script:CCIsWindows) {
        throw 'Test-CCAuthenticodeSignature is only supported on Windows systems.'
    }

    if (-not $Path -or $Path.Count -eq 0) {
        $repoRoot = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
        $Path = @(
            (Join-Path $repoRoot 'Scripts'),
            (Join-Path $repoRoot 'src/CharlandCustomizations')
        )
    }

    $ErrorActionPreference = 'Stop'

    $isPipelineOutput = $MyInvocation.PipelineLength -gt 1 -or $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    $isRedirectedOutput = $false
    $shouldRenderTable = $false
    try {
        $isRedirectedOutput = [Console]::IsOutputRedirected
        $shouldRenderTable = -not $isPipelineOutput -and -not $isRedirectedOutput
    }
    catch {
        $isRedirectedOutput = $true
        $shouldRenderTable = $false
    }

    $resolvedPaths = foreach ($candidatePath in $Path) {
        if (-not (Test-Path -Path $candidatePath)) {
            throw "Validation path does not exist: $candidatePath"
        }

        Resolve-Path -Path $candidatePath | Select-Object -ExpandProperty Path
    }

    $filesToValidate = @(
        foreach ($resolvedPath in $resolvedPaths) {
            Get-ChildItem -Path $resolvedPath -Recurse -File |
                Where-Object { $_.Extension -in $IncludeExtension }
        }
    )

    if (-not $filesToValidate) {
        throw "No files were found to validate under paths: $($resolvedPaths -join ', ')"
    }

    $invalidSignatures = @()
    foreach ($file in $filesToValidate) {
        Write-Verbose "Validating $($file.FullName)"
        $signature = Get-AuthenticodeSignature -FilePath $file.FullName
        if ($signature.Status -ne 'Valid') {
            Write-Warning "Invalid signature found: $($file.FullName)"
            $invalidSignatures += [PSCustomObject]@{
                Path   = $file.FullName
                Status = $signature.Status
            }
        }
        elseif (-not $signature.TimeStamperCertificate) {
            Write-Warning "Missing timestamp certificate: $($file.FullName)"
            $invalidSignatures += [PSCustomObject]@{
                Path   = $file.FullName
                Status = 'MissingTimestamp'
            }
        }
    }

    if ($invalidSignatures.Count -gt 0) {
        Write-Host "Signature compliance failed. Invalid signatures: $($invalidSignatures.Count)" -ForegroundColor Red

        if ($shouldRenderTable) {
            $invalidSignatures | Format-Table Status, Path -AutoSize | Out-Host
        }

        $invalidSignatures | Write-Output

        return
    }

    Write-Host "Signature compliance passed. Validated $($filesToValidate.Count) file(s)." -ForegroundColor Green
}

if ($MyInvocation.InvocationName -ne '.') {
    Test-CCAuthenticodeSignature @PSBoundParameters
}
