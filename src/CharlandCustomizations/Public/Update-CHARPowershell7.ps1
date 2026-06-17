function Update-CHARPowershell7 {
<#
.SYNOPSIS
    Updates PowerShell 7 to the current stable release (cross-platform).

.DESCRIPTION
    Updates PowerShell 7 using the platform-appropriate package manager:
    - Windows: winget (preferred) or chocolatey
    - macOS: Homebrew
    - Linux: apt (Debian/Ubuntu), dnf (Fedora/RHEL), pacman (Arch), etc.

    If no package manager is available, provides instructions for manual installation.
    Requires appropriate permissions (admin on Windows, sudo on Linux/macOS).

.INPUTS
    None.

.OUTPUTS
    System.String - Status messages and installation instructions.

.NOTES
    Cross-platform compatible. Works on Windows, macOS, and Linux.
    Visit https://github.com/PowerShell/PowerShell/releases for manual installation.

.EXAMPLE
    Update-CHARPowershell7
    Detects OS and updates using the available package manager.
#>
  [CmdletBinding()]
  param()

  $OS = $PSVersionTable.OS

  if ($OS -like '*Windows*') {
    Write-Verbose "Windows platform detected"
    if (Get-Command winget -ErrorAction SilentlyContinue) {
      Write-Output "Updating PowerShell 7 via winget..."
      & winget upgrade Microsoft.PowerShell --accept-source-agreements
    }
    elseif (Get-Command choco -ErrorAction SilentlyContinue) {
      Write-Output "Updating PowerShell 7 via Chocolatey..."
      & choco upgrade powershell-core
    }
    else {
      Write-Output "Windows detected. No package manager found. Install PowerShell 7 via:"
      Write-Output "  - winget: winget upgrade Microsoft.PowerShell"
      Write-Output "  - chocolatey: choco upgrade powershell-core"
      Write-Output "  - Manual: https://github.com/PowerShell/PowerShell/releases"
    }
  }
  elseif ($OS -like '*Darwin*') {
    Write-Verbose "macOS platform detected"
    if (Get-Command brew -ErrorAction SilentlyContinue) {
      Write-Output "Updating PowerShell 7 via Homebrew..."
      & brew upgrade powershell
    }
    else {
      Write-Output "macOS detected. Homebrew is required. Install it first:"
      Write-Output "  /bin/bash -c `$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      Write-Output "Then run: brew upgrade powershell"
    }
  }
  elseif ($OS -like '*Linux*') {
    Write-Verbose "Linux platform detected"
    if (Test-Path /etc/os-release) {
      $osInfo = Get-Content /etc/os-release | ConvertFrom-StringData
      $distroId = $osInfo.ID -replace '"', ''

      Write-Output "Linux ($distroId) detected. Run the appropriate command:"

      if ($distroId -in @('ubuntu', 'debian')) {
        Write-Output "  sudo apt update && sudo apt install -y powershell"
      }
      elseif ($distroId -in @('fedora', 'rhel', 'centos', 'rocky', 'alma')) {
        Write-Output "  sudo dnf install -y powershell"
      }
      elseif ($distroId -eq 'arch') {
        Write-Output "  sudo pacman -Syu powershell"
      }
      elseif ($distroId -like '*opensuse*') {
        Write-Output "  sudo zypper install powershell"
      }
      else {
        Write-Output "  See: https://github.com/PowerShell/PowerShell/releases"
      }
    }
    else {
      Write-Output "Linux detected. Visit: https://github.com/PowerShell/PowerShell/releases"
    }
  }
  else {
    Write-Output "Unknown platform. Visit: https://github.com/PowerShell/PowerShell/releases"
  }
}
