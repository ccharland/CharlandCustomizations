# Distribution Guide

## Preferred Publishing Path

For `CharlandCustomizations`, prefer publishing the module to a PowerShell package feed instead of asking consumers to clone the Git repository.

### Public Distribution

Use the PowerShell Gallery when the module can be public. Consumers can then install with:

```powershell
Install-PSResource CharlandCustomizations -Repository PSGallery -Scope CurrentUser
```

This works well for CloudShell, AWS WorkSpaces, Azure Cloud PCs, and other PowerShell 7 environments without requiring GitHub credentials.

### Private Distribution

If the module must stay private, publish to a private NuGet-compatible repository such as:

- Azure Artifacts
- JFrog Artifactory
- ProGet
- Nexus

Consumers can then register the repository once and install from that feed.

## Publishing to PowerShell Gallery

### One-time Setup

1. Create a PowerShell Gallery account.
2. Create a scoped API key for `CharlandCustomizations`.
3. Store the API key outside the repository.

Recommended storage options:

- `PSGALLERY_API_KEY` environment variable
- SecretManagement secret named `PSGalleryApiKey`
- Interactive prompt at publish time

Do not commit the API key to this repository, a module manifest, a script, or a tracked `.psd1` file.

### Publish Command

Use the helper script:

```powershell
$version = (Test-ModuleManifest ./src/CharlandCustomizations/CharlandCustomizations.psd1).Version.ToString()
$publishPath = "./build/CharlandCustomizations/$version"
./Scripts/Publish-CharlandCustomizations.ps1 -Path $publishPath -Repository PSGallery -WhatIf
./Scripts/Publish-CharlandCustomizations.ps1 -Path $publishPath -Repository PSGallery
```

The script publishes with `Publish-PSResource` when available and falls back to `Publish-Module` for older sessions.

PSGallery publish guardrails:

- Current branch must be `main`
- `HEAD` must have immutable release tag `ModuleVersion[-Prerelease]` from `CharlandCustomizations.psd1` (for example, `0.2.0-beta1` or `0.2.0`)
- Publish path should target signed build output in `build/CharlandCustomizations/<version>/`

### Environment Variable Example

```powershell
$env:PSGALLERY_API_KEY = 'paste-key-here'
$version = (Test-ModuleManifest ./src/CharlandCustomizations/CharlandCustomizations.psd1).Version.ToString()
$publishPath = "./build/CharlandCustomizations/$version"
./Scripts/Publish-CharlandCustomizations.ps1 -Path $publishPath -Repository PSGallery
```

### SecretManagement Example

```powershell
Set-Secret -Name PSGalleryApiKey -Secret 'paste-key-here'
$version = (Test-ModuleManifest ./src/CharlandCustomizations/CharlandCustomizations.psd1).Version.ToString()
$publishPath = "./build/CharlandCustomizations/$version"
./Scripts/Publish-CharlandCustomizations.ps1 -Path $publishPath -Repository PSGallery
```

## Creating Distribution Packages

The build script can create signed, verifiable distribution packages for sharing your module.

### Requirements

To create a distribution package, you must:

1. **Have a valid code signing certificate**
   - Certificate must not be expired
   - Must have private key
   - Must be in `Cert:\CurrentUser\My`

2. **All files must be signed**
   - Cannot use `-SkipSigning` flag
   - All signatures must be valid
   - Timestamp must be applied

### Basic Package Creation

```powershell
# Build, sign, and package
./Scripts/Build-Module.ps1 -Package
```

This will:
1. Build the module in `build/CharlandCustomizations/<version>/`
2. Sign all `.ps1`, `.psm1`, and `.psd1` files
3. Verify all signatures are valid
4. Create a zip file in `build/packages/`
5. Generate SHA256 hash file
6. Create installation README

### Clean Package Build

```powershell
# Remove old builds and create fresh package
./Scripts/Build-Module.ps1 -Clean -Package
```

## Package Contents

After running with `-Package`, you'll find in `build/packages/`:

- `CharlandCustomizations-<version>.zip` - Module package
- `CharlandCustomizations-<version>.zip.sha256` - Hash for verification
- `README-<version>.txt` - Installation instructions

## Verifying Packages

### Verify Hash

```powershell
# Calculate hash
$hash = Get-FileHash build/packages/CharlandCustomizations-0.3.0.zip -Algorithm SHA256

# Compare with hash file
Get-Content build/packages/CharlandCustomizations-0.3.0.zip.sha256
```

### Verify Signatures

```powershell
# Extract package
Expand-Archive build/packages/CharlandCustomizations-0.3.0.zip -DestinationPath temp/

# Check all signatures
Get-ChildItem temp/0.3.0/ -Include *.ps1,*.psm1,*.psd1 -Recurse | ForEach-Object {
    $sig = Get-AuthenticodeSignature $_.FullName
    [PSCustomObject]@{
        File = $_.Name
        Status = $sig.Status
        Signer = $sig.SignerCertificate.Subject
    }
} | Format-Table
```

## Distribution Workflow

### 1. Prepare Release

```powershell
# Update version in manifest
# Update CHANGELOG.md
git checkout main
git add src/CharlandCustomizations/CharlandCustomizations.psd1 docs/CHANGELOG.md
git commit -m "Prepare release v0.3.0"
```

### 2. Create Package

```powershell
./Scripts/Build-Module.ps1 -Clean -Package
```

### 3. Verify Package

```powershell
Get-FileHash build/packages/CharlandCustomizations-0.3.0.zip -Algorithm SHA256
```

### 4. Tag Release

```powershell
$manifest = Test-ModuleManifest ./src/CharlandCustomizations/CharlandCustomizations.psd1
$releaseTag = $manifest.Version.ToString()
if ($manifest.PrivateData.PSData.Prerelease) {
   $releaseTag = "$releaseTag-$($manifest.PrivateData.PSData.Prerelease)"
}
git tag $releaseTag
git push --tags
```

### 5. Publish to PSGallery

```powershell
$version = (Test-ModuleManifest ./src/CharlandCustomizations/CharlandCustomizations.psd1).Version.ToString()
$publishPath = "./build/CharlandCustomizations/$version"
./Scripts/Publish-CharlandCustomizations.ps1 -Path $publishPath -Repository PSGallery -WhatIf
./Scripts/Publish-CharlandCustomizations.ps1 -Path $publishPath -Repository PSGallery
```

### 6. Distribute

Upload to:
- GitHub Releases
- PowerShell Gallery (published in Step 5)
- Internal file share

Include:
- `.zip` file
- `.sha256` hash file
- `README-<version>.txt`

## Installation Instructions for Recipients

### From PowerShell Gallery

```powershell
Install-PSResource CharlandCustomizations -Repository PSGallery -Scope CurrentUser
Import-Module CharlandCustomizations
```

### From Package File

1. **Download and verify**
   ```powershell
   Get-FileHash CharlandCustomizations-0.3.0.zip -Algorithm SHA256
   Get-Content CharlandCustomizations-0.3.0.zip.sha256
   ```

2. **Extract and install**
   ```powershell
   Expand-Archive CharlandCustomizations-0.3.0.zip -DestinationPath .
   Copy-Item -Recurse 0.3.0 $HOME/Documents/PowerShell/Modules/CharlandCustomizations/
   Import-Module CharlandCustomizations
   ```

3. **Verify**
   ```powershell
   Get-Module CharlandCustomizations
   Get-Command -Module CharlandCustomizations
   ```

## Troubleshooting

### "Cannot create package: Not all files are signed"

Ensure you have a valid certificate and don't use `-SkipSigning`:

```powershell
Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert
./Scripts/Build-Module.ps1 -Package
```

### "No code signing certificate found"

- Obtain a code signing certificate
- Import to `Cert:\CurrentUser\My`
- Ensure it has private key and is not expired

## See Also

- `docs/BUILD-PROCESS.md` - Build system details
- `docs/INSTALLATION.md` - Installation guide
- `Scripts/Build-Module.ps1` - Build script
- `Scripts/Publish-CharlandCustomizations.ps1` - Publish script
