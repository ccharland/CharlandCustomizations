<#
.SYNOPSIS
    Script wrapper for Clear-CCAuthenticodeSignature.

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

function Clear-CCAuthenticodeSignature {
<#
.SYNOPSIS
    Removes the Authenticode signature block from PowerShell script files.

.DESCRIPTION
    Strips the "