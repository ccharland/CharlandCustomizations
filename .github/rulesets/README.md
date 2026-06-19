# GitHub Repository Rulesets

This directory contains reference copies of the GitHub repository rulesets configured for this project. These files are **not** enforced from the repository — rulesets are applied via the GitHub UI (Settings → Rules → Rulesets) or the GitHub API.

## Purpose

These files serve as documentation so the team can review, version-track, and restore ruleset configurations without needing to inspect the GitHub UI directly.

## Files

| File | Description |
|------|-------------|
| `Branch-Name-Ruleset.json` | Blocks branch creation unless the name uses one of the approved prefixes. |
| `Block-Malformed-Tags.json` | Blocks tag creation outside the version, start, and feature tag namespaces. |
| `Feature-Tag-Rules.json` | Makes `feature/*` tags immutable after creation. |
| `protect-deployment-tags.json` | Protects version tags (`v*.*.*`) used to trigger module publishing. Requires GPG-signed tags, prevents force-pushes, and enforces that all PR quality gate checks have passed before a release tag is accepted. |
| `Start-tag-rule.json` | Requires signed, immutable `start/v*.*.*` tags. |
| `require-branch-path-policy.json` | Requires pull requests into `main` to pass the Branch Path Policy status check before merge. The workflow blocks mixed code/infrastructure branch scopes. |

## Reimporting Rulesets

Delete the existing repository rulesets in GitHub, then import the active definitions:

```bash
for ruleset in \
  .github/rulesets/Branch-Name-Ruleset.json \
  .github/rulesets/Block-Malformed-Tags.json \
  .github/rulesets/Feature-Tag-Rules.json \
  .github/rulesets/protect-deployment-tags.json \
  .github/rulesets/Start-tag-rule.json
do
  gh api --method POST /repos/ccharland/CharlandCustomizations/rulesets \
    --input "$ruleset"
done
```

The branch path policy is intentionally disabled while it is being tested. Import it separately when desired:

```bash
gh api --method POST /repos/ccharland/CharlandCustomizations/rulesets \
  --input .github/rulesets/require-branch-path-policy.json
```

## Notes

- `require-branch-path-policy.json` is set to `"disabled"`. Change it to `"active"` only after its workflow has run successfully on `main`.
- `bypass_actors` is empty, meaning no one (including admins) can bypass these rules. Add actors if a hotfix escape hatch is needed.
- The existing legacy branch protection for `main` is configured separately and is not replaced by these ruleset files.
- GitHub ruleset ref-name conditions use glob patterns, not full semantic-version regular expressions. Workflows must perform strict version validation.
