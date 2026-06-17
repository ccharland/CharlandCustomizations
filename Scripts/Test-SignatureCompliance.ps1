<#
.SYNOPSIS
    Wrapper script for Test-CHARAuthenticodeSignature.
.DESCRIPTION
    Loads Test-CHARAuthenticodeSignature from module source when needed and invokes it.
.PARAMETER Path
    One or more root paths to scan recursively.
.PARAMETER IncludeExtension
    File extensions to validate. Defaults to .ps1, .psm1, .psd1.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string[]]$Path,

    [Parameter()]
    [ValidateSet('.ps1', '.psm1', '.psd1')]
    [string[]]$IncludeExtension = @('.ps1', '.psm1', '.psd1')
)

$publicFunctionPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'src/CharlandCustomizations/Public/Test-CHARAuthenticodeSignature.ps1'

if (-not (Get-Command Test-CHARAuthenticodeSignature -ErrorAction SilentlyContinue)) {
    . $publicFunctionPath
}

$result = Test-CHARAuthenticodeSignature @PSBoundParameters

if ($null -ne $result -and @($result).Count -gt 0) {
    $result | Write-Output
    exit 1
}