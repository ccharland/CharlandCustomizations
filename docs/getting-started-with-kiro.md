# Getting Started with Kiro

## Prerequisites

- [Kiro IDE](https://kiro.dev) installed
- [uv](https://docs.astral.sh/uv/getting-started/installation/) 
installed (provides `uvx` for running MCP servers)
- AWS CLI configured with at least one named profile

## MCP Server Configuration

This workspace includes MCP server configurations in `.kiro/settings/mcp.json` that provide AWS documentation lookup, CloudFormation linting, and cost analysis capabilities.

### AWS Profile Setup

The cost-analysis MCP server references `${AWS_PROFILE}` from your shell environment. Kiro passes this environment variable to the MCP server process at startup.

Set your AWS profile in your shell before launching Kiro:

```bash
# Add to ~/.zshrc or ~/.bashrc
export AWS_PROFILE=YourProfileName
```

If `AWS_PROFILE` is not set, the MCP server will fall back to the default profile in `~/.aws/config`.

### Included MCP Servers

| Server | Purpose |
|--------|---------|
| `awslabs.aws-documentation-mcp-server` | Search and read AWS documentation inline |
| `awslabs.cfn-lint-mcp-server` | Validate CloudFormation templates |
| `awslabs.cost-analysis-mcp-server` | Query AWS cost and usage data |

## Steering Files

The `.kiro/steering/` directory contains project conventions that Kiro follows automatically:

- **copilot-steering.md** — General development guidance
- **powershell-module-development.md** — Module structure, signing, testing, and AWS parameter patterns
- **Github.md** — Commit message format and PR practices

## Useful Tasks

From the Command Palette (Cmd+Shift+P → `Tasks: Run Task`):

- **Pester: Run Unit Tests** — Runs the full test suite
- **Remove Authenticode Signature Block** — Strips the signature from the active PowerShell file (useful before editing signed scripts)
