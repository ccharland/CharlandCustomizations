# Implementation Plan: Config Resource Type Validator

## Overview

Implement `Test-CHARConfigResourceType` in `Config-Operations.psm1` — a correction-first validator for AWS Config resource type strings. The function applies a multi-stage correction pipeline (trim → normalize separators → prepend prefix → PascalCase → format regex → enum validation) and integrates into existing Config-Operations functions to prevent silent API failures from malformed resource types.

## Tasks

- [x] 1. Implement Test-CHARConfigResourceType core function
  - [x] 1.1 Add module-scoped cache variable and implement the correction pipeline function
    - Add `$script:ConfigResourceTypeCache = $null` after the dot-source lines in `Config-Operations.psm1` (before any function definitions)
    - Implement `Test-CHARConfigResourceType` with full comment-based help (Synopsis, Description, Parameters, 2+ Examples, Notes with attribution)
    - Implement the correction pipeline in the `process` block: trim whitespace → normalize separators via `(?<!:):(?!:)` regex → prepend `AWS::` if missing → PascalCase each segment → validate against `^AWS::[A-Z][a-zA-Z0-9]+::[A-Z][a-zA-Z0-9]+$`
    - Implement cache population logic: check if `$script:ConfigResourceTypeCache` is `$null`, call `Get-CFGDiscoveredResourceCount`, extract unique ResourceType values
    - Implement `-RefreshCache` switch: discard cache and re-fetch
    - Implement cache fallback: on API failure, `Write-Warning`, set cache to `@()`, return format-corrected string
    - Implement enum validation: exact match → case-insensitive match (1 result = return it, 0 or 2+ = return `$false`)
    - Declare `[OutputType([object])]`, `[AllowNull()]`, `[AllowEmptyString()]` on ResourceType parameter
    - Ensure function never throws terminating errors for invalid input — always returns string or `$false`
    - _Requirements: 1.1–1.11, 2.1–2.13, 3.2–3.4, 3.7–3.8_

  - [x] 1.2 Update Export-ModuleMember and module manifest
    - Add `'Test-CHARConfigResourceType'` to the `Export-ModuleMember -Function` list in `Config-Operations.psm1`
    - Add `'Test-CHARConfigResourceType'` to the `FunctionsToExport` array in `CharlandCustomizations.psd1`
    - _Requirements: 3.1_

- [x] 2. Integrate validator into existing functions
  - [x] 2.1 Add validator call to Get-CHARConfigResourceCreationDate
    - Insert validation block at top of `process` block: call `Test-CHARConfigResourceType -ResourceType $ResourceType @awsParams`
    - If result is `$false`, write terminating error with original input value
    - If result differs from original, assign corrected value to `$ResourceType` and write `Write-Verbose` with both values
    - If result equals original, proceed without verbose message
    - _Requirements: 4.1, 4.4, 4.5, 4.6_

  - [x] 2.2 Add validator call to Get-CHARConfigResourceDeleteDate
    - Same integration pattern as 2.1 in `Get-CHARConfigResourceDeleteDate` process block
    - _Requirements: 4.2, 4.4, 4.5, 4.6_

  - [x] 2.3 Add validator call to Get-CHARConfigResourceComplianceReport
    - Same integration pattern as 2.1 in `Get-CHARConfigResourceComplianceReport` process block
    - _Requirements: 4.3, 4.4, 4.5, 4.6_

- [x] 3. Checkpoint - Verify module loads correctly
  - Ensure `Config-Operations.psm1` parses without syntax errors
  - Ensure `Import-Module CharlandCustomizations` loads without errors
  - Ensure `Test-CHARConfigResourceType` appears in exported commands
  - Ensure all tests pass, ask the user if questions arise.

- [x] 4. Create Pester tests for Test-CHARConfigResourceType
  - [x] 4.1 Create test file with input generator helpers and correction pipeline tests
    - Create `tests/src/Public/AWS/Config/Config-Operations/Test-CHARConfigResourceType.Tests.ps1`
    - Implement input generator helper functions: `New-RandomValidResourceType`, `New-RandomMiscasedResourceType`, `New-RandomInvalidResourceType`, `New-RandomWhitespacePadded`, `New-RandomSeparatorVariant`
    - Write unit tests in `Context 'Correction Pipeline - Format-Only Mode'`:
      - Valid input returned unchanged (`AWS::EC2::Instance`)
      - Capitalization correction (`aws::ec2::instance` → `AWS::Ec2::Instance` in format-only mode)
      - Missing prefix correction (`EC2::Instance` → `AWS::EC2::Instance`)
      - Single-colon separator correction (`AWS:EC2:Instance` → `AWS::EC2::Instance`)
      - Mixed separator correction (`AWS::EC2:Instance` → `AWS::EC2::Instance`)
      - Whitespace trimming combined with corrections
      - Correction order verification (trim → separators → prefix → PascalCase)
    - Write unit tests in `Context 'Invalid Input'`:
      - `$null` returns `$false`
      - Empty string returns `$false`
      - Whitespace-only returns `$false`
      - Single segment (no separators) returns `$false`
      - Segments with special characters returns `$false`
      - Segments beginning with digits returns `$false`
    - _Requirements: 5.1–5.8, 5.14_

  - [x] 4.2 Add cache-based validation and pipeline tests
    - Write unit tests in `Context 'Cache-Based Validation'`:
      - Mock `Get-CFGDiscoveredResourceCount` to return known types
      - Verify exact cache match returns the cached string
      - Verify case-insensitive correction via cache (`AWS::ec2::instance` → `AWS::EC2::Instance`)
      - Verify non-existent type returns `$false` when cache populated
      - Verify ambiguous case-insensitive matches return `$false`
    - Write unit tests in `Context 'Cache Lifecycle'`:
      - Verify cache populated on first call (mock called once)
      - Verify subsequent calls reuse cache (mock not called again)
      - Verify `-RefreshCache` discards cache and re-fetches (mock called second time)
      - Verify API failure: mock throws, warning written, format-corrected string returned
    - Write unit tests in `Context 'Pipeline Behavior'`:
      - Multiple values piped produce independent results per input
    - _Requirements: 5.9–5.18_

  - [ ]* 4.3 Write property tests for output format invariant
    - **Property 1: Output Format Invariant**
    - Use `New-RandomResourceTypeInput` to generate 100+ inputs, confirm all non-`$false` outputs match `^AWS::[A-Z][a-zA-Z0-9]+::[A-Z][a-zA-Z0-9]+$`
    - **Validates: Requirements 1.7, 1.8**

  - [ ]* 4.4 Write property tests for correction idempotence
    - **Property 2: Correction Idempotence**
    - For 100+ generated inputs where `f(x) ≠ $false`, confirm `f(f(x)) == f(x)`
    - **Validates: Requirements 1.1, 1.2**

  - [ ]* 4.5 Write property tests for whitespace invariance
    - **Property 3: Whitespace Invariance**
    - For 100+ inputs with random leading/trailing whitespace, confirm `f(padded) == f(trimmed)`
    - **Validates: Requirements 1.6**

  - [ ]* 4.6 Write property tests for invalid input rejection
    - **Property 4: Invalid Input Rejection**
    - Generate 100+ strings with non-alphanumeric segment chars, digit-leading segments, or <2 segments after prefix; confirm all return `$false`
    - **Validates: Requirements 1.8, 1.9**

  - [ ]* 4.7 Write property tests for no-throw guarantee
    - **Property 5: No-Throw Guarantee**
    - Feed 100+ arbitrary strings (including `$null`, empty, random bytes, long strings); confirm no terminating errors are thrown
    - **Validates: Requirements 1.10**

  - [ ]* 4.8 Write property tests for cache-based case correction
    - **Property 6: Cache-Based Case Correction**
    - With a mocked cache, for each cached entry generate random case variants; confirm the cache entry is always returned
    - **Validates: Requirements 2.9, 2.10**

  - [ ]* 4.9 Write property tests for non-existent type rejection with populated cache
    - **Property 7: Non-Existent Type Rejection with Populated Cache**
    - Generate format-valid strings not in the mocked cache; confirm all return `$false`
    - **Validates: Requirements 2.11**

  - [ ]* 4.10 Write property tests for pipeline independence
    - **Property 8: Pipeline Independence**
    - Pipe N random inputs; confirm each output matches individual invocation
    - **Validates: Requirements 3.5, 3.6**

- [x] 5. Update existing function tests to mock the validator
  - [x] 5.1 Add Test-CHARConfigResourceType mock to existing Config-Operations test files
    - Add `Mock Test-CHARConfigResourceType { return $ResourceType }` (pass-through) to existing test files for `Get-CHARConfigResourceCreationDate`, `Get-CHARConfigResourceDeleteDate`, and `Get-CHARConfigResourceComplianceReport`
    - Ensure existing tests still pass with the validator integration
    - _Requirements: 4.1–4.3_

- [x] 6. Final checkpoint - Verify all tests pass
  - Run full Pester test suite for Config-Operations functions
  - Confirm module imports cleanly with new function exported
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation
- Property tests validate universal correctness properties from the design document
- Unit tests validate specific examples and edge cases
- All AWS cmdlet calls in tests MUST be mocked — no live API calls
- The cache variable `$script:ConfigResourceTypeCache` must be reset between test contexts using `BeforeEach` or `BeforeAll` blocks
- Input generators produce randomized data for property tests; minimum 100 iterations per property
- The separator normalization regex `(?<!:):(?!:)` uses negative lookbehind/lookahead to avoid replacing `::` pairs

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1"] },
    { "id": 1, "tasks": ["1.2"] },
    { "id": 2, "tasks": ["2.1", "2.2", "2.3"] },
    { "id": 3, "tasks": ["4.1", "5.1"] },
    { "id": 4, "tasks": ["4.2"] },
    { "id": 5, "tasks": ["4.3", "4.4", "4.5", "4.6", "4.7", "4.8", "4.9", "4.10"] }
  ]
}
```
