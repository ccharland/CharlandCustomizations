# Repository Structure

```
CharlandCustomizations/
├── .github/                       # GitHub configuration
│   ├── rulesets/                   # Repository ruleset definitions
│   └── workflows/                  # CI/CD workflow files
├── .githooks/                     # Local git hooks
│   └── pre-commit                  # Branch path policy hook
├── .kiro/                         # Kiro IDE configuration
│   ├── specs/                     # Feature specifications
│   └── steering/                  # Development guidelines
├── Scripts/                       # Build and deployment scripts
│   ├── Build-Module.ps1
│   ├── Publish-CharlandCustomizations.ps1
│   ├── Register-LocalRepository.ps1
│   ├── Test-BranchPathPolicy.ps1
│   ├── Test-CodeQuality.ps1
│   ├── Test-HelpCompliance.ps1
│   ├── Test-ManifestCompliance.ps1
│   └── Test-SignatureCompliance.ps1
├── src/                           # Module source
│   └── CharlandCustomizations/
│       ├── CharlandCustomizations.psd1  # Module manifest
│       ├── CharlandCustomizations.psm1  # Module loader
│       ├── Private/                     # Internal helpers (not exported)
│       │   ├── New-AWSParamSplat.ps1
│       │   └── CFNPrivateFunctions.ps1
│       └── Public/                      # Exported functions
│           ├── Clear-CHARAuthenticodeSignature.ps1
│           ├── Install-CHARProfilesFromSource.ps1
│           ├── Invoke-CHARScriptMultiRegionProfile.ps1
│           ├── Set-CHARAuthenticodeSignature.ps1
│           ├── Test-CHARAuthenticodeSignature.ps1
│           ├── Update-CHARPowershell7.ps1
│           ├── AWS/
│           │   ├── AWSCustomizations.psm1
│           │   ├── Audit/Audit-AWSAccount.psm1
│           │   ├── CloudFormation/CloudFormation-TemplateProcessing.psm1
│           │   ├── Lambda/Lambda-Customizations.psm1
│           │   └── S3/S3Customizations.psm1
│           └── Git/
│               ├── GitCustomizations.psm1
│               ├── Install-CHARGitHook.ps1
│               └── Test-CHARCommitSignature.ps1
├── tests/                         # Pester tests
├── build/                         # Build output (gitignored)
├── docs/                          # Documentation
├── assets/                        # Icons and images
├── README.md
└── LICENSE
```

## Directory Details

### `src/CharlandCustomizations/`

The module source. This is the working directory for development. The module manifest (`CharlandCustomizations.psd1`) defines the module version, exported functions, and metadata.

- **`Public/`** — Functions exported by the module. Organized by domain (AWS, Git).
- **`Private/`** — Internal helper functions not exported to consumers.

### `Scripts/`

Build, deployment, and CI gate automation:

| Script | Purpose |
|--------|---------|
| `Build-Module.ps1` | Validate, sign, build, and install the module |
| `Publish-CharlandCustomizations.ps1` | Publish to PowerShell Gallery |
| `Register-LocalRepository.ps1` | Register a local NuGet repo for testing |
| `Test-BranchPathPolicy.ps1` | Validate branch/path separation rules |
| `Test-CodeQuality.ps1` | Run PSScriptAnalyzer checks |
| `Test-HelpCompliance.ps1` | Validate comment-based help on public functions |
| `Test-ManifestCompliance.ps1` | Validate manifest export alignment and formatting |
| `Test-SignatureCompliance.ps1` | Validate Authenticode signatures on release files |

### `tests/`

Pester test files. See `docs/TEST-PLAN.md` for the testing strategy.

### `build/`

Gitignored. Created by `Build-Module.ps1` with versioned output:

```
build/
├── CharlandCustomizations/<version>/   # Built module
└── packages/                           # Distribution packages
```

### `docs/`

Project documentation including this file, changelog, installation guide, and function-specific docs.

### `.github/`

GitHub configuration including CI/CD workflows and repository ruleset reference copies.

### `.githooks/`

Local git hooks installed via `Install-CHARGitHook`. The `pre-commit` hook enforces the branch path policy.

### `.kiro/`

Kiro IDE configuration including feature specifications and development steering files.

## Module Loading

The module loader (`CharlandCustomizations.psm1`) initializes script-based functions, while the module manifest controls nested modules and exports:

1. Dot-sources all `.ps1` files in `Private/`
2. Dot-sources all `.ps1` files in `Public/`
3. Loads nested modules through the manifest's `NestedModules` entry
4. Limits exported commands through the manifest's `FunctionsToExport` entry

## Command Prefix

The CHAR prefix is hardcoded directly into every public function name. The source code function names match exactly what users type at the command line:

```powershell
# Function name in source and at the command line are identical
Find-CHARCFNStackError
Get-CHAREC2SGInUse
Clear-CHARAuthenticodeSignature
```

No `DefaultCommandPrefix` is used. This makes function names explicit and discoverable without relying on PowerShell's implicit prefix mechanism.
