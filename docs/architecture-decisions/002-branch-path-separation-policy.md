# ADR-002: Branch Path Separation Policy

## Status

Accepted

## Date

2026-06-11

## Context

As AI tools (Copilot, Kiro, Codex) are used alongside manual development, there's a risk of accidentally mixing infrastructure changes (CI workflows, build scripts) with source code changes in a single branch. This makes:

- PR reviews harder (mixing unrelated concerns).
- CI failures harder to diagnose (is it a code bug or a workflow change?).
- Rollbacks riskier (can't revert one without the other).

## Decision

Enforce a branch path separation policy:

- **Code branches** (`feature/*`, `bugfix/*`, etc.) are blocked from modifying `.github/`, `Scripts/`, `.githooks/`, `.kiro/settings/`, `.vscode/`, and `tests/scripts/`, with one exact-file exception for `.vscode/cspell.json`. Everything else (including `src/`, `tests/src/`, `.vscode/cspell.json`, `docs/`, root files, `assets/`) is allowed.
- **Infrastructure branches** (`workflow/*`, `infra/*`, `ci/*`, etc.) are blocked from modifying `src/` and `tests/src/`. Everything else (including `.github/`, `Scripts/`, `.githooks/`, `.kiro/`, `.vscode/`, `tests/scripts/`, `docs/`, root files, `assets/`) is allowed.
- **Publish branches** (`publish/*`) are blocked from modifying `.github/`, `.githooks/`, `.kiro/`, `.vscode/`, `Scripts/`, and `tests/`. Everything else is allowed, including `src/`, `docs/`, root files, and `assets/`.
- **Bare AI-root branches** (`copilot/*`, `codex/*`, `kiro/*`) are blocked from modifying **any** path. Any change at all fails the policy, forcing the branch to be renamed to a `-code/` prefix (for source changes) or a `-infra/` prefix (for workflow/infrastructure changes) before it can merge into `main`. The `*-code/` and `*-infra/` variants (`copilot-code/`, `kiro-infra/`, etc.) behave as normal code or infrastructure branches respectively.

Enforcement happens at two levels:

1. **Local pre-commit hook** — immediate feedback, blocks the commit.
2. **CI workflow** (`branch-path-policy.yml`) — catches anything that bypasses the hook.

An escape hatch (`CC_GIT_HOOK_ALLOW_PATH_POLICY_OVERRIDE=1`) exists for genuinely inseparable changes.

## Consequences

### Positive

- PRs are focused — reviewers see one kind of change at a time.
- AI-generated changes can't accidentally touch CI or signing scripts on a code branch.
- Easier to reason about what broke when a CI check fails.
- Release branches can be scoped precisely.
- Code changes can add repository-specific spelling terms without granting access to unrelated editor configuration.

### Negative

- Occasionally requires two branches/PRs for tightly coupled changes (e.g., adding a function that also needs a new CI check).
- Contributors must learn the branch naming convention before their first commit.
- Branches created by AI tools need to be renamed before merging.

### Neutral

- The override mechanism means this is a guardrail, not a hard wall. Deliberate exceptions are still possible.

## Amendments

### 2026-08-13 — Allow AI-generated branch prefixes (issue #111)

AI automation tools (Copilot, Codex, Kiro) create branches using their own prefixes (`copilot/*`, `codex/*`, `kiro/*`). The branch creation ruleset now allows these prefixes so the tools can perform background work without being blocked. Dependabot also creates branches using its own prefix  (`dependabot/*`.) 

This does **not** weaken merge protections. Existing required workflow checks (`branch-path-policy.yml`, `pr-quality-gate.yml`) still enforce path separation and status checks on any PR targeting `main`. AI-generated branches must be renamed to an approved prefix (e.g. `feature/*`, `infrastructure/*`) before merge to satisfy these checks.

### 2026-08-30 — Bare AI-root branches block all paths before merge

Previously the bare AI-root prefixes (`copilot/*`, `codex/*`, `kiro/*`) only blocked `src/`, `tests/src/`, and `Scripts/`. This left a gap: a bare AI-root branch that only touched `.github/`, `docs/`, `.kiro/`, or root files could pass the policy and merge into `main` without ever being renamed.

`Test-BranchPathPolicy.ps1` now treats bare AI-root prefixes as a hard "rename required" gate using a `BlockAllPaths` flag. Any changed path fails the policy, so these branches must be renamed to a `-code/` or `-infra/` variant before merge. This approach is future-proof: new top-level directories are covered automatically without editing a blocked-path list. Branches with no changed paths still pass.