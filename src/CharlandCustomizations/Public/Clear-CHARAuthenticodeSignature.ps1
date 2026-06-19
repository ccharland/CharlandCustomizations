<#
.SYNOPSIS
    Script wrapper for Clear-CHARAuthenticodeSignature.

.DESCRIPTION
    Standalone entry point used during module build to clear Authenticode
    signatures without importing the full module. When dot-sourced or imported
    as part of the module, the inner function is loaded into the session instead.
#>
[CmdletBinding()]
param(
    [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
    [Alias('FullName')]
    [string[]]$Path
)

function Clear-CHARAuthenticodeSignature {
<#
.SYNOPSIS
    Removes the Authenticode signature block from PowerShell script files.

.DESCRIPTION
    Strips the "# SIG # Begin signature block" section and everything after it
    from the specified script file(s). Useful when you need to edit a signed script
    and plan to re-sign it afterward.

.PARAMETER Path
    Path(s) to the PowerShell script file(s) to remove the signature from.
    Accepts pipeline input from Get-ChildItem via the FullName property.

.EXAMPLE
    Clear-CHARAuthenticodeSignature -Path ./MyScript.ps1
    Removes the signature from a single file.

.EXAMPLE
    Get-ChildItem *.ps1 | Clear-CHARAuthenticodeSignature
    Removes signatures from all .ps1 files in the current directory via pipeline.

.EXAMPLE
    Get-ChildItem -Recurse -Include *.ps1,*.psm1 | Clear-CHARAuthenticodeSignature
    Removes signatures from all PowerShell files recursively.

.NOTES
    The original file is modified in place. Consider backing up before running.

    Dependencies: None (uses built-in cmdlets only)
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [string[]]$Path
    )

    process {
        foreach ($file in $Path) {
            if (-not (Test-Path $file)) {
                Write-Error "File not found: $file"
                continue
            }

            try {
                $content = Get-Content -Path $file -Raw

                $signatureStart = $content.IndexOf('# SIG # Begin signature block')

                if ($signatureStart -gt -1) {
                    $cleanContent = $content.Substring(0, $signatureStart).TrimEnd()
                    Set-Content -Path $file -Value $cleanContent -NoNewline
                    Write-Output "Authenticode signature removed from: $file"
                } else {
                    Write-Verbose "No signature block found in: $file"
                }
            } catch {
                Write-Error "Failed to remove signature from '$file': $($_.Exception.Message)"
            }
        }
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Clear-CHARAuthenticodeSignature @PSBoundParameters
}
