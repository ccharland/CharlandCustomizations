BeforeAll {
    $script:RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
    $script:SourceRoot = Join-Path $script:RepoRoot 'src/CharlandCustomizations'
    $script:TestRoot = Join-Path $script:RepoRoot 'tests/src'
}

Describe 'SRC test layout gate' {
    It 'has a matching test file with at least one It block for each src file' {
        $sourceFiles = Get-ChildItem -Path $script:SourceRoot -Recurse -File | Where-Object {
            $_.Extension -in @('.ps1', '.psm1', '.psd1')
        }

        $moduleByDirectory = @{}
        Get-ChildItem -Path $script:SourceRoot -Recurse -File -Filter '*.psm1' | ForEach-Object {
            $moduleByDirectory[$_.Directory.FullName] = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
        }

        $missing = @()
        $missingIt = @()

        foreach ($sourceFile in $sourceFiles) {
            $relativePath = $sourceFile.FullName.Substring($script:SourceRoot.Length + 1).Replace('\', '/')
            $relativeDirectory = [System.IO.Path]::GetDirectoryName($relativePath)
            if ($relativeDirectory) {
                $relativeDirectory = $relativeDirectory.Replace('\\', '/')
            }
            $sourceBaseName = [System.IO.Path]::GetFileNameWithoutExtension($relativePath)
            $sourceExtension = [System.IO.Path]::GetExtension($relativePath)

            $candidateTestRelativePaths = switch ($relativePath) {
                'CharlandCustomizations.psd1' { @('CharlandCustomizations.psd1.Tests.ps1'); break }
                'CharlandCustomizations.psm1' { @('CharlandCustomizations.psm1.Tests.ps1'); break }
                default {
                    if ($sourceExtension -eq '.psm1') {
                        $moduleRelativePath = if ($relativeDirectory) {
                            '{0}/{1}/{1}.Tests.ps1' -f $relativeDirectory, $sourceBaseName
                        }
                        else {
                            '{0}/{0}.Tests.ps1' -f $sourceBaseName
                        }

                        $legacyRelativePath = '{0}.Tests.ps1' -f ($relativePath.Substring(0, $relativePath.LastIndexOf('.')))
                        @($moduleRelativePath, $legacyRelativePath)
                        break
                    }

                    if ($sourceExtension -eq '.ps1' -and $moduleByDirectory.ContainsKey($sourceFile.Directory.FullName)) {
                        $moduleName = $moduleByDirectory[$sourceFile.Directory.FullName]
                        $moduleContainedPath = if ($relativeDirectory) {
                            '{0}/{1}/{2}.Tests.ps1' -f $relativeDirectory, $moduleName, $sourceBaseName
                        }
                        else {
                            '{0}/{1}.Tests.ps1' -f $moduleName, $sourceBaseName
                        }

                        $legacyRelativePath = '{0}.Tests.ps1' -f ($relativePath.Substring(0, $relativePath.LastIndexOf('.')))
                        @($moduleContainedPath, $legacyRelativePath)
                        break
                    }

                    @('{0}.Tests.ps1' -f ($relativePath.Substring(0, $relativePath.LastIndexOf('.'))))
                }
            }

            $testRelativePath = $candidateTestRelativePaths | Where-Object {
                Test-Path -Path (Join-Path $script:TestRoot $_)
            } | Select-Object -First 1

            if (-not $testRelativePath) {
                $missing += $candidateTestRelativePaths[0]
                continue
            }

            $testPath = Join-Path $script:TestRoot $testRelativePath
            $rawTest = Get-Content -Path $testPath -Raw
            if ($rawTest -notmatch '(?m)^\s*It\s+["'']') {
                $missingIt += $testRelativePath
            }
        }

        $missing.Count | Should -Be 0 -Because ("Missing test files under tests/src: {0}" -f ($missing -join ', '))
        $missingIt.Count | Should -Be 0 -Because ("Required tests missing an It block: {0}" -f ($missingIt -join ', '))
    }
}