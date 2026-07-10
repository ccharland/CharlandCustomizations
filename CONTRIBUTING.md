# Contributing to CharlandCustomizations

Thank you for your interest in contributing. This guide covers the workflow, standards, and checks you need to know before submitting changes.

## Prerequisites

| Requirement | Minimum Version | Notes |
|-------------|-----------------|-------|
| PowerShell | 7.2+ | Core edition only (`CompatiblePSEditions = 'Core'`) |
| Pester | 5.x | Unit test framework |
| PSScriptAnalyzer | Latest | Static analysis |
| AWS.Tools modules | Latest | Required for AWS function development and tests |
| Git | 2.x+ | With commit signing configured |
| Code signing certificate | Valid Authenticode cert | Required for Scripts/ and src/ modifications |

Optional but recommended:

- Kiro IDE (for spec-driven development and steering context)
- A local NuGet repository for testing installs (`./Scripts/Register-LocalRepository.ps1`)

## Getting Started

```powershell
# Clone the repository
git clone https://github.com/ccharland/CharlandCustomizations.git
cd CharlandCustomizations

# Install the pre-commit hook (enforces branch path policy)
Import-Module ./src/CharlandCustomizations/CharlandCustomizations.psd1 -Force
Install-CHARGitHook -Force

# Verify module loads
Get-Command -Module CharlandCustomizations | Measure-Object

# Run tests
Invoke-Pester -Path ./tests -Output Detailed

# Run code quality check
./Scripts/Test-CodeQuality.ps1
```

## Branching Strategy

### Branch Naming

All branches must use an approved prefix. The pre-commit hook and CI will reject commits on unrecognized branches.

**Code branches** (modify `src/` and `tests/src/`):

- `feature/<description>` — New functionality
- `bugfix/<description>` — Bug fixes
- `hotfix/<description>` — Urgent production fixes
- `docs/<description>` — Documentation only
- `chore/<description>` — Maintenance tasks
- `architecture/<description>` — Structural refactors
- `breaking/<description>` — Breaking changes
- `kiro-code/<description>` — Kiro-assisted code changes
- `copilot-code/<description>` — Copilot-assisted code changes

**Infrastructure branches** (modify `.github/`, `Scripts/`, `.kiro/settings/`, `.vscode/`, `tests/scripts/`):

- `workflow/<description>` or `workflows/<description>`
- `infrastructure/<description>` or `infra/<description>`
- `ci/<description>`
- `kiro-infra/<description>` or `copilot-infra/<description>`

### Path Separation Policy

The pre-commit hook enforces separation between code and infrastructure work:

| Branch Type | Can Modify | Cannot Modify |
|-------------|-----------|---------------|
| Code branches | `src/`, `tests/src/`, `docs/`, `assets/` | `.github/`, `Scripts/`, `.githooks/`, `.kiro/settings/`, `.vscode/`, `tests/scripts/` |
| Infrastructure branches | `.github/`, `Scripts/`, `.githooks/`, `.kiro/`, `.vscode/`, `tests/scripts/` | `src/`, `tests/src/` |

For exceptional mixed-scope commits, use the override deliberately:

```powershell
$env:CC_GIT_HOOK_ALLOW_PATH_POLICY_OVERRIDE = '1'
git commit -m 'Explain why this mixed-scope commit is necessary'
Remove-Item Env:\CC_GIT_HOOK_ALLOW_PATH_POLICY_OVERRIDE
```

### Commit Messages

Follow conventional commits format:

```
<type>: <description>

[optional body]
[optional footer]
```

Types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`

Keep commits atomic — one logical change per commit. Each commit should leave the code in a working state.

## Module Architecture

### Directory Layout

```
src/CharlandCustomizations/
├── CharlandCustomizations.psd1    # Module manifest (exports, version)
├── CharlandCustomizations.psm1    # Module loader
├── Private/                       # Internal helpers (not exported)
└── Public/                        # Exported functions
    ├── *.ps1                      # Top-level public functions
    ├── AWS/                       # AWS nested modules
    │   ├── AWSCustomizations.psm1
    │   ├── Audit/
    │   ├── CloudFormation/
    │   ├── Lambda/
    │   └── S3/
    └── Git/                       # Git nested modules
        └── GitCustomizations.psm1
```

### Key Rules

1. **One function per `.ps1` file** — File name matches function name exactly.
2. **CHAR prefix** — All public functions use the `CHAR` prefix directly in their name (e.g., `Get-CHARAWSObjectCount`). No `DefaultCommandPrefix` is used.
3. **Nested module boundaries** — Each `.psm1` under `Public/` is a domain boundary. Don't move functions between nested modules without updating the manifest.
4. **Manifest alignment** — When adding or removing exported functions, update `FunctionsToExport` in `CharlandCustomizations.psd1`. Keep the array sorted alphabetically, one entry per line.
5. **AWS common parameters** — Functions calling AWS cmdlets must accept the standard parameter set (`Region`, `ProfileName`, `AccessKey`, `SecretKey`, `SessionToken`, `Credential`, `ProfileLocation`, `EndpointUrl`) and splat them using `New-AWSParamSplat`.

### Adding a New Function

1. Create the function file in the appropriate `Public/` subdirectory.
2. Add the function name to `FunctionsToExport` in the manifest (sorted alphabetically).
3. Include complete comment-based help (`.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE`).
4. Add Pester tests under `tests/src/` mirroring the source path.
5. Run `./Scripts/Test-ManifestCompliance.ps1` to verify export alignment.

## Code Standards

### PowerShell References

If you're newer to PowerShell module development, these Microsoft docs are helpful:

- [Approved Verbs for PowerShell Commands](https://learn.microsoft.com/en-us/powershell/scripting/developer/cmdlet/approved-verbs-for-windows-powershell-commands) — Use `Get-Verb` locally to see the full list
- [About Comment-Based Help](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_comment_based_help) — Syntax and placement for `.SYNOPSIS`, `.PARAMETER`, `.EXAMPLE`, etc.
- [Strongly Encouraged Development Guidelines](https://learn.microsoft.com/en-us/powershell/scripting/developer/cmdlet/strongly-encouraged-development-guidelines?view=powershell-7.6) — Microsoft's recommended patterns for cmdlet design, error handling, and parameter naming

### Comment-Based Help

Every public function and script requires:

- `.SYNOPSIS` — One-line description
- `.DESCRIPTION` — Detailed explanation
- `.PARAMETER` — Document non-obvious parameters
- `.EXAMPLE` — At least one usage example

Validate with:

```powershell
./Scripts/Test-HelpCompliance.ps1
```

### ShouldProcess for State Changes

Functions that modify state must support `-WhatIf` and `-Confirm`:

```powershell
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
```

Gate destructive operations with `$PSCmdlet.ShouldProcess(...)`.

### Error Handling

- Use `try/catch` with specific error types where possible.
- Include relevant identifiers in error messages (ARN, profile name, etc.).
- Throw meaningful errors rather than silently failing.

### PSScriptAnalyzer

Run before committing:

```powershell
./Scripts/Test-CodeQuality.ps1

# Auto-fix where possible
./Scripts/Test-CodeQuality.ps1 -Fix
```

Errors fail the PR quality gate. Warnings are displayed but don't block.

## Testing

### Framework

- **Pester v5** with `Describe`/`Context`/`It` blocks.
- Tests live under `tests/src/` mirroring the source tree structure.
- Each source file must have a corresponding test file (enforced by `SourceLayout.Tests.ps1`).

### Writing Tests

```powershell
Describe 'Get-CHARSomething' -Tag 'Unit' {
    It 'returns expected output for valid input' {
        # Arrange, Act, Assert
    }

    It 'throws a useful error when input is invalid' {
        { Get-CHARSomething -BadParam } | Should -Throw '*expected message*'
    }
}
```

- Mock AWS cmdlets in unit tests — never make live API calls.
- Tag integration tests with `-Tag 'Integration'` (they don't run in CI by default).
- Test both success and failure paths.
- Include `-WhatIf` coverage for destructive commands.

### Running Tests

```powershell
# All tests
Invoke-Pester -Path ./tests -Output Detailed

# Source unit tests only
Invoke-Pester -Path ./tests/src -Output Detailed

# Source layout gate
Invoke-Pester -Path ./tests/src/SourceLayout.Tests.ps1 -Output Detailed

# Help compliance
Invoke-Pester -Path ./tests -Tag Help

# Specific test file
Invoke-Pester -Path ./tests/src/Public/AWS/AWSCustomizations/Update-CHARSSOCredentialList.Tests.ps1
```

## Code Signing

All `.ps1`, `.psm1`, and `.psd1` files under `Scripts/` and `src/` must be Authenticode-signed before merge.

### Editing Signed Files

1. **Remove** the existing signature block before modifying the file.
2. Make your changes.
3. **Re-sign** through the build workflow:

```powershell
./Scripts/Build-Module.ps1 -Install
```

The build script automatically signs files with invalid or missing signatures. Use `-UpdateAllSignatures` to force re-signing everything.

### Signature Validation

```powershell
# Validate all source and script signatures
./Scripts/Test-SignatureCompliance.ps1
```

CI runs signature compliance checks on PRs that modify `Scripts/`.

## PR Quality Gate

All PRs to `main` must pass these CI checks:

| Check | What It Validates |
|-------|-------------------|
| **Pester Tests** | Source layout gates + all unit tests pass |
| **PSScriptAnalyzer** | No static analysis errors |
| **Comment-Based Help** | All public functions have discoverable help |
| **Manifest Compliance** | Exports match source, arrays sorted one-per-line |
| **Branch Path Policy** | Changed files are appropriate for the branch type |

Additionally, PRs modifying `Scripts/**/*.ps1` trigger the **Signature Compliance** check.

### Before Opening a PR

Run this checklist locally:

```powershell
# 1. Tests pass
Invoke-Pester -Path ./tests -Output Detailed

# 2. Code quality clean
./Scripts/Test-CodeQuality.ps1

# 3. Help is complete
./Scripts/Test-HelpCompliance.ps1

# 4. Manifest aligned
./Scripts/Test-ManifestCompliance.ps1

# 5. Signatures valid (if you modified signed files)
./Scripts/Test-SignatureCompliance.ps1

# 6. Build succeeds
./Scripts/Build-Module.ps1 -Clean -Install
```

## Build and Release

### Development Build

```powershell
# Build and install locally
./Scripts/Build-Module.ps1 -Install

# Quick install from source (no build/sign)
./Scripts/Build-Module.ps1 -InstallOnly
```

### Release Flow

Releases are triggered by version tags (`v*.*.*`). The publish workflow validates that all PR quality gate checks passed on the tagged commit before publishing to PSGallery.

```powershell
# Bump version, prepare changelog, build, and install
./Scripts/Build-Module.ps1 -BumpVersion Patch -PrepareRelease -Clean -Install
```

See `docs/BUILD-PROCESS.md` for the complete release workflow.

## Documentation

When behavior changes, update the relevant docs:

- `docs/CHANGELOG.md` — All user-visible changes
- `docs/QUICK-REFERENCE.md` — Command quick reference
- Function comment-based help — Keep examples current

## Questions?

Open an issue or reach out to the maintainer. Keep branches short-lived and PRs focused.
