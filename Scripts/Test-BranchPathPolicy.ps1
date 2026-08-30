<#
.SYNOPSIS
    Validates branch/path separation for repository changes.
.DESCRIPTION
    Blocks workflow and editor configuration changes on normal code branches, except for
    the repository cSpell configuration, and blocks source and tests/src changes on
    workflow/infrastructure branches.

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
Set-StrictMode -Version 3
$ErrorActionPreference = 'Stop'

$script:SuccessExitCode = 0
$script:PolicyViolationExitCode = 1

Set-Variable -Name NormalCodeBranchBlockedPath -Option Constant -Value @(
    'Scripts'
)

Set-Variable -Name NormalCodeBranchAllowedPath -Option Constant -Value @(
    '.vscode/cspell.json'
)

Set-Variable -Name WorkflowInfrastructureBranchBlockedPath -Option Constant -Value @(
    'src'
    'tests/src'
)

Set-Variable -Name PublishBranchBlockedPath -Option Constant -Value @(
    'Scripts'
)

# Bare AI-tool prefixes block ALL paths — forces rename to -code/ or -infra/ before merge
Set-Variable -Name AIRootBranchBlockedPath -Option Constant -Value @(
    'src'
    'tests/src'
    'Scripts'
)

$approvedBranchPrefixes = @(
    [pscustomobject]@{
        BranchPrefix = 'feature/'
        BlockedPath = $NormalCodeBranchBlockedPath
        AllowedPath = $NormalCodeBranchAllowedPath
        BranchType = 'normal code branch'
    },
    [pscustomobject]@{
        BranchPrefix = 'bugfix/'
        BlockedPath = $NormalCodeBranchBlockedPath
        AllowedPath = $NormalCodeBranchAllowedPath
        BranchType = 'normal code branch'
    },
    [pscustomobject]@{
        BranchPrefix = 'hotfix/'
        BlockedPath = $NormalCodeBranchBlockedPath
        AllowedPath = $NormalCodeBranchAllowedPath
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
        AllowedPath = $NormalCodeBranchAllowedPath
        BranchType = 'normal code branch'
    },
    [pscustomobject]@{
        BranchPrefix = 'breaking/'
        BlockedPath = $NormalCodeBranchBlockedPath
        AllowedPath = $NormalCodeBranchAllowedPath
        BranchType = 'normal code branch'
    },
    [pscustomobject]@{
        BranchPrefix = 'docs/'
        BlockedPath = $NormalCodeBranchBlockedPath
        AllowedPath = $NormalCodeBranchAllowedPath
        BranchType = 'normal code branch'
    },
    [pscustomobject]@{
        BranchPrefix = 'chore/'
        BlockedPath = $NormalCodeBranchBlockedPath
        AllowedPath = $NormalCodeBranchAllowedPath
        BranchType = 'normal code branch'
    },
    [pscustomobject]@{
        BranchPrefix = 'codex-code/'
        BlockedPath = $NormalCodeBranchBlockedPath
        AllowedPath = $NormalCodeBranchAllowedPath
        BranchType = 'normal code branch'
    },
    [pscustomobject]@{
        BranchPrefix = 'copilot-code/'
        BlockedPath = $NormalCodeBranchBlockedPath
        AllowedPath = $NormalCodeBranchAllowedPath
        BranchType = 'normal code branch'
    },
    [pscustomobject]@{
        BranchPrefix = 'kiro-code/'
        BlockedPath = $NormalCodeBranchBlockedPath
        AllowedPath = $NormalCodeBranchAllowedPath
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
        BranchPrefix = 'codex/'
        BlockedPath = $AIRootBranchBlockedPath
        BranchType = 'AI root branch (rename to -code/ or -infra/ before merge)'
    },
    [pscustomobject]@{
        BranchPrefix = 'copilot/'
        BlockedPath = $AIRootBranchBlockedPath
        BranchType = 'AI root branch (rename to -code/ or -infra/ before merge)'
    },
    [pscustomobject]@{
        BranchPrefix = 'kiro/'
        BlockedPath = $AIRootBranchBlockedPath
        BranchType = 'AI root branch (rename to -code/ or -infra/ before merge)'
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
    Write-Error -ErrorAction Continue @"
Branch path policy failed.

Branch '$BranchName' has unrecognized prefix '$branchPrefix/'.
Allowed branch prefixes are: $approvedPrefixText.

All changes are blocked until the branch is renamed to an approved prefix.
"@
    exit $script:PolicyViolationExitCode
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

function Test-ExactPath {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$ExactPath
    )

    $normalizedPath = $Path -replace '\\', '/'

    foreach ($item in $ExactPath) {
        $normalizedExactPath = $item -replace '\\', '/'
        if ($normalizedPath -eq $normalizedExactPath) {
            return $true
        }
    }

    return $false
}

$blockedPrefixes = $matchingBranchPolicy.BlockedPath
$allowedPaths = @(
    if ($matchingBranchPolicy.PSObject.Properties.Name -contains 'AllowedPath') {
        $matchingBranchPolicy.AllowedPath | Where-Object { $_ }
    }
)
$branchType = $matchingBranchPolicy.BranchType

$blockedPaths = @(
    foreach ($path in $ChangedPath) {
        $isAllowedPath = $allowedPaths.Count -gt 0 -and
            (Test-ExactPath -Path $path -ExactPath $allowedPaths)

        if (
            (Test-PathPrefix -Path $path -Prefix $blockedPrefixes) -and
            -not $isAllowedPath
        ) {
            $path
        }
    }
)

if ($blockedPaths.Count -gt 0) {
    $blockedPrefixText = ($blockedPrefixes | ForEach-Object { "$($_.TrimEnd('/'))/" }) -join ', '
    Write-Error -ErrorAction Continue @"
Branch path policy failed.

Branch '$BranchName' is treated as a $branchType.
Do not include changes under $blockedPrefixText on this branch type.

Blocked changed paths:
$($blockedPaths -join [Environment]::NewLine)

Split this work into a branch whose name matches the kind of change being made.
"@
    exit $script:PolicyViolationExitCode
}

Write-Output "Branch path policy passed for '$BranchName'."
exit $script:SuccessExitCode

#
# SIG # Begin signature block
# MIIgygYJKoZIhvcNAQcCoIIguzCCILcCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCD/YLxMGhRbE+02
# I3pSqnptIMfD/D4Kv5r/x9fpEiv1n6CCG1gwggN5MIIC/qADAgECAhAcz51nzeIZ
# /xLZmv82guWnMAoGCCqGSM49BAMDMHwxCzAJBgNVBAYTAlVTMQ4wDAYDVQQIDAVU
# ZXhhczEQMA4GA1UEBwwHSG91c3RvbjEYMBYGA1UECgwPU1NMIENvcnBvcmF0aW9u
# MTEwLwYDVQQDDChTU0wuY29tIFJvb3QgQ2VydGlmaWNhdGlvbiBBdXRob3JpdHkg
# RUNDMB4XDTE5MDMwNzE5MzU0N1oXDTM0MDMwMzE5MzU0N1oweDELMAkGA1UEBhMC
# VVMxDjAMBgNVBAgMBVRleGFzMRAwDgYDVQQHDAdIb3VzdG9uMREwDwYDVQQKDAhT
# U0wgQ29ycDE0MDIGA1UEAwwrU1NMLmNvbSBDb2RlIFNpZ25pbmcgSW50ZXJtZWRp
# YXRlIENBIEVDQyBSMjB2MBAGByqGSM49AgEGBSuBBAAiA2IABOpt7gyJbfdl1TyX
# rJy6JZGueJwq39d2z/FOJTbnNRuYrlS823MWKvLp+ziKPRCumlXWYiCS5X0xZxWv
# 2FIxsD9Tf7tCm8JcqSsa6W8uRyjXT+yEBglVRcOJGZiIjeFxJKOCAUcwggFDMBIG
# A1UdEwEB/wQIMAYBAf8CAQAwHwYDVR0jBBgwFoAUgtGFczDnNQTTjgKS++Wk0cQh
# 6M0weAYIKwYBBQUHAQEEbDBqMEYGCCsGAQUFBzAChjpodHRwOi8vd3d3LnNzbC5j
# b20vcmVwb3NpdG9yeS9TU0xjb20tUm9vdENBLUVDQy0zODQtUjEuY3J0MCAGCCsG
# AQUFBzABhhRodHRwOi8vb2NzcHMuc3NsLmNvbTARBgNVHSAECjAIMAYGBFUdIAAw
# EwYDVR0lBAwwCgYIKwYBBQUHAwMwOwYDVR0fBDQwMjAwoC6gLIYqaHR0cDovL2Ny
# bHMuc3NsLmNvbS9zc2wuY29tLWVjYy1Sb290Q0EuY3JsMB0GA1UdDgQWBBQyeLEO
# kNtGzxrPtmMRbf4w52dUMDAOBgNVHQ8BAf8EBAMCAYYwCgYIKoZIzj0EAwMDaQAw
# ZgIxAIZwNaUUH2Oi1OfK9PES0J4Ay3EIm1mAOjpxEHItL3pSmV+5tJ/iQQqK2Dwg
# evkxFQIxAIHLuf6CWo8Wvxn2XZR/+3do0Q/XjqQSbfhJlqwRUVPlxUz5aK1vpJwv
# LRHaPzhzXTCCA8AwggNHoAMCAQICEFEd7vPtDKtYV7OYcsTNL88wCgYIKoZIzj0E
# AwMweDELMAkGA1UEBhMCVVMxDjAMBgNVBAgMBVRleGFzMRAwDgYDVQQHDAdIb3Vz
# dG9uMREwDwYDVQQKDAhTU0wgQ29ycDE0MDIGA1UEAwwrU1NMLmNvbSBDb2RlIFNp
# Z25pbmcgSW50ZXJtZWRpYXRlIENBIEVDQyBSMjAeFw0yNjA4MDcxOTA3NTdaFw0y
# NzExMDgxOTA3NTdaMHkxCzAJBgNVBAYTAlVTMRYwFAYDVQQIDA1OZXcgSGFtcHNo
# aXJlMRQwEgYDVQQHDAtOZXcgSXBzd2ljaDEdMBsGA1UECgwUQ2hyaXN0b3BoZXIg
# Q2hhcmxhbmQxHTAbBgNVBAMMFENocmlzdG9waGVyIENoYXJsYW5kMHYwEAYHKoZI
# zj0CAQYFK4EEACIDYgAEnBTifag8qbU07/B2aFtw7h3deXWsME/+F18vvlqQOnQg
# 5YNQyYRisw1XkwtXq2m1AMiqAddMEVOkmxIi71eYqVi87p/RQct3k/HuXi/clk4C
# YqaYFCEpq7tFMUDd8cUCo4IBkzCCAY8wDAYDVR0TAQH/BAIwADAfBgNVHSMEGDAW
# gBQyeLEOkNtGzxrPtmMRbf4w52dUMDB5BggrBgEFBQcBAQRtMGswRwYIKwYBBQUH
# MAKGO2h0dHA6Ly9jZXJ0LnNzbC5jb20vU1NMY29tLVN1YkNBLWNvZGVTaWduaW5n
# LUVDQy0zODQtUjIuY2VyMCAGCCsGAQUFBzABhhRodHRwOi8vb2NzcHMuc3NsLmNv
# bTBRBgNVHSAESjBIMAgGBmeBDAEEATA8BgwrBgEEAYKpMAEDAwEwLDAqBggrBgEF
# BQcCARYeaHR0cHM6Ly93d3cuc3NsLmNvbS9yZXBvc2l0b3J5MBMGA1UdJQQMMAoG
# CCsGAQUFBwMDMEwGA1UdHwRFMEMwQaA/oD2GO2h0dHA6Ly9jcmxzLnNzbC5jb20v
# U1NMY29tLVN1YkNBLWNvZGVTaWduaW5nLUVDQy0zODQtUjIuY3JsMB0GA1UdDgQW
# BBRaKfdK1zqVgfdqPHp69Ump7V7QDjAOBgNVHQ8BAf8EBAMCB4AwCgYIKoZIzj0E
# AwMDZwAwZAIwfyXRtBRHbkmoEP6vHjnUe6Xb6WUcfzZ+r2mFqz3pxpokqXkdYfbn
# ySinlBy2oScEAjAmFdwaA7/yG/M+bPD8UviQ9p13KC3R2X1eXbRlCoRwLwdKSF89
# FQPG4jtmL9FPIawwggaCMIIEaqADAgECAhA2wrC9fBs656Oz3TbLyXVoMA0GCSqG
# SIb3DQEBDAUAMIGIMQswCQYDVQQGEwJVUzETMBEGA1UECBMKTmV3IEplcnNleTEU
# MBIGA1UEBxMLSmVyc2V5IENpdHkxHjAcBgNVBAoTFVRoZSBVU0VSVFJVU1QgTmV0
# d29yazEuMCwGA1UEAxMlVVNFUlRydXN0IFJTQSBDZXJ0aWZpY2F0aW9uIEF1dGhv
# cml0eTAeFw0yMTAzMjIwMDAwMDBaFw0zODAxMTgyMzU5NTlaMFcxCzAJBgNVBAYT
# AkdCMRgwFgYDVQQKEw9TZWN0aWdvIExpbWl0ZWQxLjAsBgNVBAMTJVNlY3RpZ28g
# UHVibGljIFRpbWUgU3RhbXBpbmcgUm9vdCBSNDYwggIiMA0GCSqGSIb3DQEBAQUA
# A4ICDwAwggIKAoICAQCIndi5RWedHd3ouSaBmlRUwHxJBZvMWhUP2ZQQRLRBQIF3
# FJmp1OR2LMgIU14g0JIlL6VXWKmdbmKGRDILRxEtZdQnOh2qmcxGzjqemIk8et8s
# E6J+N+Gl1cnZocew8eCAawKLu4TRrCoqCAT8uRjDeypoGJrruH/drCio28aqIVEn
# 45NZiZQI7YYBex48eL78lQ0BrHeSmqy1uXe9xN04aG0pKG9ki+PC6VEfzutu6Q3I
# cZZfm00r9YAEp/4aeiLhyaKxLuhKKaAdQjRaf/h6U13jQEV1JnUTCm511n5avv4N
# +jSVwd+Wb8UMOs4netapq5Q/yGyiQOgjsP/JRUj0MAT9YrcmXcLgsrAimfWY3MzK
# m1HCxcquinTqbs1Q0d2VMMQyi9cAgMYC9jKc+3mW62/yVl4jnDcw6ULJsBkOkrcP
# LUwqj7poS0T2+2JMzPP+jZ1h90/QpZnBkhdtixMiWDVgh60KmLmzXiqJc6lGwqoU
# qpq/1HVHm+Pc2B6+wCy/GwCcjw5rmzajLbmqGygEgaj/OLoanEWP6Y52Hflef3XL
# vYnhEY4kSirMQhtberRvaI+5YsD3XVxHGBjlIli5u+NrLedIxsE88WzKXqZjj9Zi
# 5ybJL2WjeXuOTbswB7XjkZbErg7ebeAQUQiS/uRGZ58NHs57ZPUfECcgJC+v2wID
# AQABo4IBFjCCARIwHwYDVR0jBBgwFoAUU3m/WqorSs9UgOHYm8Cd8rIDZsswHQYD
# VR0OBBYEFPZ3at0//QET/xahbIICL9AKPRQlMA4GA1UdDwEB/wQEAwIBhjAPBgNV
# HRMBAf8EBTADAQH/MBMGA1UdJQQMMAoGCCsGAQUFBwMIMBEGA1UdIAQKMAgwBgYE
# VR0gADBQBgNVHR8ESTBHMEWgQ6BBhj9odHRwOi8vY3JsLnVzZXJ0cnVzdC5jb20v
# VVNFUlRydXN0UlNBQ2VydGlmaWNhdGlvbkF1dGhvcml0eS5jcmwwNQYIKwYBBQUH
# AQEEKTAnMCUGCCsGAQUFBzABhhlodHRwOi8vb2NzcC51c2VydHJ1c3QuY29tMA0G
# CSqGSIb3DQEBDAUAA4ICAQAOvmVB7WhEuOWhxdQRh+S3OyWM637ayBeR7djxQ8Si
# hTnLf2sABFoB0DFR6JfWS0snf6WDG2gtCGflwVvcYXZJJlFfym1Doi+4PfDP8s0c
# qlDmdfyGOwMtGGzJ4iImyaz3IBae91g50QyrVbrUoT0mUGQHbRcF57olpfHhQESt
# z5i6hJvVLFV/ueQ21SM99zG4W2tB1ExGL98idX8ChsTwbD/zIExAopoe3l6JrzJt
# Pxj8V9rocAnLP2C8Q5wXVVZcbw4x4ztXLsGzqZIiRh5i111TW7HV1AtsQa6vXy63
# 3vCAbAOIaKcLAo/IU7sClyZUk62XD0VUnHD+YvVNvIGezjM6CRpcWed/ODiptK+e
# vDKPU2K6synimYBaNH49v9Ih24+eYXNtI38byt5kIvh+8aW88WThRpv8lUJKaPn3
# 7+YHYafob9Rg7LyTrSYpyZoBmwRWSE4W6iPjB7wJjJpH29308ZkpKKdpkiS9WNsf
# /eeUtvRrtIEiSJHN899L1P4l6zKVsdrUu1FX1T/ubSrsxrYJD+3f3aKg6yxdbugo
# t06YwGXXiy5UUGZvOu3lXlxA+fC13dQ5OlL2gIb5lmF6Ii8+CQOYDwXM+yd9dbmo
# cQsHjcRPsccUd5E9FiswEqORvz8g3s+jR3SFCgXhN4wz7NgAnOgpCdUo4uDyllU9
# PzCCBqcwggSPoAMCAQICEQCQrAhyIP3Fp8RrXMcN9z0GMA0GCSqGSIb3DQEBDAUA
# MFcxCzAJBgNVBAYTAkdCMRgwFgYDVQQKEw9TZWN0aWdvIExpbWl0ZWQxLjAsBgNV
# BAMTJVNlY3RpZ28gUHVibGljIFRpbWUgU3RhbXBpbmcgUm9vdCBSNDYwHhcNMjYw
# MzI1MDAwMDAwWhcNNDEwMzI0MjM1OTU5WjBVMQswCQYDVQQGEwJHQjEYMBYGA1UE
# ChMPU2VjdGlnbyBMaW1pdGVkMSwwKgYDVQQDEyNTZWN0aWdvIFB1YmxpYyBUaW1l
# IFN0YW1waW5nIENBIFI0MTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIB
# AK7kSqIBrYIcYvlmLVuaA8zw1RfBhkn4G1CoemzjcYtML6yNUvKmwGH7y6/5MuSC
# 1UYP/+9KYDSqvMQt/1hEKHYxMAD9oZpBkoaDQFEKbOJHelsKe+BaO0ZcENTKfePc
# raVkA7wrGAW2XHA5gQCQv4IKori/3PNOXxnDMOk8yIMgVrlMeTxqfWJ4XkjT1xc2
# s9DD7URHWWJOFobTPoWs6mrDFlaY9FlAHDYTfbzvxQHVsvRmn3W+5ZmCwyk02I8K
# gGPT/UX4sTz41GiR+ppwUjQXa1+2tEHZbsdAKUtH3OPEVtZvlt7atx4h83IdRR8o
# Yi8wjY3OjFKXFecWpQbzzsPxbUKPwMWiTrzwkrFa8dH/1pDKRJt371W62PfqKPay
# Cr/XbnBOlRn8CALSmHnRtGzuAWtTJpcT3BKw6oy8IIL6wSbu938F6ZIbRNIc1dKb
# IJtr4ULN6R5ZfTdNEhwXctqp3RHDbg4fuOl6LjNoaFwjud92EEDhzxFJzE1jqN4c
# sceZIwxOT1aqfsfh0uFQE/lgTBuBs3i6/WL2W1OceWLy3XEdXRK1f0EWCuea6dNf
# X2RRdjUfk5EltFnJkN2+bWhnK14OPRKcyjOv5hKZ0iV4NRNd1+hjtva1rPyzb5Bs
# 7EvFxqEQhgZbOq7qH3nm0rBwA0dxniBOYCFPdu246JCxAgMBAAGjggFuMIIBajAf
# BgNVHSMEGDAWgBT2d2rdP/0BE/8WoWyCAi/QCj0UJTAdBgNVHQ4EFgQUOnSlDGfG
# QlDC/bX8x7spNIL0erkwDgYDVR0PAQH/BAQDAgGGMBIGA1UdEwEB/wQIMAYBAf8C
# AQAwEwYDVR0lBAwwCgYIKwYBBQUHAwgwIwYDVR0gBBwwGjAIBgZngQwBBAIwDgYM
# KwYBBAGyMQECAQMIMEwGA1UdHwRFMEMwQaA/oD2GO2h0dHA6Ly9jcmwuc2VjdGln
# by5jb20vU2VjdGlnb1B1YmxpY1RpbWVTdGFtcGluZ1Jvb3RSNDYuY3JsMHwGCCsG
# AQUFBwEBBHAwbjBHBggrBgEFBQcwAoY7aHR0cDovL2NydC5zZWN0aWdvLmNvbS9T
# ZWN0aWdvUHVibGljVGltZVN0YW1waW5nUm9vdFI0Ni5wN2MwIwYIKwYBBQUHMAGG
# F2h0dHA6Ly9vY3NwLnNlY3RpZ28uY29tMA0GCSqGSIb3DQEBDAUAA4ICAQAy3lJH
# ZvGeA2b43yhzoarvobHVzbfl+RfuPDwej0wCQkYAN6scTt2GwFe22qbOCv/tllqF
# lLKQZE+E9jVyuPTbyQHwrM7R0oLapAEDC1+CowsqSRf/ptira5Pfd4PoHICnb9co
# PQtyZmHSQp5y9IGvqWf1qNfq7V2fHZ8DvEQrLUzeoGF9BJRYu2OzacW3QQtUum3N
# OVf0gPRwv6I4991uhncJ6VP4lcpUpHZKB7R3hiIUC09mR9KjzPVnXHvL9n2bAwiU
# ECfK5Zezhiw27F2tgi39DETfU8M4n0N6xLgFzsf05M5GURX8C9+IX9V6kpmmKtrU
# zMti4LD66gtmf+mSm934K81NL6YQeMEk1rpYrWPypcW76Mir6wb1AgseLIHqn/Gk
# euQm7zOTDf3f5WoX14qVNjZWNHF3JxkutV6ZnhinfCLfdv5bnwKWUfceqOajCVnt
# I6uCbHxjBg6SCsexc5AfIGno7gVFvwifT4XONPsSUaJ71XsJ+EvciVUVnjOO4qxm
# 0fWJTd8a7jP8mc4ZPqwJvQFtOp7+6G+kUJAF0fnE8YgD8uttBReNTa1YmAeFMiqc
# 38e8fI4eLm0zjM/eeGCHasnoqqrbGwcF41iz9HXzFDwN4iD5z3QShp6HRiU3UpTw
# DJiiXcr0z6pjl7PyzJ3/tmWtGehV7CAfc/WlyzCCBuIwggTKoAMCAQICEQDnTvJV
# sFBP+tum3/f8i6MVMA0GCSqGSIb3DQEBDAUAMFUxCzAJBgNVBAYTAkdCMRgwFgYD
# VQQKEw9TZWN0aWdvIExpbWl0ZWQxLDAqBgNVBAMTI1NlY3RpZ28gUHVibGljIFRp
# bWUgU3RhbXBpbmcgQ0EgUjQxMB4XDTI2MDMyNTAwMDAwMFoXDTM3MDYyNDIzNTk1
# OVowcjELMAkGA1UEBhMCR0IxFzAVBgNVBAgTDkdyZWF0ZXIgTG9uZG9uMRgwFgYD
# VQQKEw9TZWN0aWdvIExpbWl0ZWQxMDAuBgNVBAMTJ1NlY3RpZ28gUHVibGljIFRp
# bWUgU3RhbXBpbmcgU2lnbmVyIFIzNzCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCC
# AgoCggIBALL/w21L3FDZRS0FEXfZuPtUrefibnRSqOT/NNyJLOJhXjQfUspqHT+g
# SSVgbjYThUI/cO+wFQHoOakKQNnSMKdkE8gR69ofXlkk5DAVY/ZlevliOUmlvrw2
# Vuz4SU28rHfb/Vgd17eqpRIvJuO6XE8vPpPzn4c4iorszUF6nwuynKEQ/+rqfDmQ
# bFNKsa+5+Z4f4kXwKdUFxUwUDjQWUhiHRwMlUWGF9N91aAvL+9a4sxCgqR/ez8W8
# HJ/XqvSu1vIeb+J6bDFKKgkv3PJkMMpQ0BsdeXR2FejZXFRXY1w9dZe6gqyMv7px
# +TpWbYMefECUV0WxoEMgXUk6RKcLo94uUHOdmfZu4Xe8ghglyro3/N4VEKTj8dcP
# PvOBGxFEx1QH6uHKTkWhloGPDScurcZnd8KUtTHl6zmlQDHM04MwGfsmQViKnYEA
# YE8RHl5XRE6GTq0ZMb59SIyJX6+CODVic/kW+dhbIS1Z5AP8HaGne/PRG+12QzSn
# eKDJp3Ot+k4GrmmlWT9iy6FNCQ/32K+d4cAZ+Ll7uWbEn6Z6gE+tEu7MyZvzWvPN
# sRKMkcyyflFW1zpRyzutwypALXc9Qg7sFsYERNXa58KZXqU9Onc/tck6+adQJFM9
# tW8xOnE//P5I4eDj84IGGKqzgUD37ihC+WST3DfY0YBKWL0ZaubnAgMBAAGjggGO
# MIIBijAfBgNVHSMEGDAWgBQ6dKUMZ8ZCUML9tfzHuyk0gvR6uTAdBgNVHQ4EFgQU
# YRDpehKvUcSF1PLPpHQPUM0gr/gwDgYDVR0PAQH/BAQDAgbAMAwGA1UdEwEB/wQC
# MAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgwSgYDVR0gBEMwQTAIBgZngQwBBAIw
# NQYMKwYBBAGyMQECAQMIMCUwIwYIKwYBBQUHAgEWF2h0dHBzOi8vc2VjdGlnby5j
# b20vQ1BTMEoGA1UdHwRDMEEwP6A9oDuGOWh0dHA6Ly9jcmwuc2VjdGlnby5jb20v
# U2VjdGlnb1B1YmxpY1RpbWVTdGFtcGluZ0NBUjQxLmNybDB6BggrBgEFBQcBAQRu
# MGwwRQYIKwYBBQUHMAKGOWh0dHA6Ly9jcnQuc2VjdGlnby5jb20vU2VjdGlnb1B1
# YmxpY1RpbWVTdGFtcGluZ0NBUjQxLmNydDAjBggrBgEFBQcwAYYXaHR0cDovL29j
# c3Auc2VjdGlnby5jb20wDQYJKoZIhvcNAQEMBQADggIBAAPqPY3RrM36GXqTpsoH
# n9TpW5I6z3dkFvc9zPL1W0Egq7j3jtnkbAvRoWeAjGX4ZK4sWsmA+u4EJG8okQmy
# buS/4tDUI5UIQb21n4hG2vihxShrneWB0VoQ2VLQ3jCCRmRtAQ+/7H7WVKNiH5Pg
# l4v2ZTOdPsStzpKnl1YuRrmww/+bcZmLqgk909ywIpZqAfubYfbEMYjIckLk90f2
# mG+L8qaGSS2JJVM02pV5XltZ1fbOFETpRN/PQhwygIv33qUUjJ1fE4ITgw0McMzR
# qziWdOJP8ocxxw7qXxz1OdRWCalyL1qvUgAFnZTVdSRiMYZKf0wLcQcM/1Xf1W4F
# W9nff8ERX8RZJGt/TtPuMWmUpf6BCv9Q6o8YyUTtknvZRpSQ0nLttWXdtwsrN2mM
# gfMuR//gxVrVXvDzCoK/lbiA6dEZOW53lQwBFtEzwE/FH8JdhegyYg4PymZOTZrG
# BEvgsbxe25yEhJ0IdGa1pwCYsarldJhJVMdNcAOU7jyIMqHcczav3wtIXp/SwbXZ
# 3xX0mfsLfANSJ47G4qPgx1atb6GIlTaQXzu/p4fTQeAIUVzZXT4K984IyfuO7NLj
# WMtog1wGUpZD98pv+4Mt9Y5bvfPUjaUVjtePy1DVdi0rl5ESNYi0zyOmXVxtA5zz
# xu1H7RdLZOZugT/XjX69rY9bMYIEyDCCBMQCAQEwgYwweDELMAkGA1UEBhMCVVMx
# DjAMBgNVBAgMBVRleGFzMRAwDgYDVQQHDAdIb3VzdG9uMREwDwYDVQQKDAhTU0wg
# Q29ycDE0MDIGA1UEAwwrU1NMLmNvbSBDb2RlIFNpZ25pbmcgSW50ZXJtZWRpYXRl
# IENBIEVDQyBSMgIQUR3u8+0Mq1hXs5hyxM0vzzANBglghkgBZQMEAgEFAKCBhDAY
# BgorBgEEAYI3AgEMMQowCKACgAChAoAAMBkGCSqGSIb3DQEJAzEMBgorBgEEAYI3
# AgEEMBwGCisGAQQBgjcCAQsxDjAMBgorBgEEAYI3AgEVMC8GCSqGSIb3DQEJBDEi
# BCDlUWaxnZsaTyFFxPZqNbiBR3Ak55ZUeQBoX6w85GtmaTALBgcqhkjOPQIBBQAE
# ZjBkAjAergOZPJ9mRm2feXQ6t/faXJoN3UZkeugDi28UmDymyOGgJ/ITr7SJLk1U
# ZB+jjzgCMGqQfkSTpYkfI8b65G2UVoGced4nKmSvUQniZSQkyiRxcqFGnuMddKpP
# srL96Lamo6GCAyMwggMfBgkqhkiG9w0BCQYxggMQMIIDDAIBATBqMFUxCzAJBgNV
# BAYTAkdCMRgwFgYDVQQKEw9TZWN0aWdvIExpbWl0ZWQxLDAqBgNVBAMTI1NlY3Rp
# Z28gUHVibGljIFRpbWUgU3RhbXBpbmcgQ0EgUjQxAhEA507yVbBQT/rbpt/3/Iuj
# FTANBglghkgBZQMEAgIFAKB5MBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJ
# KoZIhvcNAQkFMQ8XDTI2MDgzMDIyNDgyOVowPwYJKoZIhvcNAQkEMTIEMF2aLw99
# t3G0vBrKZ2y+gu0067ay7r30hoXBGQlq456nKNVahLfVXDtyjkoMY9uJCDANBgkq
# hkiG9w0BAQEFAASCAgBLrKce11lDTynQ1lCqzfWPPWTsS94QeKRA5yHU2vyQDe6H
# sdTO1O1U3zzjH+yMlvAUW+z1WN1vcw1Z0b21u/k/jAB9CVc7da3pADJjfYmB6hiR
# ejUwGBeSzxUKDlHiOZop83iHAzjx4+O4aoh6sNci8yViU0IXfhcWIU1+MPKYeqWR
# d/xcBpGQeDk718t0JhKn8jUcjJob9d5icMMZbkjCOUPy5Suv+iYkbDHANUze1ZDR
# IeDeT1wsdVp6POSiBRaIGcfu7demKt4+n1z4mzjZZjy8zdzIpKjFJikMjllLJ8D7
# FTju2113akD8x7Ij7FMo5dtN9bJIgTSMsnD2d9+3m4Q2OpZkADOmugji19exuZFj
# LO9HhHbLMufESa4SNV/kEWcHjrk6az7o7Je8HRJPS3+7scYCEDttwCxArftS7QC9
# ZmmH0rlPzdL8wPT6A3wcYpoMu/w/xnuRWcaEg5MHVCraWPrq62nrnLz31sdzlxdN
# v/SF0rylb8SPaH/Zp68Djt2pJJGWfN8agiOjtn8WSLD19w1SEkIPHJ84bXNjPLdk
# ZpRf4ZmdtjGhnn+s6oO8N3r/dBLsYkhxzZFdqXz6/L2MuinFzpt3jbG0hbqQqzOY
# cAjd49LXAS5sgtm8T1f3wX/2U3JpHNObCqghw6FKXR7psjsnumt9hKZo1oyQYg==
# SIG # End signature block
