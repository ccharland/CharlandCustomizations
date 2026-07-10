# CharlandCustomizations

![Project Icon](assets/icon-128.png)

This is my public release for my PowerShell module and related automation. These functions are primarily for my own use, and are public so I can easily use them in CloudShell, AWS WorkSpaces, and other environments without needing to clone this repository.

All public commands use the "CHAR" prefix before the noun of the command (e.g., `Find-CHARCFNStackError`, `Set-CHARAWSEnv`).

> **v0.4.0 Breaking Change:** All commands were renamed from the `CC` prefix to `CHAR` (e.g., `Find-CCCFNStackError` → `Find-CHARCFNStackError`). If you are upgrading from v0.3.x or earlier, update your scripts to use the new prefix. See [docs/CHANGELOG.md](docs/CHANGELOG.md) for full details.

## Goals

I'm using this project to learn how to build and maintain a PowerShell module, and to share useful functions that I create for my own work. The module is focused on AWS automation, but may include other utilities as well, especially around module deployment, code signing, and PowerShell Gallery publishing.

I'm also working on building a repeatable build and release process, including code signing, packaging, and publishing to the PowerShell Gallery. The goal is to make important steps hard to skip and keep module quality high over time. The more automation, the better.

## Quick start

```powershell
Install-Module CharlandCustomizations -Scope CurrentUser
Import-Module CharlandCustomizations

# Examples
Find-CHARCFNStackError
Set-CHARAWSEnv -ProfileName my-sso-profile
```

## Repository baseline
```
CharlandCustomizations/
    ├── .github/
    │   ├── rulesets/            # Repository ruleset definitions
    │   └── workflows/           # CI/CD pipelines
    ├── .githooks/
    │   └── pre-commit           # Branch path policy hook
    ├── .kiro/                   # Kiro IDE config and steering
    ├── Scripts/                 # Build, test, and deployment scripts
    ├── assets/                  # Icons and images
    ├── docs/                    # Project documentation
    ├── src/
    │   └── CharlandCustomizations/
    │       ├── CharlandCustomizations.psd1
    │       ├── CharlandCustomizations.psm1
    │       ├── Public/          # Exported functions (AWS, Git, signing)
    │       └── Private/         # Internal helpers
    ├── tests/                   # Pester tests
    ├── build/                   # Build output (gitignored)
    └── README.md
```

## Branch standards

All branches must use a `type/description` format (e.g., `feature/alarm-management`). The repository ruleset blocks branches that don't match an approved prefix, and a path policy prevents mixing source and infrastructure changes in the same branch.

See [CONTRIBUTING.md](CONTRIBUTING.md) for the full list of approved prefixes, path policy details, and override instructions.

## Release safety

### Version tags

Release tags follow the pattern `v<major>.<minor>.<patch>` (e.g., `v0.3.0`) or `v<major>.<minor>.<patch>-<prerelease>` for pre-releases. Tags are protected by a GitHub ruleset that enforces:

- **Immutability** — tags cannot be deleted, updated, or force-pushed.
- **Signed commits** — the tagged commit must have a verified signature.
- **Required status checks** — Pester Tests, PSScriptAnalyzer, Comment-Based Help, Manifest Compliance, and CodeQL must all pass.
- **No bypass actors** — no users or apps can skip these requirements.

The tag version must match the `ModuleVersion` (and optional `Prerelease`) in the module manifest. The publish workflow validates this before releasing to the PowerShell Gallery.

For release workflow details, see [docs/BUILD-PROCESS.md](docs/BUILD-PROCESS.md).

## Use of AI:

- AI is my "Intern powered by Red Bull" for code generation, documentation, and automation. I use the tools to do the majority of the work, but I review and edit when needed to make sure everything is working as expected.

- Tools used in this repository include:
  - Kiro
  - GitHub Copilot
  - ChatGPT for generic guidance and Image generation
  - Codex

## Adding components to the module

I want everything tested, documented, and included in the build and release process. This means that I need to add new functions to the module, add tests for those functions, and make sure they are included in the build and release process. My Pull requests will be large until I get the baseline established, but I will try to keep them as small as possible after that, and limit them to one module/function at a time, to keep the AI tools and code reviewers happy with smaller changes.
