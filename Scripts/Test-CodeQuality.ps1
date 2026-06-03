<#
.SYNOPSIS
    Runs PSScriptAnalyzer on the module code

.DESCRIPTION
    Validates code quality using PSScriptAnalyzer with configurable severity levels

.PARAMETER Path
    Path to analyze (defaults to Modules/CharlandCustomizations)

.PARAMETER Severity
    Severity levels to check (Error, Warning, Information)

.PARAMETER ExcludeRule
    Rules to exclude from analysis

.PARAMETER Fix
    Automatically fix issues where possible

.EXAMPLE
    ./Test-CodeQuality.ps1
    Runs analysis with default settings

.EXAMPLE
    ./Test-CodeQuality.ps1 -Severity Error
    Only shows errors

.EXAMPLE
    ./Test-CodeQuality.ps1 -Fix
    Automatically fixes issues where possible
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$Path = (Join-Path (Split-Path $PSScriptRoot -Parent) 'src/CharlandCustomizations'),

    [Parameter()]
    [ValidateSet('Error', 'Warning', 'Information')]
    [string[]]$Severity = @('Error', 'Warning'),

    [Parameter()]
    [string[]]$ExcludeRule = @(),

    [switch]$Fix
)

# Check if PSScriptAnalyzer is installed
if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
    Write-Host 'PSScriptAnalyzer not found. Installing...' -ForegroundColor Yellow
    try {
        Install-Module -Name PSScriptAnalyzer -Scope CurrentUser -Force
        Write-Host 'PSScriptAnalyzer installed successfully' -ForegroundColor Green
    } catch {
        Write-Error "Failed to install PSScriptAnalyzer: $_"
        exit 1
    }
}

Import-Module PSScriptAnalyzer

Write-Host "Running PSScriptAnalyzer on: $Path" -ForegroundColor Cyan
Write-Host "Severity levels: $($Severity -join ', ')" -ForegroundColor Cyan

$params = @{
    Path     = $Path
    Recurse  = $true
    Severity = $Severity
}

if ($ExcludeRule.Count -gt 0) {
    $params.ExcludeRule = $ExcludeRule
    Write-Host "Excluding rules: $($ExcludeRule -join ', ')" -ForegroundColor Cyan
}

if ($Fix) {
    Write-Host 'Fix mode enabled - will attempt to fix issues' -ForegroundColor Yellow
    $params.Fix = $true
}

$results = Invoke-ScriptAnalyzer @params

if ($results) {
    Write-Host "`nFound $($results.Count) issue(s):" -ForegroundColor Yellow

    # Group by severity
    $grouped = $results | Group-Object Severity
    foreach ($group in $grouped) {
        $color = switch ($group.Name) {
            'Error' { 'Red' }
            'Warning' { 'Yellow' }
            'Information' { 'Cyan' }
        }
        Write-Host "`n$($group.Name): $($group.Count)" -ForegroundColor $color
    }

    # Display results
    $results | Format-Table -Property Severity, RuleName, ScriptName, Line, Message -AutoSize

    # Check for errors
    $errors = $results | Where-Object Severity -EQ 'Error'
    if ($errors) {
        Write-Host "`nFound $($errors.Count) error(s) that must be fixed" -ForegroundColor Red
        exit 1
    }

    $warnings = $results | Where-Object Severity -EQ 'Warning'
    if ($warnings) {
        Write-Host "`nFound $($warnings.Count) warning(s) - consider fixing" -ForegroundColor Yellow
    }

    exit 0
} else {
    Write-Host "`nNo issues found! Code quality looks good." -ForegroundColor Green
    exit 0
}

# SIG # Begin signature block
# MIImXQYJKoZIhvcNAQcCoIImTjCCJkoCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCpi3ESsWl/wGNs
# eZSY+BwrDkr2HgWiuMXzdDENPaquSKCCH3IwggYUMIID/KADAgECAhB6I67aU2mW
# D5HIPlz0x+M/MA0GCSqGSIb3DQEBDAUAMFcxCzAJBgNVBAYTAkdCMRgwFgYDVQQK
# Ew9TZWN0aWdvIExpbWl0ZWQxLjAsBgNVBAMTJVNlY3RpZ28gUHVibGljIFRpbWUg
# U3RhbXBpbmcgUm9vdCBSNDYwHhcNMjEwMzIyMDAwMDAwWhcNMzYwMzIxMjM1OTU5
# WjBVMQswCQYDVQQGEwJHQjEYMBYGA1UEChMPU2VjdGlnbyBMaW1pdGVkMSwwKgYD
# VQQDEyNTZWN0aWdvIFB1YmxpYyBUaW1lIFN0YW1waW5nIENBIFIzNjCCAaIwDQYJ
# KoZIhvcNAQEBBQADggGPADCCAYoCggGBAM2Y2ENBq26CK+z2M34mNOSJjNPvIhKA
# VD7vJq+MDoGD46IiM+b83+3ecLvBhStSVjeYXIjfa3ajoW3cS3ElcJzkyZlBnwDE
# JuHlzpbN4kMH2qRBVrjrGJgSlzzUqcGQBaCxpectRGhhnOSwcjPMI3G0hedv2eNm
# GiUbD12OeORN0ADzdpsQ4dDi6M4YhoGE9cbY11XxM2AVZn0GiOUC9+XE0wI7CQKf
# OUfigLDn7i/WeyxZ43XLj5GVo7LDBExSLnh+va8WxTlA+uBvq1KO8RSHUQLgzb1g
# bL9Ihgzxmkdp2ZWNuLc+XyEmJNbD2OIIq/fWlwBp6KNL19zpHsODLIsgZ+WZ1AzC
# s1HEK6VWrxmnKyJJg2Lv23DlEdZlQSGdF+z+Gyn9/CRezKe7WNyxRf4e4bwUtrYE
# 2F5Q+05yDD68clwnweckKtxRaF0VzN/w76kOLIaFVhf5sMM/caEZLtOYqYadtn03
# 4ykSFaZuIBU9uCSrKRKTPJhWvXk4CllgrwIDAQABo4IBXDCCAVgwHwYDVR0jBBgw
# FoAU9ndq3T/9ARP/FqFsggIv0Ao9FCUwHQYDVR0OBBYEFF9Y7UwxeqJhQo1SgLqz
# YZcZojKbMA4GA1UdDwEB/wQEAwIBhjASBgNVHRMBAf8ECDAGAQH/AgEAMBMGA1Ud
# JQQMMAoGCCsGAQUFBwMIMBEGA1UdIAQKMAgwBgYEVR0gADBMBgNVHR8ERTBDMEGg
# P6A9hjtodHRwOi8vY3JsLnNlY3RpZ28uY29tL1NlY3RpZ29QdWJsaWNUaW1lU3Rh
# bXBpbmdSb290UjQ2LmNybDB8BggrBgEFBQcBAQRwMG4wRwYIKwYBBQUHMAKGO2h0
# dHA6Ly9jcnQuc2VjdGlnby5jb20vU2VjdGlnb1B1YmxpY1RpbWVTdGFtcGluZ1Jv
# b3RSNDYucDdjMCMGCCsGAQUFBzABhhdodHRwOi8vb2NzcC5zZWN0aWdvLmNvbTAN
# BgkqhkiG9w0BAQwFAAOCAgEAEtd7IK0ONVgMnoEdJVj9TC1ndK/HYiYh9lVUacah
# RoZ2W2hfiEOyQExnHk1jkvpIJzAMxmEc6ZvIyHI5UkPCbXKspioYMdbOnBWQUn73
# 3qMooBfIghpR/klUqNxx6/fDXqY0hSU1OSkkSivt51UlmJElUICZYBodzD3M/SFj
# eCP59anwxs6hwj1mfvzG+b1coYGnqsSz2wSKr+nDO+Db8qNcTbJZRAiSazr7KyUJ
# Go1c+MScGfG5QHV+bps8BX5Oyv9Ct36Y4Il6ajTqV2ifikkVtB3RNBUgwu/mSiSU
# ice/Jp/q8BMk/gN8+0rNIE+QqU63JoVMCMPY2752LmESsRVVoypJVt8/N3qQ1c6F
# ibbcRabo3azZkcIdWGVSAdoLgAIxEKBeNh9AQO1gQrnh1TA8ldXuJzPSuALOz1Uj
# b0PCyNVkWk7hkhVHfcvBfI8NtgWQupiaAeNHe0pWSGH2opXZYKYG4Lbukg7HpNi/
# KqJhue2Keak6qH9A8CeEOB7Eob0Zf+fU+CCQaL0cJqlmnx9HCDxF+3BLbUufrV64
# EbTI40zqegPZdA+sXCmbcZy6okx/SjwsusWRItFA3DE8MORZeFb6BmzBtqKJ7l93
# 9bbKBy2jvxcJI98Va95Q5JnlKor3m0E7xpMeYRriWklUPsetMSf2NvUQa/E5vVye
# fQIwggYaMIIEAqADAgECAhBiHW0MUgGeO5B5FSCJIRwKMA0GCSqGSIb3DQEBDAUA
# MFYxCzAJBgNVBAYTAkdCMRgwFgYDVQQKEw9TZWN0aWdvIExpbWl0ZWQxLTArBgNV
# BAMTJFNlY3RpZ28gUHVibGljIENvZGUgU2lnbmluZyBSb290IFI0NjAeFw0yMTAz
# MjIwMDAwMDBaFw0zNjAzMjEyMzU5NTlaMFQxCzAJBgNVBAYTAkdCMRgwFgYDVQQK
# Ew9TZWN0aWdvIExpbWl0ZWQxKzApBgNVBAMTIlNlY3RpZ28gUHVibGljIENvZGUg
# U2lnbmluZyBDQSBSMzYwggGiMA0GCSqGSIb3DQEBAQUAA4IBjwAwggGKAoIBgQCb
# K51T+jU/jmAGQ2rAz/V/9shTUxjIztNsfvxYB5UXeWUzCxEeAEZGbEN4QMgCsJLZ
# UKhWThj/yPqy0iSZhXkZ6Pg2A2NVDgFigOMYzB2OKhdqfWGVoYW3haT29PSTahYk
# wmMv0b/83nbeECbiMXhSOtbam+/36F09fy1tsB8je/RV0mIk8XL/tfCK6cPuYHE2
# 15wzrK0h1SWHTxPbPuYkRdkP05ZwmRmTnAO5/arnY83jeNzhP06ShdnRqtZlV59+
# 8yv+KIhE5ILMqgOZYAENHNX9SJDm+qxp4VqpB3MV/h53yl41aHU5pledi9lCBbH9
# JeIkNFICiVHNkRmq4TpxtwfvjsUedyz8rNyfQJy/aOs5b4s+ac7IH60B+Ja7TVM+
# EKv1WuTGwcLmoU3FpOFMbmPj8pz44MPZ1f9+YEQIQty/NQd/2yGgW+ufflcZ/ZE9
# o1M7a5Jnqf2i2/uMSWymR8r2oQBMdlyh2n5HirY4jKnFH/9gRvd+QOfdRrJZb1sC
# AwEAAaOCAWQwggFgMB8GA1UdIwQYMBaAFDLrkpr/NZZILyhAQnAgNpFcF4XmMB0G
# A1UdDgQWBBQPKssghyi47G9IritUpimqF6TNDDAOBgNVHQ8BAf8EBAMCAYYwEgYD
# VR0TAQH/BAgwBgEB/wIBADATBgNVHSUEDDAKBggrBgEFBQcDAzAbBgNVHSAEFDAS
# MAYGBFUdIAAwCAYGZ4EMAQQBMEsGA1UdHwREMEIwQKA+oDyGOmh0dHA6Ly9jcmwu
# c2VjdGlnby5jb20vU2VjdGlnb1B1YmxpY0NvZGVTaWduaW5nUm9vdFI0Ni5jcmww
# ewYIKwYBBQUHAQEEbzBtMEYGCCsGAQUFBzAChjpodHRwOi8vY3J0LnNlY3RpZ28u
# Y29tL1NlY3RpZ29QdWJsaWNDb2RlU2lnbmluZ1Jvb3RSNDYucDdjMCMGCCsGAQUF
# BzABhhdodHRwOi8vb2NzcC5zZWN0aWdvLmNvbTANBgkqhkiG9w0BAQwFAAOCAgEA
# Bv+C4XdjNm57oRUgmxP/BP6YdURhw1aVcdGRP4Wh60BAscjW4HL9hcpkOTz5jUug
# 2oeunbYAowbFC2AKK+cMcXIBD0ZdOaWTsyNyBBsMLHqafvIhrCymlaS98+QpoBCy
# KppP0OcxYEdU0hpsaqBBIZOtBajjcw5+w/KeFvPYfLF/ldYpmlG+vd0xqlqd099i
# ChnyIMvY5HexjO2AmtsbpVn0OhNcWbWDRF/3sBp6fWXhz7DcML4iTAWS+MVXeNLj
# 1lJziVKEoroGs9Mlizg0bUMbOalOhOfCipnx8CaLZeVme5yELg09Jlo8BMe80jO3
# 7PU8ejfkP9/uPak7VLwELKxAMcJszkyeiaerlphwoKx1uHRzNyE6bxuSKcutisqm
# KL5OTunAvtONEoteSiabkPVSZ2z76mKnzAfZxCl/3dq3dUNw4rg3sTCggkHSRqTq
# lLMS7gjrhTqBmzu1L90Y1KWN/Y5JKdGvspbOrTfOXyXvmPL6E52z1NZJ6ctuMFBQ
# ZH3pwWvqURR8AgQdULUvrxjUYbHHj95Ejza63zdrEcxWLDX6xWls/GDnVNueKjWU
# H3fTv1Y8Wdho698YADR7TNx8X8z2Bev6SivBBOHY+uqiirZtg0y9ShQoPzmCcn63
# Syatatvx157YK9hlcPmVoa1oDE5/L9Uo2bC5a4CH2RwwggZMMIIEtKADAgECAhAV
# VO/doV4MRRGuXmkecKnEMA0GCSqGSIb3DQEBDAUAMFQxCzAJBgNVBAYTAkdCMRgw
# FgYDVQQKEw9TZWN0aWdvIExpbWl0ZWQxKzApBgNVBAMTIlNlY3RpZ28gUHVibGlj
# IENvZGUgU2lnbmluZyBDQSBSMzYwHhcNMjMwODA5MDAwMDAwWhcNMjYwODA4MjM1
# OTU5WjBjMQswCQYDVQQGEwJVUzEWMBQGA1UECAwNTmV3IEhhbXBzaGlyZTEdMBsG
# A1UECgwUQ2hyaXN0b3BoZXIgQ2hhcmxhbmQxHTAbBgNVBAMMFENocmlzdG9waGVy
# IENoYXJsYW5kMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAwLQAcUKQ
# zYs2WJY+W2fl+/1PzX3vsFwK/W9sj1RXRLBsQjsTCYRu+jRPEZSVzL/K4L877Wxb
# 69/ye88/RrWS0d6LUyohl0OgJwgRBXBsDIcpt3hTv7GRLAFvjzcCOvK6qk+kjf+b
# xqYSUOxfl/XDK0QvM3KgWbq2IeNHoMwvAXVFBcZnRPXp1FkcHGKf+nNwxP6VGWti
# RrhIj99q0R4iwOQaQLRY8pe8m1wn/gwFRai1F1f/Q2EMSyvbgf7kYpFNHJK17LZR
# 9J/G7P8h4QFQZJdMU6C4lRT+Lk2jEDF4elKF5c7DFjfMv2zd0jf3/2vOhaycGna9
# puKwQUvtwtrmcCwOI5EXBIVBcFVS8xD6eeREvzjZXiuS83quzwxVVjNBQ2f/nuK5
# 4huEBbNQQeNjSkMdjyr5S0Xwf8Pic5NA4ggLUWuv2XYqTTMtXHQPZ41noEJM+LSB
# ulBatGT98Tu0kib3MH7e1vREcTG7gZDnicmY0RfrWM59txft97gXP7Vj99ed9t2/
# 9niQleiT+YXy3ZpNoqGFB3XC13mM44xEff49vRSLN/B0IonG5vDpMgtFoKpqPtUx
# /oKQWtYbmoWFZkvEBRUeJOmkEmIUQonzE7aqgk/uGtyjxsBHtJzIHojA+8fGeD0N
# XjlOM1bbT0OcpSMkhRXPqiOELViMQwHrAiUCAwEAAaOCAYkwggGFMB8GA1UdIwQY
# MBaAFA8qyyCHKLjsb0iuK1SmKaoXpM0MMB0GA1UdDgQWBBSO6WwZWwCa6iKws6LE
# 4InGvJQl3zAOBgNVHQ8BAf8EBAMCB4AwDAYDVR0TAQH/BAIwADATBgNVHSUEDDAK
# BggrBgEFBQcDAzBKBgNVHSAEQzBBMDUGDCsGAQQBsjEBAgEDAjAlMCMGCCsGAQUF
# BwIBFhdodHRwczovL3NlY3RpZ28uY29tL0NQUzAIBgZngQwBBAEwSQYDVR0fBEIw
# QDA+oDygOoY4aHR0cDovL2NybC5zZWN0aWdvLmNvbS9TZWN0aWdvUHVibGljQ29k
# ZVNpZ25pbmdDQVIzNi5jcmwweQYIKwYBBQUHAQEEbTBrMEQGCCsGAQUFBzAChjho
# dHRwOi8vY3J0LnNlY3RpZ28uY29tL1NlY3RpZ29QdWJsaWNDb2RlU2lnbmluZ0NB
# UjM2LmNydDAjBggrBgEFBQcwAYYXaHR0cDovL29jc3Auc2VjdGlnby5jb20wDQYJ
# KoZIhvcNAQEMBQADggGBAENPYZO6JkhXuprRcjFErvAggFDfB4bJmvHwydUUq8EE
# dDkvVvS+SnqpaL+Nw5FY/X5GnIXfWKYvQJFY1o/bskqLBSH96jOk+wMWZ2LqfuyE
# uW4OZUvBtpho2E2QwcpCQQzG47c+qtENC6lITctyoOUi5481cm9VXRL0E1g/MSDO
# qpYcd32oKt6rbqLQZD89HFgkNrfh3a4wq2O8ljai9gvQJnYV4588DGI4quzv81b6
# mGDx9ku9zHhtvI19C1L+oQddqFFUViSwUUiNrBO7aA5iFwr1vQPkiP40Zd6fSSQA
# jrRnUI/kbK9oD2l1i/Vi9hfQ8SLarLPhW0M0qaut175+RJKlwuusUZADtgYVWcrm
# Mxy20RMCUZA2bnTWXjb4pVfHUyKPU7dpM+8gG/tUPBZegMWrzWqctSPQhdREpkLT
# MCm5E/o4ZUGNE0uo+twbGMGEyPPmjsFnIKLAqN2rHMI1Fz9pR+qMdixl+/mG/ElS
# JqGSDVArmZLn1IYhr4vQ8DCCBmIwggTKoAMCAQICEQCkKTtuHt3XpzQIh616Trck
# MA0GCSqGSIb3DQEBDAUAMFUxCzAJBgNVBAYTAkdCMRgwFgYDVQQKEw9TZWN0aWdv
# IExpbWl0ZWQxLDAqBgNVBAMTI1NlY3RpZ28gUHVibGljIFRpbWUgU3RhbXBpbmcg
# Q0EgUjM2MB4XDTI1MDMyNzAwMDAwMFoXDTM2MDMyMTIzNTk1OVowcjELMAkGA1UE
# BhMCR0IxFzAVBgNVBAgTDldlc3QgWW9ya3NoaXJlMRgwFgYDVQQKEw9TZWN0aWdv
# IExpbWl0ZWQxMDAuBgNVBAMTJ1NlY3RpZ28gUHVibGljIFRpbWUgU3RhbXBpbmcg
# U2lnbmVyIFIzNjCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBANOElfRu
# pFN48j0QS3gSBzzclIFTZ2Gsn7BjsmBF659/kpA2Ey7NXK3MP6JdrMBNU8wdmkf+
# SSIyjX++UAYWtg3Y/uDRDyg8RxHeHRJ+0U1jHEyH5uPdk1ttiPC3x/gOxIc9P7Gn
# 3OgW7DQc4x07exZ4DX4XyaGDq5LoEmk/BdCM1IelVMKB3WA6YpZ/XYdJ9JueOXeQ
# ObSQ/dohQCGyh0FhmwkDWKZaqQBWrBwZ++zqlt+z/QYTgEnZo6dyIo2IhXXANFkC
# HutL8765NBxvolXMFWY8/reTnFxk3MajgM5NX6wzWdWsPJxYRhLxtJLSUJJ5yWRN
# w+NBqH1ezvFs4GgJ2ZqFJ+Dwqbx9+rw+F2gBdgo4j7CVomP49sS7CbqsdybbiOGp
# B9DJhs5QVMpYV73TVV3IwLiBHBECrTgUfZVOMF0KSEq2zk/LsfvehswavE3W4aBX
# JmGjgWSpcDz+6TqeTM8f1DIcgQPdz0IYgnT3yFTgiDbFGOFNt6eCidxdR6j9x+kp
# cN5RwApy4pRhE10YOV/xafBvKpRuWPjOPWRBlKdm53kS2aMh08spx7xSEqXn4QQl
# dCnUWRz3Lki+TgBlpwYwJUbR77DAayNwAANE7taBrz2v+MnnogMrvvct0iwvfIA1
# W8kp155Lo44SIfqGmrbJP6Mn+Udr3MR2oWozAgMBAAGjggGOMIIBijAfBgNVHSME
# GDAWgBRfWO1MMXqiYUKNUoC6s2GXGaIymzAdBgNVHQ4EFgQUiGGMoSo3ZIEoYKGb
# MdCM/SwCzk8wDgYDVR0PAQH/BAQDAgbAMAwGA1UdEwEB/wQCMAAwFgYDVR0lAQH/
# BAwwCgYIKwYBBQUHAwgwSgYDVR0gBEMwQTA1BgwrBgEEAbIxAQIBAwgwJTAjBggr
# BgEFBQcCARYXaHR0cHM6Ly9zZWN0aWdvLmNvbS9DUFMwCAYGZ4EMAQQCMEoGA1Ud
# HwRDMEEwP6A9oDuGOWh0dHA6Ly9jcmwuc2VjdGlnby5jb20vU2VjdGlnb1B1Ymxp
# Y1RpbWVTdGFtcGluZ0NBUjM2LmNybDB6BggrBgEFBQcBAQRuMGwwRQYIKwYBBQUH
# MAKGOWh0dHA6Ly9jcnQuc2VjdGlnby5jb20vU2VjdGlnb1B1YmxpY1RpbWVTdGFt
# cGluZ0NBUjM2LmNydDAjBggrBgEFBQcwAYYXaHR0cDovL29jc3Auc2VjdGlnby5j
# b20wDQYJKoZIhvcNAQEMBQADggGBAAKBPqSGclEh+WWpLj1SiuHlm8xLE0SThI2y
# Luq+75s11y6SceBchpnKpxWaGtXc8dya1Aq3RuW//y3wMThsvT4fSba2AoSWlR67
# rA4fTYGMIhgzocsids0ct/pHaocLVJSwnTYxY2pE0hPoZAvRebctbsTqENmZHyOV
# jOFlwN2R3DRweFeNs4uyZN5LRJ5EnVYlcTOq3bl1tI5poru9WaQRWQ4eynXp7Pj0
# Fz4DKr86HYECRJMWiDjeV0QqAcQMFsIjJtrYTw7mU81qf4FBc4u4swphLeKRNyn9
# DDrd3HIMJ+CpdhSHEGleeZ5I79YDg3B3A/fmVY2GaMik1Vm+FajEMv4/EN2mmHf4
# zkOuhYZNzVm4NrWJeY4UAriLBOeVYODdA1GxFr1ycbcUEGlUecc4RCPgYySs4d00
# NNuicR4a9n7idJlevAJbha/arIYMEuUqTeRRbWkhJwMKmb9yEvppRudKyu1t6l21
# sIuIZqcpVH8oLWCxHS0LpDRF9Y4jijCCBoIwggRqoAMCAQICEDbCsL18Gzrno7Pd
# NsvJdWgwDQYJKoZIhvcNAQEMBQAwgYgxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpO
# ZXcgSmVyc2V5MRQwEgYDVQQHEwtKZXJzZXkgQ2l0eTEeMBwGA1UEChMVVGhlIFVT
# RVJUUlVTVCBOZXR3b3JrMS4wLAYDVQQDEyVVU0VSVHJ1c3QgUlNBIENlcnRpZmlj
# YXRpb24gQXV0aG9yaXR5MB4XDTIxMDMyMjAwMDAwMFoXDTM4MDExODIzNTk1OVow
# VzELMAkGA1UEBhMCR0IxGDAWBgNVBAoTD1NlY3RpZ28gTGltaXRlZDEuMCwGA1UE
# AxMlU2VjdGlnbyBQdWJsaWMgVGltZSBTdGFtcGluZyBSb290IFI0NjCCAiIwDQYJ
# KoZIhvcNAQEBBQADggIPADCCAgoCggIBAIid2LlFZ50d3ei5JoGaVFTAfEkFm8xa
# FQ/ZlBBEtEFAgXcUmanU5HYsyAhTXiDQkiUvpVdYqZ1uYoZEMgtHES1l1Cc6HaqZ
# zEbOOp6YiTx63ywTon434aXVydmhx7Dx4IBrAou7hNGsKioIBPy5GMN7KmgYmuu4
# f92sKKjbxqohUSfjk1mJlAjthgF7Hjx4vvyVDQGsd5KarLW5d73E3ThobSkob2SL
# 48LpUR/O627pDchxll+bTSv1gASn/hp6IuHJorEu6EopoB1CNFp/+HpTXeNARXUm
# dRMKbnXWflq+/g36NJXB35ZvxQw6zid61qmrlD/IbKJA6COw/8lFSPQwBP1ityZd
# wuCysCKZ9ZjczMqbUcLFyq6KdOpuzVDR3ZUwxDKL1wCAxgL2Mpz7eZbrb/JWXiOc
# NzDpQsmwGQ6Stw8tTCqPumhLRPb7YkzM8/6NnWH3T9ClmcGSF22LEyJYNWCHrQqY
# ubNeKolzqUbCqhSqmr/UdUeb49zYHr7ALL8bAJyPDmubNqMtuaobKASBqP84uhqc
# RY/pjnYd+V5/dcu9ieERjiRKKsxCG1t6tG9oj7liwPddXEcYGOUiWLm742st50jG
# wTzxbMpepmOP1mLnJskvZaN5e45NuzAHteORlsSuDt5t4BBRCJL+5EZnnw0ezntk
# 9R8QJyAkL6/bAgMBAAGjggEWMIIBEjAfBgNVHSMEGDAWgBRTeb9aqitKz1SA4dib
# wJ3ysgNmyzAdBgNVHQ4EFgQU9ndq3T/9ARP/FqFsggIv0Ao9FCUwDgYDVR0PAQH/
# BAQDAgGGMA8GA1UdEwEB/wQFMAMBAf8wEwYDVR0lBAwwCgYIKwYBBQUHAwgwEQYD
# VR0gBAowCDAGBgRVHSAAMFAGA1UdHwRJMEcwRaBDoEGGP2h0dHA6Ly9jcmwudXNl
# cnRydXN0LmNvbS9VU0VSVHJ1c3RSU0FDZXJ0aWZpY2F0aW9uQXV0aG9yaXR5LmNy
# bDA1BggrBgEFBQcBAQQpMCcwJQYIKwYBBQUHMAGGGWh0dHA6Ly9vY3NwLnVzZXJ0
# cnVzdC5jb20wDQYJKoZIhvcNAQEMBQADggIBAA6+ZUHtaES45aHF1BGH5Lc7JYzr
# ftrIF5Ht2PFDxKKFOct/awAEWgHQMVHol9ZLSyd/pYMbaC0IZ+XBW9xhdkkmUV/K
# bUOiL7g98M/yzRyqUOZ1/IY7Ay0YbMniIibJrPcgFp73WDnRDKtVutShPSZQZAdt
# FwXnuiWl8eFARK3PmLqEm9UsVX+55DbVIz33Mbhba0HUTEYv3yJ1fwKGxPBsP/Mg
# TECimh7eXomvMm0/GPxX2uhwCcs/YLxDnBdVVlxvDjHjO1cuwbOpkiJGHmLXXVNb
# sdXUC2xBrq9fLrfe8IBsA4hopwsCj8hTuwKXJlSTrZcPRVSccP5i9U28gZ7OMzoJ
# GlxZ5384OKm0r568Mo9TYrqzKeKZgFo0fj2/0iHbj55hc20jfxvK3mQi+H7xpbzx
# ZOFGm/yVQkpo+ffv5gdhp+hv1GDsvJOtJinJmgGbBFZIThbqI+MHvAmMmkfb3fTx
# mSkop2mSJL1Y2x/955S29Gu0gSJIkc3z30vU/iXrMpWx2tS7UVfVP+5tKuzGtgkP
# 7d/doqDrLF1u6Ci3TpjAZdeLLlRQZm867eVeXED58LXd1Dk6UvaAhvmWYXoiLz4J
# A5gPBcz7J311uahxCweNxE+xxxR3kT0WKzASo5G/PyDez6NHdIUKBeE3jDPs2ACc
# 6CkJ1Sji4PKWVT0/MYIGQTCCBj0CAQEwaDBUMQswCQYDVQQGEwJHQjEYMBYGA1UE
# ChMPU2VjdGlnbyBMaW1pdGVkMSswKQYDVQQDEyJTZWN0aWdvIFB1YmxpYyBDb2Rl
# IFNpZ25pbmcgQ0EgUjM2AhAVVO/doV4MRRGuXmkecKnEMA0GCWCGSAFlAwQCAQUA
# oIGEMBgGCisGAQQBgjcCAQwxCjAIoAKAAKECgAAwGQYJKoZIhvcNAQkDMQwGCisG
# AQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcN
# AQkEMSIEID0sJGdLO/EuULtkclS907HfAesqcXWlbUdos4qzyl18MA0GCSqGSIb3
# DQEBAQUABIICADphJyuXMY9FGHq9+XkenOI3o1QlyS20uhLGlgWD+sjdW9mBqlUO
# KkJ0sswgNLIH+7D5gnvwAFMiVJ1b9Ry48TEAdRaSNhlwvswjkd3LpGsshq7O8t3P
# A3JrNaiXCe8L1pkJHWghmrUVCOKvCkfAybH7IYCZZ+JKQdelZmyhQm4UYJzUxadD
# SDkTN+d5jHCWRuNzF4eVZsmMcDRypgZXaCLRMKchlTAZ4k6kjLZPFR+uaKliupIn
# Y4UzLj0lPcANwZAIM0VbbflzymS5ucxVaP3FHt4rJ2txIz4x+3aGX7088dp1/pRq
# SagYTvK4gI6vtqFdRd99bc2GS8nhEk7FLx+Fwp6SqXrFmOlUuq+kCe3QuVZe/DBK
# vbkrIafUFDR9AdmkEPX7KzXpmj9HPc9gBnE2+PygW5XbAxl1XU2ikCiZ6RcISnsZ
# xxgw3UnT8wyTtzTE1H3NICKe7wl0Mf1WmRIn279MC+2lI8DAuGNeT4KS3RXaQdR5
# Ecn1pYiQkPmUG6FDR4b+qUILQEAaaZzmtkojbBHtyEOLcwe96h3jjBNwmO7J4ma+
# JCPQEFxa9QFVLUGIBERAXMm/H14cg6E3AHXs3BagiyN0mBAQb9OTpz3VcEWq29RP
# LH+WQYoIUNNQZbyi6IWquK9QTOeIB8lWLHfnHeFeeLUcSIfobYVw1iDeoYIDIzCC
# Ax8GCSqGSIb3DQEJBjGCAxAwggMMAgEBMGowVTELMAkGA1UEBhMCR0IxGDAWBgNV
# BAoTD1NlY3RpZ28gTGltaXRlZDEsMCoGA1UEAxMjU2VjdGlnbyBQdWJsaWMgVGlt
# ZSBTdGFtcGluZyBDQSBSMzYCEQCkKTtuHt3XpzQIh616TrckMA0GCWCGSAFlAwQC
# AgUAoHkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUxDxcN
# MjYwNjAzMjEwODI1WjA/BgkqhkiG9w0BCQQxMgQwVOV/bt8IbMkvHhYBbSlzcRRK
# 3KUilCfzYRno3Dhm49tV6ICS/K9e1sa1JNJur1crMA0GCSqGSIb3DQEBAQUABIIC
# ABV4K5mexdPj36AwonHZzgYoKsCVWQdXe0JEOQM/YTEcKzwcIobWolnjWD09leJV
# HC3Hd+uZxO3M5UsXX+uGjzspQmJGUDHaOQI15OjaL86eKMuXI4jDxaYv1Yzx+4VQ
# ZlXoLBYIogOXCKv3Vcz3AbG0kHEvX3bwy7a58/d8Rz41Zu/toCHSqT31IooA56dk
# h7OfzdrUIHc/01U1CaL+JPNKzJbIPkCQOhOUGdz/IYzWFrCynUsYh1Sxt78lsJh+
# L/32Ohjn7v0zcopjHfGOsIRldokfG7TY0CygO4OSIINa3akZ2xIfbh3+zOYrQlgJ
# PFyTrKiETlF9Oga8Og7hWQdcW93/x/cZNvAiAAMyRl/myICKxgt1DQWGfdjJue/t
# 5f+KAPcNrhQDHz+cmd+XB0WSYQ3TkamA806t+5lW/DMT6g2TsFlxroA/QDghYP5f
# RbZzj7EftqJ8ikH/rbr92sRV93jUzy9e5YVJZ3Xv/XPRg2GhakZbR642ho6fkXD3
# YHwBzZn9B/e/wCzgRjxShee4PpU9oShtP1azfus/tvaqExj377IJ2vTTQd6PB0aE
# zV6RYhPTwA8Njp3AuqGWJzXX6AKjVfSCfstUhExJIWXbr3Tkr02p3P0Rv0SHBDHa
# ZEC0ZzlYwpoXBNinvb0fWgEfnWOoknQCdLVbDhoTZXus
# SIG # End signature block
