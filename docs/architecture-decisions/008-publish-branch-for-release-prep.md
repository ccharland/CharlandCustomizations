# ADR-008: Publish Branch for Release Preparation

## Status

Accepted

## Date

2026-07-04

## Context

The release process requires touching multiple areas of the repository in a single workflow:

1. **`src/`** — Bump manifest version, re-sign source files.
2. **`docs/`** — Update CHANGELOG.md.
3. **`Scripts/`** — Potentially update build tooling if the release process evolves.

The existing branch path policy (ADR-002) separates code branches from infrastructure branches. Neither type has full access to all three areas:

- Code branches can't touch `Scripts/`.
- Infrastructure branches can't touch `src/`.

Previously, release prep required either:

- The path policy override (`CC_GIT_HOOK_ALLOW_PATH_POLICY_OVERRIDE=1`) on every commit — error-prone and undiscoverable.
- Splitting release work across two branches and two PRs — unnecessarily complex for a mechanical process.

## Decision

Add a `publish/*` branch type (e.g., `publish/v0.5.0`) that is **restricted to release-prep paths only**. Publish branches can modify `src/` (manifest version, re-signing), `docs/` (changelog), and root files — but are blocked from `.github/`, `.githooks/`, `.kiro/`, `.vscode/`, `Scripts/`, and `tests/`.

This ensures publish branches stay focused on the minimum necessary for a release: adding signatures, updating release notes, and bumping the version.

The intended workflow on a publish branch:

1. Bump version in the manifest (`-BumpVersion Patch` or `-Version X.Y.Z`).
2. Update `docs/CHANGELOG.md` with the release notes.
3. Re-sign all source files (`Build-Module.ps1 -UpdateAllSignatures`).
4. Commit the unsigned versions first (clean diffs), then commit signed versions.
5. Open a PR to `main`.
6. After merge, the `auto-tag-publish.yml` workflow reads the manifest version and creates the `v*.*.*` tag automatically — triggering the publish workflow.

Future automation (not yet implemented):

- Validation that the manifest version matches the branch name (e.g., `publish/v0.5.0` must have `ModuleVersion = '0.5.0'`).

Implemented automation:

- The `auto-tag-publish.yml` workflow detects when a `publish/*` PR merges to `main`, reads the manifest version, and auto-creates the version tag — which triggers the existing publish workflow. No manual `git tag` step required.

## Consequences

### Positive

- Release prep is a single branch and single PR — easy to review as one cohesive change.
- Restricted scope prevents feature creep — only release-necessary changes are allowed.
- No override hacks needed — the policy recognizes publish branches natively.
- Branch naming (`publish/v0.5.0`) makes the intent immediately clear in PR lists.
- Sets the stage for future auto-tagging automation after merge.

### Negative

- Cannot include last-minute code fixes — those must go through a separate code branch first.
- One more branch type for contributors to learn (though only the maintainer typically creates publish branches).

### Neutral

- All existing CI quality gates still apply — Pester tests, PSScriptAnalyzer, help compliance, and manifest compliance must pass before merge.
- Signature compliance on `Scripts/` is still enforced at PR merge time.
- The publish branch doesn't bypass CI checks — it only has a specific path policy scoped to release needs.
