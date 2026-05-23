# Installation Guide

## Prerequisites

- PowerShell 7.2 or later
- One of the following AWS PowerShell modules:
  - `AWS.Tools.Common` (recommended - modular)
  - `AWSPowerShell.NetCore` (monolithic)
  - `AWSPowerShell` (legacy)

## Quick Install

### Option 1: PowerShell Gallery (Recommended)

```powershell
Install-PSResource CharlandCustomizations -Repository PSGallery -Scope CurrentUser
```

### Option 2: Using Build Script

```powershell
# Clone the repository
git clone https://github.com/youruser/CharlandCustomizations.git
cd CharlandCustomizations

# Build and install
./Scripts/Build-Module.ps1 -Install
```

This will:
- Create a versioned build in `build/CharlandCustomizations/<version>/`
- Validate the module structure
- Sign files (if you have a code signing certificate)
- Install to `$HOME/Documents/PowerShell/Modules/CharlandCustomizations/<version>`
- Import and verify the module

### Option 3: Manual Installation

```powershell
# Copy module to PowerShell modules directory
Copy-Item -Recurse ./src/CharlandCustomizations $HOME/Documents/PowerShell/Modules/

# Import the module
Import-Module CharlandCustomizations
```

## Command Prefix

This module uses `DefaultCommandPrefix = 'CC'`. Exported commands have a `CC` prefix:

```powershell
# Function names get CC inserted after the verb
Find-CCCFNStackErrors
Get-CCEC2SGInUse
Clear-CCS3Bucket
```

## Verify Installation

```powershell
# Check module is loaded
Get-Module CharlandCustomizations

# List available functions
Get-Command -Module CharlandCustomizations

# Test a function
Get-Help Find-CCCFNStackErrors -Full
```

## Auto-Load on Startup

Add to your PowerShell profile (`$PROFILE`):

```powershell
Import-Module CharlandCustomizations
```

## Installing AWS PowerShell Tools

If you don't have AWS PowerShell tools installed:

```powershell
# Install modular AWS Tools (recommended)
Install-Module -Name AWS.Tools.Installer
Install-AWSToolsModule AWS.Tools.Common, AWS.Tools.CloudFormation, AWS.Tools.IdentityManagement, AWS.Tools.S3, AWS.Tools.EC2, AWS.Tools.SecurityToken, AWS.Tools.SimpleSystemsManagement, AWS.Tools.SecretsManager

# OR install monolithic version
Install-Module -Name AWSPowerShell.NetCore
```

## Updating

```powershell
# Pull latest changes
git pull

# Rebuild and reinstall
./Scripts/Build-Module.ps1 -Install
```

## Uninstall

```powershell
# Remove module
Remove-Module CharlandCustomizations
Remove-Item -Recurse $HOME/Documents/PowerShell/Modules/CharlandCustomizations
```

## Troubleshooting

### Module Not Found

Ensure the module path is in `$env:PSModulePath`:

```powershell
$env:PSModulePath -split ';'
```

Should include: `C:\Users\<YourName>\Documents\PowerShell\Modules`

### Import Errors

Check for conflicting AWS module versions:

```powershell
Get-Module -Name AWSPowerShell,AWSPowerShell.NetCore,AWS.Tools.Common -ListAvailable
```

Only one variant should be installed.

### Signature Errors

If you get signature validation errors:

```powershell
# Rebuild with signing
./Scripts/Build-Module.ps1 -Install

# Or skip signing for development
./Scripts/Build-Module.ps1 -SkipSigning -Install
```
