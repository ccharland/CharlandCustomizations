<#
.SYNOPSIS
    Build and optionally install the CharlandCustomizations module
.DESCRIPTION
    Validates module structure, signs files (if certificate available), and optionally installs to user module path.
    Creates a versioned build output in the 'build' directory.
.PARAMETER Install
    Install module to user's PowerShell modules directory after building
.PARAMETER SkipSigning
    Skip code signing step

.PARAMETER SkipAnalysis
    Skip PSScriptAnalyzer code quality check
.PARAMETER Clean
    Remove the build directory before building
.PARAMETER Package
    Create a distributable zip file (requires all files to be signed)
.PARAMETER InstallOnly
    Install module directly from source to versioned module path without build/sign/package steps
.PARAMETER Version
    Set the module version in the manifest before building (for example: 0.3.3)
.PARAMETER BumpVersion
    Increment the module version in the manifest before building (Major, Minor, or Patch)
.PARAMETER Prerelease
    Set the module prerelease label in the manifest (for example: beta1, rc1)
.PARAMETER ClearPrerelease
    Remove the module prerelease label from the manifest.
.PARAMETER PrepareRelease
    Ensure changelog contains an entry for the current version and print release commit/tag commands
.EXAMPLE
    ./Build-Module.ps1 -Install
    Builds, signs, and installs the module
.EXAMPLE
    ./Build-Module.ps1 -Clean
    Cleans and rebuilds without installing
.EXAMPLE
    ./Build-Module.ps1 -Package
    Builds, signs, and creates a distributable zip file
.EXAMPLE
    ./Build-Module.ps1 -BumpVersion Patch -Install
    Increments patch version, then builds, signs, and installs
.EXAMPLE
    ./Build-Module.ps1 -Version 1.0.0 -Package
    Sets version to 1.0.0, then builds, signs, and creates a package
.EXAMPLE
    ./Build-Module.ps1 -InstallOnly
    Installs current source module version without running build/sign/package steps
.EXAMPLE
    ./Build-Module.ps1 -BumpVersion Patch -PrepareRelease
    Increments patch version and prepares changelog/release commands
.EXAMPLE
    ./Build-Module.ps1 -Prerelease beta1 -PrepareRelease
    Sets prerelease label to beta1 and prepares changelog/release commands
#>
[CmdletBinding()]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'Build script uses Write-Host for real-time build progress output')]
param(
    [switch]$Install,
    [switch]$SkipSigning,
    [switch]$SkipAnalysis,
    [switch]$Clean,
    [switch]$Package,
    [switch]$InstallOnly,
    [version]$Version,
    [ValidateSet('Major', 'Minor', 'Patch')]
    [string]$BumpVersion,
    [string]$Prerelease,
    [switch]$ClearPrerelease,
    [switch]$PrepareRelease
)

$ErrorActionPreference = 'Stop'
$ModuleName = 'CharlandCustomizations'
$SourcePath = Join-Path (Split-Path $PSScriptRoot -Parent) "src/$ModuleName"
Write-Verbose "Sourcepath: $SourcePath"
$ManifestPath = Join-Path $SourcePath "$ModuleName.psd1"
Write-Verbose "Manifest Path: $ManifestPath"
$BuildRoot = Join-Path (Split-Path $PSScriptRoot -Parent) "build"
Write-Verbose "Buildroot: $BuildRoot"
$ChangelogPath = Join-Path (Split-Path $PSScriptRoot -Parent) "docs/CHANGELOG.md"
$didBuild = $false
$performInstall = $Install -or $InstallOnly

Write-Output "Building $ModuleName module..."

if ($InstallOnly -and $Package) {
    throw "-InstallOnly cannot be used with -Package."
}
if ($InstallOnly -and $Clean) {
    throw "-InstallOnly cannot be used with -Clean."
}
if ($InstallOnly -and $SkipSigning) {
    Write-Warning "-SkipSigning has no effect with -InstallOnly."
}

# Clean build directory if requested
if ($Clean -and (Test-Path $BuildRoot)) {
    Write-Output "Cleaning build directory..."
    Remove-Item $BuildRoot -Recurse -Force
}

# Validate source module structure
Write-Host "Validating source module structure..." -ForegroundColor Yellow
if (-not (Test-Path $ManifestPath)) {
    throw "Module manifest not found at $ManifestPath"
}

if ($PSBoundParameters.ContainsKey('Version') -and $PSBoundParameters.ContainsKey('BumpVersion')) {
    throw "Specify either -Version or -BumpVersion, not both."
}

if ($PSBoundParameters.ContainsKey('Prerelease') -and $ClearPrerelease) {
    throw "Specify either -Prerelease or -ClearPrerelease, not both."
}

# Optionally update the module version in the manifest before build.
if ($PSBoundParameters.ContainsKey('Version') -or
    $PSBoundParameters.ContainsKey('BumpVersion') -or
    $PSBoundParameters.ContainsKey('Prerelease') -or
    $ClearPrerelease) {

    $manifestData = Import-PowerShellDataFile -Path $ManifestPath
    $currentVersion = [version]$manifestData.ModuleVersion
    $currentPrerelease = $manifestData.PrivateData.PSData.Prerelease
    $targetVersion = $currentVersion
    $targetPrerelease = $currentPrerelease

    if ($PSBoundParameters.ContainsKey('Version')) {
        $targetVersion = $Version
        Write-Output "Updating module version: $currentVersion -> $targetVersion"
    }
    else {
        switch ($BumpVersion) {
            'Major' { $targetVersion = [version]::new($currentVersion.Major + 1, 0, 0) }
            'Minor' { $targetVersion = [version]::new($currentVersion.Major, $currentVersion.Minor + 1, 0) }
            'Patch' { $targetVersion = [version]::new($currentVersion.Major, $currentVersion.Minor, $currentVersion.Build + 1) }
        }
        Write-Output "Bumping module version ($BumpVersion): $currentVersion -> $targetVersion"
    }

    if ($PSBoundParameters.ContainsKey('Prerelease')) {
        $targetPrerelease = $Prerelease
        Write-Output "Setting prerelease label: '$currentPrerelease' -> '$targetPrerelease'"
    }
    elseif ($ClearPrerelease) {
        $targetPrerelease = $null
        Write-Output "Clearing prerelease label: '$currentPrerelease' -> ''"
    }

    $updateManifestParams = @{
        Path          = $ManifestPath
        ModuleVersion = $targetVersion
        ErrorAction   = 'Stop'
    }

    if ($targetPrerelease) {
        $updateManifestParams.Prerelease = $targetPrerelease
    }

    Update-ModuleManifest @updateManifestParams
}

if (-not $InstallOnly) {
    # Run PSScriptAnalyzer if available
    if ($SkipAnalysis) {
        Write-Host "Skipping PSScriptAnalyzer (SkipAnalysis flag set)" -ForegroundColor Yellow
    }
    elseif (Get-Module -ListAvailable -Name PSScriptAnalyzer) {
        Write-Host "Running PSScriptAnalyzer..." -ForegroundColor Yellow
        Import-Module PSScriptAnalyzer
        Write-Verbose "Path: $($SourcePath)"
        $analysisResults = Invoke-ScriptAnalyzer -Path $SourcePath -Recurse -Severity Error, Warning

        if ($analysisResults) {
            Write-Warning "PSScriptAnalyzer found issues:"
            $analysisResults | Format-Table -Property Severity, RuleName, ScriptName, Line, Message -AutoSize
            $errors = $analysisResults | Where-Object Severity -eq 'Error'
            if ($errors) {
                Write-Error "Build failed: PSScriptAnalyzer found $($errors.Count) error(s)"
                Write-Host "Run './Test-CodeQuality.ps1' for detailed analysis" -ForegroundColor Yellow
                exit 1
            }

            $warnings = $analysisResults | Where-Object Severity -eq 'Warning'
            if ($warnings) {
                Write-Warning "Found $($warnings.Count) warning(s) - consider fixing before release"
            }
        }
        else {
            Write-Host "  PSScriptAnalyzer: No issues found" -ForegroundColor Green
        }
    }
    else {
        Write-Host "  PSScriptAnalyzer not installed - skipping code analysis" -ForegroundColor Yellow
        Write-Host "  Install with: Install-Module PSScriptAnalyzer" -ForegroundColor Yellow
    }
}
else {
    Write-Host "Install-only mode: skipping PSScriptAnalyzer/build/sign/package steps" -ForegroundColor Yellow
}

# Test manifest and get version
Write-Host "Reading module manifest..." -ForegroundColor Yellow
$manifest = Test-ModuleManifest -Path $ManifestPath -ErrorAction Stop
$version = $manifest.Version.ToString()
$manifestData = Import-PowerShellDataFile -Path $ManifestPath
$prerelease = $manifestData.PrivateData.PSData.Prerelease
$releaseTag = $version
if ($prerelease) {
    $releaseTag = "$version-$prerelease"
}
$artifactVersion = $releaseTag
Write-Output "  Version: $version"
if ($prerelease) {
    Write-Output "  Prerelease: $prerelease"
}
Write-Output "  GUID: $($manifest.Guid)"

if (-not $InstallOnly) {
    # Create versioned build directory
    $BuildPath = Join-Path $BuildRoot "$ModuleName\$artifactVersion"
    Write-Output "Creating build directory: $BuildPath"
    if (Test-Path $BuildPath) {
        Remove-Item $BuildPath -Recurse -Force
    }
    New-Item -ItemType Directory -Path $BuildPath -Force | Out-Null

    # Copy module files to build directory
    Write-Output "Copying module files to build directory..."
    Copy-Item -Path "$SourcePath\*" -Destination $BuildPath -Recurse -Force
    Write-Output "  Copied to: $BuildPath"

    # Validate all files declared in the manifest FileList exist in the build output
    Write-Host "Validating manifest FileList..." -ForegroundColor Yellow
    $manifestData = Import-PowerShellDataFile -Path $ManifestPath
    $missingFiles = @()

    # Check RootModule
    if ($manifestData.RootModule) {
        $rootModulePath = Join-Path $BuildPath $manifestData.RootModule
        if (-not (Test-Path $rootModulePath)) {
            $missingFiles += "RootModule: $($manifestData.RootModule)"
        }
    }

    # Check NestedModules
    if ($manifestData.NestedModules) {
        foreach ($nested in $manifestData.NestedModules) {
            $nestedPath = Join-Path $BuildPath ($nested -replace '^\.\/', '' -replace '^\.\\', '')
            if (-not (Test-Path $nestedPath)) {
                $missingFiles += "NestedModule: $nested"
            }
        }
    }

    # Check FileList
    if ($manifestData.FileList) {
        foreach ($file in $manifestData.FileList) {
            $filePath = Join-Path $BuildPath ($file -replace '^\.\/', '' -replace '^\.\\', '')
            if (-not (Test-Path $filePath)) {
                $missingFiles += "FileList: $file"
            }
        }
    }

    if ($missingFiles.Count -gt 0) {
        Write-Error "Build validation failed - files declared in manifest are missing from build output:"
        $missingFiles | ForEach-Object { Write-Error "  $_" }
        exit 1
    }
    else {
        $totalChecked = @($manifestData.RootModule).Count +
        @($manifestData.NestedModules).Count +
        @($manifestData.FileList).Count
        Write-Host "  All $totalChecked manifest-declared files present in build output" -ForegroundColor Green
    }

    # Test the built module
    $builtManifestPath = Join-Path $BuildPath "$ModuleName.psd1"
    Write-Output "Testing built module..."
    Remove-Module $ModuleName -ErrorAction SilentlyContinue
    Import-Module $builtManifestPath -Force -ErrorAction Stop
    $commands = Get-Command -Module $ModuleName
    Write-Output "  Exported $($commands.Count) functions"
    $didBuild = $true
}

# Sign files if certificate available and not skipped
$allFilesSigned = $false
if (-not $InstallOnly -and -not $SkipSigning) {
    Write-Output "Checking for code signing certificate..."
    $cert = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert |
    Where-Object { $_.NotAfter -gt (Get-Date) -and $_.HasPrivateKey } |
    Sort-Object NotAfter -Descending |
    Select-Object -First 1

    if ($cert) {
        Write-Output "  Found certificate: $($cert.Subject)"
        Write-Output "Signing built module files..."

        # Load Set-CCAuthenticodeSignature if not already available
        if (-not (Get-Command Set-CCAuthenticodeSignature -ErrorAction SilentlyContinue)) {
            . (Join-Path (Split-Path $PSScriptRoot -Parent) 'src/CharlandCustomizations/Public/Set-CCAuthenticodeSignature.ps1')
        }

        $filesToSign = Get-ChildItem -Path $BuildPath -Include *.ps1, *.psm1, *.psd1 -Recurse
        $signedCount = 0
        $failedCount = 0

        foreach ($file in $filesToSign) {
            try {
                $result = Set-CCAuthenticodeSignature -MyCert $cert -Path $file.FullName
                if ($result.Status -eq 'Valid') {
                    Write-Output "  Signed: $($file.Name)"
                    $signedCount++
                }
                else {
                    Write-Warning "Signing failed for $($file.Name): $($result.Status)"
                    $failedCount++
                }
            }
            catch {
                Write-Warning "Failed to sign $($file.Name): $_"
                $failedCount++
            }
        }

        if ($failedCount -eq 0 -and $signedCount -eq $filesToSign.Count) {
            $allFilesSigned = $true
            Write-Output "  All files signed successfully ($signedCount files)"
        }
        else {
            Write-Warning "Some files failed to sign: $failedCount failed, $signedCount succeeded"
        }
    }
    else {
        Write-Output "  No code signing certificate found, skipping signing"
    }
}
elseif (-not $InstallOnly) {
    Write-Output "Skipping code signing (SkipSigning flag set)"
}

# Create distribution package if requested
if (-not $InstallOnly -and $Package) {
    Write-Output "`nCreating distribution package..."

    # Verify all files are signed
    if (-not $allFilesSigned) {
        Write-Error "Cannot create package: Not all files are signed. Run without -SkipSigning to sign files."
        exit 1
    }

    # Verify signatures
    Write-Output "Verifying signatures..."
    $filesToVerify = Get-ChildItem -Path $BuildPath -Include *.ps1, *.psm1, *.psd1 -Recurse
    $invalidSignatures = @()

    foreach ($file in $filesToVerify) {
        $sig = Get-AuthenticodeSignature -FilePath $file.FullName
        if ($sig.Status -ne 'Valid') {
            $invalidSignatures += [PSCustomObject]@{
                File   = $file.Name
                Status = $sig.Status
            }
        }
    }

    if ($invalidSignatures.Count -gt 0) {
        Write-Error "Cannot create package: Some files have invalid signatures:"
        $invalidSignatures | Format-Table -AutoSize
        exit 1
    }

    Write-Output "  All signatures verified"

    # Create package directory
    $packageDir = Join-Path $BuildRoot "packages"
    if (-not (Test-Path $packageDir)) {
        New-Item -ItemType Directory -Path $packageDir -Force | Out-Null
    }

    # Create zip file
    $zipName = "$ModuleName-$artifactVersion.zip"
    $zipPath = Join-Path $packageDir $zipName

    if (Test-Path $zipPath) {
        Remove-Item $zipPath -Force
    }

    # delete .gitkeep before making archive
    Get-ChildItem -Path $packageDir -Filter .gitkeep -Recurse -File | Remove-Item


    Write-Output "Creating package: $zipName"
    Compress-Archive -Path $BuildPath -DestinationPath $zipPath -CompressionLevel Optimal

    # Calculate hash
    $hash = Get-FileHash -Path $zipPath -Algorithm SHA256
    $hashFile = "$zipPath.sha256"
    "$($hash.Hash)  $zipName" | Set-Content -Path $hashFile -Encoding ASCII

    Write-Output "  Package created: $zipPath"
    Write-Output "  SHA256: $($hash.Hash)"
    Write-Output "  Hash file: $hashFile"

    # Create README for package
    $readmePath = Join-Path $packageDir "README-$artifactVersion.txt"
    $readmeContent = @"
$ModuleName v$artifactVersion
Distribution Package

Created: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
SHA256: $($hash.Hash)

Installation:
1. Extract $zipName
2. Copy the extracted folder to: `$HOME\Documents\PowerShell\Modules\
3. Import-Module $ModuleName

Verification:
- All files are digitally signed
- Verify hash: Get-FileHash $zipName -Algorithm SHA256
- Expected: $($hash.Hash)

Requirements:
- PowerShell 7.2 or later
- AWS.Tools.Common, AWSPowerShell.NetCore, or AWSPowerShell

For more information, see the module documentation.
"@

    Set-Content -Path $readmePath -Value $readmeContent -Encoding UTF8
    Write-Output "  Package README: $readmePath"
}

# Install if requested
if ($performInstall) {
    Write-Output "`nInstalling module..."
    # Find the user-scoped module directory from PSModulePath
    # On Windows: ~/Documents/PowerShell/Modules
    # On macOS/Linux: ~/.local/share/powershell/Modules
    $userModulePath = ($env:PSModulePath -split [System.IO.Path]::PathSeparator) |
    Where-Object { $_ -like "*$HOME*" -and $_ -notlike "*$PSHOME*" } |
    Select-Object -First 1

    if (-not $userModulePath) {
        throw "Could not determine user module path from `$env:PSModulePath"
    }

    $installBasePath = Join-Path $userModulePath $ModuleName
    $installPath = Join-Path $installBasePath $artifactVersion

    # Remove old versions if they exist
    if (Test-Path $installBasePath) {
        Write-Output "  Removing existing installations..."
        Get-ChildItem $installBasePath -Directory | ForEach-Object {
            Write-Output "    Removing version: $($_.Name)"
            Remove-Item $_.FullName -Recurse -Force
        }
    }

    # Create base directory if needed
    if (-not (Test-Path $installBasePath)) {
        New-Item -ItemType Directory -Path $installBasePath -Force | Out-Null
    }

    if ($InstallOnly) {
        Write-Output "  Install-only: copying source module files..."
        New-Item -ItemType Directory -Path $installPath -Force | Out-Null
        Copy-Item -Path "$SourcePath\*" -Destination $installPath -Recurse -Force
    }
    else {
        # Copy built module to install location
        Copy-Item -Path $BuildPath -Destination $installBasePath -Recurse -Force
    }
    Write-Output "  Installed to: $installPath"

    # Verify installation
    Remove-Module $ModuleName -ErrorAction SilentlyContinue
    Import-Module (Join-Path $installPath "$ModuleName.psd1") -Force
    $installedModule = Get-Module $ModuleName
    Write-Output "  Module imported successfully: v$($installedModule.Version)"
}

if ($PrepareRelease) {
    if (Test-Path -Path $ChangelogPath) {
        $changelogContent = Get-Content -Path $ChangelogPath -Raw
        $entryPattern = "(?m)^## \[$([regex]::Escape($version))\]\s+-\s+"

        if ($changelogContent -notmatch $entryPattern) {
            $newEntry = @"
## [$version] - $(Get-Date -Format 'yyyy-MM-dd')

### Added
-

### Changed
-

### Fixed
-

"@
            $firstReleaseMatch = [regex]::Match($changelogContent, "(?m)^## \[")
            if ($firstReleaseMatch.Success) {
                $before = $changelogContent.Substring(0, $firstReleaseMatch.Index)
                $after = $changelogContent.Substring($firstReleaseMatch.Index)
                $updatedChangelog = $before + $newEntry + $after
            }
            else {
                $updatedChangelog = $changelogContent.TrimEnd() + "`r`n`r`n" + $newEntry
            }

            Set-Content -Path $ChangelogPath -Value $updatedChangelog -Encoding UTF8
            Write-Output "Added changelog template entry for v${$version}: $ChangelogPath"
        }
        else {
            Write-Output "Changelog already contains an entry for v${$version}"
        }
    }
    else {
        Write-Warning "Changelog not found: $ChangelogPath"
    }
}

Write-Output "`nBuild complete!"
Write-Output "Module: $ModuleName v$version"
if ($didBuild) {
    Write-Output "Build output: $BuildPath"
}
else {
    Write-Output "Mode: Install-only (no build output created)"
}

if ($Package) {
    Write-Output "Distribution package: build/packages/$ModuleName-$artifactVersion.zip"
}

if (-not $performInstall) {
    Write-Output "`nTo install, run: ./Build-Module.ps1 -Install"
}
if (-not $InstallOnly -and -not $Package -and $allFilesSigned) {
    Write-Output "To create distribution package, run: ./Build-Module.ps1 -Package"
}
if (-not $InstallOnly) {
    Write-Output "To clean and rebuild, run: ./Build-Module.ps1 -Clean"
}

Write-Output "`nRelease commands (for $releaseTag):"
Write-Output "  git add src/$ModuleName/$ModuleName.psd1 docs/CHANGELOG.md"
Write-Output "  git commit -m \"Release $releaseTag\""
Write-Output "  git tag $releaseTag"
if (-not $PrepareRelease) {
    Write-Output "Optional: add changelog entry automatically with ./Build-Module.ps1 -PrepareRelease"
}
# SIG # Begin signature block
# MIImXQYJKoZIhvcNAQcCoIImTjCCJkoCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBFoMhwm+dSOJiS
# bwRXub22LkokmQuxgqVIlwYlIqOggKCCH3IwggYUMIID/KADAgECAhB6I67aU2mW
# D5HIPlz0x+M/MA0GCSqGSIb3DQEBDAUAMFcxCzAJBgNVBAYTAkdCMRgwFgYDVQQK
# Ew9TZWN0aWdvIExpbWl0ZWQxLjAsBgNVBAMTJVNlY3RpZ28gUHVibGljIFRpbWUg
# U3RhbXBpbmcgUm9vdCBSNDYwHhcNMjEwMzIyMDAwMDAwWhcNMzYwMzIxMjM1OTU5
# WjBVMQswCQYDVQQGEwJHQjEYMBYGA1UEChMPU2VjdGlnbyBMaW1pdGVkMSwwKgYD
# VQQDEyNTZWN0aWdvIFB1YmxpYyBUaW1lIFN0YW1waW5nIENBIFIzNjCCAaIwDQYJ
# KoZIhvcNAQEBBQADggGPADCCAYoCggGBAM2Y2ENBq26CK+z2M34mNOSJjNPvIhKA
# VD7vJq+MDoGD46IiM+b83+3ecLvBhStSVjeYXIjfa3ajoW3cS3ElcJzkyZlBnwDE
# JuHlzpbN4kMH2qRBVrjrGJgSlzzUqcGQBaCxpectRGhhnOSwcjPMI3G0hedv2eNm
# GiUbD12OeORN0ADzdpsQ4dDi6M4YhoGE9cbY11XxM2AVZn0GiOUC9+XE0wI7CQKf
# OUfigLDn7i/WeyxZ43XLj5GVo7LDBExSLnh+va8WxTlA+uBvq1KO8RSHUQLgzb1g
# bL9Ihgzxmkdp2ZWNuLc+XyEmJNbD2OIIq/fWlwBp6KNL19zpHsODLIsgZ+WZ1AzC
# s1HEK6VWrxmnKyJJg2Lv23DlEdZlQSGdF+z+Gyn9/CRezKe7WNyxRf4e4bwUtrYE
# 2F5Q+05yDD68clwnweckKtxRaF0VzN/w76kOLIaFVhf5sMM/caEZLtOYqYadtn03
# 4ykSFaZuIBU9uCSrKRKTPJhWvXk4CllgrwIDAQABo4IBXDCCAVgwHwYDVR0jBBgw
# FoAU9ndq3T/9ARP/FqFsggIv0Ao9FCUwHQYDVR0OBBYEFF9Y7UwxeqJhQo1SgLqz
# YZcZojKbMA4GA1UdDwEB/wQEAwIBhjASBgNVHRMBAf8ECDAGAQH/AgEAMBMGA1Ud
# JQQMMAoGCCsGAQUFBwMIMBEGA1UdIAQKMAgwBgYEVR0gADBMBgNVHR8ERTBDMEGg
# P6A9hjtodHRwOi8vY3JsLnNlY3RpZ28uY29tL1NlY3RpZ29QdWJsaWNUaW1lU3Rh
# bXBpbmdSb290UjQ2LmNybDB8BggrBgEFBQcBAQRwMG4wRwYIKwYBBQUHMAKGO2h0
# dHA6Ly9jcnQuc2VjdGlnby5jb20vU2VjdGlnb1B1YmxpY1RpbWVTdGFtcGluZ1Jv
# b3RSNDYucDdjMCMGCCsGAQUFBzABhhdodHRwOi8vb2NzcC5zZWN0aWdvLmNvbTAN
# BgkqhkiG9w0BAQwFAAOCAgEAEtd7IK0ONVgMnoEdJVj9TC1ndK/HYiYh9lVUacah
# RoZ2W2hfiEOyQExnHk1jkvpIJzAMxmEc6ZvIyHI5UkPCbXKspioYMdbOnBWQUn73
# 3qMooBfIghpR/klUqNxx6/fDXqY0hSU1OSkkSivt51UlmJElUICZYBodzD3M/SFj
# eCP59anwxs6hwj1mfvzG+b1coYGnqsSz2wSKr+nDO+Db8qNcTbJZRAiSazr7KyUJ
# Go1c+MScGfG5QHV+bps8BX5Oyv9Ct36Y4Il6ajTqV2ifikkVtB3RNBUgwu/mSiSU
# ice/Jp/q8BMk/gN8+0rNIE+QqU63JoVMCMPY2752LmESsRVVoypJVt8/N3qQ1c6F
# ibbcRabo3azZkcIdWGVSAdoLgAIxEKBeNh9AQO1gQrnh1TA8ldXuJzPSuALOz1Uj
# b0PCyNVkWk7hkhVHfcvBfI8NtgWQupiaAeNHe0pWSGH2opXZYKYG4Lbukg7HpNi/
# KqJhue2Keak6qH9A8CeEOB7Eob0Zf+fU+CCQaL0cJqlmnx9HCDxF+3BLbUufrV64
# EbTI40zqegPZdA+sXCmbcZy6okx/SjwsusWRItFA3DE8MORZeFb6BmzBtqKJ7l93
# 9bbKBy2jvxcJI98Va95Q5JnlKor3m0E7xpMeYRriWklUPsetMSf2NvUQa/E5vVye
# fQIwggYaMIIEAqADAgECAhBiHW0MUgGeO5B5FSCJIRwKMA0GCSqGSIb3DQEBDAUA
# MFYxCzAJBgNVBAYTAkdCMRgwFgYDVQQKEw9TZWN0aWdvIExpbWl0ZWQxLTArBgNV
# BAMTJFNlY3RpZ28gUHVibGljIENvZGUgU2lnbmluZyBSb290IFI0NjAeFw0yMTAz
# MjIwMDAwMDBaFw0zNjAzMjEyMzU5NTlaMFQxCzAJBgNVBAYTAkdCMRgwFgYDVQQK
# Ew9TZWN0aWdvIExpbWl0ZWQxKzApBgNVBAMTIlNlY3RpZ28gUHVibGljIENvZGUg
# U2lnbmluZyBDQSBSMzYwggGiMA0GCSqGSIb3DQEBAQUAA4IBjwAwggGKAoIBgQCb
# K51T+jU/jmAGQ2rAz/V/9shTUxjIztNsfvxYB5UXeWUzCxEeAEZGbEN4QMgCsJLZ
# UKhWThj/yPqy0iSZhXkZ6Pg2A2NVDgFigOMYzB2OKhdqfWGVoYW3haT29PSTahYk
# wmMv0b/83nbeECbiMXhSOtbam+/36F09fy1tsB8je/RV0mIk8XL/tfCK6cPuYHE2
# 15wzrK0h1SWHTxPbPuYkRdkP05ZwmRmTnAO5/arnY83jeNzhP06ShdnRqtZlV59+
# 8yv+KIhE5ILMqgOZYAENHNX9SJDm+qxp4VqpB3MV/h53yl41aHU5pledi9lCBbH9
# JeIkNFICiVHNkRmq4TpxtwfvjsUedyz8rNyfQJy/aOs5b4s+ac7IH60B+Ja7TVM+
# EKv1WuTGwcLmoU3FpOFMbmPj8pz44MPZ1f9+YEQIQty/NQd/2yGgW+ufflcZ/ZE9
# o1M7a5Jnqf2i2/uMSWymR8r2oQBMdlyh2n5HirY4jKnFH/9gRvd+QOfdRrJZb1sC
# AwEAAaOCAWQwggFgMB8GA1UdIwQYMBaAFDLrkpr/NZZILyhAQnAgNpFcF4XmMB0G
# A1UdDgQWBBQPKssghyi47G9IritUpimqF6TNDDAOBgNVHQ8BAf8EBAMCAYYwEgYD
# VR0TAQH/BAgwBgEB/wIBADATBgNVHSUEDDAKBggrBgEFBQcDAzAbBgNVHSAEFDAS
# MAYGBFUdIAAwCAYGZ4EMAQQBMEsGA1UdHwREMEIwQKA+oDyGOmh0dHA6Ly9jcmwu
# c2VjdGlnby5jb20vU2VjdGlnb1B1YmxpY0NvZGVTaWduaW5nUm9vdFI0Ni5jcmww
# ewYIKwYBBQUHAQEEbzBtMEYGCCsGAQUFBzAChjpodHRwOi8vY3J0LnNlY3RpZ28u
# Y29tL1NlY3RpZ29QdWJsaWNDb2RlU2lnbmluZ1Jvb3RSNDYucDdjMCMGCCsGAQUF
# BzABhhdodHRwOi8vb2NzcC5zZWN0aWdvLmNvbTANBgkqhkiG9w0BAQwFAAOCAgEA
# Bv+C4XdjNm57oRUgmxP/BP6YdURhw1aVcdGRP4Wh60BAscjW4HL9hcpkOTz5jUug
# 2oeunbYAowbFC2AKK+cMcXIBD0ZdOaWTsyNyBBsMLHqafvIhrCymlaS98+QpoBCy
# KppP0OcxYEdU0hpsaqBBIZOtBajjcw5+w/KeFvPYfLF/ldYpmlG+vd0xqlqd099i
# ChnyIMvY5HexjO2AmtsbpVn0OhNcWbWDRF/3sBp6fWXhz7DcML4iTAWS+MVXeNLj
# 1lJziVKEoroGs9Mlizg0bUMbOalOhOfCipnx8CaLZeVme5yELg09Jlo8BMe80jO3
# 7PU8ejfkP9/uPak7VLwELKxAMcJszkyeiaerlphwoKx1uHRzNyE6bxuSKcutisqm
# KL5OTunAvtONEoteSiabkPVSZ2z76mKnzAfZxCl/3dq3dUNw4rg3sTCggkHSRqTq
# lLMS7gjrhTqBmzu1L90Y1KWN/Y5JKdGvspbOrTfOXyXvmPL6E52z1NZJ6ctuMFBQ
# ZH3pwWvqURR8AgQdULUvrxjUYbHHj95Ejza63zdrEcxWLDX6xWls/GDnVNueKjWU
# H3fTv1Y8Wdho698YADR7TNx8X8z2Bev6SivBBOHY+uqiirZtg0y9ShQoPzmCcn63
# Syatatvx157YK9hlcPmVoa1oDE5/L9Uo2bC5a4CH2RwwggZMMIIEtKADAgECAhAV
# VO/doV4MRRGuXmkecKnEMA0GCSqGSIb3DQEBDAUAMFQxCzAJBgNVBAYTAkdCMRgw
# FgYDVQQKEw9TZWN0aWdvIExpbWl0ZWQxKzApBgNVBAMTIlNlY3RpZ28gUHVibGlj
# IENvZGUgU2lnbmluZyBDQSBSMzYwHhcNMjMwODA5MDAwMDAwWhcNMjYwODA4MjM1
# OTU5WjBjMQswCQYDVQQGEwJVUzEWMBQGA1UECAwNTmV3IEhhbXBzaGlyZTEdMBsG
# A1UECgwUQ2hyaXN0b3BoZXIgQ2hhcmxhbmQxHTAbBgNVBAMMFENocmlzdG9waGVy
# IENoYXJsYW5kMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAwLQAcUKQ
# zYs2WJY+W2fl+/1PzX3vsFwK/W9sj1RXRLBsQjsTCYRu+jRPEZSVzL/K4L877Wxb
# 69/ye88/RrWS0d6LUyohl0OgJwgRBXBsDIcpt3hTv7GRLAFvjzcCOvK6qk+kjf+b
# xqYSUOxfl/XDK0QvM3KgWbq2IeNHoMwvAXVFBcZnRPXp1FkcHGKf+nNwxP6VGWti
# RrhIj99q0R4iwOQaQLRY8pe8m1wn/gwFRai1F1f/Q2EMSyvbgf7kYpFNHJK17LZR
# 9J/G7P8h4QFQZJdMU6C4lRT+Lk2jEDF4elKF5c7DFjfMv2zd0jf3/2vOhaycGna9
# puKwQUvtwtrmcCwOI5EXBIVBcFVS8xD6eeREvzjZXiuS83quzwxVVjNBQ2f/nuK5
# 4huEBbNQQeNjSkMdjyr5S0Xwf8Pic5NA4ggLUWuv2XYqTTMtXHQPZ41noEJM+LSB
# ulBatGT98Tu0kib3MH7e1vREcTG7gZDnicmY0RfrWM59txft97gXP7Vj99ed9t2/
# 9niQleiT+YXy3ZpNoqGFB3XC13mM44xEff49vRSLN/B0IonG5vDpMgtFoKpqPtUx
# /oKQWtYbmoWFZkvEBRUeJOmkEmIUQonzE7aqgk/uGtyjxsBHtJzIHojA+8fGeD0N
# XjlOM1bbT0OcpSMkhRXPqiOELViMQwHrAiUCAwEAAaOCAYkwggGFMB8GA1UdIwQY
# MBaAFA8qyyCHKLjsb0iuK1SmKaoXpM0MMB0GA1UdDgQWBBSO6WwZWwCa6iKws6LE
# 4InGvJQl3zAOBgNVHQ8BAf8EBAMCB4AwDAYDVR0TAQH/BAIwADATBgNVHSUEDDAK
# BggrBgEFBQcDAzBKBgNVHSAEQzBBMDUGDCsGAQQBsjEBAgEDAjAlMCMGCCsGAQUF
# BwIBFhdodHRwczovL3NlY3RpZ28uY29tL0NQUzAIBgZngQwBBAEwSQYDVR0fBEIw
# QDA+oDygOoY4aHR0cDovL2NybC5zZWN0aWdvLmNvbS9TZWN0aWdvUHVibGljQ29k
# ZVNpZ25pbmdDQVIzNi5jcmwweQYIKwYBBQUHAQEEbTBrMEQGCCsGAQUFBzAChjho
# dHRwOi8vY3J0LnNlY3RpZ28uY29tL1NlY3RpZ29QdWJsaWNDb2RlU2lnbmluZ0NB
# UjM2LmNydDAjBggrBgEFBQcwAYYXaHR0cDovL29jc3Auc2VjdGlnby5jb20wDQYJ
# KoZIhvcNAQEMBQADggGBAENPYZO6JkhXuprRcjFErvAggFDfB4bJmvHwydUUq8EE
# dDkvVvS+SnqpaL+Nw5FY/X5GnIXfWKYvQJFY1o/bskqLBSH96jOk+wMWZ2LqfuyE
# uW4OZUvBtpho2E2QwcpCQQzG47c+qtENC6lITctyoOUi5481cm9VXRL0E1g/MSDO
# qpYcd32oKt6rbqLQZD89HFgkNrfh3a4wq2O8ljai9gvQJnYV4588DGI4quzv81b6
# mGDx9ku9zHhtvI19C1L+oQddqFFUViSwUUiNrBO7aA5iFwr1vQPkiP40Zd6fSSQA
# jrRnUI/kbK9oD2l1i/Vi9hfQ8SLarLPhW0M0qaut175+RJKlwuusUZADtgYVWcrm
# Mxy20RMCUZA2bnTWXjb4pVfHUyKPU7dpM+8gG/tUPBZegMWrzWqctSPQhdREpkLT
# MCm5E/o4ZUGNE0uo+twbGMGEyPPmjsFnIKLAqN2rHMI1Fz9pR+qMdixl+/mG/ElS
# JqGSDVArmZLn1IYhr4vQ8DCCBmIwggTKoAMCAQICEQCkKTtuHt3XpzQIh616Trck
# MA0GCSqGSIb3DQEBDAUAMFUxCzAJBgNVBAYTAkdCMRgwFgYDVQQKEw9TZWN0aWdv
# IExpbWl0ZWQxLDAqBgNVBAMTI1NlY3RpZ28gUHVibGljIFRpbWUgU3RhbXBpbmcg
# Q0EgUjM2MB4XDTI1MDMyNzAwMDAwMFoXDTM2MDMyMTIzNTk1OVowcjELMAkGA1UE
# BhMCR0IxFzAVBgNVBAgTDldlc3QgWW9ya3NoaXJlMRgwFgYDVQQKEw9TZWN0aWdv
# IExpbWl0ZWQxMDAuBgNVBAMTJ1NlY3RpZ28gUHVibGljIFRpbWUgU3RhbXBpbmcg
# U2lnbmVyIFIzNjCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBANOElfRu
# pFN48j0QS3gSBzzclIFTZ2Gsn7BjsmBF659/kpA2Ey7NXK3MP6JdrMBNU8wdmkf+
# SSIyjX++UAYWtg3Y/uDRDyg8RxHeHRJ+0U1jHEyH5uPdk1ttiPC3x/gOxIc9P7Gn
# 3OgW7DQc4x07exZ4DX4XyaGDq5LoEmk/BdCM1IelVMKB3WA6YpZ/XYdJ9JueOXeQ
# ObSQ/dohQCGyh0FhmwkDWKZaqQBWrBwZ++zqlt+z/QYTgEnZo6dyIo2IhXXANFkC
# HutL8765NBxvolXMFWY8/reTnFxk3MajgM5NX6wzWdWsPJxYRhLxtJLSUJJ5yWRN
# w+NBqH1ezvFs4GgJ2ZqFJ+Dwqbx9+rw+F2gBdgo4j7CVomP49sS7CbqsdybbiOGp
# B9DJhs5QVMpYV73TVV3IwLiBHBECrTgUfZVOMF0KSEq2zk/LsfvehswavE3W4aBX
# JmGjgWSpcDz+6TqeTM8f1DIcgQPdz0IYgnT3yFTgiDbFGOFNt6eCidxdR6j9x+kp
# cN5RwApy4pRhE10YOV/xafBvKpRuWPjOPWRBlKdm53kS2aMh08spx7xSEqXn4QQl
# dCnUWRz3Lki+TgBlpwYwJUbR77DAayNwAANE7taBrz2v+MnnogMrvvct0iwvfIA1
# W8kp155Lo44SIfqGmrbJP6Mn+Udr3MR2oWozAgMBAAGjggGOMIIBijAfBgNVHSME
# GDAWgBRfWO1MMXqiYUKNUoC6s2GXGaIymzAdBgNVHQ4EFgQUiGGMoSo3ZIEoYKGb
# MdCM/SwCzk8wDgYDVR0PAQH/BAQDAgbAMAwGA1UdEwEB/wQCMAAwFgYDVR0lAQH/
# BAwwCgYIKwYBBQUHAwgwSgYDVR0gBEMwQTA1BgwrBgEEAbIxAQIBAwgwJTAjBggr
# BgEFBQcCARYXaHR0cHM6Ly9zZWN0aWdvLmNvbS9DUFMwCAYGZ4EMAQQCMEoGA1Ud
# HwRDMEEwP6A9oDuGOWh0dHA6Ly9jcmwuc2VjdGlnby5jb20vU2VjdGlnb1B1Ymxp
# Y1RpbWVTdGFtcGluZ0NBUjM2LmNybDB6BggrBgEFBQcBAQRuMGwwRQYIKwYBBQUH
# MAKGOWh0dHA6Ly9jcnQuc2VjdGlnby5jb20vU2VjdGlnb1B1YmxpY1RpbWVTdGFt
# cGluZ0NBUjM2LmNydDAjBggrBgEFBQcwAYYXaHR0cDovL29jc3Auc2VjdGlnby5j
# b20wDQYJKoZIhvcNAQEMBQADggGBAAKBPqSGclEh+WWpLj1SiuHlm8xLE0SThI2y
# Luq+75s11y6SceBchpnKpxWaGtXc8dya1Aq3RuW//y3wMThsvT4fSba2AoSWlR67
# rA4fTYGMIhgzocsids0ct/pHaocLVJSwnTYxY2pE0hPoZAvRebctbsTqENmZHyOV
# jOFlwN2R3DRweFeNs4uyZN5LRJ5EnVYlcTOq3bl1tI5poru9WaQRWQ4eynXp7Pj0
# Fz4DKr86HYECRJMWiDjeV0QqAcQMFsIjJtrYTw7mU81qf4FBc4u4swphLeKRNyn9
# DDrd3HIMJ+CpdhSHEGleeZ5I79YDg3B3A/fmVY2GaMik1Vm+FajEMv4/EN2mmHf4
# zkOuhYZNzVm4NrWJeY4UAriLBOeVYODdA1GxFr1ycbcUEGlUecc4RCPgYySs4d00
# NNuicR4a9n7idJlevAJbha/arIYMEuUqTeRRbWkhJwMKmb9yEvppRudKyu1t6l21
# sIuIZqcpVH8oLWCxHS0LpDRF9Y4jijCCBoIwggRqoAMCAQICEDbCsL18Gzrno7Pd
# NsvJdWgwDQYJKoZIhvcNAQEMBQAwgYgxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpO
# ZXcgSmVyc2V5MRQwEgYDVQQHEwtKZXJzZXkgQ2l0eTEeMBwGA1UEChMVVGhlIFVT
# RVJUUlVTVCBOZXR3b3JrMS4wLAYDVQQDEyVVU0VSVHJ1c3QgUlNBIENlcnRpZmlj
# YXRpb24gQXV0aG9yaXR5MB4XDTIxMDMyMjAwMDAwMFoXDTM4MDExODIzNTk1OVow
# VzELMAkGA1UEBhMCR0IxGDAWBgNVBAoTD1NlY3RpZ28gTGltaXRlZDEuMCwGA1UE
# AxMlU2VjdGlnbyBQdWJsaWMgVGltZSBTdGFtcGluZyBSb290IFI0NjCCAiIwDQYJ
# KoZIhvcNAQEBBQADggIPADCCAgoCggIBAIid2LlFZ50d3ei5JoGaVFTAfEkFm8xa
# FQ/ZlBBEtEFAgXcUmanU5HYsyAhTXiDQkiUvpVdYqZ1uYoZEMgtHES1l1Cc6HaqZ
# zEbOOp6YiTx63ywTon434aXVydmhx7Dx4IBrAou7hNGsKioIBPy5GMN7KmgYmuu4
# f92sKKjbxqohUSfjk1mJlAjthgF7Hjx4vvyVDQGsd5KarLW5d73E3ThobSkob2SL
# 48LpUR/O627pDchxll+bTSv1gASn/hp6IuHJorEu6EopoB1CNFp/+HpTXeNARXUm
# dRMKbnXWflq+/g36NJXB35ZvxQw6zid61qmrlD/IbKJA6COw/8lFSPQwBP1ityZd
# wuCysCKZ9ZjczMqbUcLFyq6KdOpuzVDR3ZUwxDKL1wCAxgL2Mpz7eZbrb/JWXiOc
# NzDpQsmwGQ6Stw8tTCqPumhLRPb7YkzM8/6NnWH3T9ClmcGSF22LEyJYNWCHrQqY
# ubNeKolzqUbCqhSqmr/UdUeb49zYHr7ALL8bAJyPDmubNqMtuaobKASBqP84uhqc
# RY/pjnYd+V5/dcu9ieERjiRKKsxCG1t6tG9oj7liwPddXEcYGOUiWLm742st50jG
# wTzxbMpepmOP1mLnJskvZaN5e45NuzAHteORlsSuDt5t4BBRCJL+5EZnnw0ezntk
# 9R8QJyAkL6/bAgMBAAGjggEWMIIBEjAfBgNVHSMEGDAWgBRTeb9aqitKz1SA4dib
# wJ3ysgNmyzAdBgNVHQ4EFgQU9ndq3T/9ARP/FqFsggIv0Ao9FCUwDgYDVR0PAQH/
# BAQDAgGGMA8GA1UdEwEB/wQFMAMBAf8wEwYDVR0lBAwwCgYIKwYBBQUHAwgwEQYD
# VR0gBAowCDAGBgRVHSAAMFAGA1UdHwRJMEcwRaBDoEGGP2h0dHA6Ly9jcmwudXNl
# cnRydXN0LmNvbS9VU0VSVHJ1c3RSU0FDZXJ0aWZpY2F0aW9uQXV0aG9yaXR5LmNy
# bDA1BggrBgEFBQcBAQQpMCcwJQYIKwYBBQUHMAGGGWh0dHA6Ly9vY3NwLnVzZXJ0
# cnVzdC5jb20wDQYJKoZIhvcNAQEMBQADggIBAA6+ZUHtaES45aHF1BGH5Lc7JYzr
# ftrIF5Ht2PFDxKKFOct/awAEWgHQMVHol9ZLSyd/pYMbaC0IZ+XBW9xhdkkmUV/K
# bUOiL7g98M/yzRyqUOZ1/IY7Ay0YbMniIibJrPcgFp73WDnRDKtVutShPSZQZAdt
# FwXnuiWl8eFARK3PmLqEm9UsVX+55DbVIz33Mbhba0HUTEYv3yJ1fwKGxPBsP/Mg
# TECimh7eXomvMm0/GPxX2uhwCcs/YLxDnBdVVlxvDjHjO1cuwbOpkiJGHmLXXVNb
# sdXUC2xBrq9fLrfe8IBsA4hopwsCj8hTuwKXJlSTrZcPRVSccP5i9U28gZ7OMzoJ
# GlxZ5384OKm0r568Mo9TYrqzKeKZgFo0fj2/0iHbj55hc20jfxvK3mQi+H7xpbzx
# ZOFGm/yVQkpo+ffv5gdhp+hv1GDsvJOtJinJmgGbBFZIThbqI+MHvAmMmkfb3fTx
# mSkop2mSJL1Y2x/955S29Gu0gSJIkc3z30vU/iXrMpWx2tS7UVfVP+5tKuzGtgkP
# 7d/doqDrLF1u6Ci3TpjAZdeLLlRQZm867eVeXED58LXd1Dk6UvaAhvmWYXoiLz4J
# A5gPBcz7J311uahxCweNxE+xxxR3kT0WKzASo5G/PyDez6NHdIUKBeE3jDPs2ACc
# 6CkJ1Sji4PKWVT0/MYIGQTCCBj0CAQEwaDBUMQswCQYDVQQGEwJHQjEYMBYGA1UE
# ChMPU2VjdGlnbyBMaW1pdGVkMSswKQYDVQQDEyJTZWN0aWdvIFB1YmxpYyBDb2Rl
# IFNpZ25pbmcgQ0EgUjM2AhAVVO/doV4MRRGuXmkecKnEMA0GCWCGSAFlAwQCAQUA
# oIGEMBgGCisGAQQBgjcCAQwxCjAIoAKAAKECgAAwGQYJKoZIhvcNAQkDMQwGCisG
# AQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcN
# AQkEMSIEIKKOOcZpRewlEgVl4nDCmY+eeDOkyrksOmgOXiXstP/gMA0GCSqGSIb3
# DQEBAQUABIICAJroBFxIo8yZHGj4AH7wtLvyGCOH5smPsCctPiV3srv802xdwwkI
# n1Ke2y6QqT8qd2UG5OVCvC7hoyyWEspAXQRDeowipdhEmkZS1ANw9w2w7HLFPpHW
# qQ5ZCW+tBCgwPm61IXvQuDjqbpzx5rWMrbQQo4s+bXuIBUX/Ub3p9cdsMVoanpKY
# a0CdwF5dWiXfUMkTg1e6U9vr2wQ+NLSDYCBkDpox+vXF3DNOA1h+J0zgyTcCffZh
# 2GedS3TloLD1Mo3VJ6EVY3IIEEUdPpcSxceTeGqtgLGQ6XIxn4+4Lj7YRKHmFa5g
# ZYwUjdi9cRyaT0wZkDb7QYLtlP4+2J9qNeEbw24tZXEXFVs1jRvglhsB8/NMHKh3
# apFKt/kK2xxQZxUv3m9/ifrCRvm9hODin9TSzWl1Mplxu3AnXWaP6pW6ygFnM8Xu
# z1hKs04TApyiVZaaUNufw4Xio3Ct8TThCNHpEu9Zze6PSxI6eXAWVS76FZO0p8Fa
# H4CFicpeiJDWe5md40SLNqrIfZ5obYzUWlqxeStSfoDBqgqi6sNtBPdRCaaoD/Y1
# 9IhkOwQzvGvfHMF+RU1Qkc6fRSUvz2R+GCoLXx0FZ49a9GQcYoAO+qvmwaBHMtIU
# usUJIFmO/HW7gopqSlCxhBOk6F7owRRXpIN/1ABarXymXRhTsp6fS5TeoYIDIzCC
# Ax8GCSqGSIb3DQEJBjGCAxAwggMMAgEBMGowVTELMAkGA1UEBhMCR0IxGDAWBgNV
# BAoTD1NlY3RpZ28gTGltaXRlZDEsMCoGA1UEAxMjU2VjdGlnbyBQdWJsaWMgVGlt
# ZSBTdGFtcGluZyBDQSBSMzYCEQCkKTtuHt3XpzQIh616TrckMA0GCWCGSAFlAwQC
# AgUAoHkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUxDxcN
# MjYwNjExMjAxNzAyWjA/BgkqhkiG9w0BCQQxMgQwOEPW+pxi2cGfmz+qPijJCDIq
# r6D1kRBQeOKVP/HvTLM0tJG8gRWK9ZOzvO6U3AYOMA0GCSqGSIb3DQEBAQUABIIC
# AKzdXCj2S4kOS+k01Yx7rV/4LWjAfbwsJX3XgJrhFadL6+9sKaUxu9H+c0TDIWuy
# vKDAEG6JxQi6oHyFhBioS0lPju2ZBzriBlMO4EHSHaiCS9qfoS9rnvaPUQlFkTLr
# Z4/j8jZ4gFy5EuRaTO2Yz6LrmBkv9HOW5fSgOEBNDlqo77DqR0uCqy6ghaV2zsW8
# 5PIRPTTurGp1YgTIQzbUZ2fEL9InHQxQZtILtmI394yiVn5J1H/Y90Gd8Khhffwx
# iVz34g+LeVR2guP2uA0nzVXAb/U9iiYKYE2ZJzoIPfhbmOwk7nrG9VR7rSMpGC05
# muSxIp7GZumA2A37PrJvnCp7ZR0XvQGwCzLU/uj/TqpKNv7/dQVvm9dODSN3cNhH
# p0NnXVUKMBcw/R8cV562+XCQ3Fc2f/SeXCUQ9cjaTisGjpKInghTUKS+lhQHRMoL
# t8GnPHRfgKZvV6skMC5EfSjPLp5EI4z2tvHTdKchVZXO5yRMURTtXLUKo6Ffbq/4
# KUnJY65apOyzBU7HkBHi2SFdJbdM7idLMnZ3cKLS4Kg+46yCANC78VveW7EzkpHt
# 1i/8zeUwwEH4rWDrbtXPN4nyj7Syabvr+YfhlT3Bk4l3UnkMlv3VNMh0fBqI8BmC
# baWKuEs6rdHbRQQI3RwBOVxsrlJ8L4t0x0nA4YSfkGfZ
# SIG # End signature block
