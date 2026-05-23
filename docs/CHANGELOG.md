# Changelog

All notable changes to the CharlandCustomizations module will be documented in this file.

## [0.5.0] - 2026-05-21

### Added
- P

### Changed
- Refactoring/prepairing for intial PowerShell Gallery

### Fixed
- invoke-ScripMultiAccountRegion works as expected


## [0.4.0] - 2026-05-18

### Added
- 

### Changed
- 

### Fixed
- 
## [0.3.5] - 2026-05-08

### Added

- **CFNStackDirectoryInfo class** (`Private/CFNStackDirectoryInfo.ps1`)
  - Defines standard file naming conventions for CloudFormation stack directories
  - Provides static properties for all file names (template.template, parameters.json, etc.)
  - Path helper methods (GetTemplatePath, GetParametersPath, GetStackExportPath, etc.)
  - ValidateForDeploy method to check required files exist
  - NewTemplateS3Key method for consistent S3 key generation
- **CloudFormation Directory functions** (`Public/AWS/CloudFormationDirectory.psm1`)
  - `Out-CFNStackDirectory` - Export existing stacks to directory structure
  - `Build-CFNStackDirectory` - Scaffold directory from template source
  - `New-CFNStackFromDirectory` - Deploy stack from directory
  - `Update-CFNStackFromDirectory` - Update stack via change set from directory
  - `Convert-TemplateParameterToParameter` - Convert Test-CFNTemplate output to deploy params
  - `New-AWSCommonParams` / `Find-CFNTemplateBucket` internal helpers
- **Account Info functions** (`Public/AWS/AccountInfo.psm1`)
  - `Out-AWSNetworkingComponent` - Export VPC networking configuration to files
  - `Out-AWSSupportingInfo` - Export SSM parameters, secrets, and CFN exports
- **Test-CommitSignatures** function added to module (`Public/Git/`)
  - Supports both GPG and SSH signing validation
  - Wrapper script `Validate-CommitSignatures.ps1` for backward compatibility
- **Commit signing enforcement**
  - Pre-commit hook supporting GPG and SSH signing (`.githooks/pre-commit`)
  - `Setup-GitHooks.ps1` to install hooks with signing method detection
  - Updated steering docs with SSH and GPG signing instructions
- **Pester test suite** (`Tests/`)
  - `CFNStackDirectoryInfo.Tests.ps1` - 30 tests for the class (no AWS needed)
  - `CloudFormationDirectory.Tests.ps1` - 12 tests with mocked AWS calls
  - Requires Pester 5.x

### Changed

- Refactored `CloudFormation-TemplateProcessing.psm1` to use `[CFNStackDirectoryInfo]` class
  - Removed hardcoded file name constants (TEMPLATE_FILENAME, PARAMETERS_FILENAME, etc.)
  - Replaced inline S3 key generation with `[CFNStackDirectoryInfo]::NewTemplateS3Key()`
  - Added Write-Verbose for each file save operation in Out-CFNStackInfo
  - Dot-sources CFNStackDirectoryInfo.ps1 for class availability in nested module
- Renamed `Build-AWSCommonParams` to `New-AWSCommonParams` (better verb choice)
- Module manifest updated with ScriptsToProcess, new NestedModules, and FileList entries
- Added 'CloudFormation' tag to module metadata

### Fixed

- Removed stray `Public/CharlandCustomizations.psd1` that referenced non-existent ImportGuard.ps1
- Fixed `New-CFNStackFromDirectory` bug where capabilities.json was never read
- Fixed SSH signing detection in commit validation tools

## [0.3.4] - 2026-04-29

### Added

-

### Changed

-

### Fixed

- Working out deployment issues with new build script and signing process

## [0.3.3] - 2026-04-29

### Added

-

### Changed

-

### Fixed

-

## [0.3.0] - 2024-10-31

### Changed

- **Major repository restructure** for better organization
  - Moved module to `src/CharlandCustomizations/`
  - Removed version number from module path
  - Organized functions into `Public/` and `Private/` directories
  - Grouped public functions by domain (AWS, General)
- **Scripts organization**
  - Created `Scripts/` directory for build and deployment scripts
- **Module improvements**
  - Updated manifest to version 0.3.0
  - Improved module loading with auto-discovery of functions
  - Better separation of concerns

### Added

- Build script (`Scripts/Build-Module.ps1`) for validation, signing, and installation
- Comprehensive documentation in `.kiro/steering/`
  - AWS tools reference
  - PowerShell module development guidelines
  - Repository organization guide
- Updated README with quick start and usage examples

### Removed

- Hardcoded version directory (`0.2.2/`)

## [0.2.2] - 2023-08-12

### Added

- AWS MFA session management
- CloudFormation drift detection
- Stack error finding utilities
- Profile management functions
- File signing utilities

### Changed

- Updated to use Sectigo code signing certificate
- Improved AWS Tools import guard

## Earlier Versions

See git history for changes prior to 0.2.2
