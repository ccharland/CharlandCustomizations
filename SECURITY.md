# Security Policy

## Supported Versions

| Version          | Supported |
|------------------|-----------|
| Latest release   | Yes       |
| Earlier releases | No        |

Only the latest published version receives security fixes.

## Reporting a Vulnerability

If you discover a security issue in this module, **please do not open a public GitHub issue**.

Instead, report it privately:

1. Use [GitHub's private vulnerability reporting](https://github.com/ccharland/CharlandCustomizations/security/advisories/new) (preferred)
2. Or contact the maintainer through GitHub profile contact details: https://github.com/ccharland

Include:

- A description of the vulnerability
- Steps to reproduce
- Affected versions
- Potential impact

I'll acknowledge receipt within 72 hours and aim to provide a fix or mitigation within 7 days for confirmed issues.

## Scope

This policy covers:

- The `CharlandCustomizations` PowerShell module source code
- Build and deployment scripts in `Scripts/`
- GitHub Actions workflows in `.github/workflows/`
- Any credential handling, signing, or authentication logic

## Security Practices in This Repository

- **No secrets in source** — API keys, credentials, and certificates are never committed. AWS credentials are handled through profiles and environment variables.
- **Code signing** — All release artifacts are Authenticode-signed with a timestamped signature.
- **Dependency pinning** — GitHub Actions are pinned to full commit SHAs to prevent supply-chain attacks.
- **Signature compliance gates** — CI validates that signed scripts haven't been tampered with.
- **Least privilege** — Workflow permissions are scoped to the minimum required (`contents: read` by default).

## Known Sensitive Areas

- `Update-CHARSSOCredentialList` — Handles SSO tokens and optionally writes temporary credentials
- `Set-CHARAWSProfileWithMFA` / `Use-CHARAssumedRole` — Handles STS session credentials
- `Set-CHARAWSEnv` — Writes credentials to environment variables
- `Scripts/Publish-CharlandCustomizations.ps1` — Handles PSGallery API key
- `Scripts/Build-Module.ps1` — Accesses code signing certificate
