BeforeAll {
    . "$PSScriptRoot/../../../src/CharlandCustomizations/Public/Get-AWSRegionFromIP.ps1"
}

Describe 'Get-AWSRegionFromIP' -Tag 'Unit' {
    BeforeEach {
        $script:AWSIPRangesCache = $null
        $script:AWSIPRangesCacheTimestamp = $null

        Mock Invoke-RestMethod {
            [PSCustomObject]@{
                syncToken     = '12345'
                createDate    = '2026-06-21-00-00-00'
                prefixes      = @(
                    [PSCustomObject]@{
                        ip_prefix = '52.95.245.0/24'
                        region    = 'us-east-1'
                        service   = 'AMAZON'
                    }
                )
                ipv6_prefixes = @(
                    [PSCustomObject]@{
                        ipv6_prefix = '2406:da00:ff00::/48'
                        region      = 'ap-southeast-1'
                        service     = 'AMAZON'
                    }
                )
            }
        }
    }

    It 'accepts valid IPv4 addresses and returns matching region data' {
        $result = Get-AWSRegionFromIP -IPAddress '52.95.245.10'

        $result.IPAddress | Should -Be '52.95.245.10'
        $result.Region | Should -Be 'us-east-1'
        $result.Service | Should -Be 'AMAZON'
        $result.CIDR | Should -Be '52.95.245.0/24'
    }

    It 'accepts valid IPv6 addresses and returns matching region data' {
        $result = Get-AWSRegionFromIP -IPAddress '2406:da00:ff00::1'

        $result.IPAddress | Should -Be '2406:da00:ff00::1'
        $result.Region | Should -Be 'ap-southeast-1'
        $result.Service | Should -Be 'AMAZON'
        $result.CIDR | Should -Be '2406:da00:ff00::/48'
    }

    It 'rejects invalid IP addresses' {
        { Get-AWSRegionFromIP -IPAddress 'not-an-ip' } | Should -Throw
    }

    It 'returns expected AWS region for known IP ranges' {
        $result = Get-AWSRegionFromIP -IPAddress '52.95.245.200'

        $result.Region | Should -Be 'us-east-1'
        $result.CIDR | Should -Be '52.95.245.0/24'
    }

    It 'returns null region data when the IP address does not match AWS ranges' {
        $result = Get-AWSRegionFromIP -IPAddress '203.0.113.10'

        $result.IPAddress | Should -Be '203.0.113.10'
        $result.Region | Should -BeNullOrEmpty
        $result.Service | Should -BeNullOrEmpty
        $result.CIDR | Should -BeNullOrEmpty
    }

    It 'uses cached AWS IP ranges for subsequent calls within 24 hours' {
        $null = Get-AWSRegionFromIP -IPAddress '52.95.245.10'
        $null = Get-AWSRegionFromIP -IPAddress '52.95.245.20'

        Should -Invoke Invoke-RestMethod -Times 1 -Exactly
    }

    It 'throws a useful error when AWS IP ranges retrieval fails' {
        Mock Invoke-RestMethod { throw 'network unavailable' }

        { Get-AWSRegionFromIP -IPAddress '52.95.245.10' } | Should -Throw '*Unable to retrieve AWS IP ranges*'
    }
}
