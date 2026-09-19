BeforeAll {
    $script:RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    Import-Module PSScriptAnalyzer -ErrorAction Stop
    Import-Module (Join-Path $script:RepoRoot '.github/PSScriptAnalyzer/Test-CHARAWSCmdletRule.psm1') -Force
}

Describe 'Test-CHARAWSCmdlet ScriptAnalyzer rule' -Tag 'Unit' {
    It 'passes when a function calls Test-CHARAWSCmdlet' {
        $definition = @'
function Get-ExampleThing {
    Test-CHARAWSCmdlet -Name 'Get-STSCallerIdentity'
    Get-STSCallerIdentity
}
'@

        $ast = [System.Management.Automation.Language.Parser]::ParseInput($definition, [ref]$null, [ref]$null)

        @(Measure-UseTestCHARAWSCmdlet -ScriptBlockAst $ast) | Should -BeNullOrEmpty
    }

    It 'passes when the function is listed in the exclusion file' {
        $definition = @'
function Clear-CHARAuthenticodeSignature {
    param()
    Write-Output 'not an AWS helper'
}
'@

        $ast = [System.Management.Automation.Language.Parser]::ParseInput($definition, [ref]$null, [ref]$null)

        @(Measure-UseTestCHARAWSCmdlet -ScriptBlockAst $ast) | Should -BeNullOrEmpty
    }

    It 'returns an error when a function neither validates nor opts out' {
        $definition = @'
function Get-ExampleThing {
    Get-STSCallerIdentity
}
'@

        $ast = [System.Management.Automation.Language.Parser]::ParseInput($definition, [ref]$null, [ref]$null)
        $result = @(Measure-UseTestCHARAWSCmdlet -ScriptBlockAst $ast)

        $result | Should -HaveCount 1
        $result[0].RuleName | Should -Be 'UseTestCHARAWSCmdlet'
        $result[0].Severity | Should -Be 'Error'
        $result[0].Message | Should -Match 'must call Test-CHARAWSCmdlet or be added'
    }

    It 'passes against all current src functions' {
        $sourceFiles = Get-ChildItem -Path (Join-Path $script:RepoRoot 'src/CharlandCustomizations') -Recurse -Include *.ps1, *.psm1
        $results = foreach ($file in $sourceFiles) {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$null)
            Measure-UseTestCHARAWSCmdlet -ScriptBlockAst $ast
        }

        @($results) | Should -BeNullOrEmpty
    }
}
