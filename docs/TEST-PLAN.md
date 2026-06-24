# CharlandCustomizations Release Testing Plan

## 1. Purpose

This plan defines the release testing required before publishing `CharlandCustomizations`. The goal is to verify that each public function and release-support script is documented, testable, and safe enough for local use, CI, and packaging.

## 2. Release Scope

In scope:

- Exported functions listed in `src/CharlandCustomizations/CharlandCustomizations.psd1`
- Public `.ps1` scripts under `src/CharlandCustomizations/Public`
- Release and support scripts under `Scripts`
- Private helper tests when the helper owns reusable behavior
- Pester unit tests, PSScriptAnalyzer checks, packaging checks, and opt-in integration tests

Out of scope:

- Production AWS account execution
- Live destructive AWS testing outside a dedicated sandbox account
- Performance benchmarking for the first release gate

## 3. Required Per-Function And Per-Script Checks

Each function or script must have the following before release:

1. Comment-based help that is discoverable from PowerShell.
   - Functions: `Get-Help <FunctionName>` and `<FunctionName> -?`
   - Scripts: `Get-Help ./Scripts/<ScriptName>.ps1` and `./Scripts/<ScriptName>.ps1 -?`
   - Help must include `.SYNOPSIS`, parameter documentation for non-obvious parameters, and at least one `.EXAMPLE`.
2. At least one Pester test that validates expected behavior.
   - Prefer a meaningful behavior test over a smoke-only test.
   - For AWS-facing commands, mock AWS cmdlets unless the test is explicitly tagged `Integration`.
   - For destructive commands, include `-WhatIf` or `ShouldProcess` coverage.
3. Parameter contract coverage for any public parameters added or changed in the release.
4. Error-path coverage for high-risk workflows such as AWS, signing, filesystem mutation, publishing, and git hook installation.
5. Code quality pass with `./Scripts/Test-CodeQuality.ps1`.

## 4. Release Gates

The release is ready only when all required gates pass:

1. Help gate: every function and script exposes usable comment-based help.
2. Unit test gate: Pester unit tests pass.
3. Coverage gate: every exported function and release-support script has at least one mapped Pester test or a documented release exception.
4. Static analysis gate: PSScriptAnalyzer reports no errors.
5. Build gate: `./Scripts/Build-Module.ps1 -Clean -Package` completes successfully.
6. Manifest gate: exported functions in the manifest match the public release surface, and every `.psd1` array plus `.psm1` `Export-ModuleMember -Function` array is sorted with one element per line.
7. Manual smoke gate: the packaged module imports cleanly and one representative command from each area can be discovered with `Get-Command` and `Get-Help`.

## 5. Test Levels

### 5.1 Unit Tests

Unit tests are the default release requirement. Use Pester mocks for AWS, git, signing, and filesystem side effects where possible.

Validate:

- Parameter binding and defaults
- Pipeline input where supported
- AWS common parameter splatting through `New-AWSParamSplat`
- `ShouldProcess` behavior for state-changing commands
- Output object shape
- Error handling and useful failure messages

### 5.2 Integration Tests

Integration tests are optional and opt-in. They must be tagged `Integration` and must not run by default in local or CI unit test commands.

Integration tests may use:

- A dedicated AWS sandbox account/profile
- A temporary local package repository
- Temporary git repositories under the test output directory

Integration tests must not use:

- Production AWS accounts
- Personal default profiles unless explicitly configured
- Destructive operations without a unique test prefix and cleanup path

### 5.3 Regression Tests

Every bug fix must include at least one test that fails against the old behavior and passes after the fix.

## 6. Risk-Based Priorities

### Priority 1: Release Blockers

These commands can delete resources, modify credentials, publish artifacts, write signatures, or run across accounts. They require stronger testing before release.

- `Clear-CHARS3Bucket`
- `New-CHARCFNStackFromDirectory`
- `Update-CHARCFNStackFromDirectory`
- `Set-CHARAWSProfileWithMFA`
- `Update-CHARSSOCredentialList`
- `Remove-CHARExpiredAWSProfile`
- `Use-CHARAssumedRole`
- `Invoke-CHARScriptMultiRegionProfile`
- `Set-CHARAuthenticodeSignature`
- `Clear-CHARAuthenticodeSignature`
- `Install-CHARGitHook`
- `Scripts/Build-Module.ps1`
- `Scripts/Publish-CharlandCustomizations.ps1`
- `Scripts/Register-LocalRepository.ps1`

Minimum tests:

- Help exists and can be retrieved
- At least one behavior-focused Pester test
- Parameter validation and defaults
- Failure path with downstream command throwing
- `ShouldProcess` / `-WhatIf` behavior where state changes occur
- No accidental live AWS calls in unit tests

### Priority 2: Core Workflows

- `Find-CHARCFNStackError`
- `Get-CHARAWSMFASession`
- `Set-CHARAWSEnv`
- `Get-CHARAccountListFromProfile`
- `Start-CHARMultiStackDriftDetection`
- `Get-CHARAWSAccountListOfDriftedResource`
- `Get-CHARAWSObjectCount`
- `Test-CHARCFNStackFromDirectory`
- `Out-CHARCFNStackInfo`
- `New-CHARCFNStackDirectory`
- `Edit-CHARCFTTEbsVolume`
- `Test-CHARCommitSignature`
- `Scripts/Test-CodeQuality.ps1`

Minimum tests:

- Help exists and can be retrieved
- At least one behavior-focused Pester test
- Happy path with mocks or temporary test data
- Empty/null input handling
- Output object or message assertions

### Priority 3: Audit And Reporting

- `Get-CHAREC2SGInUse`
- `Get-CHAREC2Count`
- `Find-CHAREC2DBSG`
- `Out-CHARAWSSupportingInfo`
- `Out-CHARAWSNetworkingComponent`
- `Get-CHARIAMAuditList`
- `Get-CHARGlobalAuditReportItem`
- `Get-CHAREC2KeyTagNameStatus`
- `Get-CHAREC2SnapshotReport`
- `Get-CHAREC2VolumeReport`
- `Start-CHAREC2RetryLoop`
- `Find-CHAROpenSecurityGroup`
- `Get-CHARAllEC2Patch`
- `Get-CHARDeprecatedLMFunctionList`
- `Install-CHARProfilesFromSource`
- `Update-CHARPowershell7`

Minimum tests:

- Help exists and can be retrieved
- At least one behavior-focused Pester test
- Basic execution with mocks or local test data
- Null/empty collection handling
- Expected fields in output

## 7. Release Inventory Checklist

Track each item through the release. Use `Not Started`, `Help Ready`, `Test Ready`, `Passing`, or `Exception Approved`.

| Item | Type | Priority | Help | Pester Test | Notes |
| --- | --- | --- | --- | --- | --- |
| `Install-CHARProfilesFromSource` | Function | P3 | Ready | Passing | Local profile copy behavior |
| `Invoke-CHARScriptMultiRegionProfile` | Function | P1 | Ready | Passing | Multi-account execution contract |
| `Set-CHARAuthenticodeSignature` | Function | P1 | Ready | Passing | Signing side effects |
| `Update-CHARPowershell7` | Function | P3 | Ready | Passing | External install/update behavior |
| `Clear-CHARAuthenticodeSignature` | Function | P1 | Ready | Passing | File mutation |
| `Find-CHARCFNStackError` | Function | P2 | Ready | Passing | AWS mocks |
| `Set-CHARAWSProfileWithMFA` | Function | P1 | Ready | Passing | Credential mutation |
| `Get-CHARAWSMFASession` | Function | P2 | Ready | Passing | STS mocks |
| `Start-CHARMultiStackDriftDetection` | Function | P2 | Ready | Passing | CloudFormation mocks |
| `Get-CHARAWSAccountListOfDriftedResource` | Function | P2 | Ready | Passing | CloudFormation mocks |
| `Get-CHARAWSObjectCount` | Function | P2 | Ready | Passing | AWS inventory mocks |
| `Set-CHARAWSEnv` | Function | P2 | Ready | Passing | Environment mutation |
| `Update-CHARSSOCredentialList` | Function | P1 | Ready | Passing | SSO credential file behavior |
| `Remove-CHARExpiredAWSProfile` | Function | P1 | Ready | Passing | Credential file mutation |
| `Get-CHARAccountListFromProfile` | Function | P2 | Ready | Passing | Local credential parsing |
| `Use-CHARAssumedRole` | Function | P1 | Ready | Passing | Credential/environment mutation |
| `New-CHARCFNStackFromDirectory` | Function | P1 | Ready | Passing | CloudFormation create flow |
| `Test-CHARCFNStackFromDirectory` | Function | P2 | Ready | Passing | Template validation flow |
| `Out-CHARCFNStackInfo` | Function | P2 | Ready | Passing | Output file/report behavior |
| `Update-CHARCFNStackFromDirectory` | Function | P1 | Ready | Passing | CloudFormation update flow |
| `New-CHARCFNStackDirectory` | Function | P2 | Ready | Passing | File creation |
| `Edit-CHARCFTTEbsVolume` | Function | P2 | Ready | Passing | Template transformation |
| `Clear-CHARS3Bucket` | Function | P1 | Ready | Passing | Destructive S3 behavior |
| `Get-CHAREC2SGInUse` | Function | P3 | Ready | Passing | EC2/security group mocks |
| `Get-CHAREC2Count` | Function | P3 | Ready | Passing | EC2 mocks |
| `Find-CHAREC2DBSG` | Function | P3 | Ready | Passing | Security group analysis |
| `Out-CHARAWSSupportingInfo` | Function | P3 | Ready | Passing | Report output |
| `Out-CHARAWSNetworkingComponent` | Function | P3 | Ready | Passing | Report output |
| `Get-CHARIAMAuditList` | Function | P3 | Ready | Passing | IAM mocks |
| `Get-CHARGlobalAuditReportItem` | Function | P3 | Ready | Passing | Report item shape |
| `Get-CHAREC2KeyTagNameStatus` | Function | P3 | Ready | Passing | Tag analysis |
| `Get-CHAREC2SnapshotReport` | Function | P3 | Ready | Passing | Snapshot mocks |
| `Get-CHAREC2VolumeReport` | Function | P3 | Ready | Passing | Volume mocks |
| `Start-CHAREC2RetryLoop` | Function | P3 | Ready | Passing | Retry behavior |
| `Find-CHAROpenSecurityGroup` | Function | P3 | Ready | Passing | Security group rules |
| `Get-CHARAllEC2Patch` | Function | P3 | Ready | Passing | SSM patch compliance mocks |
| `Get-CHARDeprecatedLMFunctionList` | Function | P3 | Ready | Passing | Lambda mocks |
| `Test-CHARCommitSignature` | Function | P2 | Ready | Passing | Temporary git repo |
| `Install-CHARGitHook` | Function | P1 | Ready | Passing | File mutation |
| `New-AWSParamSplat` | Private Helper | P2 | Ready | Passing | Comprehensive tests in `tests/src/Private/New-AWSParamSplat.Tests.ps1` |
| `Scripts/Build-Module.ps1` | Script | P1 | Ready | Passing | Build/package gate |
| `Scripts/Publish-CharlandCustomizations.ps1` | Script | P1 | Ready | Passing | Publish flow with mocks |
| `Scripts/Register-LocalRepository.ps1` | Script | P1 | Ready | Passing | Repository registration |
| `Scripts/Test-CodeQuality.ps1` | Script | P2 | Ready | Passing | Analyzer invocation |

## 8. Recommended Test Organization

Test files are organized under `tests/src/` to mirror the source structure under `src/CharlandCustomizations/`. Module-contained functions are grouped under a module-named folder.

Structure:

- `tests/src/{CharlandCustomizations,Private,Public}/` mirrors `src/CharlandCustomizations/`
- Module files: `tests/src/Public/AWS/AWSCustomizations/AWSCustomizations.Tests.ps1` + per-function tests
- Script files in module directories: `tests/src/Public/Git/GitCustomizations/{FunctionName}.Tests.ps1`
- Scripts/helpers: `tests/src/Private/New-AWSParamSplat.Tests.ps1`
- **SRC Layout Gate**: `tests/src/SourceLayout.Tests.ps1` enforces:
  - Each `.ps1`, `.psm1`, `.psd1` under `src/` must have a corresponding `.Tests.ps1` under `tests/src/`
  - Modules must have at least one `It` block (minimum: module existence test)

Modern test organization (all under `tests/src/`):

- `tests/src/Private/*.Tests.ps1`
- `tests/src/Public/AWS/AWSCustomizations/*.Tests.ps1`
- `tests/src/Public/AWS/Audit/Audit-AWSAccount/*.Tests.ps1`
- `tests/src/Public/AWS/CloudFormation/CloudFormation-TemplateProcessing/*.Tests.ps1`
- `tests/src/Public/AWS/Lambda/Lambda-Customizations/*.Tests.ps1`
- `tests/src/Public/AWS/S3/S3Customizations/*.Tests.ps1`
- `tests/src/Public/Git/GitCustomizations/*.Tests.ps1`
- `tests/src/Public/*.Tests.ps1` (standalone functions)

Recommended tags:

- `Unit`
- `Integration`
- `Slow`
- `Destructive`
- `Regression`
- `Help`

## 9. Test Design Patterns

### 9.1 Help Coverage Pattern

```powershell
It 'has discoverable comment-based help' -Tag 'Help' {
    $help = Get-Help Clear-CHARS3Bucket -Full

    $help.Synopsis | Should -Not -BeNullOrEmpty
    $help.Examples.Example.Count | Should -BeGreaterThan 0
}
```

### 9.2 Splatting Contract Pattern

```powershell
It 'passes AWS common parameters to downstream cmdlets' -Tag 'Unit' {
    Mock Get-CFNStack { @() }

    Find-CHARCFNStackError -StackName 'app' -Region 'us-east-1' -ProfileName 'test'

    Should -Invoke Get-CFNStack -ParameterFilter {
        $Region -eq 'us-east-1' -and $ProfileName -eq 'test'
    }
}
```

### 9.3 ShouldProcess Pattern

```powershell
It 'does not call destructive commands during WhatIf' -Tag 'Unit' {
    Mock Remove-S3Object {}

    Clear-CHARS3Bucket -BucketName 'release-test' -WhatIf

    Should -Not -Invoke Remove-S3Object
}
```

### 9.4 Error Contract Pattern

```powershell
It 'throws a useful error when the downstream operation fails' -Tag 'Unit' {
    Mock Get-S3Object { throw 'AWS failure' }

    { Clear-CHARS3Bucket -BucketName 'release-test' -ErrorAction Stop } |
        Should -Throw '*AWS failure*'
}
```

## 10. Execution Commands

Run all SRC tests (module + function unit tests):

```powershell
Invoke-Pester -Path ./tests/src -Output Detailed
```

Run source layout gate (enforces test file presence and structure):

```powershell
Invoke-Pester -Path ./tests/src/SourceLayout.Tests.ps1 -Output Detailed
```

Run all unit tests (including legacy test locations):

```powershell
Invoke-Pester -Path ./tests -Tag Unit
```

Run help checks:

```powershell
Invoke-Pester -Path ./tests -Tag Help
```

Run integration tests only:

```powershell
Invoke-Pester -Path ./tests -Tag Integration
```

Run code quality checks:

```powershell
./Scripts/Test-CodeQuality.ps1
```

Run release build/package check:

```powershell
./Scripts/Build-Module.ps1 -Clean -Package
```

## 11. Release Test Sequence

1. Refresh the release inventory from `CharlandCustomizations.psd1`.
2. Verify comment-based help for every function and script.
3. Add or update Pester tests for every changed command under `tests/src/`.
4. Verify source layout gate passes: each source file has a corresponding test file under `tests/src/`.
5. Run SRC unit tests and fix failures: `Invoke-Pester -Path ./tests/src`.
6. Run PSScriptAnalyzer and fix errors via `./Scripts/Test-CodeQuality.ps1`.
7. Build and package the module: `./Scripts/Build-Module.ps1 -Clean -Package`.
8. Import the packaged module in a clean PowerShell session.
9. Run manual smoke checks for command discovery and help.
10. Run opt-in integration tests only when sandbox credentials are configured.
11. Record release exceptions, if any, before publishing.

## 12. Definition Of Done

A function or script is release-ready when:

1. It has discoverable help through `Get-Help` and `-?`.
2. It has at least one Pester test mapped in the inventory.
3. High-risk behavior has mock-based unit coverage.
4. Destructive behavior supports and tests `ShouldProcess` where applicable.
5. Tests pass in a clean environment.
6. Any skipped or deferred coverage has an explicit release exception.

## 13. Immediate Next Targets

Start with the release blockers:

1. Add help tests for all exported functions and `Scripts/*.ps1`.
2. Add unit tests for `Clear-CHARS3Bucket`.
3. Add unit tests for `Set-CHARAuthenticodeSignature` and `Clear-CHARAuthenticodeSignature`.
4. Add unit tests for `Invoke-CHARScriptMultiRegionProfile`.
5. Add unit tests for `New-CHARCFNStackFromDirectory` and `Update-CHARCFNStackFromDirectory`.
6. Add script-level tests for `Scripts/Build-Module.ps1` and `Scripts/Publish-CharlandCustomizations.ps1`.
