<#
.SYNOPSIS
    Validates that every source file under src/ has a matching test file under tests/src/.
.DESCRIPTION
    Enforces the test-layout rule: each .ps1 and .psm1 file in src/ must have a corresponding
    .Tests.ps1 file (or a directory of .Tests.ps1 files for multi-function modules) in the
    mirrored location under tests/src/, and each test file must contain at least one Pester
    'It' block.

    Mapping rules:
    - .ps1 files map 1:1:
        src/CharlandCustomizations/Public/Get-Thing.ps1
        -> tests/src/CharlandCustomizations/Public/Get-Thing.Tests.ps1

    - .psm1 files with multiple function definitions map to a sub-directory:
        src/CharlandCustomizations/Public/AWS/AWSCustomizations.psm1
        -> tests/src/CharlandCustomizations/Public/AWS/AWSCustomizations/ (directory with *.Tests.ps1)

    - .psm1 files with 0 or 1 function definitions accept either a direct file or a sub-directory:
        src/CharlandCustomizations/CharlandCustomizations.psm1
        -> tests/src/CharlandCustomizations/CharlandCustomizations.Tests.ps1
           OR tests/src/CharlandCustomizations/CharlandCustomizations/ (directory)

    The manifest (.psd1) is excluded — it is validated by Test-ManifestCompliance.ps1.
.PARAMETER SrcPath
    Path to the source root. Defaults to the src/ directory beside this script.
.PARAMETER TestsPath
    Path to the tests/src/ root. Defaults to tests/src/ beside this script.
.EXAMPLE
    ./Scripts/Test-SrcTestCoverage.ps1
    # Validates all source files have matching tests
.EXAMPLE
    ./Scripts/Test-SrcTestCoverage.ps1 -SrcPath ./src -TestsPath ./tests/src
    # Explicit paths
#>
[CmdletBinding()]
param(
    [string]$SrcPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'src'),
    [string]$TestsPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'tests' 'src')
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $SrcPath)) {
    Write-Error "Source path not found: $SrcPath"
    return
}

if (-not (Test-Path $TestsPath)) {
    Write-Error "Tests/src path not found: $TestsPath"
    return
}

function Test-TestFileHasItBlock {
    param([string]$TestFilePath)
    return [bool](Select-String -Path $TestFilePath -Pattern '\bIt\b' -Quiet)
}

$failures = [System.Collections.Generic.List[string]]::new()

# Get all source files (exclude .psd1 manifests — validated separately)
$sourceFiles = Get-ChildItem -Path $SrcPath -Recurse -Include '*.ps1', '*.psm1'

foreach ($sourceFile in $sourceFiles) {
    $relPath = $sourceFile.FullName.Substring($SrcPath.Length).TrimStart([char]'\', [char]'/') -replace '\\', '/'
    $stem = [System.IO.Path]::GetFileNameWithoutExtension($sourceFile.Name)
    $relDir = ([System.IO.Path]::GetDirectoryName($relPath) -replace '\\', '/').TrimStart('/')

    if ($sourceFile.Extension -eq '.psm1') {
        $functionCount = @(Select-String -Path $sourceFile.FullName -Pattern '^function\s' -AllMatches).Count

        if ($functionCount -gt 1) {
            # Multi-function module: expect a subdirectory with at least one .Tests.ps1
            $testDir = if ($relDir) { Join-Path $TestsPath $relDir $stem } else { Join-Path $TestsPath $stem }
            $testFiles = @(Get-ChildItem -Path $testDir -Filter '*.Tests.ps1' -ErrorAction SilentlyContinue)

            if ($testFiles.Count -eq 0) {
                $expectedDir = if ($relDir) { "tests/src/$relDir/$stem/*.Tests.ps1" } else { "tests/src/$stem/*.Tests.ps1" }
                $failures.Add("MISSING TEST DIR:  $relPath  ->  $expectedDir")
                continue
            }

            foreach ($testFile in $testFiles) {
                if (-not (Test-TestFileHasItBlock -TestFilePath $testFile.FullName)) {
                    $testRelPath = $testFile.FullName.Substring($TestsPath.Length).TrimStart([char]'\', [char]'/') -replace '\\', '/'
                    $failures.Add("NO TESTS:          tests/src/$testRelPath  (no 'It' block found)")
                }
            }
        }
        else {
            # Single-function or loader psm1: accept a direct file OR a sub-directory
            $directTestPath = if ($relDir) { Join-Path $TestsPath $relDir "$stem.Tests.ps1" } else { Join-Path $TestsPath "$stem.Tests.ps1" }
            $testDir = if ($relDir) { Join-Path $TestsPath $relDir $stem } else { Join-Path $TestsPath $stem }
            $testDirFiles = @(Get-ChildItem -Path $testDir -Filter '*.Tests.ps1' -ErrorAction SilentlyContinue)

            if (-not (Test-Path $directTestPath) -and $testDirFiles.Count -eq 0) {
                $expectedFile = if ($relDir) { "tests/src/$relDir/$stem.Tests.ps1" } else { "tests/src/$stem.Tests.ps1" }
                $failures.Add("MISSING TEST FILE:  $relPath  ->  $expectedFile  (or a directory $stem/)")
                continue
            }

            # Validate whichever form exists
            if (Test-Path $directTestPath) {
                if (-not (Test-TestFileHasItBlock -TestFilePath $directTestPath)) {
                    $expectedFile = if ($relDir) { "tests/src/$relDir/$stem.Tests.ps1" } else { "tests/src/$stem.Tests.ps1" }
                    $failures.Add("NO TESTS:          $expectedFile  (no 'It' block found)")
                }
            }
            foreach ($testFile in $testDirFiles) {
                if (-not (Test-TestFileHasItBlock -TestFilePath $testFile.FullName)) {
                    $testRelPath = $testFile.FullName.Substring($TestsPath.Length).TrimStart([char]'\', [char]'/') -replace '\\', '/'
                    $failures.Add("NO TESTS:          tests/src/$testRelPath  (no 'It' block found)")
                }
            }
        }
    }
    else {
        # .ps1 file: expect a direct StemName.Tests.ps1
        $expectedTestPath = if ($relDir) { Join-Path $TestsPath $relDir "$stem.Tests.ps1" } else { Join-Path $TestsPath "$stem.Tests.ps1" }

        if (-not (Test-Path $expectedTestPath)) {
            $expectedFile = if ($relDir) { "tests/src/$relDir/$stem.Tests.ps1" } else { "tests/src/$stem.Tests.ps1" }
            $failures.Add("MISSING TEST FILE:  $relPath  ->  $expectedFile")
            continue
        }

        if (-not (Test-TestFileHasItBlock -TestFilePath $expectedTestPath)) {
            $expectedFile = if ($relDir) { "tests/src/$relDir/$stem.Tests.ps1" } else { "tests/src/$stem.Tests.ps1" }
            $failures.Add("NO TESTS:          $expectedFile  (no 'It' block found)")
        }
    }
}

if ($failures.Count -gt 0) {
    $failureText = $failures -join [Environment]::NewLine
    Write-Error @"
Source test coverage check failed. The following source files are missing tests or have empty test files:

$failureText

Every file under src/ must have a matching .Tests.ps1 under tests/src/ that contains at least one 'It' block.
See the repository test layout documentation for the expected structure.
"@
}
else {
    Write-Host "Source test coverage check passed. All $($sourceFiles.Count) source files have matching tests." -ForegroundColor Green
}
