# Internal helpers for KMS-Customizations.psm1. Not exported.

# Matches key ARNs, including multi-Region keys (mrk-<id>).
$script:KmsKeyArnPattern = '^arn:aws[a-z-]*:kms:(?<Region>[a-z0-9-]+):(?<Account>\d{12}):key/(?<KeyId>(mrk-)?[0-9a-fA-F-]+)$'

# AWS unique-ID prefixes left behind in a policy when the referenced principal is deleted.
$script:DeletedPrincipalIdPattern = '^(AIDA|AROA|AGPA|AIPA|ASCA|APKA)[A-Z0-9]{16,}$'

function Resolve-CHARKMSKeyArn {
    # Internal helper (not exported): splits a KMS key ARN into Region/Account/KeyId.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$KeyArn
    )

    $m = [regex]::Match($KeyArn, $script:KmsKeyArnPattern)
    if (-not $m.Success) {
        throw "Invalid KMS key ARN '$KeyArn'. Expected 'arn:aws:kms:<region>:<account-id>:key/<key-id>'."
    }
    [PSCustomObject]@{
        Region  = $m.Groups['Region'].Value
        Account = $m.Groups['Account'].Value
        KeyId   = $m.Groups['KeyId'].Value
    }
}

function Get-CHARKMSConfigStringValue {
    # Internal helper (not exported): flattens an object into (Path, Value) pairs for string leaves.
    [CmdletBinding()]
    param(
        [Parameter()]
        $InputObject,

        [Parameter(Mandatory)]
        [string]$Path
    )

    if ($null -eq $InputObject) { return }

    if ($InputObject -is [string]) {
        [PSCustomObject]@{ Path = $Path; Value = $InputObject }
    }
    elseif ($InputObject -is [System.Collections.IEnumerable]) {
        foreach ($element in $InputObject) {
            Get-CHARKMSConfigStringValue -InputObject $element -Path $Path
        }
    }
    elseif ($InputObject -is [psobject] -and $InputObject.PSObject.Properties.Count -gt 0 -and
        $InputObject -isnot [ValueType]) {
        foreach ($property in $InputObject.PSObject.Properties) {
            Get-CHARKMSConfigStringValue -InputObject $property.Value -Path "$Path.$($property.Name)"
        }
    }
}
