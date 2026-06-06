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
# MIIr0AYJKoZIhvcNAQcCoIIrwTCCK70CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDmC5nODXuS7qqy
# iC/EApvwpvUZdJF9zcMd4OXMgwHZBKCCJOUwggVvMIIEV6ADAgECAhBI/JO0YFWU
# jTanyYqJ1pQWMA0GCSqGSIb3DQEBDAUAMHsxCzAJBgNVBAYTAkdCMRswGQYDVQQI
# DBJHcmVhdGVyIE1hbmNoZXN0ZXIxEDAOBgNVBAcMB1NhbGZvcmQxGjAYBgNVBAoM
# EUNvbW9kbyBDQSBMaW1pdGVkMSEwHwYDVQQDDBhBQUEgQ2VydGlmaWNhdGUgU2Vy
# dmljZXMwHhcNMjEwNTI1MDAwMDAwWhcNMjgxMjMxMjM1OTU5WjBWMQswCQYDVQQG
# EwJHQjEYMBYGA1UEChMPU2VjdGlnbyBMaW1pdGVkMS0wKwYDVQQDEyRTZWN0aWdv
# IFB1YmxpYyBDb2RlIFNpZ25pbmcgUm9vdCBSNDYwggIiMA0GCSqGSIb3DQEBAQUA
# A4ICDwAwggIKAoICAQCN55QSIgQkdC7/FiMCkoq2rjaFrEfUI5ErPtx94jGgUW+s
# hJHjUoq14pbe0IdjJImK/+8Skzt9u7aKvb0Ffyeba2XTpQxpsbxJOZrxbW6q5KCD
# J9qaDStQ6Utbs7hkNqR+Sj2pcaths3OzPAsM79szV+W+NDfjlxtd/R8SPYIDdub7
# P2bSlDFp+m2zNKzBenjcklDyZMeqLQSrw2rq4C+np9xu1+j/2iGrQL+57g2extme
# me/G3h+pDHazJyCh1rr9gOcB0u/rgimVcI3/uxXP/tEPNqIuTzKQdEZrRzUTdwUz
# T2MuuC3hv2WnBGsY2HH6zAjybYmZELGt2z4s5KoYsMYHAXVn3m3pY2MeNn9pib6q
# RT5uWl+PoVvLnTCGMOgDs0DGDQ84zWeoU4j6uDBl+m/H5x2xg3RpPqzEaDux5mcz
# mrYI4IAFSEDu9oJkRqj1c7AGlfJsZZ+/VVscnFcax3hGfHCqlBuCF6yH6bbJDoEc
# QNYWFyn8XJwYK+pF9e+91WdPKF4F7pBMeufG9ND8+s0+MkYTIDaKBOq3qgdGnA2T
# OglmmVhcKaO5DKYwODzQRjY1fJy67sPV+Qp2+n4FG0DKkjXp1XrRtX8ArqmQqsV/
# AZwQsRb8zG4Y3G9i/qZQp7h7uJ0VP/4gDHXIIloTlRmQAOka1cKG8eOO7F/05QID
# AQABo4IBEjCCAQ4wHwYDVR0jBBgwFoAUoBEKIz6W8Qfs4q8p74Klf9AwpLQwHQYD
# VR0OBBYEFDLrkpr/NZZILyhAQnAgNpFcF4XmMA4GA1UdDwEB/wQEAwIBhjAPBgNV
# HRMBAf8EBTADAQH/MBMGA1UdJQQMMAoGCCsGAQUFBwMDMBsGA1UdIAQUMBIwBgYE
# VR0gADAIBgZngQwBBAEwQwYDVR0fBDwwOjA4oDagNIYyaHR0cDovL2NybC5jb21v
# ZG9jYS5jb20vQUFBQ2VydGlmaWNhdGVTZXJ2aWNlcy5jcmwwNAYIKwYBBQUHAQEE
# KDAmMCQGCCsGAQUFBzABhhhodHRwOi8vb2NzcC5jb21vZG9jYS5jb20wDQYJKoZI
# hvcNAQEMBQADggEBABK/oe+LdJqYRLhpRrWrJAoMpIpnuDqBv0WKfVIHqI0fTiGF
# OaNrXi0ghr8QuK55O1PNtPvYRL4G2VxjZ9RAFodEhnIq1jIV9RKDwvnhXRFAZ/ZC
# J3LFI+ICOBpMIOLbAffNRk8monxmwFE2tokCVMf8WPtsAO7+mKYulaEMUykfb9gZ
# pk+e96wJ6l2CxouvgKe9gUhShDHaMuwV5KZMPWw5c9QLhTkg4IUaaOGnSDip0TYl
# d8GNGRbFiExmfS9jzpjoad+sPKhdnckcW67Y8y90z7h+9teDnRGWYpquRRPaf9xH
# +9/DUp/mBlXpnYzyOmJRvOwkDynUWICE5EV7WtgwggYUMIID/KADAgECAhB6I67a
# U2mWD5HIPlz0x+M/MA0GCSqGSIb3DQEBDAUAMFcxCzAJBgNVBAYTAkdCMRgwFgYD
# VQQKEw9TZWN0aWdvIExpbWl0ZWQxLjAsBgNVBAMTJVNlY3RpZ28gUHVibGljIFRp
# bWUgU3RhbXBpbmcgUm9vdCBSNDYwHhcNMjEwMzIyMDAwMDAwWhcNMzYwMzIxMjM1
# OTU5WjBVMQswCQYDVQQGEwJHQjEYMBYGA1UEChMPU2VjdGlnbyBMaW1pdGVkMSww
# KgYDVQQDEyNTZWN0aWdvIFB1YmxpYyBUaW1lIFN0YW1waW5nIENBIFIzNjCCAaIw
# DQYJKoZIhvcNAQEBBQADggGPADCCAYoCggGBAM2Y2ENBq26CK+z2M34mNOSJjNPv
# IhKAVD7vJq+MDoGD46IiM+b83+3ecLvBhStSVjeYXIjfa3ajoW3cS3ElcJzkyZlB
# nwDEJuHlzpbN4kMH2qRBVrjrGJgSlzzUqcGQBaCxpectRGhhnOSwcjPMI3G0hedv
# 2eNmGiUbD12OeORN0ADzdpsQ4dDi6M4YhoGE9cbY11XxM2AVZn0GiOUC9+XE0wI7
# CQKfOUfigLDn7i/WeyxZ43XLj5GVo7LDBExSLnh+va8WxTlA+uBvq1KO8RSHUQLg
# zb1gbL9Ihgzxmkdp2ZWNuLc+XyEmJNbD2OIIq/fWlwBp6KNL19zpHsODLIsgZ+WZ
# 1AzCs1HEK6VWrxmnKyJJg2Lv23DlEdZlQSGdF+z+Gyn9/CRezKe7WNyxRf4e4bwU
# trYE2F5Q+05yDD68clwnweckKtxRaF0VzN/w76kOLIaFVhf5sMM/caEZLtOYqYad
# tn034ykSFaZuIBU9uCSrKRKTPJhWvXk4CllgrwIDAQABo4IBXDCCAVgwHwYDVR0j
# BBgwFoAU9ndq3T/9ARP/FqFsggIv0Ao9FCUwHQYDVR0OBBYEFF9Y7UwxeqJhQo1S
# gLqzYZcZojKbMA4GA1UdDwEB/wQEAwIBhjASBgNVHRMBAf8ECDAGAQH/AgEAMBMG
# A1UdJQQMMAoGCCsGAQUFBwMIMBEGA1UdIAQKMAgwBgYEVR0gADBMBgNVHR8ERTBD
# MEGgP6A9hjtodHRwOi8vY3JsLnNlY3RpZ28uY29tL1NlY3RpZ29QdWJsaWNUaW1l
# U3RhbXBpbmdSb290UjQ2LmNybDB8BggrBgEFBQcBAQRwMG4wRwYIKwYBBQUHMAKG
# O2h0dHA6Ly9jcnQuc2VjdGlnby5jb20vU2VjdGlnb1B1YmxpY1RpbWVTdGFtcGlu
# Z1Jvb3RSNDYucDdjMCMGCCsGAQUFBzABhhdodHRwOi8vb2NzcC5zZWN0aWdvLmNv
# bTANBgkqhkiG9w0BAQwFAAOCAgEAEtd7IK0ONVgMnoEdJVj9TC1ndK/HYiYh9lVU
# acahRoZ2W2hfiEOyQExnHk1jkvpIJzAMxmEc6ZvIyHI5UkPCbXKspioYMdbOnBWQ
# Un733qMooBfIghpR/klUqNxx6/fDXqY0hSU1OSkkSivt51UlmJElUICZYBodzD3M
# /SFjeCP59anwxs6hwj1mfvzG+b1coYGnqsSz2wSKr+nDO+Db8qNcTbJZRAiSazr7
# KyUJGo1c+MScGfG5QHV+bps8BX5Oyv9Ct36Y4Il6ajTqV2ifikkVtB3RNBUgwu/m
# SiSUice/Jp/q8BMk/gN8+0rNIE+QqU63JoVMCMPY2752LmESsRVVoypJVt8/N3qQ
# 1c6FibbcRabo3azZkcIdWGVSAdoLgAIxEKBeNh9AQO1gQrnh1TA8ldXuJzPSuALO
# z1Ujb0PCyNVkWk7hkhVHfcvBfI8NtgWQupiaAeNHe0pWSGH2opXZYKYG4Lbukg7H
# pNi/KqJhue2Keak6qH9A8CeEOB7Eob0Zf+fU+CCQaL0cJqlmnx9HCDxF+3BLbUuf
# rV64EbTI40zqegPZdA+sXCmbcZy6okx/SjwsusWRItFA3DE8MORZeFb6BmzBtqKJ
# 7l939bbKBy2jvxcJI98Va95Q5JnlKor3m0E7xpMeYRriWklUPsetMSf2NvUQa/E5
# vVyefQIwggYaMIIEAqADAgECAhBiHW0MUgGeO5B5FSCJIRwKMA0GCSqGSIb3DQEB
# DAUAMFYxCzAJBgNVBAYTAkdCMRgwFgYDVQQKEw9TZWN0aWdvIExpbWl0ZWQxLTAr
# BgNVBAMTJFNlY3RpZ28gUHVibGljIENvZGUgU2lnbmluZyBSb290IFI0NjAeFw0y
# MTAzMjIwMDAwMDBaFw0zNjAzMjEyMzU5NTlaMFQxCzAJBgNVBAYTAkdCMRgwFgYD
# VQQKEw9TZWN0aWdvIExpbWl0ZWQxKzApBgNVBAMTIlNlY3RpZ28gUHVibGljIENv
# ZGUgU2lnbmluZyBDQSBSMzYwggGiMA0GCSqGSIb3DQEBAQUAA4IBjwAwggGKAoIB
# gQCbK51T+jU/jmAGQ2rAz/V/9shTUxjIztNsfvxYB5UXeWUzCxEeAEZGbEN4QMgC
# sJLZUKhWThj/yPqy0iSZhXkZ6Pg2A2NVDgFigOMYzB2OKhdqfWGVoYW3haT29PST
# ahYkwmMv0b/83nbeECbiMXhSOtbam+/36F09fy1tsB8je/RV0mIk8XL/tfCK6cPu
# YHE215wzrK0h1SWHTxPbPuYkRdkP05ZwmRmTnAO5/arnY83jeNzhP06ShdnRqtZl
# V59+8yv+KIhE5ILMqgOZYAENHNX9SJDm+qxp4VqpB3MV/h53yl41aHU5pledi9lC
# BbH9JeIkNFICiVHNkRmq4TpxtwfvjsUedyz8rNyfQJy/aOs5b4s+ac7IH60B+Ja7
# TVM+EKv1WuTGwcLmoU3FpOFMbmPj8pz44MPZ1f9+YEQIQty/NQd/2yGgW+ufflcZ
# /ZE9o1M7a5Jnqf2i2/uMSWymR8r2oQBMdlyh2n5HirY4jKnFH/9gRvd+QOfdRrJZ
# b1sCAwEAAaOCAWQwggFgMB8GA1UdIwQYMBaAFDLrkpr/NZZILyhAQnAgNpFcF4Xm
# MB0GA1UdDgQWBBQPKssghyi47G9IritUpimqF6TNDDAOBgNVHQ8BAf8EBAMCAYYw
# EgYDVR0TAQH/BAgwBgEB/wIBADATBgNVHSUEDDAKBggrBgEFBQcDAzAbBgNVHSAE
# FDASMAYGBFUdIAAwCAYGZ4EMAQQBMEsGA1UdHwREMEIwQKA+oDyGOmh0dHA6Ly9j
# cmwuc2VjdGlnby5jb20vU2VjdGlnb1B1YmxpY0NvZGVTaWduaW5nUm9vdFI0Ni5j
# cmwwewYIKwYBBQUHAQEEbzBtMEYGCCsGAQUFBzAChjpodHRwOi8vY3J0LnNlY3Rp
# Z28uY29tL1NlY3RpZ29QdWJsaWNDb2RlU2lnbmluZ1Jvb3RSNDYucDdjMCMGCCsG
# AQUFBzABhhdodHRwOi8vb2NzcC5zZWN0aWdvLmNvbTANBgkqhkiG9w0BAQwFAAOC
# AgEABv+C4XdjNm57oRUgmxP/BP6YdURhw1aVcdGRP4Wh60BAscjW4HL9hcpkOTz5
# jUug2oeunbYAowbFC2AKK+cMcXIBD0ZdOaWTsyNyBBsMLHqafvIhrCymlaS98+Qp
# oBCyKppP0OcxYEdU0hpsaqBBIZOtBajjcw5+w/KeFvPYfLF/ldYpmlG+vd0xqlqd
# 099iChnyIMvY5HexjO2AmtsbpVn0OhNcWbWDRF/3sBp6fWXhz7DcML4iTAWS+MVX
# eNLj1lJziVKEoroGs9Mlizg0bUMbOalOhOfCipnx8CaLZeVme5yELg09Jlo8BMe8
# 0jO37PU8ejfkP9/uPak7VLwELKxAMcJszkyeiaerlphwoKx1uHRzNyE6bxuSKcut
# isqmKL5OTunAvtONEoteSiabkPVSZ2z76mKnzAfZxCl/3dq3dUNw4rg3sTCggkHS
# RqTqlLMS7gjrhTqBmzu1L90Y1KWN/Y5JKdGvspbOrTfOXyXvmPL6E52z1NZJ6ctu
# MFBQZH3pwWvqURR8AgQdULUvrxjUYbHHj95Ejza63zdrEcxWLDX6xWls/GDnVNue
# KjWUH3fTv1Y8Wdho698YADR7TNx8X8z2Bev6SivBBOHY+uqiirZtg0y9ShQoPzmC
# cn63Syatatvx157YK9hlcPmVoa1oDE5/L9Uo2bC5a4CH2RwwggZMMIIEtKADAgEC
# AhAVVO/doV4MRRGuXmkecKnEMA0GCSqGSIb3DQEBDAUAMFQxCzAJBgNVBAYTAkdC
# MRgwFgYDVQQKEw9TZWN0aWdvIExpbWl0ZWQxKzApBgNVBAMTIlNlY3RpZ28gUHVi
# bGljIENvZGUgU2lnbmluZyBDQSBSMzYwHhcNMjMwODA5MDAwMDAwWhcNMjYwODA4
# MjM1OTU5WjBjMQswCQYDVQQGEwJVUzEWMBQGA1UECAwNTmV3IEhhbXBzaGlyZTEd
# MBsGA1UECgwUQ2hyaXN0b3BoZXIgQ2hhcmxhbmQxHTAbBgNVBAMMFENocmlzdG9w
# aGVyIENoYXJsYW5kMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAwLQA
# cUKQzYs2WJY+W2fl+/1PzX3vsFwK/W9sj1RXRLBsQjsTCYRu+jRPEZSVzL/K4L87
# 7Wxb69/ye88/RrWS0d6LUyohl0OgJwgRBXBsDIcpt3hTv7GRLAFvjzcCOvK6qk+k
# jf+bxqYSUOxfl/XDK0QvM3KgWbq2IeNHoMwvAXVFBcZnRPXp1FkcHGKf+nNwxP6V
# GWtiRrhIj99q0R4iwOQaQLRY8pe8m1wn/gwFRai1F1f/Q2EMSyvbgf7kYpFNHJK1
# 7LZR9J/G7P8h4QFQZJdMU6C4lRT+Lk2jEDF4elKF5c7DFjfMv2zd0jf3/2vOhayc
# Gna9puKwQUvtwtrmcCwOI5EXBIVBcFVS8xD6eeREvzjZXiuS83quzwxVVjNBQ2f/
# nuK54huEBbNQQeNjSkMdjyr5S0Xwf8Pic5NA4ggLUWuv2XYqTTMtXHQPZ41noEJM
# +LSBulBatGT98Tu0kib3MH7e1vREcTG7gZDnicmY0RfrWM59txft97gXP7Vj99ed
# 9t2/9niQleiT+YXy3ZpNoqGFB3XC13mM44xEff49vRSLN/B0IonG5vDpMgtFoKpq
# PtUx/oKQWtYbmoWFZkvEBRUeJOmkEmIUQonzE7aqgk/uGtyjxsBHtJzIHojA+8fG
# eD0NXjlOM1bbT0OcpSMkhRXPqiOELViMQwHrAiUCAwEAAaOCAYkwggGFMB8GA1Ud
# IwQYMBaAFA8qyyCHKLjsb0iuK1SmKaoXpM0MMB0GA1UdDgQWBBSO6WwZWwCa6iKw
# s6LE4InGvJQl3zAOBgNVHQ8BAf8EBAMCB4AwDAYDVR0TAQH/BAIwADATBgNVHSUE
# DDAKBggrBgEFBQcDAzBKBgNVHSAEQzBBMDUGDCsGAQQBsjEBAgEDAjAlMCMGCCsG
# AQUFBwIBFhdodHRwczovL3NlY3RpZ28uY29tL0NQUzAIBgZngQwBBAEwSQYDVR0f
# BEIwQDA+oDygOoY4aHR0cDovL2NybC5zZWN0aWdvLmNvbS9TZWN0aWdvUHVibGlj
# Q29kZVNpZ25pbmdDQVIzNi5jcmwweQYIKwYBBQUHAQEEbTBrMEQGCCsGAQUFBzAC
# hjhodHRwOi8vY3J0LnNlY3RpZ28uY29tL1NlY3RpZ29QdWJsaWNDb2RlU2lnbmlu
# Z0NBUjM2LmNydDAjBggrBgEFBQcwAYYXaHR0cDovL29jc3Auc2VjdGlnby5jb20w
# DQYJKoZIhvcNAQEMBQADggGBAENPYZO6JkhXuprRcjFErvAggFDfB4bJmvHwydUU
# q8EEdDkvVvS+SnqpaL+Nw5FY/X5GnIXfWKYvQJFY1o/bskqLBSH96jOk+wMWZ2Lq
# fuyEuW4OZUvBtpho2E2QwcpCQQzG47c+qtENC6lITctyoOUi5481cm9VXRL0E1g/
# MSDOqpYcd32oKt6rbqLQZD89HFgkNrfh3a4wq2O8ljai9gvQJnYV4588DGI4quzv
# 81b6mGDx9ku9zHhtvI19C1L+oQddqFFUViSwUUiNrBO7aA5iFwr1vQPkiP40Zd6f
# SSQAjrRnUI/kbK9oD2l1i/Vi9hfQ8SLarLPhW0M0qaut175+RJKlwuusUZADtgYV
# WcrmMxy20RMCUZA2bnTWXjb4pVfHUyKPU7dpM+8gG/tUPBZegMWrzWqctSPQhdRE
# pkLTMCm5E/o4ZUGNE0uo+twbGMGEyPPmjsFnIKLAqN2rHMI1Fz9pR+qMdixl+/mG
# /ElSJqGSDVArmZLn1IYhr4vQ8DCCBmIwggTKoAMCAQICEQCkKTtuHt3XpzQIh616
# TrckMA0GCSqGSIb3DQEBDAUAMFUxCzAJBgNVBAYTAkdCMRgwFgYDVQQKEw9TZWN0
# aWdvIExpbWl0ZWQxLDAqBgNVBAMTI1NlY3RpZ28gUHVibGljIFRpbWUgU3RhbXBp
# bmcgQ0EgUjM2MB4XDTI1MDMyNzAwMDAwMFoXDTM2MDMyMTIzNTk1OVowcjELMAkG
# A1UEBhMCR0IxFzAVBgNVBAgTDldlc3QgWW9ya3NoaXJlMRgwFgYDVQQKEw9TZWN0
# aWdvIExpbWl0ZWQxMDAuBgNVBAMTJ1NlY3RpZ28gUHVibGljIFRpbWUgU3RhbXBp
# bmcgU2lnbmVyIFIzNjCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBANOE
# lfRupFN48j0QS3gSBzzclIFTZ2Gsn7BjsmBF659/kpA2Ey7NXK3MP6JdrMBNU8wd
# mkf+SSIyjX++UAYWtg3Y/uDRDyg8RxHeHRJ+0U1jHEyH5uPdk1ttiPC3x/gOxIc9
# P7Gn3OgW7DQc4x07exZ4DX4XyaGDq5LoEmk/BdCM1IelVMKB3WA6YpZ/XYdJ9Jue
# OXeQObSQ/dohQCGyh0FhmwkDWKZaqQBWrBwZ++zqlt+z/QYTgEnZo6dyIo2IhXXA
# NFkCHutL8765NBxvolXMFWY8/reTnFxk3MajgM5NX6wzWdWsPJxYRhLxtJLSUJJ5
# yWRNw+NBqH1ezvFs4GgJ2ZqFJ+Dwqbx9+rw+F2gBdgo4j7CVomP49sS7Cbqsdybb
# iOGpB9DJhs5QVMpYV73TVV3IwLiBHBECrTgUfZVOMF0KSEq2zk/LsfvehswavE3W
# 4aBXJmGjgWSpcDz+6TqeTM8f1DIcgQPdz0IYgnT3yFTgiDbFGOFNt6eCidxdR6j9
# x+kpcN5RwApy4pRhE10YOV/xafBvKpRuWPjOPWRBlKdm53kS2aMh08spx7xSEqXn
# 4QQldCnUWRz3Lki+TgBlpwYwJUbR77DAayNwAANE7taBrz2v+MnnogMrvvct0iwv
# fIA1W8kp155Lo44SIfqGmrbJP6Mn+Udr3MR2oWozAgMBAAGjggGOMIIBijAfBgNV
# HSMEGDAWgBRfWO1MMXqiYUKNUoC6s2GXGaIymzAdBgNVHQ4EFgQUiGGMoSo3ZIEo
# YKGbMdCM/SwCzk8wDgYDVR0PAQH/BAQDAgbAMAwGA1UdEwEB/wQCMAAwFgYDVR0l
# AQH/BAwwCgYIKwYBBQUHAwgwSgYDVR0gBEMwQTA1BgwrBgEEAbIxAQIBAwgwJTAj
# BggrBgEFBQcCARYXaHR0cHM6Ly9zZWN0aWdvLmNvbS9DUFMwCAYGZ4EMAQQCMEoG
# A1UdHwRDMEEwP6A9oDuGOWh0dHA6Ly9jcmwuc2VjdGlnby5jb20vU2VjdGlnb1B1
# YmxpY1RpbWVTdGFtcGluZ0NBUjM2LmNybDB6BggrBgEFBQcBAQRuMGwwRQYIKwYB
# BQUHMAKGOWh0dHA6Ly9jcnQuc2VjdGlnby5jb20vU2VjdGlnb1B1YmxpY1RpbWVT
# dGFtcGluZ0NBUjM2LmNydDAjBggrBgEFBQcwAYYXaHR0cDovL29jc3Auc2VjdGln
# by5jb20wDQYJKoZIhvcNAQEMBQADggGBAAKBPqSGclEh+WWpLj1SiuHlm8xLE0ST
# hI2yLuq+75s11y6SceBchpnKpxWaGtXc8dya1Aq3RuW//y3wMThsvT4fSba2AoSW
# lR67rA4fTYGMIhgzocsids0ct/pHaocLVJSwnTYxY2pE0hPoZAvRebctbsTqENmZ
# HyOVjOFlwN2R3DRweFeNs4uyZN5LRJ5EnVYlcTOq3bl1tI5poru9WaQRWQ4eynXp
# 7Pj0Fz4DKr86HYECRJMWiDjeV0QqAcQMFsIjJtrYTw7mU81qf4FBc4u4swphLeKR
# Nyn9DDrd3HIMJ+CpdhSHEGleeZ5I79YDg3B3A/fmVY2GaMik1Vm+FajEMv4/EN2m
# mHf4zkOuhYZNzVm4NrWJeY4UAriLBOeVYODdA1GxFr1ycbcUEGlUecc4RCPgYySs
# 4d00NNuicR4a9n7idJlevAJbha/arIYMEuUqTeRRbWkhJwMKmb9yEvppRudKyu1t
# 6l21sIuIZqcpVH8oLWCxHS0LpDRF9Y4jijCCBoIwggRqoAMCAQICEDbCsL18Gzrn
# o7PdNsvJdWgwDQYJKoZIhvcNAQEMBQAwgYgxCzAJBgNVBAYTAlVTMRMwEQYDVQQI
# EwpOZXcgSmVyc2V5MRQwEgYDVQQHEwtKZXJzZXkgQ2l0eTEeMBwGA1UEChMVVGhl
# IFVTRVJUUlVTVCBOZXR3b3JrMS4wLAYDVQQDEyVVU0VSVHJ1c3QgUlNBIENlcnRp
# ZmljYXRpb24gQXV0aG9yaXR5MB4XDTIxMDMyMjAwMDAwMFoXDTM4MDExODIzNTk1
# OVowVzELMAkGA1UEBhMCR0IxGDAWBgNVBAoTD1NlY3RpZ28gTGltaXRlZDEuMCwG
# A1UEAxMlU2VjdGlnbyBQdWJsaWMgVGltZSBTdGFtcGluZyBSb290IFI0NjCCAiIw
# DQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAIid2LlFZ50d3ei5JoGaVFTAfEkF
# m8xaFQ/ZlBBEtEFAgXcUmanU5HYsyAhTXiDQkiUvpVdYqZ1uYoZEMgtHES1l1Cc6
# HaqZzEbOOp6YiTx63ywTon434aXVydmhx7Dx4IBrAou7hNGsKioIBPy5GMN7KmgY
# muu4f92sKKjbxqohUSfjk1mJlAjthgF7Hjx4vvyVDQGsd5KarLW5d73E3ThobSko
# b2SL48LpUR/O627pDchxll+bTSv1gASn/hp6IuHJorEu6EopoB1CNFp/+HpTXeNA
# RXUmdRMKbnXWflq+/g36NJXB35ZvxQw6zid61qmrlD/IbKJA6COw/8lFSPQwBP1i
# tyZdwuCysCKZ9ZjczMqbUcLFyq6KdOpuzVDR3ZUwxDKL1wCAxgL2Mpz7eZbrb/JW
# XiOcNzDpQsmwGQ6Stw8tTCqPumhLRPb7YkzM8/6NnWH3T9ClmcGSF22LEyJYNWCH
# rQqYubNeKolzqUbCqhSqmr/UdUeb49zYHr7ALL8bAJyPDmubNqMtuaobKASBqP84
# uhqcRY/pjnYd+V5/dcu9ieERjiRKKsxCG1t6tG9oj7liwPddXEcYGOUiWLm742st
# 50jGwTzxbMpepmOP1mLnJskvZaN5e45NuzAHteORlsSuDt5t4BBRCJL+5EZnnw0e
# zntk9R8QJyAkL6/bAgMBAAGjggEWMIIBEjAfBgNVHSMEGDAWgBRTeb9aqitKz1SA
# 4dibwJ3ysgNmyzAdBgNVHQ4EFgQU9ndq3T/9ARP/FqFsggIv0Ao9FCUwDgYDVR0P
# AQH/BAQDAgGGMA8GA1UdEwEB/wQFMAMBAf8wEwYDVR0lBAwwCgYIKwYBBQUHAwgw
# EQYDVR0gBAowCDAGBgRVHSAAMFAGA1UdHwRJMEcwRaBDoEGGP2h0dHA6Ly9jcmwu
# dXNlcnRydXN0LmNvbS9VU0VSVHJ1c3RSU0FDZXJ0aWZpY2F0aW9uQXV0aG9yaXR5
# LmNybDA1BggrBgEFBQcBAQQpMCcwJQYIKwYBBQUHMAGGGWh0dHA6Ly9vY3NwLnVz
# ZXJ0cnVzdC5jb20wDQYJKoZIhvcNAQEMBQADggIBAA6+ZUHtaES45aHF1BGH5Lc7
# JYzrftrIF5Ht2PFDxKKFOct/awAEWgHQMVHol9ZLSyd/pYMbaC0IZ+XBW9xhdkkm
# UV/KbUOiL7g98M/yzRyqUOZ1/IY7Ay0YbMniIibJrPcgFp73WDnRDKtVutShPSZQ
# ZAdtFwXnuiWl8eFARK3PmLqEm9UsVX+55DbVIz33Mbhba0HUTEYv3yJ1fwKGxPBs
# P/MgTECimh7eXomvMm0/GPxX2uhwCcs/YLxDnBdVVlxvDjHjO1cuwbOpkiJGHmLX
# XVNbsdXUC2xBrq9fLrfe8IBsA4hopwsCj8hTuwKXJlSTrZcPRVSccP5i9U28gZ7O
# MzoJGlxZ5384OKm0r568Mo9TYrqzKeKZgFo0fj2/0iHbj55hc20jfxvK3mQi+H7x
# pbzxZOFGm/yVQkpo+ffv5gdhp+hv1GDsvJOtJinJmgGbBFZIThbqI+MHvAmMmkfb
# 3fTxmSkop2mSJL1Y2x/955S29Gu0gSJIkc3z30vU/iXrMpWx2tS7UVfVP+5tKuzG
# tgkP7d/doqDrLF1u6Ci3TpjAZdeLLlRQZm867eVeXED58LXd1Dk6UvaAhvmWYXoi
# Lz4JA5gPBcz7J311uahxCweNxE+xxxR3kT0WKzASo5G/PyDez6NHdIUKBeE3jDPs
# 2ACc6CkJ1Sji4PKWVT0/MYIGQTCCBj0CAQEwaDBUMQswCQYDVQQGEwJHQjEYMBYG
# A1UEChMPU2VjdGlnbyBMaW1pdGVkMSswKQYDVQQDEyJTZWN0aWdvIFB1YmxpYyBD
# b2RlIFNpZ25pbmcgQ0EgUjM2AhAVVO/doV4MRRGuXmkecKnEMA0GCWCGSAFlAwQC
# AQUAoIGEMBgGCisGAQQBgjcCAQwxCjAIoAKAAKECgAAwGQYJKoZIhvcNAQkDMQwG
# CisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZI
# hvcNAQkEMSIEIBHArrcz6hoUlvsJgcXI/UCYlz7ldDMAJMcHk1VL8mKfMA0GCSqG
# SIb3DQEBAQUABIICABAmZTOofpWCwDvr5gEFaiq0OXw39dMuyBhYow6i8fcqmdY9
# WHOVXO0/fVZtzFCiJWxioHFExr3rtoGbFkIOg6vd6ir3vpX+PFXXs+3xLDMGzYW7
# sx6Cq4fhp/vMsM2WBxD7kLaJroF2xXpOUZuBF4imU2IdvyDPuCRA2NlC1o1Fp4mX
# PSo8o2kgY3lVbV8O2sKr5meuMmZVjdcuGuJF4Zk2e/+ocJt9FXFUs4E451rnRTdX
# DbhiHnCsVbhcPLHhGswVnR7s+R2UOM8yKB+5RnLXL/iwc+h06CpPPxYVes3TAECD
# OwtlvRZiu0da0yXLNWYzsEcwECAqsLwinIXWnxSLpPDwfQ4IYN5ZM+CslrZxFNIt
# pmUaWRU7cOrW22InTNjf0cllAA/S4bxUGFno1PfJYyAAopiA5jBzR38AjB1VM4LN
# +rF2xQ0Za8Cz6jmcjR7uzpzagmA+yMkD5lzNyGvrJIwwZVDr8lHa/yO5zPGGCThv
# oZJ/Ba6ZLMsuo58QUQ4dMBkWAW2t4QSqVd0jBxurWe2/4OsgBFaGMUt8V+f+pTpi
# b8XNLMF49D4bbcbinVvDmFa1+5rdTh/7/dXl+o16WGZbT7ltmX8m8mL0mTA2iLRT
# MmhrJ/5UnFsckXqSbmE3+k533a0MiJ/DUG7XKtvu3EVjiqfIsB2yaVjZjBQSoYID
# IzCCAx8GCSqGSIb3DQEJBjGCAxAwggMMAgEBMGowVTELMAkGA1UEBhMCR0IxGDAW
# BgNVBAoTD1NlY3RpZ28gTGltaXRlZDEsMCoGA1UEAxMjU2VjdGlnbyBQdWJsaWMg
# VGltZSBTdGFtcGluZyBDQSBSMzYCEQCkKTtuHt3XpzQIh616TrckMA0GCWCGSAFl
# AwQCAgUAoHkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjYwNjA2MjAzNjM2WjA/BgkqhkiG9w0BCQQxMgQwLJd7mMLs7ZykJYdGL6CX
# Vp2FT6uVSUviE3wZ31oqUASONR6FvLJrTL9hWUg0mjG9MA0GCSqGSIb3DQEBAQUA
# BIICAHicpZLeRxIKD8YI8ugcutL07/HlE+2gRO+2sDC+0DSX/n40Lnv0K/nw7DEd
# DNVHBReD6fL/hSjgYT3jZdUAOk28ZMxag4yO6eUVuhy/eI1l8dHJ1UOOCXh1S2vD
# 0dV0gFhtC7D+3trPMssO9SiUcJrH6liW0t2Sh+cvSw1CQLzookI5haJ90fPI3JIZ
# R55CSpnurAR7NuOBmPq9S6uXwN55NBQCvqyabWTdLW3e8mX4on1RwRUAcazlWVlH
# 3x+emGJ2ArzgRnm+DO2EmGjU33pY8gYFTD8whM611Hk4hEgd02wzk1KcQeFFZPaZ
# X4c3okUDnEcboBtJ48imihx3ebsezp2e0z6kVBPlO/vPioQia1RtOUH1nRev3fSd
# HSJzubdU5r5fgmLzAMiCRFRjqmjAnCihoxI02mwa9HK1Sa0gIXwHxv5M5ZO0hu/b
# dqHrrGMqaRlXJTLD/yhiwZz/oFh208L0zSRP+T13H81e7wGoPLf0ORA9mSF4tw06
# 4sbm5BhiLZrBUFjZKrTud5HnvSTLzk9LuEEL1mEz1EcGvYvG9I3Mz+3/G2/vpuoc
# 43iyeQByiG+bRNg8QXbBa69sb5f4+fNv59xCgX5SaG75HRKidOOk7RQFIklqy/Id
# GsxCPYW8dPKRp5mHT5qGZSvODTd480E+4BHiGTv4y9grK5rL
# SIG # End signature block
