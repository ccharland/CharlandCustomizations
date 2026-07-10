# ADR-005: AWS Common Parameter Splatting Pattern

## Status

Accepted

## Date

2026-06-12

## Context

AWS PowerShell cmdlets accept a standard set of credential and region parameters (`Region`, `ProfileName`, `AccessKey`, `SecretKey`, `SessionToken`, `Credential`, `ProfileLocation`, `EndpointUrl`). When writing wrapper functions, these need to be forwarded to every AWS cmdlet call.

Without a pattern, each function would either:

- Manually splat each parameter (verbose, error-prone, inconsistent).
- Omit some parameters (limiting flexibility for callers).
- Use `$PSBoundParameters` directly (includes non-AWS parameters, breaks downstream cmdlets).

## Decision

Use a shared private helper (`New-AWSParamSplat`) that:

1. Accepts `$PSBoundParameters` from the calling function.
2. Filters to only the recognized AWS common parameter names.
3. Excludes null/empty values.
4. Returns an ordered hashtable suitable for splatting.

Every AWS-facing public function declares the full common parameter set and calls `New-AWSParamSplat` in its `begin` block.

## Consequences

### Positive

- Consistent caller experience — every AWS function accepts the same credential/region parameters.
- Single point of maintenance — adding a new AWS common parameter only requires updating the helper.
- Clean splatting — downstream cmdlets never receive unexpected parameters.
- Predictable parameter order in the returned hashtable.

### Negative

- Every AWS function has ~8 boilerplate parameters in its `param()` block.
- The helper is a coupling point — a bug there affects all AWS functions.
- New contributors need to learn the pattern (documented in `docs/NEW-FEATURE-PARAMETERS.md`).

### Neutral

- Functions that don't call AWS cmdlets don't use this pattern.
- The helper lives in `Private/` and is dot-sourced by nested modules that need it.
