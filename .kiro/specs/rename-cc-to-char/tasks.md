# Implementation Plan: Rename CC Prefix to CHAR

## Overview

Rename all 40 public functions from "CC" prefix to "CHAR" prefix, strip all Authenticode signature blocks, update aliases, variables, exports, tests, and documentation. All changes must be committed together for the module to remain functional.

## Tasks

- [x] 1. Strip Authenticode signature blocks from all source files
  - [x] 1.1 Remove signature blocks from all `.ps1` files in `src/CharlandCustomizations/Public/` (6 files) and `src/CharlandCustomizations/Public/Git/` (2 files)
    - Remove everything between `# SIG # Begin signature block` and `# SIG # End signature block` (inclusive) plus the blank line before the SIG marker
    - _Requirements: 11.1, 11.2_
  - [x] 1.2 Remove signature blocks from all `.psm1` files in `src/CharlandCustomizations/Public/AWS/` and subdirectories (5 files: AWSCustomizations.psm1, CloudFormation-TemplateProcessing.psm1, S3Customizations.psm1, Audit-AWSAccount.psm1, Lambda-Customizations.psm1)
    - _Requirements: 11.1, 11.2_
  - [x] 1.3 Remove signature blocks from `src/CharlandCustomizations/Public/Git/GitCustomizations.psm1` if present
    - _Requirements: 11.1, 11.2_
  - [x] 1.4 Remove signature blocks from private function files (`Private/CFNPrivateFunctions.ps1`, `Private/New-AWSParamSplat.ps1`)
    - _Requirements: 11.1, 11.2_

- [ ] 2. Rename standalone .ps1 files and update function definitions
  - [-] 2.1 Rename `Public/Clear-CCAuthenticodeSignature.ps1` → `Clear-CHARAuthenticodeSignature.ps1` and update function definition, help examples, and alias references inside
    - _Requirements: 1.1, 2.1, 2.2, 4.1, 4.2, 7.1, 7.2_
  - [-] 2.2 Rename `Public/Set-CCAuthenticodeSignature.ps1` → `Set-CHARAuthenticodeSignature.ps1` and update function definition, help, aliases, and `$script:CCIsWindows` → `$script:IsWindows`
    - _Requirements: 1.1, 2.1, 2.2, 4.1, 4.2, 5.1, 5.2, 7.1, 7.2_
  - [-] 2.3 Rename `Public/Test-CCAuthenticodeSignature.ps1` → `Test-CHARAuthenticodeSignature.ps1` and update function definition, help, and `$script:CCIsWindows` → `$script:IsWindows`
    - _Requirements: 1.1, 2.1, 2.2, 5.1, 5.2, 7.1, 7.2_
  - [-] 2.4 Rename `Public/Install-CCProfilesFromSource.ps1` → `Install-CHARProfilesFromSource.ps1` and update function definition and help
    - _Requirements: 1.1, 2.1, 2.2, 7.1, 7.2_
  - [-] 2.5 Rename `Public/Invoke-CCScriptMultiRegionProfile.ps1` → `Invoke-CHARScriptMultiRegionProfile.ps1` and update function definition, help, and internal cross-references to other CC-prefixed functions
    - _Requirements: 1.1, 2.1, 2.2, 7.1, 7.2, 8.1, 8.2_
  - [~] 2.6 Rename `Public/Update-CCPowershell7.ps1` → `Update-CHARPowershell7.ps1` and update function definition and help
    - _Requirements: 1.1, 2.1, 2.2, 7.1, 7.2_
  - [~] 2.7 Rename `Public/Git/Test-CCCommitSignature.ps1` → `Test-CHARCommitSignature.ps1` and update function definition and help
    - _Requirements: 1.1, 2.1, 2.2, 7.1, 7.2_
  - [~] 2.8 Rename `Public/Git/Install-CCGitHook.ps1` → `Install-CHARGitHook.ps1` and update function definition and help
    - _Requirements: 1.1, 2.1, 2.2, 7.1, 7.2_

- [ ] 3. Update nested module function definitions, exports, and cross-references
  - [~] 3.1 Update `AWSCustomizations.psm1` — rename all 11 function definitions, update `Export-ModuleMember`, update help examples and internal cross-references between functions
    - Functions: Get-CCAWSMFASession→Get-CHARAWSMFASession, Find-CCCFNStackError→Find-CHARCFNStackError, Set-CCAWSProfileWithMFA→Set-CHARAWSProfileWithMFA, Set-CCAWSEnv→Set-CHARAWSEnv, Remove-CCExpiredAWSProfile→Remove-CHARExpiredAWSProfile, Get-CCAccountListFromProfile→Get-CHARAccountListFromProfile, Start-CCMultiStackDriftDetection→Start-CHARMultiStackDriftDetection, Get-CCAWSAccountListOfDriftedResource→Get-CHARAWSAccountListOfDriftedResource, Get-CCAWSObjectCount→Get-CHARAWSObjectCount, Use-CCAssumedRole→Use-CHARAssumedRole, Update-CCSSOCredentialList→Update-CHARSSOCredentialList
    - _Requirements: 1.2, 6.1, 7.1, 7.2, 8.1, 8.2_
  - [~] 3.2 Update `CloudFormation-TemplateProcessing.psm1` — rename all 6 function definitions, update `Export-ModuleMember`, update help and cross-references
    - Functions: New-CCCFNStackFromDirectory→New-CHARCFNStackFromDirectory, Test-CCCFNStackFromDirectory→Test-CHARCFNStackFromDirectory, Out-CCCFNStackInfo→Out-CHARCFNStackInfo, Update-CCCFNStackFromDirectory→Update-CHARCFNStackFromDirectory, New-CCCFNStackDirectory→New-CHARCFNStackDirectory, Edit-CCCFTTEbsVolume→Edit-CHARCFTTEbsVolume
    - _Requirements: 1.2, 6.1, 7.1, 7.2, 8.1, 8.2_
  - [~] 3.3 Update `S3Customizations.psm1` — rename `Clear-CCS3Bucket` → `Clear-CHARS3Bucket` and update `Export-ModuleMember`
    - _Requirements: 1.2, 6.1, 7.1_
  - [~] 3.4 Update `Audit-AWSAccount.psm1` — rename all 13 function definitions, update `Export-ModuleMember`, update help and cross-references
    - Functions: Get-CCEC2SGInUse→Get-CHAREC2SGInUse, Get-CCEC2Count→Get-CHAREC2Count, Find-CCEC2DBSG→Find-CHAREC2DBSG, Out-CCAWSSupportingInfo→Out-CHARAWSSupportingInfo, Out-CCAWSNetworkingComponent→Out-CHARAWSNetworkingComponent, Get-CCIAMAuditList→Get-CHARIAMAuditList, Get-CCGlobalAuditReportItem→Get-CHARGlobalAuditReportItem, Get-CCEC2KeyTagNameStatus→Get-CHAREC2KeyTagNameStatus, Get-CCEC2SnapshotReport→Get-CHAREC2SnapshotReport, Get-CCEC2VolumeReport→Get-CHAREC2VolumeReport, Start-CCEC2RetryLoop→Start-CHAREC2RetryLoop, Find-CCOpenSecurityGroup→Find-CHAROpenSecurityGroup, Get-CCAllEC2Patch→Get-CHARAllEC2Patch
    - _Requirements: 1.2, 6.1, 7.1, 7.2, 8.1, 8.2_
  - [~] 3.5 Update `Lambda-Customizations.psm1` — rename `Get-CCDeprecatedLMFunctionList` → `Get-CHARDeprecatedLMFunctionList` and update `Export-ModuleMember`
    - _Requirements: 1.2, 6.1, 7.1_
  - [~] 3.6 Update `GitCustomizations.psm1` — update dot-source paths to renamed `.ps1` files and update `Export-ModuleMember` list
    - Change `. $PSScriptRoot/Test-CCCommitSignature.ps1` → `. $PSScriptRoot/Test-CHARCommitSignature.ps1`
    - Change `. $PSScriptRoot/Install-CCGitHook.ps1` → `. $PSScriptRoot/Install-CHARGitHook.ps1`
    - Update Export-ModuleMember: `'Install-CHARGitHook', 'Test-CHARCommitSignature'`
    - _Requirements: 6.1, 8.3_

- [ ] 4. Update module manifest and private function comments
  - [~] 4.1 Update `CharlandCustomizations.psd1` — replace all 40 entries in `FunctionsToExport` with CHAR-prefixed names and replace both entries in `AliasesToExport` with CHAR-prefixed names
    - _Requirements: 1.3, 3.1, 3.2_
  - [~] 4.2 Update `Private/CFNPrivateFunctions.ps1` — update comment-based help references to public function names (CC→CHAR)
    - _Requirements: 7.3_
  - [~] 4.3 Update `Private/New-AWSParamSplat.ps1` — update any comment references to public function names (CC→CHAR) if present
    - _Requirements: 7.3_

- [~] 5. Checkpoint — verify module loads
  - Run `Import-Module ./src/CharlandCustomizations -Force` and confirm no errors
  - Run `(Get-Command -Module CharlandCustomizations).Count` and confirm it equals 40
  - Spot-check a few function names to confirm CHAR prefix is correct

- [ ] 6. Rename and update test files
  - [~] 6.1 Rename and update AWS test files (9 files in `tests/Unit/AWS/`)
    - `Find-CCCFNStackError.Tests.ps1` → `Find-CHARCFNStackError.Tests.ps1`
    - `Get-CCAWSAccountListOfDriftedResource.Tests.ps1` → `Get-CHARAWSAccountListOfDriftedResource.Tests.ps1`
    - `Get-CCAWSObjectCount.Tests.ps1` → `Get-CHARAWSObjectCount.Tests.ps1`
    - `Remove-CCExpiredAWSProfile.Tests.ps1` → `Remove-CHARExpiredAWSProfile.Tests.ps1`
    - `Set-CCAWSEnv.Tests.ps1` → `Set-CHARAWSEnv.Tests.ps1`
    - `Set-CCAWSProfileWithMFA.Tests.ps1` → `Set-CHARAWSProfileWithMFA.Tests.ps1`
    - `Start-CCMultiStackDriftDetection.Tests.ps1` → `Start-CHARMultiStackDriftDetection.Tests.ps1`
    - `Update-CCSSOCredentialList.Tests.ps1` → `Update-CHARSSOCredentialList.Tests.ps1`
    - `Use-CCAssumedRole.Tests.ps1` → `Use-CHARAssumedRole.Tests.ps1`
    - Update all function references and dot-source paths inside each file
    - _Requirements: 9.1, 9.2, 9.3, 9.4_
  - [~] 6.2 Rename and update S3 test file
    - `tests/Unit/AWS/S3/Clear-CCS3Bucket.Tests.ps1` → `Clear-CHARS3Bucket.Tests.ps1`
    - _Requirements: 9.1, 9.2, 9.3, 9.4_
  - [~] 6.3 Rename and update Lambda test file
    - `tests/Unit/AWS/Lambda/Get-CCDeprecatedLMFunctionList.Tests.ps1` → `Get-CHARDeprecatedLMFunctionList.Tests.ps1`
    - _Requirements: 9.1, 9.2, 9.3, 9.4_
  - [~] 6.4 Update Audit test files (content + rename where applicable)
    - `tests/Unit/AWS/Audit/Audit-Functions.Tests.ps1` — update all function name references (content only)
    - `tests/Unit/AWS/Audit/Get-CCAllEC2Patch.Tests.ps1` → `Get-CHARAllEC2Patch.Tests.ps1`
    - _Requirements: 9.1, 9.2, 9.4_
  - [~] 6.5 Rename and update CloudFormation test files (6 files)
    - `Edit-CCCFTTEbsVolume.Tests.ps1` → `Edit-CHARCFTTEbsVolume.Tests.ps1`
    - `New-CCCFNStackDirectory.Tests.ps1` → `New-CHARCFNStackDirectory.Tests.ps1`
    - `New-CCCFNStackFromDirectory.Tests.ps1` → `New-CHARCFNStackFromDirectory.Tests.ps1`
    - `Out-CCCFNStackInfo.Tests.ps1` → `Out-CHARCFNStackInfo.Tests.ps1`
    - `Test-CCCFNStackFromDirectory.Tests.ps1` → `Test-CHARCFNStackFromDirectory.Tests.ps1`
    - `Update-CCCFNStackFromDirectory.Tests.ps1` → `Update-CHARCFNStackFromDirectory.Tests.ps1`
    - Update all function references inside each file
    - _Requirements: 9.1, 9.2, 9.3, 9.4_
  - [~] 6.6 Rename and update Core test files (5 files)
    - `Clear-CCAuthenticodeSignature.Tests.ps1` → `Clear-CHARAuthenticodeSignature.Tests.ps1`
    - `Install-CCProfilesFromSource.Tests.ps1` → `Install-CHARProfilesFromSource.Tests.ps1`
    - `Invoke-CCScriptMultiRegionProfile.Tests.ps1` → `Invoke-CHARScriptMultiRegionProfile.Tests.ps1`
    - `Set-CCFileSignature.Tests.ps1` → `Set-CHARFileSignature.Tests.ps1`
    - `Update-CCPowershell7.Tests.ps1` → `Update-CHARPowershell7.Tests.ps1`
    - Update all function references and dot-source paths inside each file
    - _Requirements: 9.1, 9.2, 9.3, 9.4_
  - [~] 6.7 Rename and update Git test files (2 files)
    - `Install-CCGitHook.Tests.ps1` → `Install-CHARGitHook.Tests.ps1`
    - `Test-CCCommitSignature.Tests.ps1` → `Test-CHARCommitSignature.Tests.ps1`
    - Update all function references and dot-source paths inside each file
    - _Requirements: 9.1, 9.2, 9.3, 9.4_
  - [~] 6.8 Update remaining test files (content only, no rename needed)
    - `tests/Unit/Core/CFNPrivateFunctions.Tests.ps1` — update any references to public CC-prefixed functions
    - `tests/Unit/Core/CharlandCustomizations.Manifest.Tests.ps1` — update function name references
    - `tests/Unit/Help/HelpDiscoverability.Tests.ps1` — update function name references
    - `tests/New-AWSParamSplat.Tests.ps1` — check for public function references
    - `tests/Test-HelpCompliance.Tests.ps1` — check for function name references
    - `tests/Test-ManifestCompliance.Tests.ps1` — check for function name references
    - `tests/Test-SignatureCompliance.Tests.ps1` — check for function name references
    - _Requirements: 9.1, 9.2_

- [ ] 7. Update documentation and script files
  - [~] 7.1 Update `docs/QUICK-REFERENCE.md` — replace all CC-prefixed function names with CHAR-prefixed
    - _Requirements: 10.1, 10.2_
  - [~] 7.2 Update `docs/CloudFormation-TemplateProcessing.md` — replace all CC-prefixed function names with CHAR-prefixed
    - _Requirements: 10.1, 10.2_
  - [~] 7.3 Update `docs/AWS-Account-Audit.md` — replace all CC-prefixed function names with CHAR-prefixed
    - _Requirements: 10.1, 10.2_
  - [~] 7.4 Update `docs/STRUCTURE.md` — update function names and file paths
    - _Requirements: 10.1, 10.2_
  - [~] 7.5 Update `docs/CHANGELOG.md` — add entry documenting the CC→CHAR prefix change
    - _Requirements: 10.1_
  - [~] 7.6 Update `docs/INSTALLATION.md` — update usage examples
    - _Requirements: 10.1, 10.2_
  - [~] 7.7 Update `docs/TEST-PLAN.md` — update function name references
    - _Requirements: 10.1_
  - [~] 7.8 Update `docs/parameter-reference.md` — update function name references
    - _Requirements: 10.1, 10.2_
  - [~] 7.9 Update `docs/NEW-FEATURE-PARAMETERS.md` — update function name references
    - _Requirements: 10.1, 10.2_
  - [~] 7.10 Update `README.md` — update any function name references
    - _Requirements: 10.1, 10.2_
  - [~] 7.11 Update `Scripts/` directory files — check and update any CC-prefixed function references in build/test/publish scripts
    - _Requirements: 10.1_

- [~] 8. Final verification
  - Run `Import-Module ./src/CharlandCustomizations -Force` — must succeed with no errors
  - Run `Get-Command -Module CharlandCustomizations | Select-Object Name | Sort-Object Name` — confirm all 40 CHAR-prefixed names appear
  - Run `Invoke-Pester ./tests -PassThru` — all tests must pass
  - Grep the entire `src/` and `tests/` tree for `-CC[A-Z]` pattern — should find zero matches in code files (excluding .git)
  - _Requirements: 12.1, 12.2, 12.3_

## Task Dependency Graph

```json
{
  "waves": [
    {
      "wave": 1,
      "tasks": ["1"],
      "description": "Strip all Authenticode signature blocks first to avoid false CC matches in base64"
    },
    {
      "wave": 2,
      "tasks": ["2", "3", "4"],
      "description": "Core rename — standalone files, nested modules, and manifest (must all complete for module to load)"
    },
    {
      "wave": 3,
      "tasks": ["5"],
      "description": "Checkpoint — verify module loads after core rename"
    },
    {
      "wave": 4,
      "tasks": ["6", "7"],
      "description": "Update test files and documentation (can be done in parallel)"
    },
    {
      "wave": 5,
      "tasks": ["8"],
      "description": "Final verification — import, test, grep for old names"
    }
  ]
}
```

## Notes

- PBT is not applicable — this is a deterministic bulk rename, not algorithmic logic
- Private functions (`New-AWSParamSplat`, `CFNPrivateFunctions`) are NOT renamed — only their comments are updated
- All Authenticode signature blocks are stripped first to simplify the rename and avoid base64 false positives
- The root module (`CharlandCustomizations.psm1`) uses wildcard glob to dot-source `Public/*.ps1` files, so it does NOT need filename updates
- `$script:CCIsWindows` is simplified to `$script:IsWindows` (the `$script:` scope provides sufficient namespacing)
- All changes should be committed together to avoid a broken intermediate state
- Files will be re-signed after all renames are complete (outside this spec's scope)
