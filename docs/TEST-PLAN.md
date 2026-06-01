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
6. Manifest gate: exported functions in the manifest match the public release surface.
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

- `Clear-CCS3Bucket`
- `New-CCCFNStackFromDirectory`
- `Update-CCCFNStackFromDirectory`
- `Set-CCAWSProfileWithMFA`
- `Update-CCSSOCredentialList`
- `Remove-CCExpiredAWSProfiles`
- `Use-CCAssumedRole`
- `Invoke-CCScriptMultiAccountRegion`
- `Set-CCFileSignature`
- `Clear-CCAuthenticodeSignature`
- `Install-CCGitHook`
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

- `Find-CCCFNStackErrors`
- `Get-CCAWSMFASession`
- `Set-CCAWSEnv`
- `Get-CCAccountListFromProfiles`
- `Start-CCMultiStackDriftDetection`
- `Get-CCAWSAccountListOfDriftedResources`
- `Get-CCAWSObjectCount`
- `Test-CCCFNStackFromDirectory`
- `Out-CCCFNStackInfo`
- `New-CCCFNStackDirectory`
- `Edit-CCCFTTEbsVolumes`
- `Test-CCCommitSignature`
- `Scripts/Test-CodeQuality.ps1`

Minimum tests:

- Help exists and can be retrieved
- At least one behavior-focused Pester test
- Happy path with mocks or temporary test data
- Empty/null input handling
- Output object or message assertions

### Priority 3: Audit And Reporting

- `Get-CCEC2SGInUse`
- `Get-CCEC2Count`
- `Find-CCEC2DBSG`
- `Out-CCAWSSupportingInfo`
- `Out-CCAWSNetworkingComponent`
- `Get-CCIAMAuditList`
- `Get-CCGlobalAuditReportItem`
- `Get-CCEC2KeyTagNameStatus`
- `Get-CCEC2SnapshotReport`
- `Get-CCEC2VolumeReport`
- `Start-CCEC2RetryLoop`
- `Find-CCOpenSecurityGroup`
- `Install-CCProfilesFromSource`
- `Update-CCPowershell7`

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
| `Install-CCProfilesFromSource` | Function | P3 | Pending | Pending | Local profile copy behavior |
| `Invoke-CCScriptMultiAccountRegion` | Function | P1 | Pending | Pending | Multi-account execution contract |
| `Set-CCFileSignature` | Function | P1 | Pending | Pending | Signing side effects |
| `Update-CCPowershell7` | Function | P3 | Pending | Pending | External install/update behavior |
| `Clear-CCAuthenticodeSignature` | Function | P1 | Pending | Pending | File mutation |
| `Find-CCCFNStackErrors` | Function | P2 | Pending | Pending | AWS mocks |
| `Set-CCAWSProfileWithMFA` | Function | P1 | Pending | Pending | Credential mutation |
| `Get-CCAWSMFASession` | Function | P2 | Pending | Pending | STS mocks |
| `Start-CCMultiStackDriftDetection` | Function | P2 | Pending | Pending | CloudFormation mocks |
| `Get-CCAWSAccountListOfDriftedResources` | Function | P2 | Pending | Pending | CloudFormation mocks |
| `Get-CCAWSObjectCount` | Function | P2 | Pending | Pending | AWS inventory mocks |
| `Set-CCAWSEnv` | Function | P2 | Pending | Pending | Environment mutation |
| `Update-CCSSOCredentialList` | Function | P1 | Pending | Pending | SSO credential file behavior |
| `Remove-CCExpiredAWSProfiles` | Function | P1 | Pending | Pending | Credential file mutation |
| `Get-CCAccountListFromProfiles` | Function | P2 | Pending | Pending | Local credential parsing |
| `Use-CCAssumedRole` | Function | P1 | Pending | Pending | Credential/environment mutation |
| `New-CCCFNStackFromDirectory` | Function | P1 | Pending | Pending | CloudFormation create flow |
| `Test-CCCFNStackFromDirectory` | Function | P2 | Pending | Pending | Template validation flow |
| `Out-CCCFNStackInfo` | Function | P2 | Pending | Pending | Output file/report behavior |
| `Update-CCCFNStackFromDirectory` | Function | P1 | Pending | Pending | CloudFormation update flow |
| `New-CCCFNStackDirectory` | Function | P2 | Pending | Pending | File creation |
| `Edit-CCCFTTEbsVolumes` | Function | P2 | Pending | Pending | Template transformation |
| `Clear-CCS3Bucket` | Function | P1 | Pending | Pending | Destructive S3 behavior |
| `Get-CCEC2SGInUse` | Function | P3 | Pending | Pending | EC2/security group mocks |
| `Get-CCEC2Count` | Function | P3 | Pending | Pending | EC2 mocks |
| `Find-CCEC2DBSG` | Function | P3 | Pending | Pending | Security group analysis |
| `Out-CCAWSSupportingInfo` | Function | P3 | Pending | Pending | Report output |
| `Out-CCAWSNetworkingComponent` | Function | P3 | Pending | Pending | Report output |
| `Get-CCIAMAuditList` | Function | P3 | Pending | Pending | IAM mocks |
| `Get-CCGlobalAuditReportItem` | Function | P3 | Pending | Pending | Report item shape |
| `Get-CCEC2KeyTagNameStatus` | Function | P3 | Pending | Pending | Tag analysis |
| `Get-CCEC2SnapshotReport` | Function | P3 | Pending | Pending | Snapshot mocks |
| `Get-CCEC2VolumeReport` | Function | P3 | Pending | Pending | Volume mocks |
| `Start-CCEC2RetryLoop` | Function | P3 | Pending | Pending | Retry behavior |
| `Find-CCOpenSecurityGroup` | Function | P3 | Pending | Pending | Security group rules |
| `Test-CCCommitSignature` | Function | P2 | Pending | Pending | Temporary git repo |
| `Install-CCGitHook` | Function | P1 | Pending | Pending | File mutation |
| `New-AWSParamSplat` | Private Helper | P2 | Ready | Ready | Existing tests in `tests/New-AWSParamSplat.Tests.ps1` |
| `Scripts/Build-Module.ps1` | Script | P1 | Pending | Pending | Build/package gate |
| `Scripts/Publish-CharlandCustomizations.ps1` | Script | P1 | Pending | Pending | Publish flow with mocks |
| `Scripts/Register-LocalRepository.ps1` | Script | P1 | Pending | Pending | Repository registration |
| `Scripts/Test-CodeQuality.ps1` | Script | P2 | Pending | Pending | Analyzer invocation |

## 8. Recommended Test Organization

Recommended folders:

- `tests/Unit/Core/*.Tests.ps1`
- `tests/Unit/AWS/*.Tests.ps1`
- `tests/Unit/AWS/S3/*.Tests.ps1`
- `tests/Unit/AWS/Audit/*.Tests.ps1`
- `tests/Unit/CloudFormation/*.Tests.ps1`
- `tests/Unit/Git/*.Tests.ps1`
- `tests/Unit/Scripts/*.Tests.ps1`
- `tests/Integration/**/*.Tests.ps1`

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
    $help = Get-Help Clear-CCS3Bucket -Full

    $help.Synopsis | Should -Not -BeNullOrEmpty
    $help.Examples.Example.Count | Should -BeGreaterThan 0
}
```

### 9.2 Splatting Contract Pattern

```powershell
It 'passes AWS common parameters to downstream cmdlets' -Tag 'Unit' {
    Mock Get-CFNStack { @() }

    Find-CCCFNStackErrors -StackName 'app' -Region 'us-east-1' -ProfileName 'test'

    Should -Invoke Get-CFNStack -ParameterFilter {
        $Region -eq 'us-east-1' -and $ProfileName -eq 'test'
    }
}
```

### 9.3 ShouldProcess Pattern

```powershell
It 'does not call destructive commands during WhatIf' -Tag 'Unit' {
    Mock Remove-S3Object {}

    Clear-CCS3Bucket -BucketName 'release-test' -WhatIf

    Should -Not -Invoke Remove-S3Object
}
```

### 9.4 Error Contract Pattern

```powershell
It 'throws a useful error when the downstream operation fails' -Tag 'Unit' {
    Mock Get-S3Object { throw 'AWS failure' }

    { Clear-CCS3Bucket -BucketName 'release-test' -ErrorAction Stop } |
        Should -Throw '*AWS failure*'
}
```

## 10. Execution Commands

Run all unit tests:

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
3. Add or update Pester tests for every changed command.
4. Run unit tests and fix failures.
5. Run PSScriptAnalyzer and fix errors.
6. Build and package the module.
7. Import the packaged module in a clean PowerShell session.
8. Run manual smoke checks for command discovery and help.
9. Run opt-in integration tests only when sandbox credentials are configured.
10. Record release exceptions, if any, before publishing.

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
2. Add unit tests for `Clear-CCS3Bucket`.
3. Add unit tests for `Set-CCFileSignature` and `Clear-CCAuthenticodeSignature`.
4. Add unit tests for `Invoke-CCScriptMultiAccountRegion`.
5. Add unit tests for `New-CCCFNStackFromDirectory` and `Update-CCCFNStackFromDirectory`.
6. Add script-level tests for `Scripts/Build-Module.ps1` and `Scripts/Publish-CharlandCustomizations.ps1`.
