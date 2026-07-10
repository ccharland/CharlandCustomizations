# ADR-001: CHAR Prefix Convention for Exported Functions

## Status

Accepted

## Date

2026-06-05

## Context

PowerShell modules can apply a command prefix automatically via `DefaultCommandPrefix` in the module manifest. However, this causes confusion:

- Function names in source don't match what users type at the command line.
- Importing with `-Prefix` stacks on top, producing double-prefixed names.
- IDE tooling and `Get-Command` results don't obviously connect back to source.

The module was originally using `CC` as a prefix (set via `DefaultCommandPrefix`), then switched to hardcoding `CC` directly into function names. A subsequent rename changed `CC` to `CHAR` for better uniqueness and clarity.

## Decision

Hardcode the `CHAR` prefix directly into every public function name (e.g., `Find-CHARCFNStackError`, `Set-CHARAWSEnv`). Do not use `DefaultCommandPrefix` in the manifest.

## Consequences

### Positive

- Function names in source code match exactly what users type — no surprise transformations.
- Grep, `Get-Command`, and IDE navigation all work predictably.
- No risk of double-prefixing when someone uses `Import-Module -Prefix`.
- Clear namespace ownership — `CHAR` identifies this module's commands unambiguously.

### Negative

- Renaming the prefix requires touching every function, test, and doc (as proven by the CC → CHAR migration).
- Function names are longer than they'd be with an implicit prefix.

### Neutral

- Private/internal functions don't use the prefix since they're never exported.
