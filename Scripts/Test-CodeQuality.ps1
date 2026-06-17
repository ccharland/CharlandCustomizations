<#
.SYNOPSIS
    Runs PSScriptAnalyzer on the module code

.DESCRIPTION
    Validates code quality using PSScriptAnalyzer with configurable severity levels

.PARAMETER Path
    Path to analyze (defaults to Modules/CharlandCustomizations)

.PARAMETER Severity
    Severity levels to check (Error, Warning, Information)

.PARAMETER ExcludeRule
    Rules to exclude from analysis

.PARAMETER Fix
    Automatically fix issues where possible

.EXAMPLE
    ./Test-CodeQuality.ps1
    Runs analysis with default settings

.EXAMPLE
    ./Test-CodeQuality.ps1 -Severity Error
    Only shows errors

.EXAMPLE
    ./Test-CodeQuality.ps1 -Fix
    Automatically fixes issues where possible
#>
[CmdletBinding()]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'Utility script uses Write-Host for interactive analysis progress and summary output')]
param(
    [Parameter()]
    [string]$Path = (Join-Path (Split-Path $PSScriptRoot -Parent) 'src/CharlandCustomizations'),

    [Parameter()]
    [ValidateSet('Error', 'Warning', 'Information')]
    [string[]]$Severity = @('Error', 'Warning'),

    [Parameter()]
    [string[]]$ExcludeRule = @(),

    [switch]$Fix
)

# Check if PSScriptAnalyzer is installed
if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
    Write-Host 'PSScriptAnalyzer not found. Installing...' -ForegroundColor Yellow
    try {
        Install-Module -Name PSScriptAnalyzer -Scope CurrentUser -Force
        Write-Host 'PSScriptAnalyzer installed successfully' -ForegroundColor Green
    } catch {
        Write-Error "Failed to install PSScriptAnalyzer: $_"
        exit 1
    }
}

Import-Module PSScriptAnalyzer

Write-Host "Running PSScriptAnalyzer on: $Path" -ForegroundColor Cyan
Write-Host "Severity levels: $($Severity -join ', ')" -ForegroundColor Cyan

$params = @{
    Path     = $Path
    Recurse  = $true
    Severity = $Severity
}

if ($ExcludeRule.Count -gt 0) {
    $params.ExcludeRule = $ExcludeRule
    Write-Host "Excluding rules: $($ExcludeRule -join ', ')" -ForegroundColor Cyan
}

if ($Fix) {
    Write-Host 'Fix mode enabled - will attempt to fix issues' -ForegroundColor Yellow
    $params.Fix = $true
}

$results = Invoke-ScriptAnalyzer @params

if ($results) {
    Write-Host "`nFound $($results.Count) issue(s):" -ForegroundColor Yellow

    # Group by severity
    $grouped = $results | Group-Object Severity
    foreach ($group in $grouped) {
        $color = switch ($group.Name) {
            'Error' { 'Red' }
            'Warning' { 'Yellow' }
            'Information' { 'Cyan' }
        }
        Write-Host "`n$($group.Name): $($group.Count)" -ForegroundColor $color
    }

    # Display results
    $results | Format-Table -Property Severity, RuleName, ScriptName, Line, Message -AutoSize

    # Check for errors
    $errors = $results | Where-Object Severity -EQ 'Error'
    if ($errors) {
        Write-Host "`nFound $($errors.Count) error(s) that must be fixed" -ForegroundColor Red
        exit 1
    }

    $warnings = $results | Where-Object Severity -EQ 'Warning'
    if ($warnings) {
        Write-Host "`nFound $($warnings.Count) warning(s) - consider fixing" -ForegroundColor Yellow
    }

    exit 0
} else {
    Write-Host "`nNo issues found! Code quality looks good." -ForegroundColor Green
    exit 0
}