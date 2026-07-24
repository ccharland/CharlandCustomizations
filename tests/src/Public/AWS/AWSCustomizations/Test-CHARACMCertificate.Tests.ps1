BeforeAll {
    if (-not (Get-Command Get-ACMCertificateDetail -ErrorAction SilentlyContinue)) {
        Set-Item -Path function:global:Get-ACMCertificateDetail -Value { } -Force
        $script:createdDetailStub = $true
    }

    . "$PSScriptRoot/../../../../../src/CharlandCustomizations/Private/New-AWSParamSplat.ps1"
    Import-Module "$PSScriptRoot/../../../../../src/CharlandCustomizations/Public/AWS/ACM/ACM-Customizations.psm1" -Force
}

AfterAll {
    if ($script:createdDetailStub) {
        Remove-Item function:global:Get-ACMCertificateDetail -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Test-CHARACMCertificate export' -Tag 'Unit' {
    It 'is exported from ACM-Customizations' {
        (Get-Command Test-CHARACMCertificate -Module ACM-Customizations).Name | Should -Be 'Test-CHARACMCertificate'
    }
}
