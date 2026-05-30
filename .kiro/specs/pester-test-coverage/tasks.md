# Implementation Plan: Pester Test Coverage

## Overview

This plan implements a comprehensive Pester 5+ test suite for the CharlandCustomizations module. Tasks follow the risk-based priority from TEST-PLAN.md: infrastructure first, then P1 release blockers, P2 core workflows, P3 audit/reporting, help tests, and script tests. Each task creates test files that mirror the source structure, use mocks for external dependencies, and target 80%+ code coverage.

## Tasks

- [x] 1. Set up test infrastructure and Pester configuration
  - [x] 1.1 Create Pester configuration file and directory structure
    - Create `tests/pester.config.ps1` returning a `PesterConfiguration` object with Run.Path set to `tests/Unit/`, Filter.ExcludeTag set to `Integration`, CodeCoverage enabled targeting all `.ps1` and `.psm1` files under `src/CharlandCustomizations/`, CoveragePercentTarget of 80, JaCoCo output to `tests/coverage/coverage.xml`, and Detailed verbosity
    - Create directory structure: `tests/Unit/Core/`, `tests/Unit/AWS/`, `tests/Unit/AWS/S3/`, `tests/Unit/AWS/Audit/`, `tests/Unit/CloudFormation/`, `tests/Unit/Git/`, `tests/Unit/Scripts/`, `tests/Unit/Help/`, `tests/coverage/`
    - Add `tests/coverage/` to `.gitignore`
    - _Requirements: 1.1, 1.5, 9.1, 9.2, 9.3, 9.4, 10.6_

- [x] 2. Implement P1 release blocker tests — Core functions
  - [x] 2.1 Create Clear-AuthenticodeSignature tests
    - Create `tests/Unit/Core/Clear-AuthenticodeSignature.Tests.ps1` with Kiro attribution, BeforeAll dot-sourcing the SUT, `Unit` tag on Describe block
    - Test: file with signature block has content after marker removed (Req 2.3)
    - Test: file without signature block remains unchanged (Req 8.4)
    - Test: non-existent file path writes non-terminating error containing the path (Req 2.4)
    - Use `TestDrive:\` for filesystem isolation
    - _Requirements: 1.2, 1.3, 1.4, 2.3, 2.4, 8.4, 10.1_

  - [x] 2.2 Write property test for Clear-AuthenticodeSignature content preservation
    - **Property 1: Content preservation**
    - Implement parameterized test with 100 iterations of random content with/without signature blocks verifying content before marker is preserved and content after marker is removed
    - **Validates: Requirements 2.3, 8.4**

  - [x] 2.3 Create Set-FileSignature tests
    - Create `tests/Unit/Core/Set-FileSignature.Tests.ps1` with Kiro attribution, BeforeAll dot-sourcing the SUT, `Unit` tag
    - Test: no valid code-signing certificate throws terminating error "No valid codesign certificate found" (Req 2.5)
    - Test: Digicert issuer sets timestamp server to `http://timestamp.digicert.com` (Req 2.6)
    - Test: Sectigo issuer sets timestamp server to `http://timestamp.sectigo.com` (Req 2.7)
    - Test: unknown issuer without -TimeStampServer throws "No Timestamp server could be set, aborting." (Req 2.11, 8.5)
    - Mock `Get-ChildItem cert:\` to return fake certificate objects
    - _Requirements: 1.2, 1.3, 1.4, 2.5, 2.6, 2.7, 2.11, 8.5, 10.1_

  - [x] 2.4 Create Invoke-ScriptMultiAccountRegion tests
    - Create `tests/Unit/Core/Invoke-ScriptMultiAccountRegion.Tests.ps1` with Kiro attribution, BeforeAll dot-sourcing the SUT, `Unit` tag
    - Test: N profiles × M regions executes ScriptBlock N×M times (Req 2.8)
    - Test: -IncludeAccountId adds AccountId property matching Get-STSCallerIdentity (Req 2.9)
    - Test: AWS cmdlet exception writes warning with profile, region, and message (Req 8.1)
    - Test: no profile configured writes non-terminating error (Req 8.2)
    - Test: auth failure for one profile still processes subsequent profiles (Req 8.3)
    - Mock `Get-STSCallerIdentity`, `Set-AWSCredential`
    - _Requirements: 1.2, 1.3, 1.4, 2.8, 2.9, 8.1, 8.2, 8.3, 10.1_

  - [x] 2.5 Write property test for Invoke-ScriptMultiAccountRegion N×M execution
    - **Property 2: N×M execution count**
    - Generate random combinations of N profiles (1–5) and M regions (1–4), verify ScriptBlock executes exactly N×M times
    - **Validates: Requirements 2.8**

  - [x] 2.6 Write property test for Invoke-ScriptMultiAccountRegion output enrichment
    - **Property 3: Output enrichment**
    - For random profile/region combinations with -IncludeAccountId, verify every output object has AccountId matching the mocked Get-STSCallerIdentity value
    - **Validates: Requirements 2.9**

  - [x] 2.7 Create Install-GitHooks tests
    - Create `tests/Unit/Git/Install-GitHooks.Tests.ps1` with Kiro attribution, BeforeAll dot-sourcing the SUT, `Unit` tag
    - Test: source hook file copied to `.git/hooks/pre-commit` with matching content (Req 5.4)
    - Test: without -Force, existing hook prompts user via Read-Host (Req 5.5)
    - Test: with -Force, existing hook overwritten without prompt (Req 5.7)
    - Test: user declines overwrite prompt preserves existing hook (Req 5.8)
    - Test: missing source hook file writes error and does not create destination (Req 5.6)
    - Use `TestDrive:\` with temporary git directory structure
    - _Requirements: 1.2, 1.3, 1.4, 5.4, 5.5, 5.6, 5.7, 5.8, 10.1_

- [x] 3. Checkpoint - Ensure P1 core tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 4. Implement P1 release blocker tests — AWS functions
  - [x] 4.1 Create Clear-S3Bucket tests
    - Create `tests/Unit/AWS/S3/Clear-S3Bucket.Tests.ps1` with Kiro attribution, BeforeAll dot-sourcing the SUT, `Unit` tag
    - Test: -WhatIf does not call Remove-S3Object (Req 3.12)
    - Test: happy path calls Remove-S3Object for each versioned object
    - Mock `Get-S3Version`, `Remove-S3Object`
    - _Requirements: 1.2, 1.3, 1.4, 3.1, 3.12, 10.1_

  - [x] 4.2 Create Set-AWSProfileWithMFA tests
    - Create `tests/Unit/AWS/Set-AWSProfileWithMFA.Tests.ps1` with Kiro attribution, BeforeAll dot-sourcing the SUT, `Unit` tag
    - Test: valid profile and token calls Get-STSSessionToken with correct SerialNumber and TokenCode (Req 3.3)
    - Mock `Get-IAMMFADevice`, `Get-STSSessionToken`, `Set-AWSCredential`
    - _Requirements: 1.2, 1.3, 1.4, 3.1, 3.3, 10.1_

  - [x] 4.3 Create Remove-ExpiredAWSProfiles tests
    - Create `tests/Unit/AWS/Remove-ExpiredAWSProfiles.Tests.ps1` with Kiro attribution, BeforeAll dot-sourcing the SUT, `Unit` tag
    - Test: expired profile (ExpiredToken error) calls Remove-AWSCredentialProfile (Req 3.5)
    - Test: valid profile (Get-STSCallerIdentity succeeds) does not call Remove-AWSCredentialProfile (Req 3.13)
    - Mock `Get-STSCallerIdentity`, `Remove-AWSCredentialProfile`
    - _Requirements: 1.2, 1.3, 1.4, 3.1, 3.5, 3.13, 10.1_

  - [x] 4.4 Create Use-AssumedRole tests
    - Create `tests/Unit/AWS/Use-AssumedRole.Tests.ps1` with Kiro attribution, BeforeAll dot-sourcing the SUT, `Unit` tag
    - Test: valid role calls Use-STSRole with resolved ARN and Set-AWSCredential with temp credentials (Req 3.10)
    - Mock `Get-IAMRole`, `Use-STSRole`, `Set-AWSCredential`
    - _Requirements: 1.2, 1.3, 1.4, 3.1, 3.10, 10.1_

  - [x] 4.5 Create Update-SSOCredentialList tests
    - Create `tests/Unit/AWS/Update-SSOCredentialList.Tests.ps1` with Kiro attribution, BeforeAll dot-sourcing the SUT, `Unit` tag
    - Test: calls Register-SSOOIDCClient, Start-SSOOIDCDeviceAuthorization, New-SSOOIDCToken, and writes credentials (Req 3.11)
    - Mock all SSO cmdlets
    - _Requirements: 1.2, 1.3, 1.4, 3.1, 3.11, 10.1_

- [x] 5. Implement P1 release blocker tests — CloudFormation
  - [x] 5.1 Create New-CFNStackFromDirectory tests
    - Create `tests/Unit/CloudFormation/New-CFNStackFromDirectory.Tests.ps1` with Kiro attribution, BeforeAll dot-sourcing the SUT, `Unit` tag
    - Test: valid stack directory uploads template to S3, calls Test-CFNTemplate, calls New-CFNStack with correct args (Req 4.1)
    - Test: missing template.template file writes error (Req 4.7)
    - Test: parameter count mismatch throws error (Req 4.8)
    - Use `TestDrive:\` for stack directory fixtures
    - Mock `Write-S3Object`, `Test-CFNTemplate`, `New-CFNStack`
    - _Requirements: 1.2, 1.3, 1.4, 3.1, 4.1, 4.7, 4.8, 10.1_

  - [x] 5.2 Create Update-CFNStackFromDirectory tests
    - Create `tests/Unit/CloudFormation/Update-CFNStackFromDirectory.Tests.ps1` with Kiro attribution, BeforeAll dot-sourcing the SUT, `Unit` tag
    - Test: -WhatIf does not call New-CFNChangeSet or Start-CFNChangeSet (Req 4.4)
    - Test: happy path creates and executes change set
    - Mock `New-CFNChangeSet`, `Start-CFNChangeSet`, `Get-CFNChangeSet`
    - _Requirements: 1.2, 1.3, 1.4, 3.1, 4.4, 10.1_

- [x] 6. Checkpoint - Ensure P1 tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 7. Implement P2 core workflow tests — AWS
  - [x] 7.1 Create Find-CFNStackErrors tests
    - Create `tests/Unit/AWS/Find-CFNStackErrors.Tests.ps1` with Kiro attribution, BeforeAll dot-sourcing the SUT, `Unit` tag
    - Test: stacks with non-null StackStatusReason included, null excluded (Req 3.2)
    - Mock `Get-CFNStack`
    - _Requirements: 1.2, 1.3, 1.4, 3.1, 3.2, 10.1_

  - [x] 7.2 Write property test for Find-CFNStackErrors filtering
    - **Property 4: Stack error filtering**
    - Generate random collections of stacks with varying StackStatusReason (null/non-null), verify only non-null are returned
    - **Validates: Requirements 3.2**

  - [x] 7.3 Create Set-AWSEnv tests
    - Create `tests/Unit/AWS/Set-AWSEnv.Tests.ps1` with Kiro attribution, BeforeAll dot-sourcing the SUT, `Unit` tag
    - Test: -WhatIf does not modify environment variables (Req 3.4)
    - Mock environment variable access
    - _Requirements: 1.2, 1.3, 1.4, 3.1, 3.4, 10.1_

  - [x] 7.4 Create Start-MultiStackDriftDetection tests
    - Create `tests/Unit/AWS/Start-MultiStackDriftDetection.Tests.ps1` with Kiro attribution, BeforeAll dot-sourcing the SUT, `Unit` tag
    - Test: calls Start-CFNStackDriftDetection for eligible stacks (Req 3.6)
    - Test: skips stacks in ROLLBACK_COMPLETE, DELETE_FAILED, ROLLBACK_FAILED (Req 3.7)
    - Mock `Get-CFNStack`, `Start-CFNStackDriftDetection`
    - _Requirements: 1.2, 1.3, 1.4, 3.1, 3.6, 3.7, 10.1_

  - [x] 7.5 Write property test for Start-MultiStackDriftDetection eligibility filtering
    - **Property 5: Drift detection eligibility filtering**
    - Generate random sets of stacks with varying statuses, verify only non-excluded statuses trigger drift detection
    - **Validates: Requirements 3.6, 3.7**

  - [x] 7.6 Create Get-AWSAccountListOfDriftedResources tests
    - Create `tests/Unit/AWS/Get-AWSAccountListOfDriftedResources.Tests.ps1` with Kiro attribution, BeforeAll dot-sourcing the SUT, `Unit` tag
    - Test: returns only MODIFIED or DELETED resources, excludes NOT_MODIFIED and IN_SYNC (Req 3.8)
    - Mock `Get-CFNStackResourceDrift`
    - _Requirements: 1.2, 1.3, 1.4, 3.1, 3.8, 10.1_

  - [x] 7.7 Write property test for Get-AWSAccountListOfDriftedResources drift filtering
    - **Property 6: Drift status filtering**
    - Generate random collections of resources with varying drift statuses, verify only MODIFIED/DELETED are returned
    - **Validates: Requirements 3.8**

  - [x] 7.8 Create Get-AWSObjectCount tests
    - Create `tests/Unit/AWS/Get-AWSObjectCount.Tests.ps1` with Kiro attribution, BeforeAll dot-sourcing the SUT, `Unit` tag
    - Test: output contains Region, StackCount, VPCCount, EC2Count, BucketCount, LambdaCount, ScanOk properties (Req 3.9)
    - Test: AWS API error sets ScanOk to $false and counts to empty strings (Req 8.6)
    - Mock `Get-CFNStack`, `Get-EC2Vpc`, `Get-EC2Instance`, `Get-S3Bucket`, `Get-LMFunctionList`
    - _Requirements: 1.2, 1.3, 1.4, 3.1, 3.9, 8.6, 10.1_

- [x] 8. Implement P2 core workflow tests — CloudFormation and Git
  - [x] 8.1 Create Test-CFNStackFromDirectory tests
    - Create `tests/Unit/CloudFormation/Test-CFNStackFromDirectory.Tests.ps1` with Kiro attribution, BeforeAll dot-sourcing the SUT, `Unit` tag
    - Test: reads template.template and passes body to Test-CFNTemplate (Req 4.2)
    - Use `TestDrive:\` for stack directory fixture
    - Mock `Test-CFNTemplate`
    - _Requirements: 1.2, 1.3, 1.4, 3.1, 4.2, 10.1_

  - [x] 8.2 Create Out-CFNStackInfo tests
    - Create `tests/Unit/CloudFormation/Out-CFNStackInfo.Tests.ps1` with Kiro attribution, BeforeAll dot-sourcing the SUT, `Unit` tag
    - Test: exports template.template, parameters.json, tags.json, capabilities.json, outputs.json, stack.json in {AccountID}/{Region}/{StackName} structure (Req 4.3)
    - Use `TestDrive:\` for output directory
    - Mock `Get-CFNStack`, `Get-STSCallerIdentity`
    - _Requirements: 1.2, 1.3, 1.4, 3.1, 4.3, 10.1_

  - [x] 8.3 Create New-CFNStackDirectory tests
    - Create `tests/Unit/CloudFormation/New-CFNStackDirectory.Tests.ps1` with Kiro attribution, BeforeAll dot-sourcing the SUT, `Unit` tag
    - Test: creates subdirectory named after StackName with template.template containing TemplateBody (Req 4.5)
    - Use `TestDrive:\`
    - _Requirements: 1.2, 1.3, 1.4, 4.5, 10.1_

  - [x] 8.4 Create Edit-CFTTEbsVolumes tests
    - Create `tests/Unit/CloudFormation/Edit-CFTTEbsVolumes.Tests.ps1` with Kiro attribution, BeforeAll dot-sourcing the SUT, `Unit` tag
    - Test: all occurrences of OldVolumeType replaced with NewVolumeType, change set created (Req 4.6)
    - Mock `New-CFNChangeSet`
    - _Requirements: 1.2, 1.3, 1.4, 3.1, 4.6, 10.1_

  - [x] 8.5 Write property test for Edit-CFTTEbsVolumes text replacement
    - **Property 10: Text replacement completeness**
    - Generate random template bodies with varying occurrences of OldVolumeType, verify zero occurrences remain after function executes
    - **Validates: Requirements 4.6**

  - [x] 8.6 Create Test-CommitSignatures tests
    - Create `tests/Unit/Git/Test-CommitSignatures.Tests.ps1` with Kiro attribution, BeforeAll dot-sourcing the SUT, `Unit` tag
    - Test: valid signature (status 'G') returns $true (Req 5.1)
    - Test: no signature (status 'N') returns $false (Req 5.2)
    - Test: not a git repository writes error and returns $false (Req 5.3)
    - Mock `git` executable
    - _Requirements: 1.2, 1.3, 1.4, 5.1, 5.2, 5.3, 10.1_

- [x] 9. Checkpoint - Ensure P2 tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 10. Implement P3 and private helper tests
  - [x] 10.1 Create Install-ProfilesFromSource tests
    - Create `tests/Unit/Core/Install-ProfilesFromSource.Tests.ps1` with Kiro attribution, BeforeAll dot-sourcing the SUT, `Unit` tag
    - Test: copies matching profile files to corresponding $PROFILE paths (Req 2.1)
    - Test: -WhatIf does not write files (Req 2.2)
    - Mock `Copy-Item`, `Test-Path`
    - _Requirements: 1.2, 1.3, 1.4, 2.1, 2.2, 10.1_

  - [x] 10.2 Create Update-Powershell7 tests
    - Create `tests/Unit/Core/Update-Powershell7.Tests.ps1` with Kiro attribution, BeforeAll dot-sourcing the SUT, `Unit` tag
    - Test: Windows with winget invokes `winget upgrade Microsoft.PowerShell` with `--accept-source-agreements` (Req 2.10)
    - Mock `Get-Command`, winget executable
    - _Requirements: 1.2, 1.3, 1.4, 2.10, 10.1_

  - [x] 10.3 Create CFNPrivateFunctions tests
    - Create `tests/Unit/Core/CFNPrivateFunctions.Tests.ps1` with Kiro attribution, BeforeAll dot-sourcing the SUT, `Unit` tag
    - Test: ValidateForDeploy with missing files returns array of missing file names (Req 6.2)
    - Test: ValidateForDeploy with all files present returns empty array (Req 6.3)
    - Test: GetStackExportPath returns platform-appropriate joined path (Req 6.4)
    - Test: Get-CFNContext with explicit Region returns that Region (Req 6.5)
    - Test: Get-CFNContext without Region uses Get-DefaultAWSRegion (Req 6.6)
    - Use `TestDrive:\` for directory fixtures, mock `Get-DefaultAWSRegion`, `Get-STSCallerIdentity`
    - _Requirements: 1.2, 1.3, 1.4, 6.2, 6.3, 6.4, 6.5, 6.6, 10.1_

  - [x] 10.4 Write property test for CFNStackDirectoryInfo.ValidateForDeploy
    - **Property 7: ValidateForDeploy correctness**
    - Generate random subsets of required files present/absent, verify returned array matches exactly the missing file names
    - **Validates: Requirements 6.2, 6.3**

  - [x] 10.5 Write property test for CFNStackDirectoryInfo.GetStackExportPath
    - **Property 8: GetStackExportPath construction**
    - Generate random RootPath, AccountID, Region, StackName strings, verify result equals `Join-Path RootPath AccountID Region StackName`
    - **Validates: Requirements 6.4**

  - [x] 10.6 Create Audit-Functions tests
    - Create `tests/Unit/AWS/Audit/Audit-Functions.Tests.ps1` with Kiro attribution, BeforeAll dot-sourcing the SUT, `Unit` tag
    - Test basic behavior of audit functions (Get-EC2SGInUse, Get-EC2Count, Find-EC2DBSG, etc.) with mocked AWS cmdlets
    - Mock all EC2, IAM, and S3 cmdlets used by audit functions
    - _Requirements: 1.2, 1.3, 1.4, 3.1, 10.1_

- [x] 11. Implement Help discoverability and Script tests
  - [x] 11.1 Create Help discoverability tests
    - Create `tests/Unit/Help/HelpDiscoverability.Tests.ps1` with Kiro attribution, `Help` tag on Describe block
    - BeforeAll imports module manifest to get FunctionsToExport list
    - For each exported function: verify Synopsis is non-null, non-empty, not auto-generated; Description is non-null/non-empty; at least one Example present
    - _Requirements: 1.2, 1.3, 7.1, 7.2, 7.3, 7.4, 10.2_

  - [x] 11.2 Write property test for Help discoverability compliance
    - **Property 9: Help discoverability for all exported functions**
    - Iterate all functions in FunctionsToExport, verify each has valid Synopsis, Description, and Examples
    - **Validates: Requirements 7.1, 7.2, 7.3, 7.4**

  - [x] 11.3 Create Build-Module script tests
    - Create `tests/Unit/Scripts/Build-Module.Tests.ps1` with Kiro attribution, BeforeAll dot-sourcing the SUT, `Unit` tag
    - Test: script executes build steps (copy, manifest update) with mocked filesystem operations
    - Mock `Copy-Item`, `New-Item`, `Update-ModuleManifest`
    - _Requirements: 1.2, 1.3, 1.4, 10.1_

  - [x] 11.4 Create Publish-CharlandCustomizations script tests
    - Create `tests/Unit/Scripts/Publish-CharlandCustomizations.Tests.ps1` with Kiro attribution, BeforeAll dot-sourcing the SUT, `Unit` tag
    - Test: script calls Publish-Module with correct parameters
    - Mock `Publish-Module`, `Test-Path`
    - _Requirements: 1.2, 1.3, 1.4, 10.1_

  - [x] 11.5 Create Register-LocalRepository script tests
    - Create `tests/Unit/Scripts/Register-LocalRepository.Tests.ps1` with Kiro attribution, BeforeAll dot-sourcing the SUT, `Unit` tag
    - Test: script registers PSRepository with correct source location
    - Mock `Register-PSRepository`, `Get-PSRepository`
    - _Requirements: 1.2, 1.3, 1.4, 10.1_

  - [x] 11.6 Create Test-CodeQuality script tests
    - Create `tests/Unit/Scripts/Test-CodeQuality.Tests.ps1` with Kiro attribution, BeforeAll dot-sourcing the SUT, `Unit` tag
    - Test: script invokes PSScriptAnalyzer on correct paths
    - Mock `Invoke-ScriptAnalyzer`
    - _Requirements: 1.2, 1.3, 1.4, 10.1_

- [x] 12. Final checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation
- Property tests validate universal correctness properties using parameterized loops (100+ iterations) since PowerShell lacks a dedicated PBT framework
- Unit tests validate specific examples and edge cases
- The existing `tests/New-AWSParamSplat.Tests.ps1` is preserved at root for backward compatibility (Req 6.1)
- All test files use Kiro attribution: `# Generated by Kiro, reviewed by ccharland`
- All unit test Describe blocks include `-Tag 'Unit'`; help tests use `-Tag 'Help'`

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1"] },
    { "id": 1, "tasks": ["2.1", "2.3", "2.4", "2.7", "4.1", "4.2", "4.3", "4.4", "4.5"] },
    { "id": 2, "tasks": ["2.2", "2.5", "2.6", "5.1", "5.2"] },
    { "id": 3, "tasks": ["7.1", "7.3", "7.4", "7.6", "7.8", "8.1", "8.2", "8.3", "8.4", "8.6"] },
    { "id": 4, "tasks": ["7.2", "7.5", "7.7", "8.5"] },
    { "id": 5, "tasks": ["10.1", "10.2", "10.3", "10.6"] },
    { "id": 6, "tasks": ["10.4", "10.5", "11.1", "11.3", "11.4", "11.5", "11.6"] },
    { "id": 7, "tasks": ["11.2"] }
  ]
}
```
