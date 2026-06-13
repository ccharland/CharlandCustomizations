<#
.SYNOPSIS
    Publish the CharlandCustomizations module to a PowerShell repository.
.DESCRIPTION
    Reads the API key from a parameter, environment variable, or SecretManagement
    secret, then publishes using PSResourceGet when available and falls back to
    PowerShellGet for older environments.
.PARAMETER Path
    Path to the module folder that contains CharlandCustomizations.psd1.
    Default is '..\src\CharlandCustomizations' relative to the script location.
.PARAMETER Repository
    Target repository name. Defaults to PSGallery.
.PARAMETER ApiKey
    Repository API key. If omitted, the script checks PSGALLERY_API_KEY and then
    an optional SecretManagement secret.
.PARAMETER SecretName
    SecretManagement secret name to read when ApiKey is not passed.
.PARAMETER SkipRepositoryTrust
    Skip setting the target repository to trusted before publishing.
.PARAMETER SkipGitValidation
    Skip branch and tag checks when publishing to PSGallery (used in CI).
.PARAMETER SkipSignatureValidation
    Skip Authenticode signature validation (used in CI where signing is validated separately).
.PARAMETER UseLegacyPowerShellGet
    Force Publish-Module instead of Publish-PSResource.
.EXAMPLE
    $env:PSGALLERY_API_KEY = '...'
    ./Scripts/Publish-CharlandCustomizations.ps1
.EXAMPLE
    ./Scripts/Publish-CharlandCustomizations.ps1 -Repository PSGallery -SecretName PSGalleryApiKey
.EXAMPLE
    ./Scripts/Publish-CharlandCustomizations.ps1 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$Path = (Join-Path $PSScriptRoot '..\src\CharlandCustomizations'),
    [string]$Repository = 'PSGallery',
    [string]$ApiKey,
    [string]$SecretName = 'PSGalleryApiKey',
    [switch]$SkipRepositoryTrust,
    [switch]$SkipGitValidation,
    [switch]$SkipSignatureValidation,
    [switch]$UseLegacyPowerShellGet
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Variable -Name CCIsWindows -Scope Script -ErrorAction SilentlyContinue)) {
    $script:CCIsWindows = if ($PSVersionTable.PSVersion.Major -lt 7) {
        [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
    }
    else {
        [bool]$IsWindows
    }
}

if (-not $script:CCIsWindows) {
    throw 'Publish-CharlandCustomizations is only supported on Windows systems.'
}

$resolvedPath = Resolve-Path -Path $Path
$manifestPath = Join-Path $resolvedPath 'CharlandCustomizations.psd1'

if (-not (Test-Path -Path $manifestPath)) {
    throw "Module manifest not found at $manifestPath"
}

if ($Repository -ieq 'PSGallery' -and -not $SkipGitValidation) {
    $manifestData = Test-ModuleManifest -Path $manifestPath -ErrorAction Stop
    $expectedReleaseTag = $manifestData.Version.ToString()
    $prerelease = $manifestData.PrivateData.PSData.Prerelease
    if ($prerelease) {
        $expectedReleaseTag = "$expectedReleaseTag-$prerelease"
    }

    if (-not (Get-Command -Name git -ErrorAction SilentlyContinue)) {
        throw "Publishing to PSGallery requires git to verify release branch/tag. Expected tag: '$expectedReleaseTag'."
    }

    $repoRoot = (& git -C $resolvedPath rev-parse --show-toplevel 2>$null | Select-Object -First 1)
    if (-not $repoRoot) {
        throw 'Publishing to PSGallery requires running inside a git repository.'
    }

    $currentBranch = (& git -C $repoRoot branch --show-current 2>$null | Select-Object -First 1)
    if ($currentBranch -ne 'main') {
        throw "Publishing to PSGallery is only allowed from branch 'main'. Current branch: '$currentBranch'."
    }

    $headTags = @(& git -C $repoRoot tag --points-at HEAD 2>$null)
    # Accept both 'v'-prefixed and bare version tags (e.g., v0.3.0-beta or 0.3.0-beta)
    $tagMatch = $headTags | Where-Object { $_ -eq $expectedReleaseTag -or $_ -eq "v$expectedReleaseTag" }
    if (-not $tagMatch) {
        throw "Publishing to PSGallery requires immutable release tag '$expectedReleaseTag' (or 'v$expectedReleaseTag') on HEAD."
    }
}


$allowedExtensions = @('.ps1', '.psm1', '.psd1')
$allModuleFiles = @(Get-ChildItem -Path $resolvedPath -Recurse -File)
$nonPowerShellFiles = @($allModuleFiles | Where-Object { $_.Extension -notin $allowedExtensions })
if ($nonPowerShellFiles.Count -gt 0) {
    $disallowedFiles = ($nonPowerShellFiles | Select-Object -ExpandProperty FullName) -join ', '
    throw "Publishing requires the module directory to contain only .ps1, .psm1, and .psd1 files. Found disallowed file(s): $disallowedFiles"
}

$filesToValidate = @($allModuleFiles | Where-Object { $_.Extension -in $allowedExtensions })
if (-not $filesToValidate) {
    throw "No PowerShell module files were found under $resolvedPath"
}

$signatureValidationCommand = Get-Command -Name Test-CCAuthenticodeSignatures -ErrorAction SilentlyContinue
if (-not $signatureValidationCommand) {
    $signatureValidationCommand = Get-Command -Name Test-CCAuthenticodeSignature -ErrorAction SilentlyContinue
}

if (-not $SkipSignatureValidation) {
    if (-not $signatureValidationCommand) {
        throw 'Publishing requires Test-CCAuthenticodeSignatures (or Test-CCAuthenticodeSignature) to be available in the current session.'
    }

    $invalidSignatures = @(& $signatureValidationCommand.Name -Path $resolvedPath -IncludeExtension $allowedExtensions)
    if ($invalidSignatures.Count -gt 0) {
        Write-Error 'Publishing requires all module files to have valid Authenticode signatures.'
        $invalidSignatures | Format-Table -AutoSize
        throw 'Publishing aborted because one or more files have invalid Authenticode signatures.'
    }
}

if (-not $ApiKey) {
    $ApiKey = $env:PSGALLERY_API_KEY
}

if (-not $ApiKey -and (Get-Command -Name Get-Secret -ErrorAction SilentlyContinue)) {
    try {
        $secretValue = Get-Secret -Name $SecretName -AsPlainText -ErrorAction Stop
        if ($secretValue) {
            $ApiKey = $secretValue
        }
    }
    catch {
        Write-Verbose "Secret '$SecretName' was not available via SecretManagement."
    }
}

if (-not $ApiKey) {
    $ApiKey = Read-Host "Enter API key for repository '$Repository'" -MaskInput
}

if (-not $ApiKey) {
    throw 'No API key was provided.'
}

$publishWithPSResourceGet = -not $UseLegacyPowerShellGet -and (Get-Command -Name Publish-PSResource -ErrorAction SilentlyContinue)

if ($publishWithPSResourceGet) {
    if (-not $SkipRepositoryTrust -and (Get-Command -Name Get-PSResourceRepository -ErrorAction SilentlyContinue)) {
        $registeredRepository = Get-PSResourceRepository -Name $Repository -ErrorAction SilentlyContinue
        if ($registeredRepository -and -not $registeredRepository.Trusted) {
            if ($PSCmdlet.ShouldProcess("PSResource repository '$Repository'", 'Set as trusted')) {
                Set-PSResourceRepository -Name $Repository -Trusted | Out-Null
            }
        }
    }

    if ($PSCmdlet.ShouldProcess("module path '$resolvedPath'", "Publish to '$Repository' using Publish-PSResource")) {
        Publish-PSResource -Path $resolvedPath -Repository $Repository -ApiKey $ApiKey
        Write-Output "Successfully published CharlandCustomizations to '$Repository' using PSResourceGet."
    }
    exit 0
}

if (-not (Get-Command -Name Publish-Module -ErrorAction SilentlyContinue)) {
    throw 'Neither Publish-PSResource nor Publish-Module is available in this PowerShell session.'
}

if ($PSCmdlet.ShouldProcess("module path '$resolvedPath'", "Publish to '$Repository' using Publish-Module")) {
    Publish-Module -Path $resolvedPath -Repository $Repository -NuGetApiKey $ApiKey
    Write-Output "Successfully published CharlandCustomizations to '$Repository' using PowerShellGet."
}
exit 0