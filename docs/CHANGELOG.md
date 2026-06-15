# Changelog

All notable changes to the CharlandCustomizations module will be documented in this file.

## Unreleased

### Changed

- Manifest compliance now enforces sorted `.psd1` arrays and `.psm1` `Export-ModuleMember -Function` arrays with one element per line to reduce merge conflicts in frequently edited export lists.

## [0.3.1] - 2026-06-13

### Added

- `Test-CCAuthenticodeSignature` — public function and standalone script for validating Authenticode signatures on release-critical PowerShell files
- `Invoke-CCScriptMultiAccountRegion` now sets `$global:StoredAWSRegion` and `$global:StoredAWSCredentials` during ScriptBlock execution so AWS.Tools cmdlets resolve context without explicit `-Region`/`-ProfileName`
- `Invoke-CCScriptMultiAccountRegion` now wraps string and primitive ScriptBlock results in a `Value` property for consistent enrichment with `-IncludeAccountId`/`-IncludeRegion`
- `Invoke-CCScriptMultiAccountRegion` terminates early with a clear error when AWS region configuration is missing (e.g., `No RegionEndpoint`, `DefaultAWSRegion is not configured`)
- Publish workflow now supports `workflow_dispatch` with a `-WhatIf` dry-run option
- `Build-Module.ps1` strips non-PowerShell files (`.gitkeep`, etc.) from build output before packaging

### Changed

- `Publish-CharlandCustomizations.ps1` now requires Windows (throws on non-Windows)
- `Publish-CharlandCustomizations.ps1` signature validation refactored to use `Test-CCAuthenticodeSignatures`/`Test-CCAuthenticodeSignature` instead of raw `Get-AuthenticodeSignature` calls
- `Publish-CharlandCustomizations.ps1` now rejects module directories containing non-PowerShell files before publishing
- Signature Compliance workflow renamed to "Signature Compliance - Scripts" and scoped to `Scripts/**/*.ps1` only (module source validated separately)
- All scripts re-signed with updated Authenticode certificates
- Module manifest version bumped to `0.3.1`

### Fixed

- `Invoke-CCScriptMultiAccountRegion` region iteration — AWS session globals are now properly saved/restored in the `finally` block, preventing state leakage between iterations
- `Edit-CCCFTTEbsVolume` property-based test reliability — mock re-registration per iteration replaced with script-scoped variable pattern to avoid Pester overhead
## [0.3.0] - 2026-06-11

### Added

- `Get-CCAllEC2Patch` — new function to retrieve SSM patch compliance data for all EC2 instances with exponential backoff retry logic
- `Test-CCAuthenticodeSignature` — new module-first function (with standalone script wrapper) for validating Authenticode signatures with timestamp compliance
- GitHub rulesets for deployment tag protection (`protect-deployment-tags.json`, `Block-Malformed-Tags.json`) with required status checks
- Publish workflow expanded with status-check verification, Authenticode signature validation step, tag immutability via GitHub Releases, and `workflow_dispatch` support
- PR quality gate now uploads Pester test result artifacts
- `Test-HelpCompliance.ps1` now enforces dual-level help (script-level + function-level) for all `Public/*.ps1` files
- `Build-Module.ps1` removes `.gitkeep` placeholder files from build output
- Manifest now exports `Set-CCFileSignature` and `Test-CCAuthenticodeSignatures` as aliases for backward compatibility

### Changed

- Renamed `Set-CCFileSignature` → `Set-CCAuthenticodeSignature` (alias preserved for backward compat)
- Refactored `Set-CCAuthenticodeSignature` and `Clear-CCAuthenticodeSignature` into module-first commands with standalone execution support
- `Test-SignatureCompliance.ps1` simplified to a thin wrapper that delegates to `Test-CCAuthenticodeSignature`
- Publish script now accepts `-SkipGitValidation` for CI use and supports both `v`-prefixed and bare version tags
- Publish script outputs success messages and uses `exit 0` on completion
- Module manifest `IconUri` fixed to use correct lowercase `assets` path casing
- Module version bumped to `0.3.0`
- All scripts re-signed with current Authenticode certificates

### Fixed

- Module manifest `IconUri` path casing (`Assets` → `assets`) causing broken icon on PowerShell Gallery
- Duplicate file entries removed from `STRUCTURE.md`

## [0.2.0-beta] - 2026-06-05

### Changed

- Removed `DefaultCommandPrefix = 'CC'` from the module manifest (`CharlandCustomizations.psd1`)
- Hardcoded the "CC" prefix directly into all 37 public function names (e.g., `Find-CFNStackError` → `Find-CCCFNStackError`)
- Renamed standalone `.ps1` files to match new function names (e.g., `Clear-AuthenticodeSignature.ps1` → `Clear-CCAuthenticodeSignature.ps1`)
- Updated all unit test files — renamed and updated internal references to use CC-prefixed function names
- Updated all documentation to reflect the new function names
- Many code changes, working on deployment process and procedures.

### Notes

- **No breaking change for end users** — the exported command names remain the same (e.g., `Find-CCCFNStackError` still works exactly as before)
- Using `Import-Module -Prefix` will now stack on top of the already-embedded "CC" prefix (e.g., `-Prefix My` would produce `Find-MyCCCFNStackError`)
- Private/internal functions (`New-AWSParamSplat`, `CFNPrivateFunctions`) were not renamed

## [0.1.0-beta1] - 2026-05-24

### Added

- Initial release, migrated from private repository. First public version with core AWS and Git utilities.

### Notes

- Published to PowerShell Gallery as a pre-release (`0.1.0-beta1`).
- Reviewer-identified code updates are intentionally deferred to a future release; this beta focuses on packaging and documentation alignment.
