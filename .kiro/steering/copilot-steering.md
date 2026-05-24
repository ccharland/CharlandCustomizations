---
description: Copilot-specific steering for CharlandCustomizations development and maintenance
inclusion: auto
---

# Copilot Steering for CharlandCustomizations

## Purpose

This document defines how GitHub Copilot should work in this repository.
It complements existing steering documents and focuses on repo-specific implementation rules.

## Repository Facts

- Source of truth is `src/CharlandCustomizations/`.
- Build output is generated under `build/` and should not be edited directly.
- Module loader: `src/CharlandCustomizations/CharlandCustomizations.psm1`.
- Module exports are controlled by `src/CharlandCustomizations/CharlandCustomizations.psd1` via `FunctionsToExport`.
- Default command prefix is `CC` through module manifest `DefaultCommandPrefix`.

## Module Architecture Rules

- Use one function per `.ps1` file in `Public/` or `Private/`.
- File name must match function name exactly (for example, `Get-Thing.ps1` contains `function Get-Thing`).
- Public function files go in `src/CharlandCustomizations/Public/`.
- Private helper files go in `src/CharlandCustomizations/Private/`.
- Keep nested module domain boundaries intact:
  - `Public/AWS/AWSCustomizations.psm1`
  - `Public/AWS/CloudFormation/CloudFormation-TemplateProcessing.psm1`
  - `Public/AWS/S3/S3Customizations.psm1`
  - `Public/AWS/Audit/Audit-AWSAccount.psm1`
  - `Public/Git/GitCustomizations.psm1`

## Export and Manifest Discipline

When adding, renaming, or removing an exported function, update all of:

1. Function file in source tree.
2. `FunctionsToExport` in module manifest.
3. Any affected tests and docs.

Do not rely on wildcard exports for final changes.
Prefer explicit export lists in the manifest to avoid accidental API drift.

## AWS Function Contract

For functions that call AWS cmdlets, use the common parameter splatting pattern.

Required AWS common parameters:

- `Region`
- `ProfileName`
- `AccessKey`
- `SecretKey`
- `SessionToken`
- `Credential`
- `ProfileLocation`
- `EndpointUrl`

Implementation pattern:

1. Accept AWS common parameters in the function parameter block.
2. Build `$awsParams` once in `begin` using:
   `New-AWSParamSplat -BoundParameters $PSBoundParameters`
3. Splat `@awsParams` into each AWS cmdlet invocation.

This is the preferred pattern for new/refactored AWS code.

## State-Changing Safety

- Functions that change state should use:
  `[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]`
- Gate destructive operations with `$PSCmdlet.ShouldProcess(...)`.
- `-WhatIf` must prevent destructive actions.

Typical high-risk operations in this repo:

- S3 object deletion
- CloudFormation create/update/delete workflows
- Profile and credential mutation
- File/signature modification

## Code Quality Baseline

- Follow PSScriptAnalyzer guidance in `docs/CODE-QUALITY.md`.
- Avoid `Write-Host` in module functions unless there is a justified exception.
- If suppressing analyzer rules, include a clear justification.
- Keep error handling explicit (`try/catch`, actionable error output, no silent failure).

Primary quality command:

`./Scripts/Test-CodeQuality.ps1`

## Testing Baseline

- Use Pester v5 style tests under `tests/`.
- Add or update tests when changing exported behavior.
- Mock AWS cmdlets in unit tests.
- Include regression tests for bug fixes.

Useful test command:

`Invoke-Pester -Path ./tests`

Risk-based test priorities are defined in `docs/TEST-PLAN.md`.

## Build and Release Workflow

Use `Scripts/Build-Module.ps1` as the canonical build path.

Common flows:

- Validate/build: `./Scripts/Build-Module.ps1`
- Build/install: `./Scripts/Build-Module.ps1 -Install`
- Release prep: `./Scripts/Build-Module.ps1 -BumpVersion Patch -PrepareRelease -Clean -Install`

Release-related updates should include:

1. Manifest version update.
2. Changelog updates in `docs/CHANGELOG.md`.
3. Verification that module imports and exports expected commands.

## Git and Change Hygiene

- Keep changes focused and minimal.
- Do not edit generated build artifacts as source changes.
- Use signed commits per repository guidance.
- Use clear commit messages that describe the concrete change.

## Documentation Expectations

When behavior changes, update relevant docs in `docs/` and examples where needed.
At minimum, keep these aligned with code:

- `docs/QUICK-REFERENCE.md`
- `docs/TEST-PLAN.md`
- `docs/CODE-QUALITY.md`
- `docs/BUILD-PROCESS.md`

## Copilot Implementation Checklist

Before finishing a code change, verify:

1. Source edits were made only under intended source directories.
2. Exported function changes are reflected in manifest and tests.
3. AWS cmdlet functions follow the shared splatting pattern.
4. Analyzer and tests were run (or clearly reported if not run).
5. Documentation was updated when externally visible behavior changed.
