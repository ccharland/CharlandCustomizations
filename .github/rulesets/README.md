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
| `Log-RulesetSnapshot.ps1` | Helper script that logs current ruleset status and optional ruleset detail snapshots. |

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

## Check Ruleset Status via API

Use these commands to confirm which rulesets are active in GitHub (not just in local JSON files).

### List all rulesets and enforcement state

```bash
gh api /repos/ccharland/CharlandCustomizations/rulesets \
  --jq '.[] | {id: .id, name: .name, target: .target, enforcement: .enforcement}'
```

### Check one ruleset by name

```bash
gh api /repos/ccharland/CharlandCustomizations/rulesets \
  --jq '.[] | select(.name == "Require Branch Path Policy") | {id: .id, name: .name, enforcement: .enforcement, target: .target}'
```

### Get full details for a specific ruleset ID

```bash
gh api /repos/ccharland/CharlandCustomizations/rulesets/<RULESET_ID>
```

### PowerShell-friendly check for active/disabled rulesets

```powershell
$rulesets = gh api /repos/ccharland/CharlandCustomizations/rulesets | ConvertFrom-Json
$rulesets | Select-Object id, name, target, enforcement | Format-Table -AutoSize
```

### Quick validation after importing/updating a ruleset

```bash
gh api /repos/ccharland/CharlandCustomizations/rulesets \
  --jq '.[] | select(.name == "Block Malformed Branch Names" or .name == "Require Branch Path Policy") | {name: .name, enforcement: .enforcement}'
```

## Change Logging

Use the commands below to keep a durable local history of ruleset changes in `.github/rulesets/ruleset-activiation-logs.txt`.

### Use the helper script (recommended)

```powershell
# Summary snapshot to the log file
pwsh -NoProfile -ExecutionPolicy Bypass -File ./.github/rulesets/Log-RulesetSnapshot.ps1

# Snapshot + full detail for one ruleset id
pwsh -NoProfile -ExecutionPolicy Bypass -File ./.github/rulesets/Log-RulesetSnapshot.ps1 -RulesetId <RULESET_ID> -Label before-update

# Snapshot + detail + JSON snapshot file under .github/rulesets/snapshots/
pwsh -NoProfile -ExecutionPolicy Bypass -File ./.github/rulesets/Log-RulesetSnapshot.ps1 -RulesetId <RULESET_ID> -Label after-update -WriteSnapshotFile
```

### Append a timestamped status snapshot

```powershell
$logPath = ".github/rulesets/ruleset-activiation-logs.txt"
"`n=== Ruleset status snapshot $(Get-Date -Format o) ===" | Out-File -FilePath $logPath -Append -Encoding utf8
gh api /repos/ccharland/CharlandCustomizations/rulesets `
  --jq '.[] | {id: .id, name: .name, target: .target, enforcement: .enforcement, updated: .updated_at, created: .created_at}' |
  Out-File -FilePath $logPath -Append -Encoding utf8
```

### Capture full before/after JSON for one ruleset

```powershell
$rulesetId = "<RULESET_ID>"
$logPath = ".github/rulesets/ruleset-activiation-logs.txt"

"`n=== BEFORE update $rulesetId $(Get-Date -Format o) ===" | Out-File -FilePath $logPath -Append -Encoding utf8
gh api "/repos/ccharland/CharlandCustomizations/rulesets/$rulesetId" |
  Out-File -FilePath $logPath -Append -Encoding utf8

# Run your create/update/delete command here.

"`n=== AFTER update $rulesetId $(Get-Date -Format o) ===" | Out-File -FilePath $logPath -Append -Encoding utf8
gh api "/repos/ccharland/CharlandCustomizations/rulesets/$rulesetId" |
  Out-File -FilePath $logPath -Append -Encoding utf8
```

### Optional: create one JSON file per snapshot

```powershell
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$outFile = ".github/rulesets/snapshots/rulesets-$stamp.json"
New-Item -ItemType Directory -Path ".github/rulesets/snapshots" -Force | Out-Null
gh api /repos/ccharland/CharlandCustomizations/rulesets | Out-File -FilePath $outFile -Encoding utf8
```

## Notes

- `bypass_actors` is empty, meaning no one (including admins) can bypass these rules. Add actors if a hotfix escape hatch is needed.
- The existing legacy branch protection for `main` is configured separately and is not replaced by these ruleset files.
- GitHub ruleset ref-name conditions use glob patterns, not full semantic-version regular expressions. Workflows must perform strict version validation.
