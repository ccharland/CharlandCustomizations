Describe 'CharlandCustomizations manifest metadata' -Tag 'Unit' {
    It 'uses the correct lowercase assets path for IconUri' {
        $manifestPath = Join-Path $PSScriptRoot '../../../src/CharlandCustomizations/CharlandCustomizations.psd1'
        $manifest = Import-PowerShellDataFile -Path $manifestPath

        $manifest.PrivateData.PSData.IconUri | Should -Be 'https://raw.githubusercontent.com/ccharland/CharlandCustomizations/main/assets/icon-512.png'
    }
}
