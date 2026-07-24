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

BeforeAll {
    $script:testPfxPath = Join-Path ([System.IO.Path]::GetTempPath()) "Update-CHARPfxCertificateInACM_$([guid]::NewGuid().ToString('N')).pfx"
    $script:testPasswordSecure = ConvertTo-SecureString -String 'P@ssw0rd!' -AsPlainText -Force
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
