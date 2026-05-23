$publicFunctions = Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public') -Filter '*.ps1' -File -ErrorAction SilentlyContinue
foreach ($file in $publicFunctions) {
    . $file.FullName
}

$privateFunctions = Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private') -Filter '*.ps1' -File -ErrorAction SilentlyContinue
foreach ($file in $privateFunctions) {
    . $file.FullName
}

if ($publicFunctions) {
    Export-ModuleMember -Function $publicFunctions.BaseName
}
