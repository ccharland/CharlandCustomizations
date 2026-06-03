<#
.SYNOPSIS
    Validates that all exported functions and release scripts have comment-based help.
.DESCRIPTION
    Imports the CharlandCustomizations module and checks every exported function for a
    valid .SYNOPSIS. Also validates all .ps1 scripts under the Scripts directory.
    Functions missing help or returning the default (function name as synopsis) are
    flagged as failures.
.PARAMETER ModulePath
    Path to the module manifest. Defaults to src/CharlandCustomizations/CharlandCustomizations.psd1.
.PARAMETER ScriptPath
    Path to the Scripts directory. Defaults to Scripts.
.EXAMPLE
    ./Scripts/Test-HelpCompliance.ps1
    Validates help for all exported functions and scripts.
.EXAMPLE
    ./Scripts/Test-HelpCompliance.ps1 -ModulePath ./src/CharlandCustomizations/CharlandCustomizations.psd1
    Validates help using an explicit module path.
.OUTPUTS
    PSCustomObject

    If any functions or scripts fail validation, objects are emitted with Name, Type, and Issue properties.
#>
[CmdletBinding()]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'Gate script uses Write-Host for high-visibility pass/fail status in release workflows')]
param(
    [Parameter()]
    [string]$ModulePath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'src/CharlandCustomizations/CharlandCustomizations.psd1'),

    [Parameter()]
    [string]$ScriptPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'Scripts')
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -Path $ModulePath)) {
    throw "Module manifest not found: $ModulePath"
}

if (-not (Test-Path -Path $ScriptPath)) {
    throw "Scripts directory not found: $ScriptPath"
}

# Import module so Get-Help can discover function help
Import-Module $ModulePath -Force

$manifest = Import-PowerShellDataFile -Path $ModulePath
$prefix = $manifest.DefaultCommandPrefix

$failures = @()

# Validate exported functions
foreach ($function in $manifest.FunctionsToExport) {
    $prefixedName = "$prefix$function"
    Write-Verbose "Checking function: $function (prefixed: $prefixedName)"

    # Get-Help uses the prefixed name when DefaultCommandPrefix is set
    $help = Get-Help $prefixedName -ErrorAction SilentlyContinue

    # Fall back to unprefixed if prefixed lookup fails
    if (-not $help -or $help.Synopsis -like '*is not recognized*') {
        $help = Get-Help $function -ErrorAction SilentlyContinue
    }

    if (-not $help -or [string]::IsNullOrWhiteSpace($help.Synopsis)) {
        $failures += [PSCustomObject]@{
            Name  = $function
            Type  = 'Function'
            Issue = 'Missing .SYNOPSIS'
        }
    }
    elseif ($help.Synopsis -eq $function -or $help.Synopsis -eq $prefixedName) {
        # PowerShell returns the function name as Synopsis when no help block exists
        $failures += [PSCustomObject]@{
            Name  = $function
            Type  = 'Function'
            Issue = 'Missing .SYNOPSIS (returns default)'
        }
    }
}

# Validate Scripts/*.ps1
$scripts = Get-ChildItem -Path $ScriptPath -Filter '*.ps1'
foreach ($script in $scripts) {
    Write-Verbose "Checking script: $($script.Name)"
    $help = Get-Help $script.FullName -ErrorAction SilentlyContinue

    if (-not $help -or [string]::IsNullOrWhiteSpace($help.Synopsis)) {
        $failures += [PSCustomObject]@{
            Name  = $script.Name
            Type  = 'Script'
            Issue = 'Missing .SYNOPSIS'
        }
    }
    elseif ($help.Synopsis -eq $script.FullName -or $help.Synopsis -eq $script.Name) {
        $failures += [PSCustomObject]@{
            Name  = $script.Name
            Type  = 'Script'
            Issue = 'Missing .SYNOPSIS (returns default)'
        }
    }
}

if ($failures.Count -gt 0) {
    Write-Host "Help compliance failed. $($failures.Count) issue(s) found:" -ForegroundColor Red
    $failures | Format-Table Type, Name, Issue -AutoSize | Out-Host

    throw 'One or more functions or scripts are missing required comment-based help.'
}

Write-Host "Help compliance passed. Validated $($manifest.FunctionsToExport.Count) function(s) and $($scripts.Count) script(s)." -ForegroundColor Green
