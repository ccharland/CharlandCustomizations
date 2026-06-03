<#
.SYNOPSIS
    Validates that FunctionsToExport in the manifest matches the actual public function surface.
.DESCRIPTION
    Uses the PowerShell AST to discover all function definitions in the Public directory
    (both .ps1 and .psm1 files, including nested module sources). Compares the discovered
    functions against FunctionsToExport in the module manifest.

    Reports two types of drift:
    - Functions defined in source but missing from FunctionsToExport (forgot to export)
    - Functions listed in FunctionsToExport but not defined in source (stale export)
.PARAMETER ManifestPath
    Path to the module manifest (.psd1). Defaults to src/CharlandCustomizations/CharlandCustomizations.psd1.
.PARAMETER PublicPath
    Path to the Public source directory. Defaults to src/CharlandCustomizations/Public.
.EXAMPLE
    ./Scripts/Test-ManifestCompliance.ps1
    Validates the manifest matches the public function surface.
.EXAMPLE
    ./Scripts/Test-ManifestCompliance.ps1 -Verbose
    Shows each discovered function as it's found.
.OUTPUTS
    PSCustomObject

    If drift is detected, objects are emitted with FunctionName and Issue properties.
#>
[CmdletBinding()]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'Gate script uses Write-Host for high-visibility pass/fail status in release workflows')]
param(
    [Parameter()]
    [string]$ManifestPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'src/CharlandCustomizations/CharlandCustomizations.psd1'),

    [Parameter()]
    [string]$PublicPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'src/CharlandCustomizations/Public')
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -Path $ManifestPath)) {
    throw "Module manifest not found: $ManifestPath"
}

if (-not (Test-Path -Path $PublicPath)) {
    throw "Public source directory not found: $PublicPath"
}

$manifest = Import-PowerShellDataFile -Path $ManifestPath
$exportedFunctions = @($manifest.FunctionsToExport)

# Discover all function definitions in Public/**/*.ps1 and Public/**/*.psm1 using AST
$sourceFiles = Get-ChildItem -Path $PublicPath -Recurse -Include '*.ps1', '*.psm1' -File
$discoveredFunctions = @()

foreach ($file in $sourceFiles) {
    Write-Verbose "Scanning: $($file.FullName)"

    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $file.FullName, [ref]$null, [ref]$null
    )

    # Find all function definitions at any depth in the AST
    $functionDefs = $ast.FindAll(
        { param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] },
        $true
    )

    foreach ($func in $functionDefs) {
        Write-Verbose "  Found: $($func.Name)"
        $discoveredFunctions += $func.Name
    }
}

# Deduplicate (a function could be defined in a .ps1 that is dot-sourced by a .psm1)
$discoveredFunctions = $discoveredFunctions | Sort-Object -Unique

$failures = @()

# Check for functions in source that are NOT exported
$missingExports = $discoveredFunctions | Where-Object { $_ -notin $exportedFunctions }
foreach ($func in $missingExports) {
    $failures += [PSCustomObject]@{
        FunctionName = $func
        Issue        = 'Defined in source but missing from FunctionsToExport'
    }
}

# Check for functions in manifest that are NOT in source
$staleExports = $exportedFunctions | Where-Object { $_ -notin $discoveredFunctions }
foreach ($func in $staleExports) {
    $failures += [PSCustomObject]@{
        FunctionName = $func
        Issue        = 'Listed in FunctionsToExport but not found in Public source'
    }
}

if ($failures.Count -gt 0) {
    Write-Host "Manifest compliance failed. $($failures.Count) issue(s) found:" -ForegroundColor Red
    $failures | Format-Table FunctionName, Issue -AutoSize | Out-Host

    throw 'FunctionsToExport does not match the public function surface. Update the manifest or add/remove the function.'
}

Write-Host "Manifest compliance passed. $($exportedFunctions.Count) exported function(s) match $($discoveredFunctions.Count) discovered function(s)." -ForegroundColor Green
