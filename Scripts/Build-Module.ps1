<#
.SYNOPSIS
    Build and optionally install the CharlandCustomizations module
.DESCRIPTION
    Validates module structure, signs files (if certificate available), and optionally installs to user module path.
    Creates a versioned build output in the 'build' directory.

    Safety guardrails:
    - Aborts if a git tag matching the current version already exists.
    - Aborts if duplicate function names are detected across source files.
    - Aborts if the working tree is dirty when -Package or -PrepareRelease is used.
    - Runs Pester tests before packaging (-Package) and aborts on any failure.
    - Throws if -UpdateAllSignatures and -SkipSigning are both specified.

    By default, the signing step only re-signs files with invalid or missing Authenticode
    signatures (including files without a timestamp counter-signature). Use
    -UpdateAllSignatures to force re-signing of all PowerShell files regardless of
    their current signature state.
.PARAMETER Install
    Install module to user's PowerShell modules directory after building
.PARAMETER SkipSigning
    Skip code signing step
.PARAMETER UpdateAllSignatures
    Force re-sign all PowerShell files in the build output, even those with valid
    signatures. Without this switch, only files with invalid, missing, or
    non-timestamped signatures are re-signed.
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
    Builds, signs invalid/missing signatures, and installs the module
.EXAMPLE
    ./Build-Module.ps1 -UpdateAllSignatures -Install
    Builds, re-signs all files, and installs the module
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
    [switch]$UpdateAllSignatures,
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
if ($UpdateAllSignatures -and $SkipSigning) {
    throw "-UpdateAllSignatures cannot be used with -SkipSigning."
}

# Clean build directory if requested
if ($Clean -and (Test-Path $BuildRoot)) {
    Write-Output "Cleaning build directory..."
    Remove-Item $BuildRoot -Recurse -Force
}

# Dirty working tree check — prevent packaging/releasing with uncommitted changes
if ($Package -or $PrepareRelease) {
    $gitStatus = git status --porcelain 2>$null
    if ($gitStatus) {
        $dirtyCount = ($gitStatus | Measure-Object).Count
        Write-Error "Build aborted: working tree has $dirtyCount uncommitted change(s). Commit or stash changes before using -Package or -PrepareRelease."
        exit 1
    }
    else {
        Write-Verbose "Working tree is clean — safe to proceed with release operations"
    }
}

# Duplicate function name detection — scan source for conflicting definitions
Write-Host "Checking for duplicate function definitions..." -ForegroundColor Yellow
$functionDefinitions = @{}
$sourceFiles = Get-ChildItem -Path $SourcePath -Include *.ps1, *.psm1 -Recurse
foreach ($srcFile in $sourceFiles) {
    $content = Get-Content -Path $srcFile.FullName -Raw
    $matches = [regex]::Matches($content, '(?mi)^\s*function\s+([\w-]+)')
    foreach ($m in $matches) {
        $funcName = $m.Groups[1].Value
        if ($functionDefinitions.ContainsKey($funcName)) {
            Write-Error "Build aborted: duplicate function '$funcName' defined in both '$($functionDefinitions[$funcName])' and '$($srcFile.Name)'."
            exit 1
        }
        $functionDefinitions[$funcName] = $srcFile.Name
    }
}
Write-Verbose "  Scanned $($sourceFiles.Count) files, found $($functionDefinitions.Count) unique function definitions"

# Pester gate — run tests before packaging to prevent shipping broken code
if ($Package) {
    Write-Host "Running Pester tests (required for -Package)..." -ForegroundColor Yellow
    $testsPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'tests'
    if (Test-Path $testsPath) {
        $pesterResult = Invoke-Pester -Path $testsPath -PassThru -Output Minimal
        if ($pesterResult.FailedCount -gt 0) {
            Write-Error "Build aborted: $($pesterResult.FailedCount) Pester test(s) failed. Fix failing tests before packaging."
            exit 1
        }
        Write-Host "  All $($pesterResult.TotalCount) tests passed" -ForegroundColor Green
    }
    else {
        Write-Warning "Tests directory not found at $testsPath — skipping Pester gate"
    }
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

# Abort if a git tag for this version already exists in the repository
$existingTag = git tag -l $releaseTag 2>$null
if ($existingTag) {
    Write-Error "Build aborted: tag '$releaseTag' already exists in the repository. Bump the version before building."
    exit 1
}
else {
    Write-Verbose "Tag '$releaseTag' does not exist — safe to build"
}

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
    
    Write-Output "Looking for .gitkeep placeholders in $($BuildPath)"
    # Delete any .gitkeep placeholders in $BuildPath
    Get-ChildItem -Path $BuildRoot -Filter '.gitkeep' -Recurse -File -ErrorAction SilentlyContinue |
    Remove-Item -Force -ErrorAction SilentlyContinue

    # Remove any non-PowerShell files that shouldn't be in the published module
    $allowedBuildExtensions = @('.ps1', '.psm1', '.psd1')
    $junkFiles = @(Get-ChildItem -Path $BuildPath -Recurse -File |
        Where-Object { $_.Extension -notin $allowedBuildExtensions })
    if ($junkFiles.Count -gt 0) {
        Write-Output "  Removing $($junkFiles.Count) non-PowerShell file(s) from build output:"
        foreach ($junk in $junkFiles) {
            Write-Output "    Removed: $($junk.Name)"
            Remove-Item -Path $junk.FullName -Force
        }
    }


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

        # Load Set-CCAuthenticodeSignature if not already available
        if (-not (Get-Command Set-CCAuthenticodeSignature -ErrorAction SilentlyContinue)) {
            . (Join-Path (Split-Path $PSScriptRoot -Parent) 'src/CharlandCustomizations/Public/Set-CCAuthenticodeSignature.ps1')
        }

        $allFiles = Get-ChildItem -Path $BuildPath -Include *.ps1, *.psm1, *.psd1 -Recurse

        if ($UpdateAllSignatures) {
            Write-Output "Signing all built module files (-UpdateAllSignatures)..."
            $filesToSign = $allFiles
        }
        else {
            # Default: only sign files with invalid, missing, or non-timestamped signatures
            Write-Output "Checking signatures and signing invalid/missing files..."
            $filesToSign = @()
            foreach ($file in $allFiles) {
                $sig = Get-AuthenticodeSignature -FilePath $file.FullName
                if ($sig.Status -ne 'Valid') {
                    Write-Verbose "  Needs signing (status: $($sig.Status)): $($file.Name)"
                    $filesToSign += $file
                }
                elseif (-not $sig.TimeStamperCertificate) {
                    Write-Verbose "  Needs signing (missing timestamp): $($file.Name)"
                    $filesToSign += $file
                }
                else {
                    Write-Verbose "  Valid signature: $($file.Name)"
                }
            }

            $alreadyValid = $allFiles.Count - $filesToSign.Count
            if ($alreadyValid -gt 0) {
                Write-Output "  $alreadyValid file(s) already have valid signatures"
            }
        }

        $signedCount = 0
        $failedCount = 0

        if ($filesToSign.Count -eq 0) {
            Write-Output "  All files already have valid signatures — nothing to sign"
            $allFilesSigned = $true
        }
        else {
            Write-Output "  Signing $($filesToSign.Count) file(s)..."
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

            if ($failedCount -eq 0) {
                $allFilesSigned = $true
                Write-Output "  All files signed successfully ($signedCount signed)"
            }
            else {
                Write-Warning "Some files failed to sign: $failedCount failed, $signedCount succeeded"
            }
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