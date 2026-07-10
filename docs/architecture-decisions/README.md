# Architecture Decision Records

This directory contains Architecture Decision Records (ADRs) for the CharlandCustomizations module.

## What is an ADR?

An ADR captures a significant design or architectural choice along with its context and consequences. They help future-you (and contributors) understand *why* something was done a certain way.

## Format

Each ADR follows a lightweight template:

- **Status** — Proposed, Accepted, Deprecated, Superseded
- **Context** — What prompted the decision
- **Decision** — What we chose to do
- **Consequences** — What follows from the decision (good and bad)

## Index

| ADR | Title | Status | Date |
|-----|-------|--------|------|
| [001](001-char-prefix-convention.md) | CHAR prefix convention for exported functions | Accepted | 2026-06-05 |
| [002](002-branch-path-separation-policy.md) | Branch path separation policy | Accepted | 2026-06-11 |
| [003](003-authenticode-signing-workflow.md) | Authenticode signing as release gate | Accepted | 2026-06-11 |
| [004](004-sso-config-over-credentials.md) | SSO config profiles over temporary credentials | Accepted | 2026-07-04 |
| [005](005-aws-common-parameter-splatting.md) | AWS common parameter splatting pattern | Accepted | 2026-06-12 |
| [006](006-enforce-quality-gates-early.md) | Enforce quality gates early, even for a small project | Accepted | 2026-07-04 |
| [007](007-intentional-ai-assisted-development.md) | Intentional AI-assisted development | Accepted | 2026-07-04 |

## Creating a New ADR

1. Copy `000-template.md` to a new file with the next number and a descriptive slug.
2. Fill in the sections.
3. Add an entry to the index table above.
4. Commit on the appropriate branch type.
