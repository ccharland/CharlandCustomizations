# Implementation Plan: AWS Config Operations Module

## Overview

Implement `Config-Operations.psm1` — a PowerShell module providing four AWS Config query functions following the established CharlandCustomizations patterns. The module uses `New-AWSParamSplat` for credential splatting, `Test-CHARAWSCmdlet` for cmdlet validation, and outputs PSCustomObjects for pipeline compatibility. Tests follow the existing Pester 5 structure with mocks scoped to `-ModuleName Config-Operations`.

## Tasks

- [x] 1. Create module file with initialization and first function
  - [x] 1.1 Create `src/CharlandCustomizations/Public/AWS/Config/Config-Operations.psm1` with module-level comment-based help, dot-source statements for `New-AWSParamSplat.ps1` and `Test-CHARAWSCmdlet.ps1`, and implement `Get-CHARConfigResourceCreationDate`
    - Create the `Config/` directory under `src/CharlandCustomizations/Public/AWS/`
    - Add module-level `<# .SYNOPSIS .DESCRIPTION .NOTES #>` header with Kiro attribution
    - Dot-source helpers using relative paths: `"$PSScriptRoot/../../../Private/New-AWSParamSplat.ps1"` and `"$PSScriptRoot/../../Test-CHARAWSCmdlet.ps1"`
    - Implement `Get-CHARConfigResourceCreationDate` with full comment-based help (Synopsis, Description, Parameter docs for all params including AWS common, two Examples, Notes with attribution)
    - Use `begin`/`process`/`end` pattern: validate cmdlets (`Get-CFGResourceConfigHistory`, `Find-CTEvent`) and build splat in `begin`; query Config history, extract earliest item, query CloudTrail, build ordered PSCustomObject output in `process`
    - Handle `ResourceNotDiscoveredException` with `Write-Warning` + return `$null`; permission errors and service exceptions with `Write-Error`
    - Accept `ResourceId` (Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName) and `ResourceType` (Mandatory, ValueFromPipelineByPropertyName)
    - Output: ordered PSCustomObject with ResourceId, ResourceType, CreationDate, PrincipalName, EventName, EventSource
    - _Requirements: 1.1-1.5, 2.1-2.4, 3.1-3.2, 4.1-4.9, 8.1-8.3, 9.1-9.5, 10.1-10.3_

- [x] 2. Implement remaining lifecycle and compliance functions
  - [x] 2.1 Implement `Get-CHARConfigResourceDeleteDate` in `Config-Operations.psm1`
    - Same begin/process/end pattern; validate `Get-CFGResourceConfigHistory` and `Find-CTEvent`
    - Query Config history, filter for `ConfigurationItemStatus -eq 'ResourceDeleted'`
    - Query CloudTrail around deletion timestamp for the resource
    - Output: ordered PSCustomObject with ResourceId, ResourceType, DeletionDate, PrincipalName, EventName, EventSource
    - Handle no deletion record: `Write-Warning` + return `$null`; CloudTrail unavailable: null CT fields
    - Full comment-based help with two examples and attribution
    - _Requirements: 5.1-5.9, 2.1-2.4, 3.1-3.2, 8.1-8.3, 9.1-9.5, 10.1-10.3_

  - [x] 2.2 Implement `Get-CHARConfigNonCompliantResource` in `Config-Operations.psm1`
    - Validate `Get-CFGComplianceDetailsByConfigRule` in begin block
    - Query with `ComplianceType` = `NON_COMPLIANT` for the specified `ConfigRuleName`
    - Handle `NoSuchConfigRuleException` with `Write-Error` and terminate
    - Handle empty results: `Write-Verbose` indicating full compliance, return empty collection
    - Emit each result as ordered PSCustomObject: ResourceId, ResourceType, ComplianceType, ConfigRuleName
    - Accept `ConfigRuleName` (Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)
    - Full comment-based help
    - _Requirements: 6.1-6.7, 2.1-2.4, 3.1-3.2, 8.1-8.3, 9.1-9.5, 10.1-10.3_

  - [x] 2.3 Implement `Get-CHARConfigResourceComplianceReport` in `Config-Operations.psm1`
    - Validate `Get-CFGComplianceDetailsByResource` in begin block
    - Query all compliance evaluations for the resource ID and type
    - Handle no results: `Write-Warning` indicating no Config rules have evaluated, return empty collection
    - Emit each evaluation as ordered PSCustomObject: ResourceId, ResourceType, ConfigRuleName, ComplianceType, LastEvaluatedTime
    - Accept `ResourceId` (Mandatory, ValueFromPipeline) and `ResourceType` (Mandatory)
    - Full comment-based help
    - _Requirements: 7.1-7.7, 2.1-2.4, 3.1-3.2, 8.1-8.3, 9.1-9.5, 10.1-10.3_

- [x] 3. Update module manifest
  - [x] 3.1 Add `Config-Operations.psm1` to `NestedModules` in `CharlandCustomizations.psd1` and add all four function names to `FunctionsToExport`
    - Add `'Public/AWS/Config/Config-Operations.psm1'` to the `NestedModules` array
    - Add `'Get-CHARConfigResourceCreationDate'`, `'Get-CHARConfigResourceDeleteDate'`, `'Get-CHARConfigNonCompliantResource'`, `'Get-CHARConfigResourceComplianceReport'` to `FunctionsToExport`
    - Maintain alphabetical ordering within the array
    - _Requirements: 1.1, 1.4_

- [x] 4. Checkpoint - Verify module loads cleanly
  - Ensure the module imports without errors by running `Import-Module` in a PowerShell session. Ensure all tests pass, ask the user if questions arise.

- [x] 5. Create module-level Pester test file
  - [x] 5.1 Create `tests/src/Public/AWS/Config/Config-Operations/Config-Operations.Tests.ps1`
    - Create the `tests/src/Public/AWS/Config/Config-Operations/` directory
    - Follow the pattern from `S3Customizations.Tests.ps1`: resolve module path, parse for syntax errors, import and verify exported function names
    - Add parameter validation tests: for each of the four functions, verify all 8 AWS common parameters exist and are optional (Property 1)
    - Verify each function has its required mandatory parameters (ResourceId, ResourceType, ConfigRuleName as applicable)
    - All Describe blocks use `-Tag 'Unit'`
    - Include `.NOTES` header with Kiro attribution
    - _Requirements: 11.1-11.4, 11.8_

- [x] 6. Create per-function test files for lifecycle functions
  - [x] 6.1 Create `tests/src/Public/AWS/Config/Config-Operations/Get-CHARConfigResourceCreationDate.Tests.ps1`
    - BeforeAll: remove/reimport module using six-level path traversal
    - Mock `Test-CHARAWSCmdlet`, `New-AWSParamSplat`, `Get-CFGResourceConfigHistory`, `Find-CTEvent` with `-ModuleName Config-Operations`
    - Context 'Cmdlet validation failure': mock `Test-CHARAWSCmdlet` to throw, verify no AWS cmdlets called (Property 2)
    - Context 'Happy path': mock Config history + CloudTrail event, verify output has 6 properties in correct order (Property 3), verify property values
    - Context 'CloudTrail unavailable': mock `Find-CTEvent` returning empty, verify PrincipalName/EventName/EventSource are `$null` (Property 4)
    - Context 'No Config history': mock `Get-CFGResourceConfigHistory` to throw `ResourceNotDiscoveredException`, verify `$null` return and warning stream (Property 5)
    - Context 'AWS API errors': mock permission denied and service exceptions, verify error messages contain action name and details (Property 9)
    - Context 'Pipeline input': pipe ResourceId string into function, verify it processes correctly (Property 8)
    - _Requirements: 11.2, 11.4-11.10_

  - [x] 6.2 Create `tests/src/Public/AWS/Config/Config-Operations/Get-CHARConfigResourceDeleteDate.Tests.ps1`
    - Same structure as 6.1 adapted for deletion function
    - Mock Config history returning `ResourceDeleted` status item for happy path
    - Context 'No deletion record': mock Config history without `ResourceDeleted` item, verify `$null` return and warning (Property 5)
    - Context 'CloudTrail unavailable': verify null CT fields (Property 4)
    - Context 'Happy path': verify 6 properties with DeletionDate (Property 3)
    - _Requirements: 11.2, 11.4-11.10_

- [x] 7. Create per-function test files for compliance functions
  - [x] 7.1 Create `tests/src/Public/AWS/Config/Config-Operations/Get-CHARConfigNonCompliantResource.Tests.ps1`
    - Mock `Get-CFGComplianceDetailsByConfigRule` with `-ModuleName Config-Operations`
    - Context 'Happy path': return multiple non-compliant resources, verify 4-property output objects (Property 3), verify multiple objects emitted individually (Property 8)
    - Context 'Config rule not found': mock `NoSuchConfigRuleException`, verify error contains rule name and no output (Property 6)
    - Context 'No non-compliant resources': mock empty return, verify empty collection and verbose message (Property 7)
    - Context 'Cmdlet validation failure': verify no API calls (Property 2)
    - Context 'AWS API errors': verify error context (Property 9)
    - Context 'Pipeline input': pipe ConfigRuleName into function
    - _Requirements: 11.2, 11.4-11.10_

  - [x] 7.2 Create `tests/src/Public/AWS/Config/Config-Operations/Get-CHARConfigResourceComplianceReport.Tests.ps1`
    - Mock `Get-CFGComplianceDetailsByResource` with `-ModuleName Config-Operations`
    - Context 'Happy path': return multiple evaluations (COMPLIANT + NON_COMPLIANT), verify 5-property output objects (Property 3), verify streaming (Property 8)
    - Context 'No evaluations': mock empty return, verify empty collection and warning message
    - Context 'Cmdlet validation failure': verify no API calls (Property 2)
    - Context 'AWS API errors': verify error context (Property 9)
    - Context 'Pipeline input': pipe ResourceId into function
    - _Requirements: 11.2, 11.4-11.10_

- [x] 8. Final checkpoint - Run full Pester test suite
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP — no tasks in this plan are marked optional as all tests are required per Requirement 11
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation
- Property tests validate the 9 correctness properties defined in the design document
- The module follows the single-file nested module pattern established by `S3Customizations.psm1`
- Test mocks use `-ModuleName Config-Operations` to scope mocks within the module's session state
- The six-level path traversal in test BeforeAll blocks accounts for `tests/src/Public/AWS/Config/Config-Operations/` back to repo root

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1"] },
    { "id": 1, "tasks": ["2.1", "2.2", "2.3"] },
    { "id": 2, "tasks": ["3.1", "5.1"] },
    { "id": 3, "tasks": ["6.1", "6.2", "7.1", "7.2"] }
  ]
}
```
