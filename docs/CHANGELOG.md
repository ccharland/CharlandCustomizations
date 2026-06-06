# Changelog

All notable changes to the CharlandCustomizations module will be documented in this file.

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
