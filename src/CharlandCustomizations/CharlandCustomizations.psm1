<#
.SYNOPSIS
    CharlandCustomizations module loader.

.DESCRIPTION
    Main module file for CharlandCustomizations. Validates prerequisites, then
    dot-sources all public and private function files.

    Public functions (src/Public/*.ps1) are exported automatically.
    Private functions (src/Private/*.ps1) are available internally but not exported.

    AWS-specific functions are loaded via NestedModules defined in the manifest.

.NOTES
    Requires PowerShell 7.2+
    Requires AWS.Tools.Common v5+ or AWSPowerShell.NetCore v5+
    Modified by Kiro (aws-common-params spec): removed Export-ModuleMember,
    exports now controlled by manifest FunctionsToExport list.
#>

# Require AWS PowerShell tools v5+.
# Prompt to install if not found, or throw if version < 5.

$awsCmd = Get-Command -Name 'Set-AWSCredential' -ErrorAction SilentlyContinue
if (-not $awsCmd) {
    $ask = 'AWS PowerShell tools not found. Install current AWS.Tools.Common ?'
    Write-Host $ask

    $installAwsTools = $false
    if ($PSCmdlet) {
        $installAwsTools = $PSCmdlet.ShouldContinue($ask, 'Install AWS Tools.Common')
    } elseif ($Host -and $Host.UI) {
        $choices = [System.Management.Automation.Host.ChoiceDescription[]] @(
            (New-Object System.Management.Automation.Host.ChoiceDescription '&Yes', 'Install AWS.Tools.Common now'),
            (New-Object System.Management.Automation.Host.ChoiceDescription '&No', 'Do not install and stop module import')
        )
        $selection = $Host.UI.PromptForChoice('Install AWS Tools.Common', $ask, $choices, 1)
        $installAwsTools = ($selection -eq 0)
    }

    if ($installAwsTools) {
        Install-Module -Name 'AWS.Tools.Common' -Force -Scope CurrentUser
        $awsCmd = Get-Command -Name 'Set-AWSCredential' -ErrorAction SilentlyContinue
    } else {
        throw 'AWS.Tools.Common install declined. This module requires AWS.Tools.Common v5+ or AWSPowerShell.NetCore v5+.'
    }
}
$awsVersion = $awsCmd.Module.Version
if ($awsVersion.Major -lt 5) {
    throw "AWS PowerShell tools v$awsVersion detected. Version 5+ is required. Run: Update-AWSToolsModule"
} else {
    Write-Verbose "AWS PowerShell tools v$awsVersion detected."
}

# Dot-source public functions (exported)
$publicScripts = Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public') -Filter '*.ps1' -File -ErrorAction SilentlyContinue
foreach ($file in $publicScripts) {
    . $file.FullName
}

# Dot-source private functions (internal helpers, not exported)
$privateScripts = Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private') -Filter '*.ps1' -File -ErrorAction SilentlyContinue
foreach ($file in $privateScripts) {
    . $file.FullName
}

