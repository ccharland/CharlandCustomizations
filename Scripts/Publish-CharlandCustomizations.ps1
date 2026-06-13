<#
.SYNOPSIS
    Publish the CharlandCustomizations module to a PowerShell repository.
.DESCRIPTION
    Reads the API key from a parameter, environment variable, or SecretManagement
    secret, then publishes using PSResourceGet when available and falls back to
    PowerShellGet for older environments.
.PARAMETER Path
    Path to the module folder that contains CharlandCustomizations.psd1.
    Default is '..\src\CharlandCustomizations' relative to the script location.
.PARAMETER Repository
    Target repository name. Defaults to PSGallery.
.PARAMETER ApiKey
    Repository API key. If omitted, the script checks PSGALLERY_API_KEY and then
    an optional SecretManagement secret.
.PARAMETER SecretName
    SecretManagement secret name to read when ApiKey is not passed.
.PARAMETER SkipRepositoryTrust
    Skip setting the target repository to trusted before publishing.
.PARAMETER SkipGitValidation
    Skip branch and tag checks when publishing to PSGallery (used in CI).
.PARAMETER SkipSignatureValidation
    Skip Authenticode signature validation (used in CI where signing is validated separately).
.PARAMETER UseLegacyPowerShellGet
    Force Publish-Module instead of Publish-PSResource.
.EXAMPLE
    $env:PSGALLERY_API_KEY = '...'
    ./Scripts/Publish-CharlandCustomizations.ps1
.EXAMPLE
    ./Scripts/Publish-CharlandCustomizations.ps1 -Repository PSGallery -SecretName PSGalleryApiKey
.EXAMPLE
    ./Scripts/Publish-CharlandCustomizations.ps1 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$Path = (Join-Path $PSScriptRoot '..\src\CharlandCustomizations'),
    [string]$Repository = 'PSGallery',
    [string]$ApiKey,
    [string]$SecretName = 'PSGalleryApiKey',
    [switch]$SkipRepositoryTrust,
    [switch]$SkipGitValidation,
    [switch]$SkipSignatureValidation,
    [switch]$UseLegacyPowerShellGet
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Variable -Name CCIsWindows -Scope Script -ErrorAction SilentlyContinue)) {
    $script:CCIsWindows = if ($PSVersionTable.PSVersion.Major -lt 7) {
        [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
    }
    else {
        [bool]$IsWindows
    }
}

if (-not $script:CCIsWindows) {
    throw 'Publish-CharlandCustomizations is only supported on Windows systems.'
}

$resolvedPath = Resolve-Path -Path $Path
$manifestPath = Join-Path $resolvedPath 'CharlandCustomizations.psd1'

if (-not (Test-Path -Path $manifestPath)) {
    throw "Module manifest not found at $manifestPath"
}

if ($Repository -ieq 'PSGallery' -and -not $SkipGitValidation) {
    $manifestData = Test-ModuleManifest -Path $manifestPath -ErrorAction Stop
    $expectedReleaseTag = $manifestData.Version.ToString()
    $prerelease = $manifestData.PrivateData.PSData.Prerelease
    if ($prerelease) {
        $expectedReleaseTag = "$expectedReleaseTag-$prerelease"
    }

    if (-not (Get-Command -Name git -ErrorAction SilentlyContinue)) {
        throw "Publishing to PSGallery requires git to verify release branch/tag. Expected tag: '$expectedReleaseTag'."
    }

    $repoRoot = (& git -C $resolvedPath rev-parse --show-toplevel 2>$null | Select-Object -First 1)
    if (-not $repoRoot) {
        throw 'Publishing to PSGallery requires running inside a git repository.'
    }

    $currentBranch = (& git -C $repoRoot branch --show-current 2>$null | Select-Object -First 1)
    if ($currentBranch -ne 'main') {
        throw "Publishing to PSGallery is only allowed from branch 'main'. Current branch: '$currentBranch'."
    }

    $headTags = @(& git -C $repoRoot tag --points-at HEAD 2>$null)
    # Accept both 'v'-prefixed and bare version tags (e.g., v0.3.0-beta or 0.3.0-beta)
    $tagMatch = $headTags | Where-Object { $_ -eq $expectedReleaseTag -or $_ -eq "v$expectedReleaseTag" }
    if (-not $tagMatch) {
        throw "Publishing to PSGallery requires immutable release tag '$expectedReleaseTag' (or 'v$expectedReleaseTag') on HEAD."
    }
}


$allowedExtensions = @('.ps1', '.psm1', '.psd1')
$allModuleFiles = @(Get-ChildItem -Path $resolvedPath -Recurse -File)
$nonPowerShellFiles = @($allModuleFiles | Where-Object { $_.Extension -notin $allowedExtensions })
if ($nonPowerShellFiles.Count -gt 0) {
    $disallowedFiles = ($nonPowerShellFiles | Select-Object -ExpandProperty FullName) -join ', '
    throw "Publishing requires the module directory to contain only .ps1, .psm1, and .psd1 files. Found disallowed file(s): $disallowedFiles"
}

$filesToValidate = @($allModuleFiles | Where-Object { $_.Extension -in $allowedExtensions })
if (-not $filesToValidate) {
    throw "No PowerShell module files were found under $resolvedPath"
}

$signatureValidationCommand = Get-Command -Name Test-CCAuthenticodeSignatures -ErrorAction SilentlyContinue
if (-not $signatureValidationCommand) {
    $signatureValidationCommand = Get-Command -Name Test-CCAuthenticodeSignature -ErrorAction SilentlyContinue
}

if (-not $SkipSignatureValidation) {
    if (-not $signatureValidationCommand) {
        throw 'Publishing requires Test-CCAuthenticodeSignatures (or Test-CCAuthenticodeSignature) to be available in the current session.'
    }

    $invalidSignatures = @(& $signatureValidationCommand.Name -Path $resolvedPath -IncludeExtension $allowedExtensions)
    if ($invalidSignatures.Count -gt 0) {
        Write-Error 'Publishing requires all module files to have valid Authenticode signatures.'
        $invalidSignatures | Format-Table -AutoSize
        throw 'Publishing aborted because one or more files have invalid Authenticode signatures.'
    }
}

if (-not $ApiKey) {
    $ApiKey = $env:PSGALLERY_API_KEY
}

if (-not $ApiKey -and (Get-Command -Name Get-Secret -ErrorAction SilentlyContinue)) {
    try {
        $secretValue = Get-Secret -Name $SecretName -AsPlainText -ErrorAction Stop
        if ($secretValue) {
            $ApiKey = $secretValue
        }
    }
    catch {
        Write-Verbose "Secret '$SecretName' was not available via SecretManagement."
    }
}

if (-not $ApiKey) {
    $ApiKey = Read-Host "Enter API key for repository '$Repository'" -MaskInput
}

if (-not $ApiKey) {
    throw 'No API key was provided.'
}

$publishWithPSResourceGet = -not $UseLegacyPowerShellGet -and (Get-Command -Name Publish-PSResource -ErrorAction SilentlyContinue)

if ($publishWithPSResourceGet) {
    if (-not $SkipRepositoryTrust -and (Get-Command -Name Get-PSResourceRepository -ErrorAction SilentlyContinue)) {
        $registeredRepository = Get-PSResourceRepository -Name $Repository -ErrorAction SilentlyContinue
        if ($registeredRepository -and -not $registeredRepository.Trusted) {
            if ($PSCmdlet.ShouldProcess("PSResource repository '$Repository'", 'Set as trusted')) {
                Set-PSResourceRepository -Name $Repository -Trusted | Out-Null
            }
        }
    }

    if ($PSCmdlet.ShouldProcess("module path '$resolvedPath'", "Publish to '$Repository' using Publish-PSResource")) {
        Publish-PSResource -Path $resolvedPath -Repository $Repository -ApiKey $ApiKey
        Write-Output "Successfully published CharlandCustomizations to '$Repository' using PSResourceGet."
    }
    exit 0
}

if (-not (Get-Command -Name Publish-Module -ErrorAction SilentlyContinue)) {
    throw 'Neither Publish-PSResource nor Publish-Module is available in this PowerShell session.'
}

if ($PSCmdlet.ShouldProcess("module path '$resolvedPath'", "Publish to '$Repository' using Publish-Module")) {
    Publish-Module -Path $resolvedPath -Repository $Repository -NuGetApiKey $ApiKey
    Write-Output "Successfully published CharlandCustomizations to '$Repository' using PowerShellGet."
}
exit 0
# SIG # Begin signature block
# MIIr0AYJKoZIhvcNAQcCoIIrwTCCK70CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBlaAKkA5ITfL77
# ZGj6CuSCYfIZnOrkW7we47wLs+mtkKCCJOUwggVvMIIEV6ADAgECAhBI/JO0YFWU
# jTanyYqJ1pQWMA0GCSqGSIb3DQEBDAUAMHsxCzAJBgNVBAYTAkdCMRswGQYDVQQI
# DBJHcmVhdGVyIE1hbmNoZXN0ZXIxEDAOBgNVBAcMB1NhbGZvcmQxGjAYBgNVBAoM
# EUNvbW9kbyBDQSBMaW1pdGVkMSEwHwYDVQQDDBhBQUEgQ2VydGlmaWNhdGUgU2Vy
# dmljZXMwHhcNMjEwNTI1MDAwMDAwWhcNMjgxMjMxMjM1OTU5WjBWMQswCQYDVQQG
# EwJHQjEYMBYGA1UEChMPU2VjdGlnbyBMaW1pdGVkMS0wKwYDVQQDEyRTZWN0aWdv
# IFB1YmxpYyBDb2RlIFNpZ25pbmcgUm9vdCBSNDYwggIiMA0GCSqGSIb3DQEBAQUA
# A4ICDwAwggIKAoICAQCN55QSIgQkdC7/FiMCkoq2rjaFrEfUI5ErPtx94jGgUW+s
# hJHjUoq14pbe0IdjJImK/+8Skzt9u7aKvb0Ffyeba2XTpQxpsbxJOZrxbW6q5KCD
# J9qaDStQ6Utbs7hkNqR+Sj2pcaths3OzPAsM79szV+W+NDfjlxtd/R8SPYIDdub7
# P2bSlDFp+m2zNKzBenjcklDyZMeqLQSrw2rq4C+np9xu1+j/2iGrQL+57g2extme
# me/G3h+pDHazJyCh1rr9gOcB0u/rgimVcI3/uxXP/tEPNqIuTzKQdEZrRzUTdwUz
# T2MuuC3hv2WnBGsY2HH6zAjybYmZELGt2z4s5KoYsMYHAXVn3m3pY2MeNn9pib6q
# RT5uWl+PoVvLnTCGMOgDs0DGDQ84zWeoU4j6uDBl+m/H5x2xg3RpPqzEaDux5mcz
# mrYI4IAFSEDu9oJkRqj1c7AGlfJsZZ+/VVscnFcax3hGfHCqlBuCF6yH6bbJDoEc
# QNYWFyn8XJwYK+pF9e+91WdPKF4F7pBMeufG9ND8+s0+MkYTIDaKBOq3qgdGnA2T
# OglmmVhcKaO5DKYwODzQRjY1fJy67sPV+Qp2+n4FG0DKkjXp1XrRtX8ArqmQqsV/
# AZwQsRb8zG4Y3G9i/qZQp7h7uJ0VP/4gDHXIIloTlRmQAOka1cKG8eOO7F/05QID
# AQABo4IBEjCCAQ4wHwYDVR0jBBgwFoAUoBEKIz6W8Qfs4q8p74Klf9AwpLQwHQYD
# VR0OBBYEFDLrkpr/NZZILyhAQnAgNpFcF4XmMA4GA1UdDwEB/wQEAwIBhjAPBgNV
# HRMBAf8EBTADAQH/MBMGA1UdJQQMMAoGCCsGAQUFBwMDMBsGA1UdIAQUMBIwBgYE
# VR0gADAIBgZngQwBBAEwQwYDVR0fBDwwOjA4oDagNIYyaHR0cDovL2NybC5jb21v
# ZG9jYS5jb20vQUFBQ2VydGlmaWNhdGVTZXJ2aWNlcy5jcmwwNAYIKwYBBQUHAQEE
# KDAmMCQGCCsGAQUFBzABhhhodHRwOi8vb2NzcC5jb21vZG9jYS5jb20wDQYJKoZI
# hvcNAQEMBQADggEBABK/oe+LdJqYRLhpRrWrJAoMpIpnuDqBv0WKfVIHqI0fTiGF
# OaNrXi0ghr8QuK55O1PNtPvYRL4G2VxjZ9RAFodEhnIq1jIV9RKDwvnhXRFAZ/ZC
# J3LFI+ICOBpMIOLbAffNRk8monxmwFE2tokCVMf8WPtsAO7+mKYulaEMUykfb9gZ
# pk+e96wJ6l2CxouvgKe9gUhShDHaMuwV5KZMPWw5c9QLhTkg4IUaaOGnSDip0TYl
# d8GNGRbFiExmfS9jzpjoad+sPKhdnckcW67Y8y90z7h+9teDnRGWYpquRRPaf9xH
# +9/DUp/mBlXpnYzyOmJRvOwkDynUWICE5EV7WtgwggYUMIID/KADAgECAhB6I67a
# U2mWD5HIPlz0x+M/MA0GCSqGSIb3DQEBDAUAMFcxCzAJBgNVBAYTAkdCMRgwFgYD
# VQQKEw9TZWN0aWdvIExpbWl0ZWQxLjAsBgNVBAMTJVNlY3RpZ28gUHVibGljIFRp
# bWUgU3RhbXBpbmcgUm9vdCBSNDYwHhcNMjEwMzIyMDAwMDAwWhcNMzYwMzIxMjM1
# OTU5WjBVMQswCQYDVQQGEwJHQjEYMBYGA1UEChMPU2VjdGlnbyBMaW1pdGVkMSww
# KgYDVQQDEyNTZWN0aWdvIFB1YmxpYyBUaW1lIFN0YW1waW5nIENBIFIzNjCCAaIw
# DQYJKoZIhvcNAQEBBQADggGPADCCAYoCggGBAM2Y2ENBq26CK+z2M34mNOSJjNPv
# IhKAVD7vJq+MDoGD46IiM+b83+3ecLvBhStSVjeYXIjfa3ajoW3cS3ElcJzkyZlB
# nwDEJuHlzpbN4kMH2qRBVrjrGJgSlzzUqcGQBaCxpectRGhhnOSwcjPMI3G0hedv
# 2eNmGiUbD12OeORN0ADzdpsQ4dDi6M4YhoGE9cbY11XxM2AVZn0GiOUC9+XE0wI7
# CQKfOUfigLDn7i/WeyxZ43XLj5GVo7LDBExSLnh+va8WxTlA+uBvq1KO8RSHUQLg
# zb1gbL9Ihgzxmkdp2ZWNuLc+XyEmJNbD2OIIq/fWlwBp6KNL19zpHsODLIsgZ+WZ
# 1AzCs1HEK6VWrxmnKyJJg2Lv23DlEdZlQSGdF+z+Gyn9/CRezKe7WNyxRf4e4bwU
# trYE2F5Q+05yDD68clwnweckKtxRaF0VzN/w76kOLIaFVhf5sMM/caEZLtOYqYad
# tn034ykSFaZuIBU9uCSrKRKTPJhWvXk4CllgrwIDAQABo4IBXDCCAVgwHwYDVR0j
# BBgwFoAU9ndq3T/9ARP/FqFsggIv0Ao9FCUwHQYDVR0OBBYEFF9Y7UwxeqJhQo1S
# gLqzYZcZojKbMA4GA1UdDwEB/wQEAwIBhjASBgNVHRMBAf8ECDAGAQH/AgEAMBMG
# A1UdJQQMMAoGCCsGAQUFBwMIMBEGA1UdIAQKMAgwBgYEVR0gADBMBgNVHR8ERTBD
# MEGgP6A9hjtodHRwOi8vY3JsLnNlY3RpZ28uY29tL1NlY3RpZ29QdWJsaWNUaW1l
# U3RhbXBpbmdSb290UjQ2LmNybDB8BggrBgEFBQcBAQRwMG4wRwYIKwYBBQUHMAKG
# O2h0dHA6Ly9jcnQuc2VjdGlnby5jb20vU2VjdGlnb1B1YmxpY1RpbWVTdGFtcGlu
# Z1Jvb3RSNDYucDdjMCMGCCsGAQUFBzABhhdodHRwOi8vb2NzcC5zZWN0aWdvLmNv
# bTANBgkqhkiG9w0BAQwFAAOCAgEAEtd7IK0ONVgMnoEdJVj9TC1ndK/HYiYh9lVU
# acahRoZ2W2hfiEOyQExnHk1jkvpIJzAMxmEc6ZvIyHI5UkPCbXKspioYMdbOnBWQ
# Un733qMooBfIghpR/klUqNxx6/fDXqY0hSU1OSkkSivt51UlmJElUICZYBodzD3M
# /SFjeCP59anwxs6hwj1mfvzG+b1coYGnqsSz2wSKr+nDO+Db8qNcTbJZRAiSazr7
# KyUJGo1c+MScGfG5QHV+bps8BX5Oyv9Ct36Y4Il6ajTqV2ifikkVtB3RNBUgwu/m
# SiSUice/Jp/q8BMk/gN8+0rNIE+QqU63JoVMCMPY2752LmESsRVVoypJVt8/N3qQ
# 1c6FibbcRabo3azZkcIdWGVSAdoLgAIxEKBeNh9AQO1gQrnh1TA8ldXuJzPSuALO
# z1Ujb0PCyNVkWk7hkhVHfcvBfI8NtgWQupiaAeNHe0pWSGH2opXZYKYG4Lbukg7H
# pNi/KqJhue2Keak6qH9A8CeEOB7Eob0Zf+fU+CCQaL0cJqlmnx9HCDxF+3BLbUuf
# rV64EbTI40zqegPZdA+sXCmbcZy6okx/SjwsusWRItFA3DE8MORZeFb6BmzBtqKJ
# 7l939bbKBy2jvxcJI98Va95Q5JnlKor3m0E7xpMeYRriWklUPsetMSf2NvUQa/E5
# vVyefQIwggYaMIIEAqADAgECAhBiHW0MUgGeO5B5FSCJIRwKMA0GCSqGSIb3DQEB
# DAUAMFYxCzAJBgNVBAYTAkdCMRgwFgYDVQQKEw9TZWN0aWdvIExpbWl0ZWQxLTAr
# BgNVBAMTJFNlY3RpZ28gUHVibGljIENvZGUgU2lnbmluZyBSb290IFI0NjAeFw0y
# MTAzMjIwMDAwMDBaFw0zNjAzMjEyMzU5NTlaMFQxCzAJBgNVBAYTAkdCMRgwFgYD
# VQQKEw9TZWN0aWdvIExpbWl0ZWQxKzApBgNVBAMTIlNlY3RpZ28gUHVibGljIENv
# ZGUgU2lnbmluZyBDQSBSMzYwggGiMA0GCSqGSIb3DQEBAQUAA4IBjwAwggGKAoIB
# gQCbK51T+jU/jmAGQ2rAz/V/9shTUxjIztNsfvxYB5UXeWUzCxEeAEZGbEN4QMgC
# sJLZUKhWThj/yPqy0iSZhXkZ6Pg2A2NVDgFigOMYzB2OKhdqfWGVoYW3haT29PST
# ahYkwmMv0b/83nbeECbiMXhSOtbam+/36F09fy1tsB8je/RV0mIk8XL/tfCK6cPu
# YHE215wzrK0h1SWHTxPbPuYkRdkP05ZwmRmTnAO5/arnY83jeNzhP06ShdnRqtZl
# V59+8yv+KIhE5ILMqgOZYAENHNX9SJDm+qxp4VqpB3MV/h53yl41aHU5pledi9lC
# BbH9JeIkNFICiVHNkRmq4TpxtwfvjsUedyz8rNyfQJy/aOs5b4s+ac7IH60B+Ja7
# TVM+EKv1WuTGwcLmoU3FpOFMbmPj8pz44MPZ1f9+YEQIQty/NQd/2yGgW+ufflcZ
# /ZE9o1M7a5Jnqf2i2/uMSWymR8r2oQBMdlyh2n5HirY4jKnFH/9gRvd+QOfdRrJZ
# b1sCAwEAAaOCAWQwggFgMB8GA1UdIwQYMBaAFDLrkpr/NZZILyhAQnAgNpFcF4Xm
# MB0GA1UdDgQWBBQPKssghyi47G9IritUpimqF6TNDDAOBgNVHQ8BAf8EBAMCAYYw
# EgYDVR0TAQH/BAgwBgEB/wIBADATBgNVHSUEDDAKBggrBgEFBQcDAzAbBgNVHSAE
# FDASMAYGBFUdIAAwCAYGZ4EMAQQBMEsGA1UdHwREMEIwQKA+oDyGOmh0dHA6Ly9j
# cmwuc2VjdGlnby5jb20vU2VjdGlnb1B1YmxpY0NvZGVTaWduaW5nUm9vdFI0Ni5j
# cmwwewYIKwYBBQUHAQEEbzBtMEYGCCsGAQUFBzAChjpodHRwOi8vY3J0LnNlY3Rp
# Z28uY29tL1NlY3RpZ29QdWJsaWNDb2RlU2lnbmluZ1Jvb3RSNDYucDdjMCMGCCsG
# AQUFBzABhhdodHRwOi8vb2NzcC5zZWN0aWdvLmNvbTANBgkqhkiG9w0BAQwFAAOC
# AgEABv+C4XdjNm57oRUgmxP/BP6YdURhw1aVcdGRP4Wh60BAscjW4HL9hcpkOTz5
# jUug2oeunbYAowbFC2AKK+cMcXIBD0ZdOaWTsyNyBBsMLHqafvIhrCymlaS98+Qp
# oBCyKppP0OcxYEdU0hpsaqBBIZOtBajjcw5+w/KeFvPYfLF/ldYpmlG+vd0xqlqd
# 099iChnyIMvY5HexjO2AmtsbpVn0OhNcWbWDRF/3sBp6fWXhz7DcML4iTAWS+MVX
# eNLj1lJziVKEoroGs9Mlizg0bUMbOalOhOfCipnx8CaLZeVme5yELg09Jlo8BMe8
# 0jO37PU8ejfkP9/uPak7VLwELKxAMcJszkyeiaerlphwoKx1uHRzNyE6bxuSKcut
# isqmKL5OTunAvtONEoteSiabkPVSZ2z76mKnzAfZxCl/3dq3dUNw4rg3sTCggkHS
# RqTqlLMS7gjrhTqBmzu1L90Y1KWN/Y5JKdGvspbOrTfOXyXvmPL6E52z1NZJ6ctu
# MFBQZH3pwWvqURR8AgQdULUvrxjUYbHHj95Ejza63zdrEcxWLDX6xWls/GDnVNue
# KjWUH3fTv1Y8Wdho698YADR7TNx8X8z2Bev6SivBBOHY+uqiirZtg0y9ShQoPzmC
# cn63Syatatvx157YK9hlcPmVoa1oDE5/L9Uo2bC5a4CH2RwwggZMMIIEtKADAgEC
# AhAVVO/doV4MRRGuXmkecKnEMA0GCSqGSIb3DQEBDAUAMFQxCzAJBgNVBAYTAkdC
# MRgwFgYDVQQKEw9TZWN0aWdvIExpbWl0ZWQxKzApBgNVBAMTIlNlY3RpZ28gUHVi
# bGljIENvZGUgU2lnbmluZyBDQSBSMzYwHhcNMjMwODA5MDAwMDAwWhcNMjYwODA4
# MjM1OTU5WjBjMQswCQYDVQQGEwJVUzEWMBQGA1UECAwNTmV3IEhhbXBzaGlyZTEd
# MBsGA1UECgwUQ2hyaXN0b3BoZXIgQ2hhcmxhbmQxHTAbBgNVBAMMFENocmlzdG9w
# aGVyIENoYXJsYW5kMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAwLQA
# cUKQzYs2WJY+W2fl+/1PzX3vsFwK/W9sj1RXRLBsQjsTCYRu+jRPEZSVzL/K4L87
# 7Wxb69/ye88/RrWS0d6LUyohl0OgJwgRBXBsDIcpt3hTv7GRLAFvjzcCOvK6qk+k
# jf+bxqYSUOxfl/XDK0QvM3KgWbq2IeNHoMwvAXVFBcZnRPXp1FkcHGKf+nNwxP6V
# GWtiRrhIj99q0R4iwOQaQLRY8pe8m1wn/gwFRai1F1f/Q2EMSyvbgf7kYpFNHJK1
# 7LZR9J/G7P8h4QFQZJdMU6C4lRT+Lk2jEDF4elKF5c7DFjfMv2zd0jf3/2vOhayc
# Gna9puKwQUvtwtrmcCwOI5EXBIVBcFVS8xD6eeREvzjZXiuS83quzwxVVjNBQ2f/
# nuK54huEBbNQQeNjSkMdjyr5S0Xwf8Pic5NA4ggLUWuv2XYqTTMtXHQPZ41noEJM
# +LSBulBatGT98Tu0kib3MH7e1vREcTG7gZDnicmY0RfrWM59txft97gXP7Vj99ed
# 9t2/9niQleiT+YXy3ZpNoqGFB3XC13mM44xEff49vRSLN/B0IonG5vDpMgtFoKpq
# PtUx/oKQWtYbmoWFZkvEBRUeJOmkEmIUQonzE7aqgk/uGtyjxsBHtJzIHojA+8fG
# eD0NXjlOM1bbT0OcpSMkhRXPqiOELViMQwHrAiUCAwEAAaOCAYkwggGFMB8GA1Ud
# IwQYMBaAFA8qyyCHKLjsb0iuK1SmKaoXpM0MMB0GA1UdDgQWBBSO6WwZWwCa6iKw
# s6LE4InGvJQl3zAOBgNVHQ8BAf8EBAMCB4AwDAYDVR0TAQH/BAIwADATBgNVHSUE
# DDAKBggrBgEFBQcDAzBKBgNVHSAEQzBBMDUGDCsGAQQBsjEBAgEDAjAlMCMGCCsG
# AQUFBwIBFhdodHRwczovL3NlY3RpZ28uY29tL0NQUzAIBgZngQwBBAEwSQYDVR0f
# BEIwQDA+oDygOoY4aHR0cDovL2NybC5zZWN0aWdvLmNvbS9TZWN0aWdvUHVibGlj
# Q29kZVNpZ25pbmdDQVIzNi5jcmwweQYIKwYBBQUHAQEEbTBrMEQGCCsGAQUFBzAC
# hjhodHRwOi8vY3J0LnNlY3RpZ28uY29tL1NlY3RpZ29QdWJsaWNDb2RlU2lnbmlu
# Z0NBUjM2LmNydDAjBggrBgEFBQcwAYYXaHR0cDovL29jc3Auc2VjdGlnby5jb20w
# DQYJKoZIhvcNAQEMBQADggGBAENPYZO6JkhXuprRcjFErvAggFDfB4bJmvHwydUU
# q8EEdDkvVvS+SnqpaL+Nw5FY/X5GnIXfWKYvQJFY1o/bskqLBSH96jOk+wMWZ2Lq
# fuyEuW4OZUvBtpho2E2QwcpCQQzG47c+qtENC6lITctyoOUi5481cm9VXRL0E1g/
# MSDOqpYcd32oKt6rbqLQZD89HFgkNrfh3a4wq2O8ljai9gvQJnYV4588DGI4quzv
# 81b6mGDx9ku9zHhtvI19C1L+oQddqFFUViSwUUiNrBO7aA5iFwr1vQPkiP40Zd6f
# SSQAjrRnUI/kbK9oD2l1i/Vi9hfQ8SLarLPhW0M0qaut175+RJKlwuusUZADtgYV
# WcrmMxy20RMCUZA2bnTWXjb4pVfHUyKPU7dpM+8gG/tUPBZegMWrzWqctSPQhdRE
# pkLTMCm5E/o4ZUGNE0uo+twbGMGEyPPmjsFnIKLAqN2rHMI1Fz9pR+qMdixl+/mG
# /ElSJqGSDVArmZLn1IYhr4vQ8DCCBmIwggTKoAMCAQICEQCkKTtuHt3XpzQIh616
# TrckMA0GCSqGSIb3DQEBDAUAMFUxCzAJBgNVBAYTAkdCMRgwFgYDVQQKEw9TZWN0
# aWdvIExpbWl0ZWQxLDAqBgNVBAMTI1NlY3RpZ28gUHVibGljIFRpbWUgU3RhbXBp
# bmcgQ0EgUjM2MB4XDTI1MDMyNzAwMDAwMFoXDTM2MDMyMTIzNTk1OVowcjELMAkG
# A1UEBhMCR0IxFzAVBgNVBAgTDldlc3QgWW9ya3NoaXJlMRgwFgYDVQQKEw9TZWN0
# aWdvIExpbWl0ZWQxMDAuBgNVBAMTJ1NlY3RpZ28gUHVibGljIFRpbWUgU3RhbXBp
# bmcgU2lnbmVyIFIzNjCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBANOE
# lfRupFN48j0QS3gSBzzclIFTZ2Gsn7BjsmBF659/kpA2Ey7NXK3MP6JdrMBNU8wd
# mkf+SSIyjX++UAYWtg3Y/uDRDyg8RxHeHRJ+0U1jHEyH5uPdk1ttiPC3x/gOxIc9
# P7Gn3OgW7DQc4x07exZ4DX4XyaGDq5LoEmk/BdCM1IelVMKB3WA6YpZ/XYdJ9Jue
# OXeQObSQ/dohQCGyh0FhmwkDWKZaqQBWrBwZ++zqlt+z/QYTgEnZo6dyIo2IhXXA
# NFkCHutL8765NBxvolXMFWY8/reTnFxk3MajgM5NX6wzWdWsPJxYRhLxtJLSUJJ5
# yWRNw+NBqH1ezvFs4GgJ2ZqFJ+Dwqbx9+rw+F2gBdgo4j7CVomP49sS7Cbqsdybb
# iOGpB9DJhs5QVMpYV73TVV3IwLiBHBECrTgUfZVOMF0KSEq2zk/LsfvehswavE3W
# 4aBXJmGjgWSpcDz+6TqeTM8f1DIcgQPdz0IYgnT3yFTgiDbFGOFNt6eCidxdR6j9
# x+kpcN5RwApy4pRhE10YOV/xafBvKpRuWPjOPWRBlKdm53kS2aMh08spx7xSEqXn
# 4QQldCnUWRz3Lki+TgBlpwYwJUbR77DAayNwAANE7taBrz2v+MnnogMrvvct0iwv
# fIA1W8kp155Lo44SIfqGmrbJP6Mn+Udr3MR2oWozAgMBAAGjggGOMIIBijAfBgNV
# HSMEGDAWgBRfWO1MMXqiYUKNUoC6s2GXGaIymzAdBgNVHQ4EFgQUiGGMoSo3ZIEo
# YKGbMdCM/SwCzk8wDgYDVR0PAQH/BAQDAgbAMAwGA1UdEwEB/wQCMAAwFgYDVR0l
# AQH/BAwwCgYIKwYBBQUHAwgwSgYDVR0gBEMwQTA1BgwrBgEEAbIxAQIBAwgwJTAj
# BggrBgEFBQcCARYXaHR0cHM6Ly9zZWN0aWdvLmNvbS9DUFMwCAYGZ4EMAQQCMEoG
# A1UdHwRDMEEwP6A9oDuGOWh0dHA6Ly9jcmwuc2VjdGlnby5jb20vU2VjdGlnb1B1
# YmxpY1RpbWVTdGFtcGluZ0NBUjM2LmNybDB6BggrBgEFBQcBAQRuMGwwRQYIKwYB
# BQUHMAKGOWh0dHA6Ly9jcnQuc2VjdGlnby5jb20vU2VjdGlnb1B1YmxpY1RpbWVT
# dGFtcGluZ0NBUjM2LmNydDAjBggrBgEFBQcwAYYXaHR0cDovL29jc3Auc2VjdGln
# by5jb20wDQYJKoZIhvcNAQEMBQADggGBAAKBPqSGclEh+WWpLj1SiuHlm8xLE0ST
# hI2yLuq+75s11y6SceBchpnKpxWaGtXc8dya1Aq3RuW//y3wMThsvT4fSba2AoSW
# lR67rA4fTYGMIhgzocsids0ct/pHaocLVJSwnTYxY2pE0hPoZAvRebctbsTqENmZ
# HyOVjOFlwN2R3DRweFeNs4uyZN5LRJ5EnVYlcTOq3bl1tI5poru9WaQRWQ4eynXp
# 7Pj0Fz4DKr86HYECRJMWiDjeV0QqAcQMFsIjJtrYTw7mU81qf4FBc4u4swphLeKR
# Nyn9DDrd3HIMJ+CpdhSHEGleeZ5I79YDg3B3A/fmVY2GaMik1Vm+FajEMv4/EN2m
# mHf4zkOuhYZNzVm4NrWJeY4UAriLBOeVYODdA1GxFr1ycbcUEGlUecc4RCPgYySs
# 4d00NNuicR4a9n7idJlevAJbha/arIYMEuUqTeRRbWkhJwMKmb9yEvppRudKyu1t
# 6l21sIuIZqcpVH8oLWCxHS0LpDRF9Y4jijCCBoIwggRqoAMCAQICEDbCsL18Gzrn
# o7PdNsvJdWgwDQYJKoZIhvcNAQEMBQAwgYgxCzAJBgNVBAYTAlVTMRMwEQYDVQQI
# EwpOZXcgSmVyc2V5MRQwEgYDVQQHEwtKZXJzZXkgQ2l0eTEeMBwGA1UEChMVVGhl
# IFVTRVJUUlVTVCBOZXR3b3JrMS4wLAYDVQQDEyVVU0VSVHJ1c3QgUlNBIENlcnRp
# ZmljYXRpb24gQXV0aG9yaXR5MB4XDTIxMDMyMjAwMDAwMFoXDTM4MDExODIzNTk1
# OVowVzELMAkGA1UEBhMCR0IxGDAWBgNVBAoTD1NlY3RpZ28gTGltaXRlZDEuMCwG
# A1UEAxMlU2VjdGlnbyBQdWJsaWMgVGltZSBTdGFtcGluZyBSb290IFI0NjCCAiIw
# DQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAIid2LlFZ50d3ei5JoGaVFTAfEkF
# m8xaFQ/ZlBBEtEFAgXcUmanU5HYsyAhTXiDQkiUvpVdYqZ1uYoZEMgtHES1l1Cc6
# HaqZzEbOOp6YiTx63ywTon434aXVydmhx7Dx4IBrAou7hNGsKioIBPy5GMN7KmgY
# muu4f92sKKjbxqohUSfjk1mJlAjthgF7Hjx4vvyVDQGsd5KarLW5d73E3ThobSko
# b2SL48LpUR/O627pDchxll+bTSv1gASn/hp6IuHJorEu6EopoB1CNFp/+HpTXeNA
# RXUmdRMKbnXWflq+/g36NJXB35ZvxQw6zid61qmrlD/IbKJA6COw/8lFSPQwBP1i
# tyZdwuCysCKZ9ZjczMqbUcLFyq6KdOpuzVDR3ZUwxDKL1wCAxgL2Mpz7eZbrb/JW
# XiOcNzDpQsmwGQ6Stw8tTCqPumhLRPb7YkzM8/6NnWH3T9ClmcGSF22LEyJYNWCH
# rQqYubNeKolzqUbCqhSqmr/UdUeb49zYHr7ALL8bAJyPDmubNqMtuaobKASBqP84
# uhqcRY/pjnYd+V5/dcu9ieERjiRKKsxCG1t6tG9oj7liwPddXEcYGOUiWLm742st
# 50jGwTzxbMpepmOP1mLnJskvZaN5e45NuzAHteORlsSuDt5t4BBRCJL+5EZnnw0e
# zntk9R8QJyAkL6/bAgMBAAGjggEWMIIBEjAfBgNVHSMEGDAWgBRTeb9aqitKz1SA
# 4dibwJ3ysgNmyzAdBgNVHQ4EFgQU9ndq3T/9ARP/FqFsggIv0Ao9FCUwDgYDVR0P
# AQH/BAQDAgGGMA8GA1UdEwEB/wQFMAMBAf8wEwYDVR0lBAwwCgYIKwYBBQUHAwgw
# EQYDVR0gBAowCDAGBgRVHSAAMFAGA1UdHwRJMEcwRaBDoEGGP2h0dHA6Ly9jcmwu
# dXNlcnRydXN0LmNvbS9VU0VSVHJ1c3RSU0FDZXJ0aWZpY2F0aW9uQXV0aG9yaXR5
# LmNybDA1BggrBgEFBQcBAQQpMCcwJQYIKwYBBQUHMAGGGWh0dHA6Ly9vY3NwLnVz
# ZXJ0cnVzdC5jb20wDQYJKoZIhvcNAQEMBQADggIBAA6+ZUHtaES45aHF1BGH5Lc7
# JYzrftrIF5Ht2PFDxKKFOct/awAEWgHQMVHol9ZLSyd/pYMbaC0IZ+XBW9xhdkkm
# UV/KbUOiL7g98M/yzRyqUOZ1/IY7Ay0YbMniIibJrPcgFp73WDnRDKtVutShPSZQ
# ZAdtFwXnuiWl8eFARK3PmLqEm9UsVX+55DbVIz33Mbhba0HUTEYv3yJ1fwKGxPBs
# P/MgTECimh7eXomvMm0/GPxX2uhwCcs/YLxDnBdVVlxvDjHjO1cuwbOpkiJGHmLX
# XVNbsdXUC2xBrq9fLrfe8IBsA4hopwsCj8hTuwKXJlSTrZcPRVSccP5i9U28gZ7O
# MzoJGlxZ5384OKm0r568Mo9TYrqzKeKZgFo0fj2/0iHbj55hc20jfxvK3mQi+H7x
# pbzxZOFGm/yVQkpo+ffv5gdhp+hv1GDsvJOtJinJmgGbBFZIThbqI+MHvAmMmkfb
# 3fTxmSkop2mSJL1Y2x/955S29Gu0gSJIkc3z30vU/iXrMpWx2tS7UVfVP+5tKuzG
# tgkP7d/doqDrLF1u6Ci3TpjAZdeLLlRQZm867eVeXED58LXd1Dk6UvaAhvmWYXoi
# Lz4JA5gPBcz7J311uahxCweNxE+xxxR3kT0WKzASo5G/PyDez6NHdIUKBeE3jDPs
# 2ACc6CkJ1Sji4PKWVT0/MYIGQTCCBj0CAQEwaDBUMQswCQYDVQQGEwJHQjEYMBYG
# A1UEChMPU2VjdGlnbyBMaW1pdGVkMSswKQYDVQQDEyJTZWN0aWdvIFB1YmxpYyBD
# b2RlIFNpZ25pbmcgQ0EgUjM2AhAVVO/doV4MRRGuXmkecKnEMA0GCWCGSAFlAwQC
# AQUAoIGEMBgGCisGAQQBgjcCAQwxCjAIoAKAAKECgAAwGQYJKoZIhvcNAQkDMQwG
# CisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZI
# hvcNAQkEMSIEIG85LjsrfykUwQZ0ovDhi4NMlAzXCLgZMmSJ9twHs8waMA0GCSqG
# SIb3DQEBAQUABIICAJjyJu/zqPBfj36iSSdDet1v3FHBtgUWwExm66te6JzAfgpX
# bITs9BhFuldRDZD++hugSleGSlmzS7WWj7wTq9nLUqjFBC2lwL9kZNQoKb6XWXs0
# ouhYtgzl8mhkls+DjNojyVs7cz+VTvfYqUbJia+TeG2fQd6ysq2BkziRVSzGN608
# NeNZWUdQHHFwbVXpYFm/CGF5OsRmhOUhgAOV8csDu0RZTaWAh7BTkvfPzCRcsuE2
# f+UjUxtdu2IF3YRCIkPCK05jrVQC3etmcvpZzZiBTEYYgAkYQuXmCyt4g8z+UqpJ
# 9L57++JoOkntliCjRWooYtLwolzXNlDRi7xCzfZsKeJFZkyi5I0FrQS67KCYe45h
# /5bXKqkJWzf0Llq0sjjtr/gU4c98Pf3jqj6zNXaJL4HuFqoQ01+TxY+N8Zzeik+q
# LolRVo6xkEpdz2IFGPHF/f3JgPqXCXaoebiQxFFEX+eMPHYdJTKobAJXe3/VWtU0
# DwQb5fmd1O1ZMhbXuQJ1JvObbvX2BaqVbk3ptDNjjR+5DOo+Sy9Rw5OJRh6gMYPG
# iXTDgzOpnMPUTcxXACb4EJaEQp9pSJYv/b+s+LPUwOp4ogW1ul657M6k8f9jp32Q
# cm0HOcGTqpQnmARAUCDQJWA1V14CgK+N3sRzPWdjseeCun+pxAx5V2UVFzOsoYID
# IzCCAx8GCSqGSIb3DQEJBjGCAxAwggMMAgEBMGowVTELMAkGA1UEBhMCR0IxGDAW
# BgNVBAoTD1NlY3RpZ28gTGltaXRlZDEsMCoGA1UEAxMjU2VjdGlnbyBQdWJsaWMg
# VGltZSBTdGFtcGluZyBDQSBSMzYCEQCkKTtuHt3XpzQIh616TrckMA0GCWCGSAFl
# AwQCAgUAoHkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjYwNjEzMDQxNzAxWjA/BgkqhkiG9w0BCQQxMgQwAShgZ9ZXwP40U6ngL2Tq
# 5P3d+hvLXeVU6+rAJnq79gaTCid0CBVtqJfRiY2QAb24MA0GCSqGSIb3DQEBAQUA
# BIICALoLh0gIM2PVMEvUruKWZHlwBtgza+taws0+uokEuUm1PkuoNAXyVoXO5U8b
# +UdvC9CPFSBaS/ZzGyhQ5UTYoVXDpD2zjSHUFk/Th/WeRnRMB+vNwZE9Cnygqq/2
# vPefCfkk7Drn2qaTajhVQ/BZaa2QSBKCfpHi87lN5Rpg1EwVJJLg27k6ML7138oR
# gnTS+oAH65xS5L6KNRr6aR9IKEieNzMm2V8hxc+SBokgtqXGgV2xCCuNASwAOKUl
# A0Pc/kGWQtmxigt9CG6SFwZNkHzzVZFSuiBlcj5viuBU72RuUJda4uptanDvwmiG
# qjPwLR82fix2trFbCSurc5xSFR3c9MQIxxiHBdI3eVpWiJsm/LOkuapI4rPZ0Vuo
# w8Dxm1wlfHbTPTkitFqCXxv1QoedGwkLmqVLMWMyN0/WkKmuPs+0uTcz0WD0Hhuy
# 5OA2ulNAwjHrseag7tETlBLuiBHa7g0wt+po3o+pDPaS4yFl/IYjfSeBsE8W0obI
# vhfDVQJ97RhvOPdkiSS8t/e55R1GwV3Mag3NR0MIOEubZeYVE3kZ4ohi5lWa7b0g
# ofMawvTL/nCB1iAJAmrVl0l8IF6qHKA5So4wQOjpkRkO5YAaigtMn3mu+6zm24Hf
# CLjijy23n8fQEptMCTA5xiKDmvh2PULwqy5lkGQoI5R/1bzz
# SIG # End signature block
