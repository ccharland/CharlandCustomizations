<#
.NOTES
    Tests for the ACM certificate inspection, validation, replacement, and inventory functions.
#>
BeforeAll {
    foreach ($commandName in 'Import-ACMCertificate', 'Get-ACMCertificateDetail', 'Get-ACMCertificateList') {
        if (-not (Get-Command $commandName -ErrorAction SilentlyContinue)) {
            Set-Item -Path "function:global:$commandName" -Value { } -Force
            $script:createdCommandStubs = @($script:createdCommandStubs) + $commandName
        }
    }

    . "$PSScriptRoot/../../../../../src/CharlandCustomizations/Private/New-AWSParamSplat.ps1"
    Import-Module "$PSScriptRoot/../../../../../src/CharlandCustomizations/Public/AWS/ACM/ACM-Customizations.psm1" -Force

    $script:testRoot = Join-Path ([System.IO.Path]::GetTempPath()) "ACM-Customizations_$([guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $script:testRoot -Force | Out-Null

    $script:testPfxPath = Join-Path $script:testRoot 'unit-test-certificate.pfx'
    $script:testPasswordPlain = 'P@ssw0rd!'
    $script:testPasswordSecure = ConvertTo-SecureString -String $script:testPasswordPlain -AsPlainText -Force

    if ($IsMacOS) {
        $testKeyPath = Join-Path $script:testRoot 'unit-test.key'
        $testCertPath = Join-Path $script:testRoot 'unit-test.crt'
        & openssl req -x509 -newkey rsa:2048 -keyout $testKeyPath -out $testCertPath -days 45 -nodes -subj '/CN=unit-test.example' 2>$null
        & openssl pkcs12 -export -legacy -out $script:testPfxPath -inkey $testKeyPath -in $testCertPath -passout "pass:$($script:testPasswordPlain)" 2>$null
        if ($LASTEXITCODE -ne 0) {
            throw 'OpenSSL failed to create the macOS PFX test fixture.'
        }
    }
    else {
        $rsa = [System.Security.Cryptography.RSA]::Create(2048)
        try {
            $request = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
                'CN=unit-test.example',
                $rsa,
                [System.Security.Cryptography.HashAlgorithmName]::SHA256,
                [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
            )
            $certificate = $request.CreateSelfSigned(
                [DateTimeOffset]::UtcNow.AddDays(-1),
                [DateTimeOffset]::UtcNow.AddDays(45)
            )
            try {
                $pfxBytes = $certificate.Export(
                    [System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx,
                    $script:testPasswordPlain
                )
                [System.IO.File]::WriteAllBytes($script:testPfxPath, $pfxBytes)
            }
            finally {
                $certificate.Dispose()
            }
        }
        finally {
            $rsa.Dispose()
        }
    }
}

AfterAll {
    if (Test-Path $script:testRoot) {
        Remove-Item -Path $script:testRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    foreach ($commandName in @($script:createdCommandStubs)) {
        Remove-Item "function:global:$commandName" -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Test-CHARPfxCertificate' -Tag 'Unit' {
    It 'returns certificate validity and private-key information' {
        $result = Test-CHARPfxCertificate -PfxPath $script:testPfxPath -Password $script:testPasswordSecure

        $result.Path | Should -Be (Resolve-Path $script:testPfxPath).ProviderPath
        $result.Subject | Should -Be 'CN=unit-test.example'
        $result.HasPrivateKey | Should -BeTrue
        $result.IsExpired | Should -BeFalse
        $result.IsCurrentlyValid | Should -BeTrue
        $result.DaysRemaining | Should -BeGreaterThan 40
        $result.CertificateCount | Should -Be 1
    }

    It 'throws a useful error when the PFX path does not exist' {
        {
            Test-CHARPfxCertificate -PfxPath (Join-Path $script:testRoot 'missing.pfx')
        } | Should -Throw '*PFX file not found*'
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

Describe 'Update-CHARPfxCertificateInACM' -Tag 'Unit' {
    BeforeEach {
        Mock Import-CHARPfxCertificateToACM -ModuleName ACM-Customizations {
            [PSCustomObject]@{
                CertificateArn = $CertificateArn
                SourcePath = $PfxPath
            }
        }
    }

    It 'reimports the PFX into the supplied certificate ARN' {
        $certificateArn = 'arn:aws:acm:us-east-1:123456789012:certificate/replace'

        $result = Update-CHARPfxCertificateInACM -CertificateArn $certificateArn -PfxPath $script:testPfxPath -Password $script:testPasswordSecure -Region us-east-1 -Confirm:$false

        $result.CertificateArn | Should -Be $certificateArn
        Should -Invoke Import-CHARPfxCertificateToACM -ModuleName ACM-Customizations -Times 1 -ParameterFilter {
            $CertificateArn -eq 'arn:aws:acm:us-east-1:123456789012:certificate/replace' -and
            $PfxPath -eq $script:testPfxPath -and
            $Region -eq 'us-east-1'
        }
    }

    It 'supports WhatIf without reimporting the certificate' {
        $null = Update-CHARPfxCertificateInACM -CertificateArn 'arn:aws:acm:us-east-1:123456789012:certificate/replace' -PfxPath $script:testPfxPath -WhatIf

        Should -Invoke Import-CHARPfxCertificateToACM -ModuleName ACM-Customizations -Times 0
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

        Should -Invoke Get-ACMCertificateList -ModuleName ACM-Customizations -Times 1 -ParameterFilter {
            $Region -eq 'us-east-1' -and $ProfileName -eq 'test-profile'
        }
        Should -Invoke Get-ACMCertificateDetail -ModuleName ACM-Customizations -Times 2
    }
}
