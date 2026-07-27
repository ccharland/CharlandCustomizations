# CharlandCustomizations Release Testing Plan

## 1. Purpose

This plan defines testing standards and release requirements for `CharlandCustomizations`. All functions shipped before v0.5.0 have passing Pester tests and are not tracked here. This document focuses on:

- Requirements for new functions and modules added going forward (see section 3.1)
- The test inventory for v0.5.0 additions (see section 7)
- Standards and patterns for maintaining quality as the module grows

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

## 3.1 Adding a New Function or Module

Every new public function or nested module added to the module must satisfy all of the following before the PR is ready for review. These requirements are a superset of the per-release checks in section 3 and are meant to be completed during development, not at release time.

### Source files

- Place the function in the correct subdirectory under `src/CharlandCustomizations/Public/`:
  - Standalone functions: `Public/<FunctionName>.ps1`
  - AWS domain functions: `Public/AWS/<Domain>/<Domain>-Customizations.psm1` (add to the existing nested module file for the domain, or create a new nested module under a new subdirectory)
- Add or update `Export-ModuleMember -Function` in the nested module file where the function lives. The list must be sorted alphabetically, one entry per line.
- Add the function name to `FunctionsToExport` in `CharlandCustomizations.psd1`. The array must be sorted alphabetically, one entry per line.
- If a new nested module (`.psm1`) is created, add it to `NestedModules` in `CharlandCustomizations.psd1`.

### Comment-based help

- Every function must have a `.SYNOPSIS`, a `.DESCRIPTION`, `.PARAMETER` blocks for all non-obvious parameters, and at least one `.EXAMPLE`.
- Run `Get-Help <FunctionName> -Full` after loading the module to confirm help is discoverable.

### Pester tests

- Create a test file that mirrors the source path under `tests/src/`:
  - Standalone function: `tests/src/Public/<FunctionName>.Tests.ps1`
  - Nested module function: `tests/src/Public/AWS/<Domain>/<ModuleName>/<FunctionName>.Tests.ps1`
- The test file must have at least:
  1. A help check (`Get-Help <FunctionName>` returns a synopsis and at least one example)
  2. A happy-path behavior test with mocks for any AWS, filesystem, or external calls
  3. An error-path test for the most likely failure mode
  4. A `-WhatIf` / `ShouldProcess` test for any function that mutates state
- Tag unit tests with `-Tag 'Unit'` and help tests with `-Tag 'Help'`.
- Run `Invoke-Pester -Path ./tests/src -Output Detailed` to verify the new tests pass and do not break existing ones.

### Manifest and quality gates

- Run `./Scripts/Test-ManifestCompliance.ps1` — must pass with no errors.
- Run `./Scripts/Test-HelpCompliance.ps1` — must pass with no errors.
- Run `./Scripts/Test-CodeQuality.ps1` — PSScriptAnalyzer must report no errors.

### Documentation

- Add the function to section 6 (Risk-Based Priorities) of this file under the appropriate priority tier:
  - **P1** — mutates credentials, ACM/AWS resources, files on disk, or runs across accounts
  - **P2** — core workflow, installs/registers software, or interacts with external services
  - **P3** — read-only audit, reporting, or informational output
- Add a row to the Release Inventory Checklist in section 7 with status `Passing` once tests are green.
- Add an example to `docs/QUICK-REFERENCE.md` under the relevant section.
- If the function lives in a new nested module, add it to the source tree in `docs/STRUCTURE.md` and to the "When To Use It" list in `docs/NEW-FEATURE-PARAMETERS.md`.

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

Examples:

- Clear-CHARS3Bucket
- Invoke-CHARScriptMultiRegionProfile
- Set-CHARAuthenticodeSignature

Minimum tests:

- Help exists and can be retrieved
- At least one behavior-focused Pester test
- Parameter validation and defaults
- Failure path with downstream command throwing
- `ShouldProcess` / `-WhatIf` behavior where state changes occur
- No accidental live AWS calls in unit tests

### Priority 2: Core Workflows

- These commands are part of the core module workflow, install or register software, or interact with external services. They require moderate testing before release.
  Examples:

- Install-CHARProfilesFromSource
- Test-CHARAWSCmdlet
- Update-CHARSSOCredentialList

Minimum tests:

- Help exists and can be retrieved
- At least one behavior-focused Pester test
- Happy path with mocks or temporary test data
- Empty/null input handling
- Output object or message assertions

### Priority 3: Audit And Reporting

- Functions that read state, report, or audit without mutating credentials or resources.

Minimum tests:

- Help exists and can be retrieved
- At least one behavior-focused Pester test
- Basic execution with mocks or local test data
- Null/empty collection handling
- Expected fields in output

## 7. Recommended Test Organization

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
- `tests/src/Public/AWS/ACM/ACM-Customizations/*.Tests.ps1`
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

## 8. Test Design Patterns

### 8.1 Help Coverage Pattern

```powershell
It 'has discoverable comment-based help' -Tag 'Help' {
    $help = Get-Help Clear-CHARS3Bucket -Full

    $help.Synopsis | Should -Not -BeNullOrEmpty
    $help.Examples.Example.Count | Should -BeGreaterThan 0
}
```

### 8.2 Splatting Contract Pattern

```powershell
It 'passes AWS common parameters to downstream cmdlets' -Tag 'Unit' {
    Mock Get-CFNStack { @() }

    Find-CHARCFNStackError -StackName 'app' -Region 'us-east-1' -ProfileName 'test'

    Should -Invoke Get-CFNStack -ParameterFilter {
        $Region -eq 'us-east-1' -and $ProfileName -eq 'test'
    }
}
```

### 8.3 ShouldProcess Pattern

```powershell
It 'does not call destructive commands during WhatIf' -Tag 'Unit' {
    Mock Remove-S3Object {}

    Clear-CHARS3Bucket -BucketName 'release-test' -WhatIf

    Should -Not -Invoke Remove-S3Object
}
```

### 8.4 Error Contract Pattern

```powershell
It 'throws a useful error when the downstream operation fails' -Tag 'Unit' {
    Mock Get-S3Object { throw 'AWS failure' }

    { Clear-CHARS3Bucket -BucketName 'release-test' -ErrorAction Stop } |
        Should -Throw '*AWS failure*'
}
```

## 9. Execution Commands

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

## 10. Release Test Sequence

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

## 11. Definition Of Done

A function or script is release-ready when:

1. It has discoverable help through `Get-Help` and `-?`.
2. It has at least one Pester test mapped in the inventory.
3. High-risk behavior has mock-based unit coverage.
4. Destructive behavior supports and tests `ShouldProcess` where applicable.
5. Tests pass in a clean environment.
6. Any skipped or deferred coverage has an explicit release exception.
