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

- **Code branches** (`feature/*`, `bugfix/*`, etc.) are blocked from modifying `.github/`, `Scripts/`, `.githooks/`, `.kiro/settings/`, `.vscode/`, and `tests/scripts/`. Everything else (including `src/`, `tests/src/`, `docs/`, root files, `assets/`) is allowed.
- **Infrastructure branches** (`workflow/*`, `infra/*`, `ci/*`, etc.) are blocked from modifying `src/` and `tests/src/`. Everything else (including `.github/`, `Scripts/`, `.githooks/`, `.kiro/`, `.vscode/`, `tests/scripts/`, `docs/`, root files, `assets/`) is allowed.
- **Publish branches** (`publish/*`) are blocked from modifying `.github/`, `.githooks/`, `.kiro/`, `.vscode/`, `Scripts/`, and `tests/`. Everything else is allowed, including `src/`, `docs/`, root files, and `assets/`.

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

### Negative

- Occasionally requires two branches/PRs for tightly coupled changes (e.g., adding a function that also needs a new CI check).
- Contributors must learn the branch naming convention before their first commit.

### Neutral

- The override mechanism means this is a guardrail, not a hard wall. Deliberate exceptions are still possible.
