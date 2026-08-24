function Measure-UseTestCHARAWSCmdlet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.ScriptBlockAst]$ScriptBlockAst
    )

    $settingsPath = Join-Path $PSScriptRoot 'Test-CHARAWSCmdletRule.Exclusions.psd1'
    $settings = Import-PowerShellDataFile -Path $settingsPath
    $excludedFunctions = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($functionName in $settings.ExcludeFunction.Keys) {
        $null = $excludedFunctions.Add($functionName)
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
