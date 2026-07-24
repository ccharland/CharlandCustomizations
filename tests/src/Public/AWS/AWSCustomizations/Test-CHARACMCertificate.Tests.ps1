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

Describe 'Test-CHARACMCertificate' -Tag 'Unit' {
    BeforeEach {
        Mock Get-ACMCertificateDetail -ModuleName ACM-Customizations {
            [PSCustomObject]@{
                CertificateArn = 'arn:aws:acm:us-east-1:123456789012:certificate/valid'
                DomainName = 'unit-test.example'
                Status = 'ISSUED'
                NotAfter = [DateTime]::UtcNow.AddDays(60)
                InUseBy = @('arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/test')
            }
        }
    }

    It 'reports an issued certificate with sufficient lifetime as valid' {
        $result = Test-CHARACMCertificate -CertificateArn 'arn:aws:acm:us-east-1:123456789012:certificate/valid' -MinimumDaysRemaining 30

        $result.Region | Should -Be 'us-east-1'
        $result.IsIssued | Should -BeTrue
        $result.IsExpired | Should -BeFalse
        $result.HasMinimumValidity | Should -BeTrue
        $result.IsValid | Should -BeTrue
        @($result.ValidationMessages).Count | Should -Be 0
    }

    It 'reports status and lifetime failures' {
        Mock Get-ACMCertificateDetail -ModuleName ACM-Customizations {
            [PSCustomObject]@{
                CertificateArn = 'arn:aws:acm:us-west-2:123456789012:certificate/invalid'
                DomainName = 'expired.example'
                Status = 'EXPIRED'
                NotAfter = [DateTime]::UtcNow.AddDays(-2)
                InUseBy = @()
            }
        }

        $result = Test-CHARACMCertificate -CertificateArn 'arn:aws:acm:us-west-2:123456789012:certificate/invalid'

        $result.IsValid | Should -BeFalse
        $result.IsIssued | Should -BeFalse
        $result.IsExpired | Should -BeTrue
        (@($result.ValidationMessages) -join ' ') | Should -Match 'not.*ISSUED'
        (@($result.ValidationMessages) -join ' ') | Should -Match 'expired'
    }
}
