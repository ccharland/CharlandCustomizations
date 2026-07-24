<#
.NOTES
    Tests for the ACM certificate inspection, validation, replacement, and inventory functions.
#>
BeforeAll {
    $script:createdCommandStubs = @()
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
