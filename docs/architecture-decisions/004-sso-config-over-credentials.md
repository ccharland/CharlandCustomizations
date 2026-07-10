# ADR-004: SSO Config Profiles Over Temporary Credentials

## Status

Accepted

## Date

2026-07-04

## Context

`Update-CHARSSOCredentialList` originally retrieved short-lived STS credentials (access key, secret key, session token) for every SSO role and wrote them to `~/.aws/credentials`. This had several issues:

- Credentials expire in 1–12 hours, requiring frequent re-runs.
- The credentials file grows large with many accounts/roles.
- Tools like `aws sso login` don't recognize these entries — they expect SSO-style config profiles.
- Storing temporary credentials on disk is a larger security surface than necessary.

## Decision

By default, write SSO-style profiles to `~/.aws/config` containing `sso_session`, `sso_account_id`, `sso_role_name`, and `region`. Do NOT persist temporary credentials unless explicitly requested via `-SaveCredentials`.

This aligns with the AWS CLI's native `aws configure sso` output format, so tools like `aws sso login` work seamlessly with the generated profiles.

## Consequences

### Positive

- Generated profiles work with `aws sso login` and SDK token provider chains — no re-running the function every hour.
- Smaller security surface — no access keys sitting in a file by default.
- Config file is human-readable and matches what AWS documentation shows.
- `-SaveCredentials` opt-in preserves the old behavior for scripts that need explicit keys.

### Negative

- Tools that only understand `aws_access_key_id` / `aws_secret_access_key` entries won't work without `-SaveCredentials`.
- Requires `aws sso login --profile <name>` (or SDK automatic browser flow) before the profile can be used for API calls.

### Neutral

- Profile naming changed to `<RoleName>-<AccountId>` format for clarity.
- `-SSOSessionName` parameter gives control over the shared session block name.
