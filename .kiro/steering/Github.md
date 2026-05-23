---
description: Git commit reminders, commit message format, and GitHub best practices for PowerShell projects
inclusion: auto
---

# GitHub Best Practices

## Commit Reminders

**IMPORTANT**: After completing major activities, ALWAYS:
1. Provide the exact git commands to run
2. Suggest a clear commit message
3. Ask the user to confirm they completed the commit before proceeding

Remind the user to commit changes after:
- Completing Requirements phase
- Completing Design phase
- Completing Tasks phase (spec creation complete)
- Completing each major task or checkpoint during implementation
- Before starting a new feature or project
- After fixing a critical bug
- After completing a CloudFormation template
- After completing a Lambda function
- After major repository restructuring
- After updating module versions

**Confirmation Required**: Wait for user confirmation that the commit was completed before moving to the next phase or task. This helps maintain clean git history and prevents lost work.

## Commit Message Format

Use clear, descriptive commit messages:
- Start with a verb: "Add", "Update", "Fix", "Remove", "Refactor", "Release"
- Be specific about what changed
- Examples:
  - `Add CloudWatch alarm management Lambda function`
  - `Update API Gateway resource policy for organization access`
  - `Fix authorization logic for tag-based filtering`
  - `Complete requirements for cross-account alarm management`
  - `Restructure repository for better module organization`
  - `Release v0.3.0 - Add build system and WIP tracking`

## Commit Signing (Required)

**All commits must be signed with GPG or SSH.**

Git supports two signing methods:
- GPG (GNU Privacy Guard) - Traditional cryptographic signing
- SSH - Uses your existing SSH keys (simpler, available in Git 2.34+)

### Option 1: SSH Signing (Recommended for simplicity)

```bash
# Configure git to use SSH signing
git config --global gpg.format ssh
git config --global commit.gpgsign true
git config --global user.signingkey ~/.ssh/id_ed25519.pub

# Configure allowed signers for verification
git config --global gpg.ssh.allowedSignersFile ~/.ssh/allowed_signers

# Add your public key to allowed signers
echo "$(git config user.email) $(cat ~/.ssh/id_ed25519.pub)" >> ~/.ssh/allowed_signers
```

### Option 2: GPG Signing (Traditional method)

```bash
# Configure git to sign commits
git config --global commit.gpgsign true
git config --global user.signingkey <YOUR_GPG_KEY_ID>

# For Windows with GPG4Win
git config --global gpg.program "C:/Program Files (x86)/GnuPG/bin/gpg.exe"
```

### Verify Signing is Enabled

```powershell
# Check if signing is configured
git config --get commit.gpgsign
# Should return: true

# Check your signing key
git config --get user.signingkey
# Should return your key (GPG key ID or SSH public key)

# Check signing format (if using SSH)
git config --get gpg.format
# Should return: ssh (or empty for GPG)
```

### Validate Commits

Use the validation script or module function to check commits are signed:

```powershell
# Using the module function (after importing module)
Test-CommitSignatures

# Check last 10 commits
Test-CommitSignatures -Count 10

# Check specific range
Test-CommitSignatures -Range "HEAD~5..HEAD"
```

### Pre-Commit Hook

The repository includes a pre-commit hook that validates signing is enabled.
If you try to commit without signing configured, the commit will be rejected.

### Troubleshooting

**SSH Signing Issues**

"error: gpg.ssh.allowedSignersFile needs to be configured"
```bash
# Configure allowed signers file
git config --global gpg.ssh.allowedSignersFile ~/.ssh/allowed_signers

# Add your public key
echo "$(git config user.email) $(cat ~/.ssh/id_ed25519.pub)" >> ~/.ssh/allowed_signers
```

**GPG Signing Issues**

"gpg failed to sign the data"
```bash
# Test GPG
echo "test" | gpg --clearsign

# If fails, restart gpg-agent
gpgconf --kill gpg-agent
gpgconf --launch gpg-agent
```

"No secret key"
```bash
# List your keys
gpg --list-secret-keys --keyid-format LONG

# Set the key in git
git config --global user.signingkey <KEY_ID>
```

**Commits not showing as verified on GitHub**

For GPG:
- Upload your public GPG key to GitHub
- Settings → SSH and GPG keys → New GPG key
- Paste your public key: `gpg --armor --export <KEY_ID>`

For SSH:
- Upload your SSH public key to GitHub as a signing key
- Settings → SSH and GPG keys → New SSH key
- Select "Signing Key" as the key type
- Paste your public key: `cat ~/.ssh/id_ed25519.pub`

## Branch Strategy (for small projects)

- **main**: Production-ready code
- **dev** (optional): Integration branch for testing
- Feature branches: Use descriptive names like `feature/alarm-management` or `fix/iam-permissions`
- Keep branches short-lived (merge within days, not weeks)

## What to Commit

**Always commit:**
- PowerShell modules and scripts
- Test files
- Documentation (README, deployment guides)
- Requirements and design documents
- Configuration files
- Build scripts
- Steering files

**Never commit:**
- AWS credentials or secrets
- `.env` files with sensitive data
- Build artifacts (`build/` directory)
- Large binary files
- IDE-specific files (add to .gitignore)
- Temporary test outputs
- Signed packages (unless intentionally distributing)

## Commit Frequency

For PowerShell module projects:
- Commit after completing each major function
- Commit after restructuring
- Commit after tests pass
- Commit before making risky changes (easy rollback)
- Commit after updating documentation
- Don't wait until "everything is perfect"

## .gitignore Essentials

Ensure your .gitignore includes:
```
# PowerShell
*.ps1xml

# Build artifacts
build/
*.zip
*.sha256

# Temporary files
**/temp.ps1
*.tmp

# IDE
.vscode/settings.json
.idea/
*.swp

# OS
.DS_Store
Thumbs.db

# Credentials
*.credentials
**/secrets/
.env
```

## README Requirements

Each project directory should have a README with:
- Project purpose (1-2 sentences)
- Prerequisites (PowerShell version, required modules)
- Installation instructions
- Usage examples
- Key features
- Documentation links

## Tags for Releases

Use tags for module versions:
- `v0.1.0` - Initial public release
- `v0.1.1` - Bug fix release
- `v0.2.0` - New feature added
- Tag after successful build and testing
- Tag matches version in module manifest

## PowerShell Module Specific

### Version Management
- Update version in `.psd1` manifest only
- Update `CHANGELOG.md` with changes
- Tag release after building and testing

### Documentation Updates
- Update README for new features
- Update steering files for new patterns
- Keep examples current

### Release Workflow
```powershell
# 1. Update version in manifest
# 2. Update CHANGELOG.md
# 3. Commit changes (will be signed automatically)
git add .
git commit -m "Release v0.1.0 - Initial public release"

# 4. Run tests
Invoke-Pester -Path ./tests/ -Output Detailed

# 5. Test functionality
Import-Module ./src/CharlandCustomizations/CharlandCustomizations.psd1 -Force
Get-Command -Module CharlandCustomizations

# 6. Tag release (signed)
git tag -s v0.1.0 -m "Release v0.1.0"

# 7. Push with tags
git push origin main --tags
```

## Git Hooks

The repository includes git hooks to enforce commit signing:

### Setup Hooks

```powershell
# Install hooks
Install-GitHooks
```

This installs a pre-commit hook that:
- Checks commit signing is enabled
- Verifies signing key is configured
- For SSH signing: warns if `gpg.ssh.allowedSignersFile` is not configured
- Prevents commits if signing is not set up

### Hook Templates

Hook templates are stored in `.githooks/` directory:
- `.githooks/pre-commit` - Validates commit signing configuration
- `.githooks/README.md` - Hook documentation

The setup script copies these to `.git/hooks/` and makes them executable.

### Manual Hook Installation

If the setup script doesn't work, manually copy:
```powershell
# macOS/Linux
cp .githooks/pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```
