<#
.SYNOPSIS
    Registers the build directory as a local PSRepository for testing

.DESCRIPTION
    Creates a local NuGet-based PSRepository pointing to the build output directory.
    This allows testing Install-Module, Find-Module, and Update-Module workflows
    against locally built packages without publishing to PSGallery.

    The script will also publish the current build to the local repository if
    a built module is found.

.PARAMETER Name
    Name for the local repository (default: LocalTest)

.PARAMETER Unregister
    Remove the local repository registration

.PARAMETER PublishOnly
    Skip registration and only publish the current build to an existing repository

.EXAMPLE
    ./Register-LocalRepository.ps1
    Registers the local repo and publishes the current build

.EXAMPLE
    ./Register-LocalRepository.ps1 -Name MyLocalRepo
    Registers with a custom repository name

.EXAMPLE
    ./Register-LocalRepository.ps1 -Unregister
    Removes the local repository registration

.EXAMPLE
    ./Register-LocalRepository.ps1 -PublishOnly
    Publishes the current build to the already-registered local repository
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$Name = 'LocalTest',

    [switch]$Unregister,

    [switch]$PublishOnly
)

$ErrorActionPreference = 'Stop'
$ModuleName = 'CharlandCustomizations'
$BuildRoot = Join-Path (Split-Path $PSScriptRoot -Parent) 'build'
$RepoPath = Join-Path $BuildRoot 'LocalRepo'

# Unregister and exit if requested
if ($Unregister) {
    $existing = Get-PSRepository -Name $Name -ErrorAction SilentlyContinue
    if ($existing) {
        Unregister-PSRepository -Name $Name
        Write-Output "Unregistered repository: $Name"
    }
    else {
        Write-Output "Repository '$Name' is not registered."
    }
    return
}

# Ensure the build directory exists
if (-not (Test-Path $BuildRoot)) {
    Write-Error "Build directory not found: $BuildRoot`nRun ./Scripts/Build-Module.ps1 first."
    return
}

# Find the latest built module version
$versionDirs = Get-ChildItem -Path (Join-Path $BuildRoot $ModuleName) -Directory -ErrorAction SilentlyContinue |
Sort-Object { [version]$_.Name } -Descending

if (-not $versionDirs) {
    Write-Error "No built module versions found in: $BuildRoot\$ModuleName`nRun ./Scripts/Build-Module.ps1 first."
    return
}

$latestVersion = $versionDirs | Select-Object -First 1
$modulePath = $latestVersion.FullName
Write-Output "Found built module: $ModuleName v$($latestVersion.Name)"
Write-Output "  Path: $modulePath"

# Create the local repository directory
if (-not (Test-Path $RepoPath)) {
    New-Item -ItemType Directory -Path $RepoPath -Force | Out-Null
    Write-Output "Created local repository directory: $RepoPath"
}

# Register the repository if not in PublishOnly mode
if (-not $PublishOnly) {
    $existing = Get-PSRepository -Name $Name -ErrorAction SilentlyContinue
    if ($existing) {
        if ($existing.SourceLocation -eq $RepoPath) {
            Write-Output "Repository '$Name' already registered at: $RepoPath"
        }
        else {
            Write-Output "Updating repository '$Name' source location..."
            Set-PSRepository -Name $Name -SourceLocation $RepoPath -InstallationPolicy Trusted
            Write-Output "  Updated to: $RepoPath"
        }
    }
    else {
        Register-PSRepository -Name $Name -SourceLocation $RepoPath -InstallationPolicy Trusted
        Write-Output "Registered repository: $Name"
        Write-Output "  Source: $RepoPath"
        Write-Output "  InstallationPolicy: Trusted"
    }
}
else {
    # Verify the repository exists for PublishOnly mode
    $existing = Get-PSRepository -Name $Name -ErrorAction SilentlyContinue
    if (-not $existing) {
        Write-Error "Repository '$Name' is not registered. Run without -PublishOnly first."
        return
    }
}

# Publish the module to the local repository
Write-Output "`nPublishing $ModuleName v$($latestVersion.Name) to '$Name'..."

try {
    Publish-Module -Path $modulePath -Repository $Name -Force
    Write-Output "  Published successfully."
}
catch {
    if ($_.Exception.Message -match 'already available') {
        Write-Output "  Version $($latestVersion.Name) already exists in repository. Use -Force or bump version."
    }
    else {
        Write-Error "Failed to publish module: $_"
        return
    }
}

# Show available modules in the local repo
Write-Output "`nModules available in '$Name':"
Find-Module -Repository $Name -Name $ModuleName -ErrorAction SilentlyContinue |
Format-Table Name, Version, Description -AutoSize

# Usage hints
Write-Output "Usage:"
Write-Output "  Find-Module -Repository $Name"
Write-Output "  Install-Module -Name $ModuleName -Repository $Name -Scope CurrentUser"
Write-Output "  Update-Module -Name $ModuleName"
Write-Output "`nTo unregister: ./Scripts/Register-LocalRepository.ps1 -Unregister"