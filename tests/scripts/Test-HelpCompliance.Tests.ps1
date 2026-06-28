BeforeAll {
    $script:SUTPath = "$PSScriptRoot/../../Scripts/Test-HelpCompliance.ps1"
}

Describe 'Test-HelpCompliance script' -Tag 'Unit' {
    It 'exists and contains a script synopsis and parameters' {
        (Test-Path -Path $script:SUTPath) | Should -BeTrue

        $raw = Get-Content -Path $script:SUTPath -Raw
        $raw | Should -Match '(?s)\.SYNOPSIS'
        $raw | Should -Match '(?s)param\s*\('
    }
}
