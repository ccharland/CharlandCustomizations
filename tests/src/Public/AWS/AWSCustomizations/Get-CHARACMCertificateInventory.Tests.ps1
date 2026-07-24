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

Describe 'Get-CHARACMCertificateInventory' -Tag 'Unit' {
    BeforeEach {
        Mock Get-ACMCertificateList -ModuleName ACM-Customizations {
            @(
                [PSCustomObject]@{ CertificateArn = 'arn:aws:acm:us-east-1:123456789012:certificate/one' }
                [PSCustomObject]@{ CertificateArn = 'arn:aws:acm:us-east-1:123456789012:certificate/two' }
            )
        }
        Mock Get-ACMCertificateDetail -ModuleName ACM-Customizations {
            [PSCustomObject]@{
                CertificateArn = $CertificateArn
                DomainName = if ($CertificateArn -like '*/one') { 'one.example' } else { 'two.example' }
                Status = 'ISSUED'
                NotAfter = [DateTime]::UtcNow.AddDays(90)
                InUseBy = @("resource-for-$CertificateArn")
            }
        }
    }

    It 'returns the issue-required inventory fields for every certificate' {
        $results = @(Get-CHARACMCertificateInventory -Region us-east-1 -ProfileName test-profile)

        $results.Count | Should -Be 2
        $results[0].PSObject.Properties.Name | Should -Contain 'Region'
        $results[0].PSObject.Properties.Name | Should -Contain 'CertificateArn'
        $results[0].PSObject.Properties.Name | Should -Contain 'DomainName'
        $results[0].PSObject.Properties.Name | Should -Contain 'Status'
        $results[0].PSObject.Properties.Name | Should -Contain 'NotAfter'
        $results[0].PSObject.Properties.Name | Should -Contain 'DaysRemaining'
        $results[0].PSObject.Properties.Name | Should -Contain 'InUseBy'

        Should -Invoke Get-ACMCertificateList -ModuleName ACM-Customizations -Times 1
        Should -Invoke Get-ACMCertificateDetail -ModuleName ACM-Customizations -Times 2
    }
}
