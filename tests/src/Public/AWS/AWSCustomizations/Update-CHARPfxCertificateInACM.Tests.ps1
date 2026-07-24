BeforeAll {
    if (-not (Get-Command Import-ACMCertificate -ErrorAction SilentlyContinue)) {
        Set-Item -Path function:global:Import-ACMCertificate -Value { } -Force
        $script:createdImportStub = $true
    }

    . "$PSScriptRoot/../../../../../src/CharlandCustomizations/Private/New-AWSParamSplat.ps1"
    Import-Module "$PSScriptRoot/../../../../../src/CharlandCustomizations/Public/AWS/ACM/ACM-Customizations.psm1" -Force
}

AfterAll {
    if ($script:createdImportStub) {
        Remove-Item function:global:Import-ACMCertificate -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Update-CHARPfxCertificateInACM export' -Tag 'Unit' {
    It 'is exported from ACM-Customizations' {
        (Get-Command Update-CHARPfxCertificateInACM -Module ACM-Customizations).Name | Should -Be 'Update-CHARPfxCertificateInACM'
    }
}
