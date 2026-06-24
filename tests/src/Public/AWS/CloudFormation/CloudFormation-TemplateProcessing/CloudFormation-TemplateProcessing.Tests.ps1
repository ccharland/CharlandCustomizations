BeforeAll {
    $repoRoot = $PSScriptRoot
    while ($repoRoot -and -not (Test-Path (Join-Path $repoRoot 'src/CharlandCustomizations'))) {
        $repoRoot = Split-Path -Path $repoRoot -Parent
    }

    if (-not $repoRoot) {
        throw 'Unable to locate repository root.'
    }

    $script:SourcePath = Join-Path $repoRoot 'src/CharlandCustomizations/Public/AWS/CloudFormation/CloudFormation-TemplateProcessing.psm1'
}

Describe 'CloudFormation-TemplateProcessing.psm1 source test' {
    It 'exists and is not empty' {
        (Test-Path -Path $script:SourcePath) | Should -BeTrue
        (Get-Content -Path $script:SourcePath -Raw).Length | Should -BeGreaterThan 0
    }
}