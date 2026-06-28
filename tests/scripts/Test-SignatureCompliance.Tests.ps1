BeforeAll {
    $script:SUTPath = "$PSScriptRoot/../../Scripts/Test-SignatureCompliance.ps1"

    if (-not (Get-Command Test-CHARAuthenticodeSignature -ErrorAction SilentlyContinue)) {
        function global:Test-CHARAuthenticodeSignature {
            param(
                [string[]]$Path,
                [string[]]$IncludeExtension
            )
        }
    }

    function Invoke-TestSignatureComplianceScript {
        [CmdletBinding()]
        param(
            [string[]]$Path,
            [string[]]$IncludeExtension
        )

        $scriptContent = Get-Content -Path $script:SUTPath -Raw
        $scriptDirectory = Split-Path -Path $script:SUTPath -Parent

        $scriptContent = $scriptContent -replace '\$PSScriptRoot', "'$scriptDirectory'"
        $scriptContent = $scriptContent -replace '(?s)# SIG # Begin signature block.*# SIG # End signature block', ''
        $scriptContent = $scriptContent -replace '\bexit\s+\d+', 'return'
        $scriptContent = $scriptContent -replace '\bexit\b', 'return'

        $invokeParams = @{}
        if ($Path) { $invokeParams.Path = $Path }
        if ($IncludeExtension) { $invokeParams.IncludeExtension = $IncludeExtension }

        & ([scriptblock]::Create($scriptContent)) @invokeParams
    }
}

Describe 'Test-SignatureCompliance script' -Tag 'Unit' {
    It 'calls Test-CHARAuthenticodeSignature with passed parameters' {
        Mock Test-CHARAuthenticodeSignature { @() }

        Invoke-TestSignatureComplianceScript -Path @('./src') -IncludeExtension @('.ps1')

        Should -Invoke Test-CHARAuthenticodeSignature -Times 1 -Exactly -ParameterFilter {
            $Path -eq './src' -and $IncludeExtension -eq '.ps1'
        }
    }

    It 'returns failures from Test-CHARAuthenticodeSignature output' {
        Mock Test-CHARAuthenticodeSignature {
            @([pscustomobject]@{ Path = './Scripts/Build-Module.ps1'; Status = 'NotSigned' })
        }

        $result = Invoke-TestSignatureComplianceScript

        $result | Should -Not -BeNullOrEmpty
        $result.Status | Should -Contain 'NotSigned'
    }
}
