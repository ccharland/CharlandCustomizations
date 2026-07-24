BeforeAll {
    foreach ($commandName in 'Get-ACMCertificateDetail', 'Get-ACMCertificateList') {
        if (-not (Get-Command $commandName -ErrorAction SilentlyContinue)) {
            Set-Item -Path "function:global:$commandName" -Value { } -Force
            $script:createdCommandStubs = @($script:createdCommandStubs) + $commandName
        }
    }

    . "$PSScriptRoot/../../../../../src/CharlandCustomizations/Private/New-AWSParamSplat.ps1"
    Import-Module "$PSScriptRoot/../../../../../src/CharlandCustomizations/Public/AWS/ACM/ACM-Customizations.psm1" -Force
}

AfterAll {
    foreach ($commandName in @($script:createdCommandStubs)) {
        Remove-Item "function:global:$commandName" -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Get-CHARACMCertificateInventory export' -Tag 'Unit' {
    It 'is exported from ACM-Customizations' {
        (Get-Command Get-CHARACMCertificateInventory -Module ACM-Customizations).Name | Should -Be 'Get-CHARACMCertificateInventory'
    }
}
