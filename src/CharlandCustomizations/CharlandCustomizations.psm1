<#
.SYNOPSIS
    CharlandCustomizations module loader.

.DESCRIPTION
    Main module file for CharlandCustomizations. Validates prerequisites, then
    dot-sources all public and private function files.

    Public functions (src/Public/*.ps1) are exported automatically.
    Private functions (src/Private/*.ps1) are available internally but not exported.

    AWS-specific functions are loaded via NestedModules defined in the manifest.

.NOTES
    Requires PowerShell 7.2+
    Requires AWS.Tools.Common v5+ or AWSPowerShell.NetCore v5+
#>

# Require AWS PowerShell tools v5+
$awsCmd = Get-Command -Name 'Set-AWSCredential' -ErrorAction SilentlyContinue
if (-not $awsCmd) {
    throw "AWS PowerShell tools not found. Install AWS.Tools.Common v5+ or AWSPowerShell.NetCore v5+."
}
$awsVersion = $awsCmd.Module.Version
if ($awsVersion.Major -lt 5) {
    throw "AWS PowerShell tools v$awsVersion detected. Version 5+ is required. Run: Update-AWSToolsModule"
}

# Dot-source public functions (exported)
$publicScripts = Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public') -Filter '*.ps1' -File -ErrorAction SilentlyContinue
foreach ($file in $publicScripts) {
    . $file.FullName
}

# Dot-source private functions (internal helpers, not exported)
$privateScripts = Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private') -Filter '*.ps1' -File -ErrorAction SilentlyContinue
foreach ($file in $privateScripts) {
    . $file.FullName
}

# Export only public functions by filename convention
$publicFunctionNames = @($publicScripts | ForEach-Object { $_.BaseName } | Where-Object { $_ })
Export-ModuleMember -Function $publicFunctionNames
