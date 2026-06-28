BeforeAll {
    $script:SUTPath = "$PSScriptRoot/../../Scripts/Test-ManifestCompliance.ps1"
}

Describe 'Test-ManifestCompliance script' -Tag 'Unit' {
    It 'exists and defines expected compliance parameters' {
        (Test-Path -Path $script:SUTPath) | Should -BeTrue

        $raw = Get-Content -Path $script:SUTPath -Raw
        $raw | Should -Match '(?s)\$ManifestPath'
        $raw | Should -Match '(?s)\$PublicPath'
    }
}
