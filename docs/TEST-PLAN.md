# CharlandCustomizations Test Plan

## 1. Purpose

This plan defines how to test module functions in `CharlandCustomizations` with a risk-based approach that prioritizes destructive AWS operations and security-sensitive workflows.

## 2. Scope

In scope:

- Exported functions listed in `src/CharlandCustomizations/CharlandCustomizations.psd1`
- Unit tests (Pester + mocks)
- Contract tests (parameter behavior, ShouldProcess, splatting support)
- Integration tests (optional, gated by AWS test account/profile)
- Regression tests for fixed defects

Out of scope:

- Real production account execution
- Performance benchmarking in first phase

## 3. Current Baseline

Existing tests found:

- `tests/New-AWSParamSplat.Tests.ps1`

Baseline quality gate currently available:

- `./Scripts/Test-CodeQuality.ps1` (PSScriptAnalyzer)

## 4. Test Levels

### 4.1 Unit Tests (default for most functions)

Use Pester mocks for AWS cmdlets:

- `Get-STSCallerIdentity`
- `Get-S3Bucket`, `Write-S3Object`, `Remove-S3Object`, `Get-S3PreSignedURL`
- CloudFormation cmdlets (`Get-CFNStack`, `New-CFNStack`, `New-CFNChangeSet`, etc.)

Validate:

- Parameter handling (including Region/ProfileName)
- ShouldProcess behavior for destructive functions
- Error handling and messages
- Return/output shape

### 4.2 Integration Tests (opt-in)

Run only when environment variables/profile are present.

- Tag as `Integration`
- Execute in a dedicated sandbox account/region
- Never run by default locally or in CI

### 4.3 Regression Tests

Every bug fix must include at least one test reproducing the original failure.

## 5. Risk-Based Priority Matrix

### Priority 1 (Critical/High impact)

Functions:

- `Clear-S3Bucket`
- `New-CFNStackFromDirectory`
- `Update-CFNStackFromDirectory`
- `Set-AWSProfileWithMFA`
- `Invoke-ScriptMultiAccountRegion`

Minimum tests per function:

- Parameter validation and defaults
- Region/ProfileName splatting path
- ShouldProcess / -WhatIf behavior (where applicable)
- Failure path does not terminate session unexpectedly

### Priority 2 (Core AWS workflows)

Functions:

- `Find-CFNStackErrors`
- `Start-MultiStackDriftDetection`
- `Get-AWSAccountListOfDriftedResources`
- `Get-AWSObjectCount`
- `Test-CFNTemplateFromFile`
- `Out-CFNStackInfo`
- `Test-CFNStackFromDirectory`
- `New-CFNStackDirectory`

Minimum tests per function:

- Happy path with mocks
- Missing file/resource path
- Output object/message assertions

### Priority 3 (Audit and utility reporting)

Functions:

- `Get-EC2SGInUse`
- `Get-IAMAuditList`
- `Get-GlobalAuditReportItem`
- `Get-EC2KeyTagNameStatus`
- `Get-EC2SnapshotReport`
- `Get-EC2VolumeReport`
- `Out-AWSSupportingInfo`
- `Out-AWSNetworkingComponent`

Minimum tests per function:

- Basic execution with mocks
- Null/empty collection handling
- Expected fields in output

## 6. Required Test Categories Per Function

For each exported function, include tests for:

1. `ParameterSet` and default behavior
2. `Region/ProfileName` splatting support
3. `ErrorPath` (AWS cmdlet throws)
4. `PipelineInput` (if supported)
5. `ShouldProcess` compliance (if destructive)

## 7. Test Design Patterns

### 7.1 Splatting Contract Test Pattern

- Mock AWS cmdlet
- Call function with `-Region` and `-ProfileName`
- Assert mock was invoked with both parameters

### 7.2 ShouldProcess Pattern

- Call with `-WhatIf`
- Assert destructive cmdlets were not called
- Call without `-WhatIf` and assert they were called

### 7.3 Error Contract Pattern

- Mock downstream cmdlet to throw
- Assert function throws or logs expected error
- Assert no `exit`/session termination behavior

## 8. File/Tag Organization

Recommended structure:

- `tests/Unit/AWS/*.Tests.ps1`
- `tests/Unit/CloudFormation/*.Tests.ps1`
- `tests/Unit/Git/*.Tests.ps1`
- `tests/Integration/**/*.Tests.ps1`

Recommended tags:

- `Unit`
- `Integration`
- `Slow`
- `Destructive`
- `Regression`

## 9. Execution Commands

Run all unit tests:

```powershell
Invoke-Pester -Path ./tests -Tag Unit
```

Run cloudformation-focused tests:

```powershell
Invoke-Pester -Path ./tests/Unit/CloudFormation
```

Run integration tests only:

```powershell
Invoke-Pester -Path ./tests -Tag Integration
```

Run code quality checks:

```powershell
./Scripts/Test-CodeQuality.ps1
```

## 10. CI Quality Gates

Minimum gate for merge:

1. Pester Unit tests pass
2. No PSScriptAnalyzer errors
3. New/modified function includes at least one test
4. Any bug fix includes a regression test

## 11. 30-60-90 Day Rollout

### First 30 days

- Complete Priority 1 unit tests
- Standardize test tags and folder layout
- Add splatting contract tests to all CloudFormation and S3 destructive flows

### Days 31-60

- Complete Priority 2 unit tests
- Add integration smoke tests for sandbox AWS account

### Days 61-90

- Complete Priority 3 tests
- Add regression suite for all fixed critical/high issues
- Tune CI gates and flaky test handling

## 12. Definition of Done

A function is considered fully covered when:

1. Unit tests exist for happy path and failure path
2. Region/ProfileName behavior is verified
3. ShouldProcess behavior is verified (if destructive)
4. Tests pass in clean environment
5. Test is mapped to a priority bucket in this plan

## 13. Immediate Next Implementation Targets

Start with these files:

1. `tests/New-AWSParamSplat.Tests.ps1` (already exists)

Add new files:

1. `tests/Unit/AWS/S3/Clear-S3Bucket.Tests.ps1`
2. `tests/Unit/AWS/AWSCustomizations.Tests.ps1`
3. `tests/Unit/AWS/Audit/Audit-AWSAccount.Tests.ps1`
4. `tests/Unit/CloudFormation/CloudFormation-TemplateProcessing.Tests.ps1`
