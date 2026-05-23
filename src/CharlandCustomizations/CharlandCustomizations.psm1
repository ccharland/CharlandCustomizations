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
