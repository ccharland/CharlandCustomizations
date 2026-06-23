function Get-CHARAWSRegionFromIp {
<#
.SYNOPSIS
    Resolves an IP address to the matching AWS region from official AWS IP ranges.

.DESCRIPTION
    Downloads and evaluates the AWS public IP ranges dataset from:
    https://ip-ranges.amazonaws.com/ip-ranges.json

    The function supports IPv4 and IPv6 input, performs CIDR matching against the
    AWS ranges, and returns the matching region/service/CIDR when found.

    AWS IP ranges are cached in memory for 24 hours to reduce repeated network calls.

.PARAMETER IPAddress
    The IPv4 or IPv6 address to evaluate.

.EXAMPLE
    Get-CHARAWSRegionFromIp -IPAddress '52.95.245.10'

    Returns the matching AWS region, service, and CIDR for the provided IPv4 address.

.EXAMPLE
    Get-CHARAWSRegionFromIp -IPAddress '2406:da00:ff00::1'

    Returns the matching AWS region, service, and CIDR for the provided IPv6 address.

.NOTES
    Data source: AWS IP Ranges JSON (https://ip-ranges.amazonaws.com/ip-ranges.json)
    Cache duration: 24 hours (module session memory cache)
    Requires: Internet access to refresh cache when expired
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({
                $parsedAddress = $null
                if (-not [System.Net.IPAddress]::TryParse($_, [ref]$parsedAddress)) {
                    throw "IPAddress must be a valid IPv4 or IPv6 address. Received: '$_'"
                }
                $true
            })]
        [string]$IPAddress
    )

    $convertToBigIntegerFromIPAddress = {
        param(
            [Parameter(Mandatory)]
            [System.Net.IPAddress]$Address
        )

        $value = [System.Numerics.BigInteger]::Zero
        foreach ($byte in $Address.GetAddressBytes()) {
            $value = [System.Numerics.BigInteger]::op_LeftShift($value, 8)
            $value += [System.Numerics.BigInteger]$byte
        }

        return $value
    }

    $testIPInCIDRBlock = {
        param(
            [Parameter(Mandatory)]
            [System.Net.IPAddress]$Address,

            [Parameter(Mandatory)]
            [string]$CIDR
        )

        $cidrParts = $CIDR -split '/'
        if ($cidrParts.Count -ne 2) {
            return $false
        }

        $network = $null
        if (-not [System.Net.IPAddress]::TryParse($cidrParts[0], [ref]$network)) {
            return $false
        }

        $prefixLength = 0
        if (-not [int]::TryParse($cidrParts[1], [ref]$prefixLength)) {
            return $false
        }

        if ($Address.AddressFamily -ne $network.AddressFamily) {
            return $false
        }

        $totalBits = if ($Address.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork) { 32 } else { 128 }
        if ($prefixLength -lt 0 -or $prefixLength -gt $totalBits) {
            return $false
        }

        $addressValue = & $convertToBigIntegerFromIPAddress -Address $Address
        $networkValue = & $convertToBigIntegerFromIPAddress -Address $network

        $hostBits = $totalBits - $prefixLength
        $allBitsSet = [System.Numerics.BigInteger]::op_Subtraction(
            [System.Numerics.BigInteger]::op_LeftShift([System.Numerics.BigInteger]::One, $totalBits),
            [System.Numerics.BigInteger]::One
        )
        $hostMask = if ($hostBits -eq 0) {
            [System.Numerics.BigInteger]::Zero
        }
        else {
            [System.Numerics.BigInteger]::op_Subtraction(
                [System.Numerics.BigInteger]::op_LeftShift([System.Numerics.BigInteger]::One, $hostBits),
                [System.Numerics.BigInteger]::One
            )
        }
        $networkMask = [System.Numerics.BigInteger]::op_ExclusiveOr($allBitsSet, $hostMask)

        $maskedAddress = [System.Numerics.BigInteger]::op_BitwiseAnd($addressValue, $networkMask)
        $maskedNetwork = [System.Numerics.BigInteger]::op_BitwiseAnd($networkValue, $networkMask)

        return $maskedAddress -eq $maskedNetwork
    }

    try {
        $parsedInputAddress = [System.Net.IPAddress]::Parse($IPAddress)
        $now = [DateTimeOffset]::UtcNow
        $cacheDuration = [TimeSpan]::FromHours(24)

        if (
            -not $script:AWSIPRangesCache -or
            -not $script:AWSIPRangesCacheTimestamp -or
            ($now - $script:AWSIPRangesCacheTimestamp) -ge $cacheDuration
        ) {
            try {
                $script:AWSIPRangesCache = Invoke-RestMethod -Uri 'https://ip-ranges.amazonaws.com/ip-ranges.json' -Method Get -ErrorAction Stop
                $script:AWSIPRangesCacheTimestamp = $now
            }
            catch {
                throw "Unable to retrieve AWS IP ranges from https://ip-ranges.amazonaws.com/ip-ranges.json. $($_.Exception.Message)"
            }
        }

        $usesIPv4AddressFamily = $parsedInputAddress.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork
        $ranges = if ($usesIPv4AddressFamily) { $script:AWSIPRangesCache.prefixes } else { $script:AWSIPRangesCache.ipv6_prefixes }

        foreach ($range in $ranges) {
            $cidr = if ($usesIPv4AddressFamily) { $range.ip_prefix } else { $range.ipv6_prefix }
            if (-not $cidr) {
                continue
            }

            if (& $testIPInCIDRBlock -Address $parsedInputAddress -CIDR $cidr) {
                return [PSCustomObject]@{
                    IPAddress = $IPAddress
                    Region    = $range.region
                    Service   = $range.service
                    CIDR      = $cidr
                }
            }
        }

        return [PSCustomObject]@{
            IPAddress = $IPAddress
            Region    = $null
            Service   = $null
            CIDR      = $null
        }
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}
