---
description: "Use when editing signed PowerShell scripts, module files, build scripts, or release scripts. Remove Authenticode signature blocks before modifying signed .ps1, .psm1, or .psd1 files, then re-sign through the repo's signing workflow."
applyTo: "Scripts/**/*.ps1,src/CharlandCustomizations/**/*.ps1,src/CharlandCustomizations/**/*.psm1,src/CharlandCustomizations/**/*.psd1"
---
# Signed PowerShell Editing

- Before modifying a signed `.ps1`, `.psm1`, or `.psd1` file, remove the existing Authenticode signature block first.
- Use the repository signing workflow after the edit instead of editing through an existing signature block.
- Treat signature removal and re-signing as part of the normal change flow for signed release files.
- Keep every `.psd1` array and `.psm1` `Export-ModuleMember -Function` array sorted alphabetically with one element per line. Run `./Scripts/Test-ManifestCompliance.ps1` after manifest or nested module export edits because the PR gate enforces this format.
