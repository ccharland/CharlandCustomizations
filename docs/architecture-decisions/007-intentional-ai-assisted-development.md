# ADR-007: Intentional AI-Assisted Development

## Status

Accepted

## Date

2026-07-09

## Context

AI coding tools (Kiro, GitHub Copilot, Codex, ChatGPT) are increasingly capable of generating code, tests, documentation, and infrastructure. The question isn't whether to use them — it's how to use them intentionally rather than accidentally.

Without guardrails, AI-generated code can:

- Introduce inconsistent patterns across the codebase.
- Touch infrastructure or signing scripts it shouldn't be modifying.
- Generate plausible-looking code that doesn't match the module's conventions.
- Skip testing, help, or manifest updates that humans would also skip under time pressure.

## Decision

Use AI tools deliberately as a primary development accelerator, with the human as reviewer, architect, and decision-maker. Treat AI as a highly productive collaborator that needs the same guardrails as any contributor. My view of AI tools is that they have the skill of an `Intern fueled by Red Bull.` Steering and guidance guidelines will be changed often, and as needed to improve the quality.

### How AI is used in this project

- **Code generation** — AI writes the bulk of implementation code, tests, and documentation. The human reviews, edits, and directs.
- **Spec-driven development** — Kiro specs define requirements and design before implementation starts, giving AI structured context.
- **Documentation** — AI generates and maintains comment-based help, ADRs, and contributor docs. Human validates accuracy.
- **Refactoring** — AI handles mechanical changes (renames, pattern application) across many files consistently.
- **Learning** — AI explains PowerShell patterns, AWS conventions, and module development practices as questions arise.
- **Code Review** - Multiple Agents review each PR, because this is mostly a solo project, and I can miss changes.

### Guardrails that keep AI in bounds

- **Branch path policy** — AI-assisted branches (`kiro-code/*`, `copilot-code/*`, etc.) follow the same path restrictions as human branches. An AI can't accidentally modify CI workflows on a code branch.
- **Quality gates in CI** — AI-generated code passes the same Pester, PSScriptAnalyzer, help, and manifest checks as human code. No free passes.
- **Attribution** — AI-generated code includes Kiro attribution comments so it's clear what was machine-generated.
- **Steering files** — `.kiro/steering/` provides persistent context so AI tools follow module conventions without being told every time.
- **Code signing** — AI can't sign code. The human must sign, which creates a deliberate review checkpoint.
- **Human-owned decisions** — Architecture decisions (like these ADRs) are authored and approved by the human, even if AI drafts them.

### Tools used

| Tool | Primary Use |
|------|-------------|
| Kiro | Implementation, specs, steering-driven development |
| GitHub Copilot | Inline completions, quick edits |
| Codex | Batch code generation, exploration |
| ChatGPT | General guidance, image generation, research |

## Consequences

### Positive

- Dramatically faster development — AI handles the volume work, human handles the judgment work.
- Consistent style — AI follows steering rules more reliably than memory alone.
- Better documentation — AI doesn't get tired of writing help text and examples.
- Lower barrier to maintaining quality gates — AI generates the tests and help that gates require.
- Learning accelerator — exploring new patterns is cheap when AI can generate working examples quickly.

### Negative

- Over-reliance risk — human must still understand what the code does, not just approve it.
- Attribution noise — Kiro comments add lines to every file.
- Tooling dependency — steering files and MCP configs must be maintained as tools evolve.
- Review fatigue — large AI-generated PRs require discipline to review thoroughly.

### Neutral

- AI-generated code isn't inherently better or worse than human code — it just needs the same quality checks.
- The approach scales: more AI involvement is fine as long as gates hold.
- This is a learning project. Part of the learning is discovering how to work effectively with AI tools.
