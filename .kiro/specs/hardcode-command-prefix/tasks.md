# Implementation Plan: Hardcode Command Prefix

## Overview

Rename all 37 public functions to embed the "CC" prefix directly in the noun, remove `DefaultCommandPrefix` from the manifest, and update all references across source, tests, and documentation. The core rename (tasks 1–2) must be applied atomically for the module to remain functional.

## Tasks

- [x] 1. Core rename — standalone .ps1 files and function definitions
  - [x] 1.1 Rename `Public/Clear-AuthenticodeSignature.ps1` → `Clear-CCAuthenticodeSignature.ps1` and update `function Clear-AuthenticodeSignature` → `function Clear-CCAuthenticodeSignature` inside the file
    - Also update any `.EXAMPLE` help and cross-references within the file
    - _Requirements: 2.1, 3.1, 3.2, 5.1, 5.2_
  - [x] 1.2 Rename `Public/Install-ProfilesFromSource.ps1` → `Install-CCProfilesFromSource.ps1` and update function definition and help
    - _Requirements: 2.1, 3.1, 3.2, 5.1, 5.2_
  - [x] 1.3 Rename `Public/Invoke-ScriptMultiAccountRegion.ps1` → `Invoke-CCScriptMultiAccountRegion.ps1` and update function definition and help
    - _Requirements: 2.1, 3.1, 3.2, 5.1, 5.2_
  - [x] 1.4 Rename `Public/Set-FileSignature.ps1` → `Set-CCFileSignature.ps1` and update function definition and help
    - _Requirements: 2.1, 3.1, 3.2, 5.1, 5.2_
  - [x] 1.5 Rename `Public/Update-Powershell7.ps1` → `Update-CCPowershell7.ps1` and update function definition and help
    - _Requirements: 2.1, 3.1, 3.2, 5.1, 5.2_
  - [x] 1.6 Rename `Public/Git/Test-CommitSignatures.ps1` → `Test-CCCommitSignatures.ps1` and update function definition and help
    - _Requirements: 2.1, 3.1, 3.2, 5.1, 5.2_
  - [x] 1.7 Rename `Public/Git/Install-GitHooks.ps1` → `Install-CCGitHooks.ps1` and update function definition and help
    - _Requirements: 2.1, 3.1, 3.2, 5.1, 5.2_

- [x] 2. Core rename — nested module function definitions, exports, and manifest
  - [x] 2.1 Update `AWSCustomizations.psm1` — rename all 11 function definitions and update `Export-ModuleMember` list
    - Functions: Get-AWSMFASession→Get-CCAWSMFASession, Find-CFNStackError→Find-CCCFNStackError, Set-AWSProfileWithMFA→Set-CCAWSProfileWithMFA, Set-AWSEnv→Set-CCAWSEnv, Remove-ExpiredAWSProfiles→Remove-CCExpiredAWSProfiles, Get-AccountListFromProfiles→Get-CCAccountListFromProfiles, Start-MultiStackDriftDetection→Start-CCMultiStackDriftDetection, Get-AWSAccountListOfDriftedResources→Get-CCAWSAccountListOfDriftedResources, Get-AWSObjectCount→Get-CCAWSObjectCount, Use-AssumedRole→Use-CCAssumedRole, Update-SSOCredentialList→Update-CCSSOCredentialList
    - Also update help examples and any internal cross-references between these functions
    - _Requirements: 2.2, 4.1, 5.1, 5.2, 8.1, 8.2_
  - [x] 2.2 Update `CloudFormation-TemplateProcessing.psm1` — rename all 6 function definitions and update `Export-ModuleMember` list
    - Functions: New-CFNStackFromDirectory→New-CCCFNStackFromDirectory, Test-CFNStackFromDirectory→Test-CCCFNStackFromDirectory, Out-CFNStackInfo→Out-CCCFNStackInfo, Update-CFNStackFromDirectory→Update-CCCFNStackFromDirectory, New-CFNStackDirectory→New-CCCFNStackDirectory, Edit-CFTTEbsVolumes→Edit-CCCFTTEbsVolumes
    - Also update help examples and internal cross-references
    - _Requirements: 2.2, 4.1, 5.1, 5.2, 8.1, 8.2_
  - [x] 2.3 Update `S3Customizations.psm1` — rename `Clear-S3Bucket` → `Clear-CCS3Bucket` and update `Export-ModuleMember`
    - _Requirements: 2.2, 4.1, 5.1, 5.2_
  - [x] 2.4 Update `Audit-AWSAccount.psm1` — rename all 12 function definitions and update `Export-ModuleMember` list
    - Functions: Get-EC2SGInUse→Get-CCEC2SGInUse, Get-EC2Count→Get-CCEC2Count, Find-EC2DBSG→Find-CCEC2DBSG, Out-AWSSupportingInfo→Out-CCAWSSupportingInfo, Out-AWSNetworkingComponent→Out-CCAWSNetworkingComponent, Get-IAMAuditList→Get-CCIAMAuditList, Get-GlobalAuditReportItem→Get-CCGlobalAuditReportItem, Get-EC2KeyTagNameStatus→Get-CCEC2KeyTagNameStatus, Get-EC2SnapshotReport→Get-CCEC2SnapshotReport, Get-EC2VolumeReport→Get-CCEC2VolumeReport, Start-EC2RetryLoop→Start-CCEC2RetryLoop, Find-OpenSecurityGroup→Find-CCOpenSecurityGroup
    - Also update help examples and internal cross-references
    - _Requirements: 2.2, 4.1, 5.1, 5.2, 8.1, 8.2_
  - [x] 2.5 Update `GitCustomizations.psm1` — update dot-source paths to renamed `.ps1` files and update `Export-ModuleMember` list
    - Change `. $PSScriptRoot/Test-CommitSignatures.ps1` → `. $PSScriptRoot/Test-CCCommitSignatures.ps1`
    - Change `. $PSScriptRoot/Install-GitHooks.ps1` → `. $PSScriptRoot/Install-CCGitHooks.ps1`
    - Update Export-ModuleMember: `'Test-CCCommitSignatures', 'Install-CCGitHooks'`
    - _Requirements: 4.1_
  - [x] 2.6 Update `CharlandCustomizations.psd1` — replace entire `FunctionsToExport` list with CC-prefixed names and remove `DefaultCommandPrefix = 'CC'`
    - All 37 functions must appear with their new CC-prefixed names
    - The `DefaultCommandPrefix` line must be removed entirely
    - _Requirements: 1.1, 1.2, 2.3_

- [x] 3. Checkpoint — verify module loads
  - Run `Import-Module ./src/CharlandCustomizations -Force` and confirm no errors
  - Run `(Get-Command -Module CharlandCustomizations).Count` and confirm it equals 37
  - Ensure all tests pass, ask the user if questions arise.

- [x] 4. Rename and update test files
  - [x] 4.1 Rename and update AWS test files
    - `tests/Unit/AWS/Find-CFNStackError.Tests.ps1` → `Find-CCCFNStackError.Tests.ps1` — update all function references inside
    - `tests/Unit/AWS/Get-AWSAccountListOfDriftedResources.Tests.ps1` → `Get-CCAWSAccountListOfDriftedResources.Tests.ps1` — update references
    - `tests/Unit/AWS/Get-AWSObjectCount.Tests.ps1` → `Get-CCAWSObjectCount.Tests.ps1` — update references
    - `tests/Unit/AWS/Remove-ExpiredAWSProfiles.Tests.ps1` → `Remove-CCExpiredAWSProfiles.Tests.ps1` — update references
    - `tests/Unit/AWS/Set-AWSEnv.Tests.ps1` → `Set-CCAWSEnv.Tests.ps1` — update references
    - `tests/Unit/AWS/Set-AWSProfileWithMFA.Tests.ps1` → `Set-CCAWSProfileWithMFA.Tests.ps1` — update references
    - `tests/Unit/AWS/Start-MultiStackDriftDetection.Tests.ps1` → `Start-CCMultiStackDriftDetection.Tests.ps1` — update references
    - `tests/Unit/AWS/Update-SSOCredentialList.Tests.ps1` → `Update-CCSSOCredentialList.Tests.ps1` — update references
    - `tests/Unit/AWS/Use-AssumedRole.Tests.ps1` → `Use-CCAssumedRole.Tests.ps1` — update references
    - _Requirements: 6.1, 6.2, 6.3, 6.4_
  - [x] 4.2 Rename and update S3 test file
    - `tests/Unit/AWS/S3/Clear-S3Bucket.Tests.ps1` → `Clear-CCS3Bucket.Tests.ps1` — update references
    - _Requirements: 6.1, 6.2, 6.3, 6.4_
  - [x] 4.3 Update Audit test file (content only, filename doesn't match a single function)
    - `tests/Unit/AWS/Audit/Audit-Functions.Tests.ps1` — update all function name references to CC-prefixed names
    - _Requirements: 6.1, 6.2_
  - [x] 4.4 Rename and update CloudFormation test files
    - `tests/Unit/CloudFormation/Edit-CFTTEbsVolumes.Tests.ps1` → `Edit-CCCFTTEbsVolumes.Tests.ps1`
    - `tests/Unit/CloudFormation/New-CFNStackDirectory.Tests.ps1` → `New-CCCFNStackDirectory.Tests.ps1`
    - `tests/Unit/CloudFormation/New-CFNStackFromDirectory.Tests.ps1` → `New-CCCFNStackFromDirectory.Tests.ps1`
    - `tests/Unit/CloudFormation/Out-CFNStackInfo.Tests.ps1` → `Out-CCCFNStackInfo.Tests.ps1`
    - `tests/Unit/CloudFormation/Test-CFNStackFromDirectory.Tests.ps1` → `Test-CCCFNStackFromDirectory.Tests.ps1`
    - `tests/Unit/CloudFormation/Update-CFNStackFromDirectory.Tests.ps1` → `Update-CCCFNStackFromDirectory.Tests.ps1`
    - Update all function references inside each file
    - _Requirements: 6.1, 6.2, 6.3, 6.4_
  - [x] 4.5 Rename and update Core test files
    - `tests/Unit/Core/Clear-AuthenticodeSignature.Tests.ps1` → `Clear-CCAuthenticodeSignature.Tests.ps1`
    - `tests/Unit/Core/Install-ProfilesFromSource.Tests.ps1` → `Install-CCProfilesFromSource.Tests.ps1`
    - `tests/Unit/Core/Invoke-ScriptMultiAccountRegion.Tests.ps1` → `Invoke-CCScriptMultiAccountRegion.Tests.ps1`
    - `tests/Unit/Core/Set-FileSignature.Tests.ps1` → `Set-CCFileSignature.Tests.ps1`
    - `tests/Unit/Core/Update-Powershell7.Tests.ps1` → `Update-CCPowershell7.Tests.ps1`
    - Update all function references and dot-source paths inside each file
    - _Requirements: 6.1, 6.2, 6.3, 6.4_
  - [x] 4.6 Rename and update Git test files
    - `tests/Unit/Git/Install-GitHooks.Tests.ps1` → `Install-CCGitHooks.Tests.ps1`
    - `tests/Unit/Git/Test-CommitSignatures.Tests.ps1` → `Test-CCCommitSignatures.Tests.ps1`
    - Update all function references and dot-source paths inside each file
    - _Requirements: 6.1, 6.2, 6.3, 6.4_
  - [x] 4.7 Update `tests/New-AWSParamSplat.Tests.ps1` — check for any references to public functions and update to CC-prefixed names (private function name `New-AWSParamSplat` stays unchanged)
    - _Requirements: 6.1_
  - [x] 4.8 Update `tests/Unit/Help/HelpDiscoverability.Tests.ps1` — update any function name references to CC-prefixed names
    - _Requirements: 6.1, 6.2_

- [x] 5. Update documentation files
  - [x] 5.1 Update `docs/QUICK-REFERENCE.md` — replace all old function names with CC-prefixed names
    - _Requirements: 7.1, 7.2_
  - [x] 5.2 Update `docs/CloudFormation-TemplateProcessing.md` — replace all old function names with CC-prefixed names
    - _Requirements: 7.1, 7.2_
  - [x] 5.3 Update `docs/AWS-Account-Audit.md` — replace all old function names with CC-prefixed names
    - _Requirements: 7.1, 7.2_
  - [x] 5.4 Update `docs/STRUCTURE.md` — update function names and file paths to reflect renames
    - _Requirements: 7.1, 7.2_
  - [x] 5.5 Update `docs/CHANGELOG.md` — add entry documenting the prefix change
    - _Requirements: 7.1_
  - [x] 5.6 Update `docs/INSTALLATION.md` — update any usage examples with CC-prefixed names
    - _Requirements: 7.1, 7.2_
  - [x] 5.7 Update `docs/TEST-PLAN.md` — update function name references
    - _Requirements: 7.1_
  - [x] 5.8 Update `docs/parameter-reference.md` — update function name references
    - _Requirements: 7.1, 7.2_
  - [x] 5.9 Update `docs/NEW-FEATURE-PARAMETERS.md` — update function name references
    - _Requirements: 7.1, 7.2_
  - [x] 5.10 Update `README.md` — update any function name references in the project root readme
    - _Requirements: 7.1, 7.2_

- [x] 6. Final verification
  - Run `Import-Module ./src/CharlandCustomizations -Force` — must succeed with no errors
  - Run `Get-Command -Module CharlandCustomizations | Select-Object Name | Sort-Object Name` — confirm all 37 CC-prefixed names appear
  - Run `Invoke-Pester ./tests -PassThru` — all tests must pass
  - Run `Invoke-ScriptAnalyzer -Path ./src -Recurse` — no errors on modified files
  - Grep the entire `src/` and `tests/` tree for any remaining old (non-prefixed) function names — should find zero matches in code files
  - Ensure all tests pass, ask the user if questions arise.
  - _Requirements: 9.1, 9.2_

## Task Dependency Graph

```json
{
  "waves": [
    {
      "wave": 1,
      "tasks": ["1", "2"],
      "description": "Core rename — standalone files and nested modules (must complete together)"
    },
    {
      "wave": 2,
      "tasks": ["3"],
      "description": "Checkpoint — verify module loads after core rename"
    },
    {
      "wave": 3,
      "tasks": ["4", "5"],
      "description": "Update test files and documentation (can be done in parallel)"
    },
    {
      "wave": 4,
      "tasks": ["6"],
      "description": "Final verification — import, test, grep for old names"
    }
  ]
}
```

## Notes

- PBT is not applicable — this is a deterministic bulk rename, not algorithmic logic
- Private functions (`New-AWSParamSplat`, `CFNPrivateFunctions`) are NOT renamed
- All changes should be committed together to avoid a broken intermediate state
- The `CFNPrivateFunctions.Tests.ps1` file tests private helpers and should not need function name changes (verify during task 4)
- Tasks 1 and 2 form the atomic core — the module will not load correctly until both are complete
