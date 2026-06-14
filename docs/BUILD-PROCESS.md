# Build Process

## Overview

The build process creates versioned, signed module artifacts from source while keeping the source directory clean and version-agnostic.

## Directory Structure

```
Source:  src/CharlandCustomizations/               (no version in path)
Build:   build/CharlandCustomizations/<version>/   (versioned output)
Install: $HOME/Documents/PowerShell/Modules/CharlandCustomizations/<version>/
```

## Build Script Usage

### Basic Build

```powershell
# Validate and build (no install)
./Scripts/Build-Module.ps1
```

Creates versioned output in `build/CharlandCustomizations/<version>/`

### Build and Install

```powershell
# Build, sign, and install
./Scripts/Build-Module.ps1 -Install
```

Installs to user's PowerShell modules directory with version number.

### Install Only (No Build)

```powershell
# Install current source version only
./Scripts/Build-Module.ps1 -InstallOnly
```

Install-only mode:
- Skips analyzer, build output creation, signing, and packaging
- Copies source module files directly to: `$HOME/Documents/PowerShell/Modules/CharlandCustomizations/<version>/`

### Create Distribution Package

```powershell
# Build, sign, and create distributable zip
./Scripts/Build-Module.ps1 -Package
```

**Requirements for packaging:**
- All files must be signed (cannot use `-SkipSigning`)
- All signatures must be valid
- Creates versioned zip in `build/packages/`
- Includes SHA256 hash file for verification
- Generates installation README

**Package contents:**
- `CharlandCustomizations-<version>.zip` - Module package
- `CharlandCustomizations-<version>.zip.sha256` - Hash for verification
- `README-<version>.txt` - Installation instructions

### Clean Build

```powershell
# Remove build directory and rebuild
./Scripts/Build-Module.ps1 -Clean -Install
```

### Skip Signing

```powershell
# Build without code signing
./Scripts/Build-Module.ps1 -SkipSigning -Install
```

### Update Version During Build

```powershell
# Set an explicit version before build
./Scripts/Build-Module.ps1 -Version 0.3.3

# Increment semantic version before build
./Scripts/Build-Module.ps1 -BumpVersion Patch
./Scripts/Build-Module.ps1 -BumpVersion Minor
./Scripts/Build-Module.ps1 -BumpVersion Major
```

Notes:
- Use either `-Version` or `-BumpVersion` (not both in the same run).
- The selected version is written to `src/CharlandCustomizations/CharlandCustomizations.psd1` before build output is created.

### Prepare Changelog and Release Commands

```powershell
# Add changelog template (if missing) and print release commands
./Scripts/Build-Module.ps1 -PrepareRelease

# Common release flow
./Scripts/Build-Module.ps1 -BumpVersion Patch -PrepareRelease -Clean -Install
```

`-PrepareRelease` behavior:
- Ensures `docs/CHANGELOG.md` contains a section for the current version
- Prints version-aware git commands for commit and tag (for example, `Release v0.3.3` and `v0.3.3`)

### Publish to PowerShell Repository

Use the publish script after a successful build so publish validation runs against the signed build output.

```powershell
# Read current manifest version
$version = (Test-ModuleManifest ./src/CharlandCustomizations/CharlandCustomizations.psd1).Version.ToString()

# Publish path should target the signed build output, not src/
$publishPath = "./build/CharlandCustomizations/$version"

# Dry run first
./Scripts/Publish-CharlandCustomizations.ps1 -Path $publishPath -Repository PSGallery -WhatIf

# Actual publish
./Scripts/Publish-CharlandCustomizations.ps1 -Path $publishPath -Repository PSGallery
```

Notes:
- The publish script validates Authenticode signatures by default.
- `-SkipSignatureValidation` can bypass this gate, but should not be used for release publishing.
- API key can come from `PSGALLERY_API_KEY`, `Get-Secret PSGalleryApiKey`, or prompt input.
- PSGallery publishing is only allowed when:
   - Current branch is `main`
   - `HEAD` has immutable release tag `ModuleVersion[-Prerelease]` from `CharlandCustomizations.psd1` (for example, `0.2.0-beta1` or `0.2.0`)

### Source Signature Compliance Gate

Validate source and release scripts before packaging/publishing:

```powershell
./Scripts/Test-SignatureCompliance.ps1
```

Default gate scope:
- `Scripts/`
- `src/CharlandCustomizations/`

The gate validates `.ps1`, `.psm1`, and `.psd1` files and fails if any signature status is not `Valid`.

## Git Hook Path Policy

Install the local pre-commit hook after cloning or when `.githooks/pre-commit` changes:

```powershell
Install-CCGitHook -Force
```

The hook keeps code work and repository automation work separated by branch type:

- Normal code branches block staged changes under `.github/`, `.kiro/`, and `.vscode/`.
- Workflow or infrastructure branches block staged changes under `src/` and `tests/`.
- Branch names containing `workflow`, `workflows`, `infra`, or `infrastructure` are treated as workflow/infrastructure branches.
- Branch names that use `ci` as a branch segment or token, such as `ci/update` or `chore-ci-config`, are also treated as workflow/infrastructure branches.

For an exceptional mixed-scope commit, make the override deliberate and visible:

```powershell
$env:CC_GIT_HOOK_ALLOW_PATH_POLICY_OVERRIDE = '1'
git commit -m 'Explain why this mixed-scope commit is necessary'
Remove-Item Env:\CC_GIT_HOOK_ALLOW_PATH_POLICY_OVERRIDE
```

Use the override only when splitting the commit would make the history harder to review.

## Build Process Steps

1. **Validate Source**
   - Checks module manifest exists
   - Tests manifest syntax
   - Reads version number
   - Runs PSScriptAnalyzer (if installed)

2. **Create Build Directory**
   - Creates `build/CharlandCustomizations/<version>/`
   - Removes existing build for that version

3. **Copy Files**
   - Copies all module files from source to build directory
   - Preserves directory structure

4. **Test Module**
   - Imports built module
   - Validates all functions export correctly
   - Reports function count

5. **Sign Files** (if certificate available)
   - Finds valid code signing certificate
   - Signs all `.ps1`, `.psm1`, `.psd1` files in build output
   - Uses Sectigo timestamp server
   - Verifies all signatures

6. **Create Package** (if `-Package` flag)
   - Verifies all files are signed
   - Creates zip file
   - Generates SHA256 hash
   - Creates installation README

7. **Install** (if `-Install` flag)
   - Removes old versions from install location
   - Copies built module to `$HOME/Documents/PowerShell/Modules/`
   - Imports and validates installed module

## Version Management

### Source (src/)
- No version in directory path
- Version only in `.psd1` manifest
- Easy to work with, no path changes

### Build (build/)
- Versioned directory: `build/CharlandCustomizations/0.3.0/`
- Ready for distribution
- Gitignored (not committed)

### Install ($HOME/Documents/PowerShell/Modules/)
- Versioned directory: `CharlandCustomizations/<version>/`
- PowerShell automatically loads highest version
- Multiple versions can coexist

## Workflow

### Development
```powershell
# Edit files in src/CharlandCustomizations/
# Test directly from source
Import-Module ./src/CharlandCustomizations/CharlandCustomizations.psd1 -Force
```

### Release
```powershell
# 1. Update CHANGELOG.md
# 2. Build and test (optionally bump version as part of build)
./Scripts/Build-Module.ps1 -Clean -BumpVersion Patch -Install

# 3. Validate source signatures (Scripts + src)
./Scripts/Test-SignatureCompliance.ps1

# 4. Commit release changes on main
git checkout main
git add src/CharlandCustomizations/CharlandCustomizations.psd1 docs/CHANGELOG.md
git commit -m "Release v0.3.0"

# 5. Create immutable release tag from manifest version/prerelease
$manifest = Test-ModuleManifest ./src/CharlandCustomizations/CharlandCustomizations.psd1
$releaseTag = $manifest.Version.ToString()
if ($manifest.PrivateData.PSData.Prerelease) {
   $releaseTag = "$releaseTag-$($manifest.PrivateData.PSData.Prerelease)"
}
git tag $releaseTag

# 6. Determine version and publish from signed build output
$version = (Test-ModuleManifest ./src/CharlandCustomizations/CharlandCustomizations.psd1).Version.ToString()
$publishPath = "./build/CharlandCustomizations/$version"
./Scripts/Publish-CharlandCustomizations.ps1 -Path $publishPath -Repository PSGallery -WhatIf
./Scripts/Publish-CharlandCustomizations.ps1 -Path $publishPath -Repository PSGallery

# 7. Verify
Get-Module CharlandCustomizations
Get-Command -Module CharlandCustomizations

# 8. Push branch and tags
git push
git push --tags
```

### Distribution
```powershell
# Build and create signed distribution package
./Scripts/Build-Module.ps1 -Package

# Package is in: build/packages/CharlandCustomizations-<version>.zip
# With hash file: build/packages/CharlandCustomizations-<version>.zip.sha256

# Verify package integrity
Get-FileHash build/packages/CharlandCustomizations-0.3.0.zip -Algorithm SHA256
# Compare with .sha256 file
```

## Troubleshooting

### Build Directory Not Created
Check permissions on repository directory.

### Module Not Found After Install
```powershell
# Check module path
$env:PSModulePath -split ';'

# Should include: C:\Users\<You>\Documents\PowerShell\Modules
```

### Old Version Still Loading
```powershell
# Remove all versions
Remove-Module CharlandCustomizations
Remove-Item $HOME/Documents/PowerShell/Modules/CharlandCustomizations -Recurse

# Reinstall
./Scripts/Build-Module.ps1 -Install
```

### Signing Fails
- Ensure you have a valid code signing certificate
- Certificate must not be expired
- Certificate must have private key
- Use `-SkipSigning` to bypass
