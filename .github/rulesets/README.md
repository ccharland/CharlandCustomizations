# GitHub Repository Rulesets

This directory contains reference copies of the GitHub repository rulesets configured for this project. These files are **not** enforced from the repository — rulesets are applied via the GitHub UI (Settings → Rules → Rulesets) or the GitHub API.

## Purpose

These files serve as documentation so the team can review, version-track, and restore ruleset configurations without needing to inspect the GitHub UI directly.

## Files

| File | Description |
|------|-------------|
| `protect-deployment-tags.json` | Protects version tags (`v*.*.*`) used to trigger module publishing. Requires GPG-signed tags, prevents force-pushes, and enforces that all PR quality gate checks have passed before a release tag is accepted. |

## Applying Changes

To update the live ruleset from this file:

```bash
# Update an existing ruleset via the GitHub API
gh api --method PUT /repos/ccharland/CharlandCustomizations/rulesets/17577728 \
  --input .github/rulesets/protect-deployment-tags.json
```

To import a new ruleset:

```bash
gh api --method POST /repos/ccharland/CharlandCustomizations/rulesets \
  --input .github/rulesets/protect-deployment-tags.json
```

## Notes

- The `enforcement` field is set to `"disabled"` for testing. Change to `"active"` when ready to enforce.
- `bypass_actors` is empty, meaning no one (including admins) can bypass these rules. Add actors if a hotfix escape hatch is needed.
