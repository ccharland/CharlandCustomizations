<#
.SYNOPSIS
    Validates branch/path separation for repository changes.
.DESCRIPTION
    Blocks workflow and editor configuration changes on normal code branches, and blocks
    source and tests/src changes on workflow/infrastructure branches.

    Used in workflows:
        - .github/workflows/pr-quality-gate.yml
        - .github/workflows/publish.yml
    to enforce branch/path separation policy.

    Test paths are separated by concern:
    - tests/src/  mirrors the source module and is owned by code branches
    - tests/scripts/ mirrors Scripts/ and is owned by infrastructure branches
.PARAMETER BranchName
    Branch name to classify.
.PARAMETER ChangedPath
    Changed repository-relative paths to validate.
.EXAMPLE
    ./Scripts/Test-BranchPathPolicy.ps1 -BranchName 'feature/add-audit' -ChangedPath @('src/CharlandCustomizations/Public/AWS/Audit/Audit-AWSAccount.psm1')
    # Passes: source changes are allowed on a normal code branch
.EXAMPLE
    ./Scripts/Test-BranchPathPolicy.ps1 -BranchName 'feature/add-audit' -ChangedPath @('tests/src/CharlandCustomizations/Public/AWS/Audit/Audit-AWSAccount/Audit-Functions.Tests.ps1')
    # Passes: tests/src changes are allowed on a normal code branch
.EXAMPLE
    ./Scripts/Test-BranchPathPolicy.ps1 -BranchName 'feature/add-audit' -ChangedPath @('.github/workflows/publish.yml')
    # Fails: workflow changes are not allowed on a normal code branch
.EXAMPLE
    ./Scripts/Test-BranchPathPolicy.ps1 -BranchName 'feature/add-audit' -ChangedPath @('tests/scripts/Build-Module.Tests.ps1')
    # Fails: tests/scripts changes are not allowed on a normal code branch
.EXAMPLE
    ./Scripts/Test-BranchPathPolicy.ps1 -BranchName 'ci/update-workflows' -ChangedPath @('.github/workflows/publish.yml', '.kiro/settings/mcp.json')
    # Passes: workflow/infra changes are allowed on a CI branch
.EXAMPLE
    ./Scripts/Test-BranchPathPolicy.ps1 -BranchName 'ci/update-workflows' -ChangedPath @('tests/scripts/Build-Module.Tests.ps1')
    # Passes: tests/scripts changes are allowed on a CI branch
.EXAMPLE
    ./Scripts/Test-BranchPathPolicy.ps1 -BranchName 'ci/update-workflows' -ChangedPath @('tests/src/CharlandCustomizations/Public/Test-Thing.Tests.ps1')
    # Fails: tests/src changes are not allowed on an infrastructure branch
.EXAMPLE
    ./Scripts/Test-BranchPathPolicy.ps1 -BranchName 'infra/pipeline-fixes' -ChangedPath @('src/CharlandCustomizations/Public/Get-Something.ps1')
    # Fails: source changes are not allowed on an infrastructure branch
.EXAMPLE
    ./Scripts/Test-BranchPathPolicy.ps1 -BranchName 'experiment/new-policy' -ChangedPath @('src/CharlandCustomizations/Public/Get-Something.ps1')
    # Fails: branch prefix is not approved
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$BranchName,

    [Parameter(Mandatory)]
    [AllowEmptyCollection()]
    [string[]]$ChangedPath
)

$ErrorActionPreference = 'Stop'

Set-Variable -Name NormalCodeBranchBlockedPath -Option Constant -Value @(
    '.github'
    '.githooks'
    '.kiro/settings'
    '.vscode'
    'Scripts'
    'tests/scripts'
)

Set-Variable -Name WorkflowInfrastructureBranchBlockedPath -Option Constant -Value @(
    'src'
    'tests/src'
)

Set-Variable -Name PublishBranchBlockedPath -Option Constant -Value @(
    '.github'
    '.githooks'
    '.kiro'
    '.vscode'
    'Scripts'
    'tests'
)

$approvedBranchPrefixes = @(
    [pscustomobject]@{
        BranchPrefix = 'feature/'
        BlockedPath = $NormalCodeBranchBlockedPath
        BranchType = 'normal code branch'
    },
    [pscustomobject]@{
        BranchPrefix = 'bugfix/'
        BlockedPath = $NormalCodeBranchBlockedPath
        BranchType = 'normal code branch'
    },
    [pscustomobject]@{
        BranchPrefix = 'hotfix/'
        BlockedPath = $NormalCodeBranchBlockedPath
        BranchType = 'normal code branch'
    },
    [pscustomobject]@{
        BranchPrefix = 'workflow/'
        BlockedPath = $WorkflowInfrastructureBranchBlockedPath
        BranchType = 'workflow/infrastructure branch'
    },
    [pscustomobject]@{
        BranchPrefix = 'workflows/'
        BlockedPath = $WorkflowInfrastructureBranchBlockedPath
        BranchType = 'workflow/infrastructure branch'
    },
    [pscustomobject]@{
        BranchPrefix = 'infrastructure/'
        BlockedPath = $WorkflowInfrastructureBranchBlockedPath
        BranchType = 'workflow/infrastructure branch'
    },
    [pscustomobject]@{
        BranchPrefix = 'infra/'
        BlockedPath = $WorkflowInfrastructureBranchBlockedPath
        BranchType = 'workflow/infrastructure branch'
    },
    [pscustomobject]@{
        BranchPrefix = 'ci/'
        BlockedPath = $WorkflowInfrastructureBranchBlockedPath
        BranchType = 'workflow/infrastructure branch'
    },
    [pscustomobject]@{
        BranchPrefix = 'architecture/'
        BlockedPath = $NormalCodeBranchBlockedPath
        BranchType = 'normal code branch'
    },
    [pscustomobject]@{
        BranchPrefix = 'breaking/'
        BlockedPath = $NormalCodeBranchBlockedPath
        BranchType = 'normal code branch'
    },
    [pscustomobject]@{
        BranchPrefix = 'docs/'
        BlockedPath = $NormalCodeBranchBlockedPath
        BranchType = 'normal code branch'
    },
    [pscustomobject]@{
        BranchPrefix = 'chore/'
        BlockedPath = $NormalCodeBranchBlockedPath
        BranchType = 'normal code branch'
    },
    [pscustomobject]@{
        BranchPrefix = 'codex-code/'
        BlockedPath = $NormalCodeBranchBlockedPath
        BranchType = 'normal code branch'
    },
    [pscustomobject]@{
        BranchPrefix = 'copilot-code/'
        BlockedPath = $NormalCodeBranchBlockedPath
        BranchType = 'normal code branch'
    },
    [pscustomobject]@{
        BranchPrefix = 'kiro-code/'
        BlockedPath = $NormalCodeBranchBlockedPath
        BranchType = 'normal code branch'
    },
    [pscustomobject]@{
        BranchPrefix = 'codex-infra/'
        BlockedPath = $WorkflowInfrastructureBranchBlockedPath
        BranchType = 'workflow/infrastructure branch'
    },
    [pscustomobject]@{
        BranchPrefix = 'copilot-infra/'
        BlockedPath = $WorkflowInfrastructureBranchBlockedPath
        BranchType = 'workflow/infrastructure branch'
    },
    [pscustomobject]@{
        BranchPrefix = 'kiro-infra/'
        BlockedPath = $WorkflowInfrastructureBranchBlockedPath
        BranchType = 'workflow/infrastructure branch'
    },
    [pscustomobject]@{
        BranchPrefix = 'publish/'
        BlockedPath = $PublishBranchBlockedPath
        BranchType = 'publish/release branch'
    }
)


$normalizedBranchName = $BranchName.ToLowerInvariant()
$matchingBranchPolicy = $approvedBranchPrefixes | Where-Object {
    $normalizedBranchName.StartsWith($_.BranchPrefix)
} | Select-Object -First 1

if (-not $matchingBranchPolicy) {
    $branchPrefix = ($BranchName -split '/', 2)[0].ToLowerInvariant()
    $approvedPrefixText = ($approvedBranchPrefixes | ForEach-Object { "'$($_.BranchPrefix)*'" }) -join ', '
    Write-Error @"
Branch path policy failed.

Branch '$BranchName' has unrecognized prefix '$branchPrefix/'.
Allowed branch prefixes are: $approvedPrefixText.

All changes are blocked until the branch is renamed to an approved prefix.
"@
    return
}

function Test-PathPrefix {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string[]]$Prefix
    )

    $normalizedPath = $Path -replace '\\', '/'

    foreach ($item in $Prefix) {
        $normalizedPrefix = $item.TrimEnd('/')
        if ($normalizedPath -eq $normalizedPrefix -or $normalizedPath.StartsWith("$normalizedPrefix/")) {
            return $true
        }
    }

    return $false
}

$blockedPrefixes = $matchingBranchPolicy.BlockedPath
$branchType = $matchingBranchPolicy.BranchType

$blockedPaths = @(
    foreach ($path in $ChangedPath) {
        if (Test-PathPrefix -Path $path -Prefix $blockedPrefixes) {
            $path
        }
    }
)

if ($blockedPaths.Count -gt 0) {
    $blockedPrefixText = ($blockedPrefixes | ForEach-Object { "$($_.TrimEnd('/'))/" }) -join ', '
    Write-Error @"
Branch path policy failed.

Branch '$BranchName' is treated as a $branchType.
Do not include changes under $blockedPrefixText on this branch type.

Blocked changed paths:
$($blockedPaths -join [Environment]::NewLine)

Split this work into a branch whose name matches the kind of change being made.
"@
}

Write-Output "Branch path policy passed for '$BranchName'."
# SIG # Begin signature block
# MIIncAYJKoZIhvcNAQcCoIInYTCCJ10CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDG+whAIBzN6X1x
# KjzAGXRpfWirxM0Par/jIJVBKxwmyqCCIIUwggYaMIIEAqADAgECAhBiHW0MUgGe
# O5B5FSCJIRwKMA0GCSqGSIb3DQEBDAUAMFYxCzAJBgNVBAYTAkdCMRgwFgYDVQQK
# Ew9TZWN0aWdvIExpbWl0ZWQxLTArBgNVBAMTJFNlY3RpZ28gUHVibGljIENvZGUg
# U2lnbmluZyBSb290IFI0NjAeFw0yMTAzMjIwMDAwMDBaFw0zNjAzMjEyMzU5NTla
# MFQxCzAJBgNVBAYTAkdCMRgwFgYDVQQKEw9TZWN0aWdvIExpbWl0ZWQxKzApBgNV
# BAMTIlNlY3RpZ28gUHVibGljIENvZGUgU2lnbmluZyBDQSBSMzYwggGiMA0GCSqG
# SIb3DQEBAQUAA4IBjwAwggGKAoIBgQCbK51T+jU/jmAGQ2rAz/V/9shTUxjIztNs
# fvxYB5UXeWUzCxEeAEZGbEN4QMgCsJLZUKhWThj/yPqy0iSZhXkZ6Pg2A2NVDgFi
# gOMYzB2OKhdqfWGVoYW3haT29PSTahYkwmMv0b/83nbeECbiMXhSOtbam+/36F09
# fy1tsB8je/RV0mIk8XL/tfCK6cPuYHE215wzrK0h1SWHTxPbPuYkRdkP05ZwmRmT
# nAO5/arnY83jeNzhP06ShdnRqtZlV59+8yv+KIhE5ILMqgOZYAENHNX9SJDm+qxp
# 4VqpB3MV/h53yl41aHU5pledi9lCBbH9JeIkNFICiVHNkRmq4TpxtwfvjsUedyz8
# rNyfQJy/aOs5b4s+ac7IH60B+Ja7TVM+EKv1WuTGwcLmoU3FpOFMbmPj8pz44MPZ
# 1f9+YEQIQty/NQd/2yGgW+ufflcZ/ZE9o1M7a5Jnqf2i2/uMSWymR8r2oQBMdlyh
# 2n5HirY4jKnFH/9gRvd+QOfdRrJZb1sCAwEAAaOCAWQwggFgMB8GA1UdIwQYMBaA
# FDLrkpr/NZZILyhAQnAgNpFcF4XmMB0GA1UdDgQWBBQPKssghyi47G9IritUpimq
# F6TNDDAOBgNVHQ8BAf8EBAMCAYYwEgYDVR0TAQH/BAgwBgEB/wIBADATBgNVHSUE
# DDAKBggrBgEFBQcDAzAbBgNVHSAEFDASMAYGBFUdIAAwCAYGZ4EMAQQBMEsGA1Ud
# HwREMEIwQKA+oDyGOmh0dHA6Ly9jcmwuc2VjdGlnby5jb20vU2VjdGlnb1B1Ymxp
# Y0NvZGVTaWduaW5nUm9vdFI0Ni5jcmwwewYIKwYBBQUHAQEEbzBtMEYGCCsGAQUF
# BzAChjpodHRwOi8vY3J0LnNlY3RpZ28uY29tL1NlY3RpZ29QdWJsaWNDb2RlU2ln
# bmluZ1Jvb3RSNDYucDdjMCMGCCsGAQUFBzABhhdodHRwOi8vb2NzcC5zZWN0aWdv
# LmNvbTANBgkqhkiG9w0BAQwFAAOCAgEABv+C4XdjNm57oRUgmxP/BP6YdURhw1aV
# cdGRP4Wh60BAscjW4HL9hcpkOTz5jUug2oeunbYAowbFC2AKK+cMcXIBD0ZdOaWT
# syNyBBsMLHqafvIhrCymlaS98+QpoBCyKppP0OcxYEdU0hpsaqBBIZOtBajjcw5+
# w/KeFvPYfLF/ldYpmlG+vd0xqlqd099iChnyIMvY5HexjO2AmtsbpVn0OhNcWbWD
# RF/3sBp6fWXhz7DcML4iTAWS+MVXeNLj1lJziVKEoroGs9Mlizg0bUMbOalOhOfC
# ipnx8CaLZeVme5yELg09Jlo8BMe80jO37PU8ejfkP9/uPak7VLwELKxAMcJszkye
# iaerlphwoKx1uHRzNyE6bxuSKcutisqmKL5OTunAvtONEoteSiabkPVSZ2z76mKn
# zAfZxCl/3dq3dUNw4rg3sTCggkHSRqTqlLMS7gjrhTqBmzu1L90Y1KWN/Y5JKdGv
# spbOrTfOXyXvmPL6E52z1NZJ6ctuMFBQZH3pwWvqURR8AgQdULUvrxjUYbHHj95E
# jza63zdrEcxWLDX6xWls/GDnVNueKjWUH3fTv1Y8Wdho698YADR7TNx8X8z2Bev6
# SivBBOHY+uqiirZtg0y9ShQoPzmCcn63Syatatvx157YK9hlcPmVoa1oDE5/L9Uo
# 2bC5a4CH2RwwggZMMIIEtKADAgECAhAVVO/doV4MRRGuXmkecKnEMA0GCSqGSIb3
# DQEBDAUAMFQxCzAJBgNVBAYTAkdCMRgwFgYDVQQKEw9TZWN0aWdvIExpbWl0ZWQx
# KzApBgNVBAMTIlNlY3RpZ28gUHVibGljIENvZGUgU2lnbmluZyBDQSBSMzYwHhcN
# MjMwODA5MDAwMDAwWhcNMjYwODA4MjM1OTU5WjBjMQswCQYDVQQGEwJVUzEWMBQG
# A1UECAwNTmV3IEhhbXBzaGlyZTEdMBsGA1UECgwUQ2hyaXN0b3BoZXIgQ2hhcmxh
# bmQxHTAbBgNVBAMMFENocmlzdG9waGVyIENoYXJsYW5kMIICIjANBgkqhkiG9w0B
# AQEFAAOCAg8AMIICCgKCAgEAwLQAcUKQzYs2WJY+W2fl+/1PzX3vsFwK/W9sj1RX
# RLBsQjsTCYRu+jRPEZSVzL/K4L877Wxb69/ye88/RrWS0d6LUyohl0OgJwgRBXBs
# DIcpt3hTv7GRLAFvjzcCOvK6qk+kjf+bxqYSUOxfl/XDK0QvM3KgWbq2IeNHoMwv
# AXVFBcZnRPXp1FkcHGKf+nNwxP6VGWtiRrhIj99q0R4iwOQaQLRY8pe8m1wn/gwF
# Rai1F1f/Q2EMSyvbgf7kYpFNHJK17LZR9J/G7P8h4QFQZJdMU6C4lRT+Lk2jEDF4
# elKF5c7DFjfMv2zd0jf3/2vOhaycGna9puKwQUvtwtrmcCwOI5EXBIVBcFVS8xD6
# eeREvzjZXiuS83quzwxVVjNBQ2f/nuK54huEBbNQQeNjSkMdjyr5S0Xwf8Pic5NA
# 4ggLUWuv2XYqTTMtXHQPZ41noEJM+LSBulBatGT98Tu0kib3MH7e1vREcTG7gZDn
# icmY0RfrWM59txft97gXP7Vj99ed9t2/9niQleiT+YXy3ZpNoqGFB3XC13mM44xE
# ff49vRSLN/B0IonG5vDpMgtFoKpqPtUx/oKQWtYbmoWFZkvEBRUeJOmkEmIUQonz
# E7aqgk/uGtyjxsBHtJzIHojA+8fGeD0NXjlOM1bbT0OcpSMkhRXPqiOELViMQwHr
# AiUCAwEAAaOCAYkwggGFMB8GA1UdIwQYMBaAFA8qyyCHKLjsb0iuK1SmKaoXpM0M
# MB0GA1UdDgQWBBSO6WwZWwCa6iKws6LE4InGvJQl3zAOBgNVHQ8BAf8EBAMCB4Aw
# DAYDVR0TAQH/BAIwADATBgNVHSUEDDAKBggrBgEFBQcDAzBKBgNVHSAEQzBBMDUG
# DCsGAQQBsjEBAgEDAjAlMCMGCCsGAQUFBwIBFhdodHRwczovL3NlY3RpZ28uY29t
# L0NQUzAIBgZngQwBBAEwSQYDVR0fBEIwQDA+oDygOoY4aHR0cDovL2NybC5zZWN0
# aWdvLmNvbS9TZWN0aWdvUHVibGljQ29kZVNpZ25pbmdDQVIzNi5jcmwweQYIKwYB
# BQUHAQEEbTBrMEQGCCsGAQUFBzAChjhodHRwOi8vY3J0LnNlY3RpZ28uY29tL1Nl
# Y3RpZ29QdWJsaWNDb2RlU2lnbmluZ0NBUjM2LmNydDAjBggrBgEFBQcwAYYXaHR0
# cDovL29jc3Auc2VjdGlnby5jb20wDQYJKoZIhvcNAQEMBQADggGBAENPYZO6JkhX
# uprRcjFErvAggFDfB4bJmvHwydUUq8EEdDkvVvS+SnqpaL+Nw5FY/X5GnIXfWKYv
# QJFY1o/bskqLBSH96jOk+wMWZ2LqfuyEuW4OZUvBtpho2E2QwcpCQQzG47c+qtEN
# C6lITctyoOUi5481cm9VXRL0E1g/MSDOqpYcd32oKt6rbqLQZD89HFgkNrfh3a4w
# q2O8ljai9gvQJnYV4588DGI4quzv81b6mGDx9ku9zHhtvI19C1L+oQddqFFUViSw
# UUiNrBO7aA5iFwr1vQPkiP40Zd6fSSQAjrRnUI/kbK9oD2l1i/Vi9hfQ8SLarLPh
# W0M0qaut175+RJKlwuusUZADtgYVWcrmMxy20RMCUZA2bnTWXjb4pVfHUyKPU7dp
# M+8gG/tUPBZegMWrzWqctSPQhdREpkLTMCm5E/o4ZUGNE0uo+twbGMGEyPPmjsFn
# IKLAqN2rHMI1Fz9pR+qMdixl+/mG/ElSJqGSDVArmZLn1IYhr4vQ8DCCBoIwggRq
# oAMCAQICEDbCsL18Gzrno7PdNsvJdWgwDQYJKoZIhvcNAQEMBQAwgYgxCzAJBgNV
# BAYTAlVTMRMwEQYDVQQIEwpOZXcgSmVyc2V5MRQwEgYDVQQHEwtKZXJzZXkgQ2l0
# eTEeMBwGA1UEChMVVGhlIFVTRVJUUlVTVCBOZXR3b3JrMS4wLAYDVQQDEyVVU0VS
# VHJ1c3QgUlNBIENlcnRpZmljYXRpb24gQXV0aG9yaXR5MB4XDTIxMDMyMjAwMDAw
# MFoXDTM4MDExODIzNTk1OVowVzELMAkGA1UEBhMCR0IxGDAWBgNVBAoTD1NlY3Rp
# Z28gTGltaXRlZDEuMCwGA1UEAxMlU2VjdGlnbyBQdWJsaWMgVGltZSBTdGFtcGlu
# ZyBSb290IFI0NjCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAIid2LlF
# Z50d3ei5JoGaVFTAfEkFm8xaFQ/ZlBBEtEFAgXcUmanU5HYsyAhTXiDQkiUvpVdY
# qZ1uYoZEMgtHES1l1Cc6HaqZzEbOOp6YiTx63ywTon434aXVydmhx7Dx4IBrAou7
# hNGsKioIBPy5GMN7KmgYmuu4f92sKKjbxqohUSfjk1mJlAjthgF7Hjx4vvyVDQGs
# d5KarLW5d73E3ThobSkob2SL48LpUR/O627pDchxll+bTSv1gASn/hp6IuHJorEu
# 6EopoB1CNFp/+HpTXeNARXUmdRMKbnXWflq+/g36NJXB35ZvxQw6zid61qmrlD/I
# bKJA6COw/8lFSPQwBP1ityZdwuCysCKZ9ZjczMqbUcLFyq6KdOpuzVDR3ZUwxDKL
# 1wCAxgL2Mpz7eZbrb/JWXiOcNzDpQsmwGQ6Stw8tTCqPumhLRPb7YkzM8/6NnWH3
# T9ClmcGSF22LEyJYNWCHrQqYubNeKolzqUbCqhSqmr/UdUeb49zYHr7ALL8bAJyP
# DmubNqMtuaobKASBqP84uhqcRY/pjnYd+V5/dcu9ieERjiRKKsxCG1t6tG9oj7li
# wPddXEcYGOUiWLm742st50jGwTzxbMpepmOP1mLnJskvZaN5e45NuzAHteORlsSu
# Dt5t4BBRCJL+5EZnnw0ezntk9R8QJyAkL6/bAgMBAAGjggEWMIIBEjAfBgNVHSME
# GDAWgBRTeb9aqitKz1SA4dibwJ3ysgNmyzAdBgNVHQ4EFgQU9ndq3T/9ARP/FqFs
# ggIv0Ao9FCUwDgYDVR0PAQH/BAQDAgGGMA8GA1UdEwEB/wQFMAMBAf8wEwYDVR0l
# BAwwCgYIKwYBBQUHAwgwEQYDVR0gBAowCDAGBgRVHSAAMFAGA1UdHwRJMEcwRaBD
# oEGGP2h0dHA6Ly9jcmwudXNlcnRydXN0LmNvbS9VU0VSVHJ1c3RSU0FDZXJ0aWZp
# Y2F0aW9uQXV0aG9yaXR5LmNybDA1BggrBgEFBQcBAQQpMCcwJQYIKwYBBQUHMAGG
# GWh0dHA6Ly9vY3NwLnVzZXJ0cnVzdC5jb20wDQYJKoZIhvcNAQEMBQADggIBAA6+
# ZUHtaES45aHF1BGH5Lc7JYzrftrIF5Ht2PFDxKKFOct/awAEWgHQMVHol9ZLSyd/
# pYMbaC0IZ+XBW9xhdkkmUV/KbUOiL7g98M/yzRyqUOZ1/IY7Ay0YbMniIibJrPcg
# Fp73WDnRDKtVutShPSZQZAdtFwXnuiWl8eFARK3PmLqEm9UsVX+55DbVIz33Mbhb
# a0HUTEYv3yJ1fwKGxPBsP/MgTECimh7eXomvMm0/GPxX2uhwCcs/YLxDnBdVVlxv
# DjHjO1cuwbOpkiJGHmLXXVNbsdXUC2xBrq9fLrfe8IBsA4hopwsCj8hTuwKXJlST
# rZcPRVSccP5i9U28gZ7OMzoJGlxZ5384OKm0r568Mo9TYrqzKeKZgFo0fj2/0iHb
# j55hc20jfxvK3mQi+H7xpbzxZOFGm/yVQkpo+ffv5gdhp+hv1GDsvJOtJinJmgGb
# BFZIThbqI+MHvAmMmkfb3fTxmSkop2mSJL1Y2x/955S29Gu0gSJIkc3z30vU/iXr
# MpWx2tS7UVfVP+5tKuzGtgkP7d/doqDrLF1u6Ci3TpjAZdeLLlRQZm867eVeXED5
# 8LXd1Dk6UvaAhvmWYXoiLz4JA5gPBcz7J311uahxCweNxE+xxxR3kT0WKzASo5G/
# PyDez6NHdIUKBeE3jDPs2ACc6CkJ1Sji4PKWVT0/MIIGpzCCBI+gAwIBAgIRAJCs
# CHIg/cWnxGtcxw33PQYwDQYJKoZIhvcNAQEMBQAwVzELMAkGA1UEBhMCR0IxGDAW
# BgNVBAoTD1NlY3RpZ28gTGltaXRlZDEuMCwGA1UEAxMlU2VjdGlnbyBQdWJsaWMg
# VGltZSBTdGFtcGluZyBSb290IFI0NjAeFw0yNjAzMjUwMDAwMDBaFw00MTAzMjQy
# MzU5NTlaMFUxCzAJBgNVBAYTAkdCMRgwFgYDVQQKEw9TZWN0aWdvIExpbWl0ZWQx
# LDAqBgNVBAMTI1NlY3RpZ28gUHVibGljIFRpbWUgU3RhbXBpbmcgQ0EgUjQxMIIC
# IjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAruRKogGtghxi+WYtW5oDzPDV
# F8GGSfgbUKh6bONxi0wvrI1S8qbAYfvLr/ky5ILVRg//70pgNKq8xC3/WEQodjEw
# AP2hmkGShoNAUQps4kd6Wwp74Fo7RlwQ1Mp949ytpWQDvCsYBbZccDmBAJC/ggqi
# uL/c805fGcMw6TzIgyBWuUx5PGp9YnheSNPXFzaz0MPtREdZYk4WhtM+hazqasMW
# Vpj0WUAcNhN9vO/FAdWy9Gafdb7lmYLDKTTYjwqAY9P9RfixPPjUaJH6mnBSNBdr
# X7a0Qdlux0ApS0fc48RW1m+W3tq3HiHzch1FHyhiLzCNjc6MUpcV5xalBvPOw/Ft
# Qo/AxaJOvPCSsVrx0f/WkMpEm3fvVbrY9+oo9rIKv9ducE6VGfwIAtKYedG0bO4B
# a1MmlxPcErDqjLwggvrBJu73fwXpkhtE0hzV0psgm2vhQs3pHll9N00SHBdy2qnd
# EcNuDh+46XouM2hoXCO533YQQOHPEUnMTWOo3hyxx5kjDE5PVqp+x+HS4VAT+WBM
# G4GzeLr9YvZbU5x5YvLdcR1dErV/QRYK55rp019fZFF2NR+TkSW0WcmQ3b5taGcr
# Xg49EpzKM6/mEpnSJXg1E13X6GO29rWs/LNvkGzsS8XGoRCGBls6ruofeebSsHAD
# R3GeIE5gIU927bjokLECAwEAAaOCAW4wggFqMB8GA1UdIwQYMBaAFPZ3at0//QET
# /xahbIICL9AKPRQlMB0GA1UdDgQWBBQ6dKUMZ8ZCUML9tfzHuyk0gvR6uTAOBgNV
# HQ8BAf8EBAMCAYYwEgYDVR0TAQH/BAgwBgEB/wIBADATBgNVHSUEDDAKBggrBgEF
# BQcDCDAjBgNVHSAEHDAaMAgGBmeBDAEEAjAOBgwrBgEEAbIxAQIBAwgwTAYDVR0f
# BEUwQzBBoD+gPYY7aHR0cDovL2NybC5zZWN0aWdvLmNvbS9TZWN0aWdvUHVibGlj
# VGltZVN0YW1waW5nUm9vdFI0Ni5jcmwwfAYIKwYBBQUHAQEEcDBuMEcGCCsGAQUF
# BzAChjtodHRwOi8vY3J0LnNlY3RpZ28uY29tL1NlY3RpZ29QdWJsaWNUaW1lU3Rh
# bXBpbmdSb290UjQ2LnA3YzAjBggrBgEFBQcwAYYXaHR0cDovL29jc3Auc2VjdGln
# by5jb20wDQYJKoZIhvcNAQEMBQADggIBADLeUkdm8Z4DZvjfKHOhqu+hsdXNt+X5
# F+48PB6PTAJCRgA3qxxO3YbAV7baps4K/+2WWoWUspBkT4T2NXK49NvJAfCsztHS
# gtqkAQMLX4KjCypJF/+m2Ktrk993g+gcgKdv1yg9C3JmYdJCnnL0ga+pZ/Wo1+rt
# XZ8dnwO8RCstTN6gYX0ElFi7Y7NpxbdBC1S6bc05V/SA9HC/ojj33W6GdwnpU/iV
# ylSkdkoHtHeGIhQLT2ZH0qPM9Wdce8v2fZsDCJQQJ8rll7OGLDbsXa2CLf0MRN9T
# wzifQ3rEuAXOx/TkzkZRFfwL34hf1XqSmaYq2tTMy2LgsPrqC2Z/6ZKb3fgrzU0v
# phB4wSTWulitY/KlxbvoyKvrBvUCCx4sgeqf8aR65CbvM5MN/d/lahfXipU2NlY0
# cXcnGS61XpmeGKd8It92/lufApZR9x6o5qMJWe0jq4JsfGMGDpIKx7FzkB8gaeju
# BUW/CJ9Phc40+xJRonvVewn4S9yJVRWeM47irGbR9YlN3xruM/yZzhk+rAm9AW06
# nv7ob6RQkAXR+cTxiAPy620FF41NrViYB4UyKpzfx7x8jh4ubTOMz954YIdqyeiq
# qtsbBwXjWLP0dfMUPA3iIPnPdBKGnodGJTdSlPAMmKJdyvTPqmOXs/LMnf+2Za0Z
# 6FXsIB9z9aXLMIIG4jCCBMqgAwIBAgIRAOdO8lWwUE/626bf9/yLoxUwDQYJKoZI
# hvcNAQEMBQAwVTELMAkGA1UEBhMCR0IxGDAWBgNVBAoTD1NlY3RpZ28gTGltaXRl
# ZDEsMCoGA1UEAxMjU2VjdGlnbyBQdWJsaWMgVGltZSBTdGFtcGluZyBDQSBSNDEw
# HhcNMjYwMzI1MDAwMDAwWhcNMzcwNjI0MjM1OTU5WjByMQswCQYDVQQGEwJHQjEX
# MBUGA1UECBMOR3JlYXRlciBMb25kb24xGDAWBgNVBAoTD1NlY3RpZ28gTGltaXRl
# ZDEwMC4GA1UEAxMnU2VjdGlnbyBQdWJsaWMgVGltZSBTdGFtcGluZyBTaWduZXIg
# UjM3MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAsv/DbUvcUNlFLQUR
# d9m4+1St5+JudFKo5P803Iks4mFeNB9SymodP6BJJWBuNhOFQj9w77AVAeg5qQpA
# 2dIwp2QTyBHr2h9eWSTkMBVj9mV6+WI5SaW+vDZW7PhJTbysd9v9WB3Xt6qlEi8m
# 47pcTy8+k/OfhziKiuzNQXqfC7KcoRD/6up8OZBsU0qxr7n5nh/iRfAp1QXFTBQO
# NBZSGIdHAyVRYYX033VoC8v71rizEKCpH97Pxbwcn9eq9K7W8h5v4npsMUoqCS/c
# 8mQwylDQGx15dHYV6NlcVFdjXD11l7qCrIy/unH5OlZtgx58QJRXRbGgQyBdSTpE
# pwuj3i5Qc52Z9m7hd7yCGCXKujf83hUQpOPx1w8+84EbEUTHVAfq4cpORaGWgY8N
# Jy6txmd3wpS1MeXrOaVAMczTgzAZ+yZBWIqdgQBgTxEeXldEToZOrRkxvn1IjIlf
# r4I4NWJz+Rb52FshLVnkA/wdoad789Eb7XZDNKd4oMmnc636TgauaaVZP2LLoU0J
# D/fYr53hwBn4uXu5ZsSfpnqAT60S7szJm/Na882xEoyRzLJ+UVbXOlHLO63DKkAt
# dz1CDuwWxgRE1drnwplepT06dz+1yTr5p1AkUz21bzE6cT/8/kjh4OPzggYYqrOB
# QPfuKEL5ZJPcN9jRgEpYvRlq5ucCAwEAAaOCAY4wggGKMB8GA1UdIwQYMBaAFDp0
# pQxnxkJQwv21/Me7KTSC9Hq5MB0GA1UdDgQWBBRhEOl6Eq9RxIXU8s+kdA9QzSCv
# +DAOBgNVHQ8BAf8EBAMCBsAwDAYDVR0TAQH/BAIwADAWBgNVHSUBAf8EDDAKBggr
# BgEFBQcDCDBKBgNVHSAEQzBBMAgGBmeBDAEEAjA1BgwrBgEEAbIxAQIBAwgwJTAj
# BggrBgEFBQcCARYXaHR0cHM6Ly9zZWN0aWdvLmNvbS9DUFMwSgYDVR0fBEMwQTA/
# oD2gO4Y5aHR0cDovL2NybC5zZWN0aWdvLmNvbS9TZWN0aWdvUHVibGljVGltZVN0
# YW1waW5nQ0FSNDEuY3JsMHoGCCsGAQUFBwEBBG4wbDBFBggrBgEFBQcwAoY5aHR0
# cDovL2NydC5zZWN0aWdvLmNvbS9TZWN0aWdvUHVibGljVGltZVN0YW1waW5nQ0FS
# NDEuY3J0MCMGCCsGAQUFBzABhhdodHRwOi8vb2NzcC5zZWN0aWdvLmNvbTANBgkq
# hkiG9w0BAQwFAAOCAgEAA+o9jdGszfoZepOmygef1OlbkjrPd2QW9z3M8vVbQSCr
# uPeO2eRsC9GhZ4CMZfhkrixayYD67gQkbyiRCbJu5L/i0NQjlQhBvbWfiEba+KHF
# KGud5YHRWhDZUtDeMIJGZG0BD7/sftZUo2Ifk+CXi/ZlM50+xK3OkqeXVi5GubDD
# /5txmYuqCT3T3LAilmoB+5th9sQxiMhyQuT3R/aYb4vypoZJLYklUzTalXleW1nV
# 9s4UROlE389CHDKAi/fepRSMnV8TghODDQxwzNGrOJZ04k/yhzHHDupfHPU51FYJ
# qXIvWq9SAAWdlNV1JGIxhkp/TAtxBwz/Vd/VbgVb2d9/wRFfxFkka39O0+4xaZSl
# /oEK/1DqjxjJRO2Se9lGlJDScu21Zd23Cys3aYyB8y5H/+DFWtVe8PMKgr+VuIDp
# 0Rk5bneVDAEW0TPAT8Ufwl2F6DJiDg/KZk5NmsYES+CxvF7bnISEnQh0ZrWnAJix
# quV0mElUx01wA5TuPIgyodxzNq/fC0hen9LBtdnfFfSZ+wt8A1Injsbio+DHVq1v
# oYiVNpBfO7+nh9NB4AhRXNldPgr3zgjJ+47s0uNYy2iDXAZSlkP3ym/7gy31jlu9
# 89SNpRWO14/LUNV2LSuXkRI1iLTPI6ZdXG0DnPPG7UftF0tk5m6BP9eNfr2tj1sx
# ggZBMIIGPQIBATBoMFQxCzAJBgNVBAYTAkdCMRgwFgYDVQQKEw9TZWN0aWdvIExp
# bWl0ZWQxKzApBgNVBAMTIlNlY3RpZ28gUHVibGljIENvZGUgU2lnbmluZyBDQSBS
# MzYCEBVU792hXgxFEa5eaR5wqcQwDQYJYIZIAWUDBAIBBQCggYQwGAYKKwYBBAGC
# NwIBDDEKMAigAoAAoQKAADAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgor
# BgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQgOVAfKWrj
# EPCnCjBT6ilYbPsfenZeZnELmMl0N0McPO8wDQYJKoZIhvcNAQEBBQAEggIARxWP
# Wa1iAeIIutcJ42oVfd19Xf6yHAEnDRCujqpktO9VlStpVsg6zQNt1EoKyvz2hj+7
# HOfoCbwpqjVJSIEhSV3FCFZLFbRAtpzSMZa/Siv+k+eRXpLUJR7n6lDltrwXCuU3
# 0Ns8Mjgf350TD9Ahv5VkO2LvXl8O1PCi2SW/wR0xUc2t7CtV1aGLvPPYqUDnft2F
# CPFaWcLOrL+zbInzYi/bYftZYn3V8h5v3kNc5s/fVSXtjSrT/MNEGtbhNZsUWwfw
# VZo5KPeHyGZomyEXPojF7ZrNJiQRByP55DMdvQwZ9Rp/tuPOboOgTXMvFKIAHmua
# py5xyVYof5V2JhHXL9DwiIVYAAGh1gAJo8s9HC7RIIZChvlVNagdAIyKj/1Bmi7A
# DTTWEmQ/K8rQp82NWGbBlJeJnnvGFVi0bJxYRJboxu4S81wDihWQXaJEaSYizunz
# H/AH4/97jjqhtM9TJNLl8z+18D55tr5PI37+ZBWPwetu9RUhNUFFVse36fAeRCkc
# gbDsWtJgZHyG5T7oKW+MfUWdik7GncQrM2jh4zFqfVbQT4HS7oDPVXiTZkG3+aNi
# c58oZiudtvBb7MZlqqcNI5zJUZ1lk9/ONixReOg5QsGmVD8EPilJee6tN1h9WdR4
# 33RvHUw/qQuUQGz1y9veMLaH25t6FHeqG26CtI6hggMjMIIDHwYJKoZIhvcNAQkG
# MYIDEDCCAwwCAQEwajBVMQswCQYDVQQGEwJHQjEYMBYGA1UEChMPU2VjdGlnbyBM
# aW1pdGVkMSwwKgYDVQQDEyNTZWN0aWdvIFB1YmxpYyBUaW1lIFN0YW1waW5nIENB
# IFI0MQIRAOdO8lWwUE/626bf9/yLoxUwDQYJYIZIAWUDBAICBQCgeTAYBgkqhkiG
# 9w0BCQMxCwYJKoZIhvcNAQcBMBwGCSqGSIb3DQEJBTEPFw0yNjA3MTAxNjI1NDZa
# MD8GCSqGSIb3DQEJBDEyBDAI6ylCBmqKXXaBoYDElM9N6V70OODUOJBS1BnTurgv
# 3eiZYNSbM3x3MRGByIwVzTAwDQYJKoZIhvcNAQEBBQAEggIAJzM0sxBtYy51casy
# rf3G3Ra/ytX7E2hUgjYNM9vGLBdFrz991qB9f/42PeMiVBhu1FtgmIV9Cep0O+yY
# 9qLRfjaT9MVhdzBGqDbwSjzkK6SgHOkfu6Z4Py8M80G/OdUnIoocwAwFuBj7dWKC
# xMKsgiW6ZhWCajMCLMC0OxIBOtgC8NurhNXxt4j0qPtkIbtbkXe/9DLM1NZKDip5
# b2Ql9og2k93J5QGNIxBV+Zw2g7gK4skgIC+4DXkEkzztA6QGd0+U9yy+wbwGBvQ2
# xerx3oKU+g8Q+goObCz0P54hN8i3gdaAXjzM2pbORginvFzikq6Dc40IsbTERORu
# VaqV8V73BnvQbXrxfUk3Aec+XzDV7W9/xYn4mc/1IehxpE0yKbVKBNIC2FmApcnu
# c53U3QpLQ44CMxKQw2yURmi9tt0C4JYLgB/CJ64306pfRW9GEJ5ltl0TKtNeHuJA
# eK2pBGhRinVVhSAArGQCryhXr7wG+5eIdVXbubemDjLzr0w4/qLN4i7z1s4pDDZo
# ltSv29x0Cn4vlwAiVJ6CJZFhHC4AjsN3VBuKjClGqNggmUc9MBtKp81JDdA/7rtC
# FwRQocfwJkAejHUVvzl/FMKHf3SypflSD1YXsaH+d8MDqB86Kpc58+h4NFJgp54S
# 5MkJO2R7S78Yhk+UNd5/DlchC7s=
# SIG # End signature block
