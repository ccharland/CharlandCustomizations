function Measure-UseTestCHARAWSCmdlet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.ScriptBlockAst]$ScriptBlockAst
    )

    $settingsPath = Join-Path $PSScriptRoot 'Test-CHARAWSCmdletRule.Exclusions.psd1'
    if (-not (Test-Path -Path $settingsPath)) {
        throw "Exclusion file not found: $settingsPath"
    }
    try {
        $settings = Import-PowerShellDataFile -Path $settingsPath -ErrorAction Stop
    } catch {
        throw "Failed to load exclusion file '$settingsPath': $_"
    }
    $excludedFunctions = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    if ($null -ne $settings.ExcludeFunction) {
        foreach ($functionName in $settings.ExcludeFunction.Keys) {
            $null = $excludedFunctions.Add($functionName)
        }
    }

    $functions = $ScriptBlockAst.FindAll({
            param($Ast)
            $Ast -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $Ast.Parent -is [System.Management.Automation.Language.NamedBlockAst]
        }, $true)

    foreach ($functionDefinition in $functions) {
        if ($excludedFunctions.Contains($functionDefinition.Name)) {
            continue
        }

        $usesTestCharAwsCmdlet = $null -ne $functionDefinition.Body.Find({
                param($Ast)
                $Ast -is [System.Management.Automation.Language.CommandAst] -and
                $Ast.GetCommandName() -eq 'Test-CHARAWSCmdlet'
            }, $true)

        if ($usesTestCharAwsCmdlet) {
            continue
        }

        [Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord]::new(
            "Function '$($functionDefinition.Name)' must call Test-CHARAWSCmdlet or be added to .github/PSScriptAnalyzer/Test-CHARAWSCmdletRule.Exclusions.psd1.",
            $functionDefinition.Extent,
            'UseTestCHARAWSCmdlet',
            'Error',
            $null,
            $functionDefinition.Name,
            $null
        )
    }
}

Export-ModuleMember -Function Measure-UseTestCHARAWSCmdlet
