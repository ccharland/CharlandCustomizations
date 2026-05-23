# Require AWS PowerShell tools v5+
$awsCmd = Get-Command -Name 'Set-AWSCredential' -ErrorAction SilentlyContinue
if (-not $awsCmd) {
    throw "AWS PowerShell tools not found. Install AWS.Tools.Common v5+ or AWSPowerShell.NetCore v5+."
}
$awsVersion = $awsCmd.Module.Version
if ($awsVersion.Major -lt 5) {
    throw "AWS PowerShell tools v$awsVersion detected. Version 5+ is required. Run: Update-AWSToolsModule"
}

$publicScripts = Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public') -Filter '*.ps1' -File -ErrorAction SilentlyContinue
foreach ($file in $publicScripts) {
    . $file.FullName
}

$privateScripts = Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private') -Filter '*.ps1' -File -ErrorAction SilentlyContinue
foreach ($file in $privateScripts) {
    . $file.FullName
}

$publicFunctionNames = @($publicScripts | ForEach-Object { $_.BaseName } | Where-Object { $_ })
Export-ModuleMember -Function $publicFunctionNames
