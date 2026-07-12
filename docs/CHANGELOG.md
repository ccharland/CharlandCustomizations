# Changelog

All notable changes to the CharlandCustomizations module will be documented in this file.

## [0.4.1] - 2026-07-12

### Added

- `Invoke-CHARScriptMultiRegionProfile` — ambient credentials support: when no `-ProfileName` is specified and no stored profile exists, the function now detects and uses ambient credentials (AWS CloudShell, EC2 instance roles, ECS task roles, environment variables) via a `Get-STSCallerIdentity` probe (#77)
- `Invoke-CHARScriptMultiRegionProfile` — `-SuppressEmptyResult` parameter to skip emitting placeholder objects for profile/region combinations that return no data (#76)
- `publish/*` branch type added to branch path policy — scoped to release-prep paths only (`src/`, `docs/`, root files, `assets/`), blocked from `.github/`, `.githooks/`, `.kiro/`, `.vscode/`, `Scripts/`, and `tests/` (#73)
- `auto-tag-publish.yml` workflow — automatically creates a signed version tag when a `publish/*` PR merges to `main`, triggering the existing publish workflow (#73)
- GPG tag signature verification step added to `publish.yml` — publish workflow now validates the tag was signed by the authorized release key before proceeding (#73)
- `CONTRIBUTING.md` — comprehensive contributor guide covering prerequisites, branching, code standards, testing, signing, and release flow (#72)
- `SECURITY.md` — security policy with private vulnerability reporting instructions (#72)
- Architecture Decision Records (ADRs) added in `docs/architecture-decisions/` — documenting the CHAR prefix convention, branch path policy, Authenticode signing workflow, SSO config decision, AWS parameter splatting, quality gates philosophy, AI-assisted development approach, and publish branch design (#72)

### Changed

- `Invoke-CHARScriptMultiRegionProfile` — AWS session state restore now uses direct global variable assignment instead of `Set-AWSCredential -ProfileName`, fixing issues where `$StoredAWSCredentials` held a credential object rather than a profile name string (#77)
- `Invoke-CHARScriptMultiRegionProfile` — `$PSDefaultParameterValues` injected into ScriptBlock no longer includes `*:ProfileName` when running with ambient credentials (#77)
- `Invoke-CHARScriptMultiRegionProfile` — removed excessive `Write-Debug`/`Write-Verbose` noise from inner loops (#77)
- README branch standards section condensed — detailed branching and path policy docs moved to `CONTRIBUTING.md` (#72)
- `docs/BUILD-PROCESS.md` — consolidated distribution content from deleted `docs/DISTRIBUTION.md`; fixed release tag construction to include `v` prefix (#72)
- `docs/AWS-Account-Audit.md` and `docs/CloudFormation-TemplateProcessing.md` — trimmed redundant prerequisites, installation, and contributing sections; added cross-reference links (#72)
- `docs/STRUCTURE.md` — moved module-loading and prefix details to `CONTRIBUTING.md` (#72)
- `Test-BranchPathPolicy.ps1` — added `publish/*` blocked paths and branch prefix entry; re-signed (#73)
- Branch name ruleset updated to include `refs/heads/publish/*` (#73)
- Pre-commit hook updated with `publish/*` branch classification and approved-prefix text (#73)
- Module manifest version bumped to `0.4.1`

### Removed

- `docs/DISTRIBUTION.md` — content merged into `docs/BUILD-PROCESS.md` (#72)
- `docs/parameter-reference.md` — raw parameter documentation removed (covered by `Get-Help` and `docs/NEW-FEATURE-PARAMETERS.md`) (#72)

### Infrastructure

- Kiro steering and development-standards documentation updated (#72)
- Ruleset activation logs updated for publish branch additions (#73)

## [0.4.0] - 2026-07-05

### Added

- `Get-CHARDeprecatedLMFunctionList` — date-aware Lambda deprecated runtime filter command (#21)
- `Update-CHARSSOCredentialList` refactored to write SSO profiles to the shared AWS credential file for use with `aws sso login` workflows (#68)
- Dependabot configuration with GitHub Actions pinned to full commit SHAs for supply-chain security (#53)
- Branch path policy now separates test ownership by branch type — code branches own `tests/src/`, infrastructure branches own `tests/scripts/` (#60)
- Comprehensive Pester test coverage added for previously untested functions (#66)
- `Test-ManifestCompliance.ps1` script to validate manifest export alignment and sorted array formatting (#39)

### Changed

- **Breaking:** Renamed all 40 public functions from `CC` prefix to `CHAR` prefix (e.g., `Get-CCAWSMFASession` → `Get-CHARAWSMFASession`, `Find-CCCFNStackError` → `Find-CHARCFNStackError`, `Clear-CCS3Bucket` → `Clear-CHARS3Bucket`) (#48)
- **Breaking:** Renamed `Invoke-CCScriptMultiAccountRegion` → `Invoke-CHARScriptMultiRegionProfile` (verb-noun alignment + prefix rename) (#43, #48)
- Renamed all standalone `.ps1` files to match new CHAR-prefixed function names (8 files)
- Updated all nested module `Export-ModuleMember` declarations to export CHAR-prefixed names
- Updated module manifest `FunctionsToExport` and `AliasesToExport` to use CHAR-prefixed names (`Set-CHARFileSignature`, `Test-CHARAuthenticodeSignatures`)
- Renamed all unit test files and updated internal references to use CHAR-prefixed function names (24 test files)
- Updated all documentation to reflect new function names
- Simplified `$script:CCIsWindows` to `$script:IsWindows` in applicable scripts
- Stripped all Authenticode signature blocks from source files and re-signed them for this release
- `Invoke-CHARScriptMultiRegionProfile` — improved credential and region handling for multi-account execution (#62)
- Manifest compliance now enforces sorted `.psd1` arrays and `.psm1` `Export-ModuleMember -Function` arrays with one element per line to reduce merge conflicts (#39)
- Reorganized test directory structure — module tests moved to `tests/src/`, script tests moved to `tests/scripts/` (#61, #63)
- Improved build process with enhanced validation and CI gates (#45, #52)
- Promoted module from beta to stable release (removed `Prerelease` tag from manifest)

### Fixed

- Lambda `Get-CHARDeprecatedLMFunctionList` — `Runtime` property is now converted to string before comparison to prevent type mismatch errors (#64)
- Various test fixes for source-mirrored test layout (#67)

### Infrastructure

- Added repository rulesets for branch naming and path controls (#49)
- Added Kiro and AI-assistant configuration files (#42)
- GitHub Actions workflows pinned to full commit SHAs (#53)

### Notes

- **Breaking change for end users** — all exported command names now use the `CHAR` prefix instead of `CC`. Users must update scripts that reference the old names.
- **Breaking rename** — `Invoke-CCScriptMultiAccountRegion` is now `Invoke-CHARScriptMultiRegionProfile`. The new name better reflects that it iterates regions per profile.
- Private/internal functions (`New-AWSParamSplat`, `CFNPrivateFunctions`) were not renamed; only their comment references were updated.
- The `CHAR` prefix was chosen to be more unique, clearly identifying these as Charland's custom functions, and avoiding potential naming conflicts with other modules.
- All source files have been signed with Authenticode certificates in this release.
- This is the first stable (non-beta) release.

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
