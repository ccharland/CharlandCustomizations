# ADR-003: Authenticode Signing as Release Gate

## Status

Accepted

## Date

2026-06-11

## Context

PowerShell execution policies on Windows can block unsigned scripts. Additionally, as a public module published to PSGallery, consumers benefit from knowing the code hasn't been tampered with after the author committed it.

Options considered:

1. **Don't sign** — simpler, but limits where the module can run and provides no tamper evidence.
2. **Sign only at publish time** — reduces friction during development, but source and build output differ.
3. **Sign all source and enforce in CI** — highest assurance, but adds friction to every edit.

## Decision

Sign all `.ps1`, `.psm1`, and `.psd1` files in both `Scripts/` and `src/`. `Scripts/` signatures are enforced at PR merge time via the Signature Compliance CI workflow. `src/` signatures are not enforced at merge, but are enforced before publishing — the publish script and tag-based workflow both validate that all files carry valid Authenticode signatures before releasing to PSGallery. Objects in `Scripts/` are used to enforce workflow processes, signing of them is enforced at PR merge time.

Workflow for editing signed files:

1. Strip the signature block.
2. Commit the unsigned version (clean diff).
3. Make changes.
4. Re-sign via `Build-Module.ps1`.

Signatures use a Sectigo timestamp counter-signature so they remain valid after the cert expires.

## Consequences

### Positive

- Module runs under `AllSigned` and `RemoteSigned` execution policies without intervention.
- Tamper detection — any modification after signing invalidates the signature.
- PSGallery consumers can verify publisher identity.
- CI enforces `Scripts/` signature compliance at PR merge time.
- Publishing is fully gated — no unsigned code ships to PSGallery.

### Negative

- Requires a valid code signing certificate (cost + renewal).
- Every source edit requires stripping and re-signing — an extra step.
- CI can't re-sign (cert is local), so `src/` signature compliance is only validated at publish time, not at PR merge. `Scripts/` compliance is validated at merge.
- Git diffs include signature block churn if you forget to commit unsigned first.

### Neutral

- The build script automates most of the re-signing friction.
- `-SkipSigning` flag exists for local development when you don't need valid signatures.
