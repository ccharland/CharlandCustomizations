# ADR-009: Newcomer-friendly design choices

## Status

Accepted

## Date

2026-08-28

## Context

This module is used by people with a range of PowerShell experience levels, including those who are new to PowerShell modules and to the AWS Tools for PowerShell ecosystem. Several sources of friction disproportionately hurt newcomers:

- **Module dependency management.** AWS Tools for PowerShell is split into many `AWS.Tools.*` service modules. A service cmdlet (for example `Get-EC2Instance`) fails with an unhelpful "term not recognized" error if the matching module is missing, and mismatched versions across service modules cause subtle, hard-to-diagnose failures. A newcomer hitting this early often abandons the tool before doing any real work.
- **Cognitive load of dependency setup.** Requiring users to manually discover, install, and version-align the correct `AWS.Tools.*` module before they can run a function is a barrier that experienced users tolerate but newcomers find opaque and frustrating.
- **Unforgiving raw AWS cmdlets.** The underlying AWS cmdlets reject input that is "almost right" (wrong casing, wrong separators, a missing prefix) and expect the caller to already know the exact shape of every argument and the multi-step sequence for common tasks. Newcomers rarely know these conventions up front.
- **Scaling a single operation across an estate.** Running the same read against many accounts and regions is a common real-world need, but doing it by hand means writing profile/region loops and credential juggling — well beyond what a newcomer should have to build to get an answer.

Keeping the installed `AWS.Tools.*` service modules in sync with the locally available `AWS.Tools.Common` version is important for correctness. A recurring design question is *where* responsibility should live: on the user, or absorbed by the module.

## Decision

Favor design choices that reduce friction for newcomers, even when they add boilerplate or cost for maintainers. Three standing patterns embody this principle.

### 1. Absorb dependency and version-sync responsibility (`Test-CHARAWSCmdlet`)

- **Every AWS-facing function calls `Test-CHARAWSCmdlet` for the first cmdlet it uses from each distinct AWS Tools service module.** This is an intentional, standing choice — not incidental boilerplate. When a required service module is missing, `Test-CHARAWSCmdlet` locates the owning `AWS.Tools.*` module in the gallery, installs the version that matches the local `AWS.Tools.Common`, and verifies the cmdlet resolves. It prompts before installing (and supports `-Force` for unattended runs).
- **The module absorbs dependency and version-sync responsibility so the user does not have to.** Removing this friction is treated as a first-class goal, worth the repetition and performance impact it introduces across functions.
- **The root module loader applies the same philosophy for the base dependency.** `CharlandCustomizations.psm1` does not simply fail when AWS Tools is absent; it prompts to install `AWS.Tools.Common`, honors `CHAR_AUTO_INSTALL_AWS_TOOLS` for unattended runs, and emits an actionable remediation command (`Update-AWSToolsModule`) when the installed version is too old. This is the loader-level counterpart to the per-function `Test-CHARAWSCmdlet` check.

Scope guardrails (to keep the cost bounded):

- Validate only the *first* cmdlet from each distinct service module per function — not every cmdlet from the same module.
- Do not re-validate `AWS.Tools.Common`; the root loader already handles that.

### 2. Make wrappers forgiving — guess the user's likely intent

Wrapper functions should make intelligent guesses about what most users are trying to do, rather than rejecting near-miss input or forcing the user to assemble a multi-step operation themselves.

- **Correct-first validation instead of hard rejection.** `Test-CHARConfigResourceType` is the reference example: given `aws::ec2::instance` it normalizes casing, separators, and the missing `AWS::` prefix and returns `AWS::EC2::Instance`, only returning `$false` when the input truly cannot be salvaged. It never throws on bad input.
- **Sensible defaults so a bare call does the useful thing.** Functions such as `Get-CHAREC2SGInUse` run with no arguments — defaulting to the current region and all resources — so a newcomer gets a meaningful result immediately.
- **Wrap a common multi-step task into one obvious verb.** The ACM certificate audit functions, the Lambda deprecation functions (`Get-CHARDeprecatedLMFunctionList`), and similar wrappers exist to collapse a sequence of raw AWS calls into the single operation most users actually want, with opinionated defaults for the rest.

The intent: the wrapper should behave the way a reasonable user expects on the first try, not demand that the user already know the exact conventions of the underlying AWS cmdlet.

### 3. Make estate-wide execution a first-class, low-effort operation

`Invoke-CHARScriptMultiRegionProfile` lets a user run a script block across many profiles and regions without writing their own credential/region loops. It handles ambient credentials (CloudShell, instance/task roles), per-iteration error capture, and consistent output shape so failures in one region do not derail the run.

**Wrapper compatibility is a design requirement, not a coincidence.** The runner injects `$Region`, `$ProfileName`, and `$PSDefaultParameterValues` into the script block scope, so any function that accepts `-Region`/`-ProfileName` (which every AWS wrapper here does, per [ADR-005](005-aws-common-parameter-splatting.md)) automatically picks up the current iteration's values without the user passing them explicitly. New AWS wrappers must preserve this compatibility: accept the AWS common parameters and honor injected defaults so they drop cleanly into a multi-region/profile run.

## Consequences

### Positive

- Newcomers can run a function and be guided through installing the correct, version-matched service module instead of hitting a cryptic failure.
- `AWS.Tools.*` service modules stay aligned with `AWS.Tools.Common`, avoiding a whole class of version-mismatch bugs.
- Forgiving wrappers and sensible defaults mean a first attempt is more likely to succeed, which keeps newcomers engaged.
- Estate-wide data gathering is a one-liner, and every conforming wrapper works inside it for free.

### Negative

- Repetition: the `Test-CHARAWSCmdlet` call and the full AWS common parameter block appear in many functions, which looks redundant to experienced readers.
- A small runtime cost on first use of each service module (the availability check and possible install).
- Correction-first validation can mask genuinely wrong input if a caller is not paying attention to the corrected value that comes back.
- `Test-CHARAWSCmdlet` and the multi-region runner become coupling points — a bug in either affects the newcomer experience module-wide.

### Neutral

- Functions that do not call AWS cmdlets do not use these patterns.
- Experienced users who already manage their modules simply see the check pass with negligible overhead.
- The patterns are documented for contributors in `docs/NEW-FEATURE-PARAMETERS.md` and the agent steering, so new code follows them by default.

---

Authored by Kiro (Auto), reviewed by ccharland, on 2026-08-28.
