BeforeAll {
    $script:RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
    $script:ScriptsRoot = Join-Path $script:RepoRoot 'Scripts'
    $script:TestsRoot = Join-Path $script:RepoRoot 'tests/scripts'
}

Describe 'Scripts test layout gate' {
    It 'has a matching tests/scripts file with at least one It block for each script' {
        $scriptFiles = Get-ChildItem -Path $script:ScriptsRoot -File -Filter '*.ps1'

        $missing = @()
        $missingIt = @()

        foreach ($scriptFile in $scriptFiles) {
            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($scriptFile.Name)
            $testRelativePath = "$baseName.Tests.ps1"
            $testPath = Join-Path $script:TestsRoot $testRelativePath

            if (-not (Test-Path -Path $testPath)) {
                $missing += $testRelativePath
                continue
            }

            $rawTest = Get-Content -Path $testPath -Raw
            if ($rawTest -notmatch '(?m)^\s*It\s+["'']') {
                $missingIt += $testRelativePath
            }
        }

        $missing.Count | Should -Be 0 -Because ("Missing script tests under tests/scripts: {0}" -f ($missing -join ', '))
        $missingIt.Count | Should -Be 0 -Because ("Script tests missing an It block: {0}" -f ($missingIt -join ', '))
    }
}
