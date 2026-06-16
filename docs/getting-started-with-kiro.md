# Getting Started with Kiro

## Prerequisites

- [Kiro IDE](https://kiro.dev) installed

- [uv](https://docs.astral.sh/uv/getting-started/installation/) installed (provides `uvx` for running MCP servers)

  **Important (Windows):** Install `uv` so that `uvx` is on your *system* PATH, not just inside a project `.venv` or a PowerShell-profile-only path. Kiro spawns MCP servers via CMD, which does not inherit per-user profile modifications. Verify with: `cmd /c where uvx` — if that fails, add the `uv` bin directory to your system PATH.

- AWS CLI configured with at least one named profile

## MCP Server Configuration

This workspace includes an MCP server configuration in `.kiro/settings/mcp.json` that provides AWS documentation search and retrieval.

### Included MCP Servers

| Server | Purpose |
|--------|---------|
| `awslabs.aws-documentation-mcp-server` | Search and read AWS documentation inline |

The server version is pinned in the workspace config. To update, change the version in `.kiro/settings/mcp.json`.

## Steering Files

The `.kiro/steering/` directory contains project conventions that Kiro follows automatically:

- **copilot-steering.md** — General development guidance
- **powershell-module-development.md** — Module structure, signing, testing, and AWS parameter patterns
- **Github.md** — Commit message format and PR practices

## Useful Tasks

From the Command Palette (Cmd+Shift+P on macOS, Ctrl+Shift+P on Windows/Linux → `Tasks: Run Task`):

- **Pester: Run Unit Tests** — Runs the full test suite
- **Remove Authenticode Signature Block** — Strips the signature from the active PowerShell file (useful before editing signed scripts)
