# ADR-006: Enforce Quality Gates Early, Even for a Small Project

## Status

Accepted

## Date

2026-07-09

## Context

This module is primarily one person's work. The test suite, CI gates, signature compliance, help validation, manifest checks, and source layout enforcement might seem excessive for a project of this size.

The temptation is to skip the ceremony and "just ship it" — add gates later when the project is bigger or has more contributors.

But habits formed early are habits that stick. Retrofitting quality checks onto a mature codebase is painful. Adding a test after the fact means reverse-engineering intent. Adding help documentation months later means re-learning what a function does. Enforcing a manifest gate after 50 functions are exported means fixing 50 entries in one shot.

## Decision

Invest in quality gates from the start, even when the project is small enough that they feel like overkill:

- **1:1 source-to-test mapping** enforced by `SourceLayout.Tests.ps1` — every source file must have a corresponding test file.
- **Comment-based help validation** in CI — every public function must have discoverable help before merge.
- **Manifest compliance gate** — export lists must be sorted, one-per-line, and match the actual public surface.
- **PSScriptAnalyzer errors block the PR** — no exceptions for "it's just a quick fix."
- **Authenticode signing on `Scripts/`** — even though it's extra friction, it proves the release pipeline works.
- **Branch path policy** — prevents lazy mixed-scope commits even when you're the only contributor.

The goal is to make quality the path of least resistance, so it's never a conscious effort to "do it right."

## Consequences

### Positive

- Every function ships with tests and help from day one — no backlog of "add tests later."
- Build and release process is proven and reliable before the module grows.
- New contributors (or AI assistants) get immediate feedback when something doesn't meet standards.
- Muscle memory builds — the workflow becomes automatic rather than aspirational.
- The module can serve as a reference implementation for how to maintain a PowerShell project.

### Negative

- Slower to ship individual changes — more steps per commit/PR.
- Some gates feel ceremonial for trivial one-line fixes.
- Requires maintaining the gates themselves (CI workflows, test scripts, compliance checks).

### Neutral

- These are all standard practices. The only unusual thing is applying them consistently to a personal project from the start.
- The overhead decreases as the workflow becomes habit.
- We all have to start somewhere.
