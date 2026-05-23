---
description: PowerShell module development practices, testing, code quality, and PSScriptAnalyzer guidelines
inclusion: auto
---

# PowerShell Module Development Guidelines

## Module Structure

This repository uses dot-sourced `.ps1` files (one function per file):

```
src/CharlandCustomizations/
├── CharlandCustomizations.psd1    # Module manifest
├── CharlandCustomizations.psm1    # Loader (dot-sources Public/ and Private/)
├── Private/                       # Internal helper functions (.ps1)
└── Public/                        # Exported functions (.ps1)
```

The `.psm1` loader automatically dot-sources all `.ps1` files in `Public/` and `Private/`, then exports public functions by file basename.

## Code Standards

Scripts will be analyzed using PSScriptAnalyzer.

- Avoid Write-Host, use Write-Output
- Avoid trailing whitespace on lines
- One function per `.ps1` file in `Public/` or `Private/`
- File name must match the function name (e.g., `Get-Something.ps1` contains `function Get-Something`)

## Version Management

- Version is managed in the `.psd1` manifest file only
- Use semantic versioning (MAJOR.MINOR.PATCH)
- Update version when making changes to the module

## Adding New Functions

### Public Functions (Exported)

1. Create a new `.ps1` file in `src/CharlandCustomizations/Public/`
2. Name the file after the function: `Verb-Noun.ps1`
3. Include proper comment-based help
4. Functions are auto-exported by the `.psm1` loader

### Private Functions (Internal)

1. Create a new `.ps1` file in `src/CharlandCustomizations/Private/`
2. These are not exported but available to public functions

## AWS Cmdlet Parameter Splatting

All scripts that invoke AWS cmdlets **must** accept optional `-Region` and `-ProfileName` parameters and pass them via splatting. This keeps AWS credential/region handling consistent and allows callers to override the session defaults.

### Pattern

```powershell
[CmdletBinding()]
param(
    [Parameter()]
    [string]$Region,

    [Parameter()]
    [string]$ProfileName

    # ... other parameters
)

begin {
    # Build splat hash for AWS cmdlet calls
    $awsParams = @{}
    if ($Region) {
        $awsParams['Region'] = $Region
    }
    if ($ProfileName) {
        $awsParams['ProfileName'] = $ProfileName
    }
}

process {
    # Splat into every AWS cmdlet call
    $results = Get-EC2Instance @awsParams
    $stacks = Get-CFNStack @awsParams
}
```

### Rules

- Name the splat hashtable `$awsParams`
- Build it once in the `begin` block
- Only add keys when the parameter is provided (do not add empty-string keys)
- Splat `@awsParams` into every AWS cmdlet call in the script
- This applies to all module functions

## Code Quality

### PSScriptAnalyzer

Use PSScriptAnalyzer to validate code quality:

```powershell
# Install if needed
Install-Module -Name PSScriptAnalyzer -Scope CurrentUser

# Analyze entire module
Invoke-ScriptAnalyzer -Path ./src/CharlandCustomizations/ -Recurse

# Analyze with specific severity
Invoke-ScriptAnalyzer -Path ./src/CharlandCustomizations/ -Recurse -Severity Error,Warning
```

### Common Rules to Follow

**ShouldProcess Support**
Functions that modify system state should support `-WhatIf` and `-Confirm`:

```powershell
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param()

if ($PSCmdlet.ShouldProcess($target, $action)) {
    # Make changes here
}
```

Examples of functions that should support ShouldProcess:

- Functions that modify files
- Functions that change environment variables
- Functions that delete resources
- Functions that modify configuration

**Suppressing Warnings**

Use `SuppressMessageAttribute` when you have a valid reason:

```powershell
function Show-Progress {
    [CmdletBinding()]
    # Suppress: Write-Host needed for real-time user feedback
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Real-time progress display required')]
    param([string]$Message)

    Write-Host $Message -ForegroundColor Cyan
}
```

**Always document why you're suppressing a warning!**

Common suppressions:

- `PSAvoidUsingWriteHost` - When you need direct console output
- `PSAvoidUsingCmdletAliases` - In interactive scripts (but avoid in modules)
- `PSUseDeclaredVarsMoreThanAssignments` - For variables used in different scopes

**Parameter Validation**

```powershell
[Parameter(Mandatory)]
[ValidateNotNullOrEmpty()]
[string]$Name

[Parameter()]
[ValidateSet('Low', 'Medium', 'High')]
[string]$Priority = 'Medium'

[Parameter()]
[ValidateScript({ Test-Path $_ })]
[string]$Path
```

**Error Handling**

```powershell
try {
    # Risky operation
}
catch {
    Write-Error "Operation failed: $_"
    throw
}
```

**Output Types**

```powershell
[OutputType([PSCustomObject])]
param()

return [PSCustomObject]@{
    Property1 = $value1
    Property2 = $value2
}
```

### Pre-Commit Validation

```powershell
# Before committing
$results = Invoke-ScriptAnalyzer -Path ./src/CharlandCustomizations/ -Recurse -Severity Error
if ($results) {
    Write-Error "PSScriptAnalyzer found errors:"
    $results | Format-Table
    exit 1
}
```

## Testing

### Pester Tests

This project uses [Pester](https://pester.dev/) (v5+) for unit testing. Tests live in the `tests/` directory.

#### Test File Location and Naming

- All test files go in `tests/` at the repository root
- Name test files `<FunctionName>.Tests.ps1`

#### Running Tests

```powershell
# Run all tests
Invoke-Pester -Path ./tests/ -Output Detailed

# Run a specific test file
Invoke-Pester -Path ./tests/Get-Something.Tests.ps1 -Output Detailed

# Run with code coverage
Invoke-Pester -Path ./tests/ -Output Detailed -CodeCoverage ./src/CharlandCustomizations/**/*.ps1
```

#### Test Structure

Tests use Pester v5 syntax with `BeforeAll`, `Describe`, and `It` blocks:

```powershell
#Requires -Modules Pester

BeforeAll {
    . "$PSScriptRoot/../src/CharlandCustomizations/Public/Get-Something.ps1"
}

Describe 'Get-Something' {
    It 'Returns expected output' {
        $result = Get-Something -Name 'Test'
        $result | Should -Not -BeNullOrEmpty
    }
}
```

#### Mocking AWS Commands

Since tests run without AWS credentials, mock all AWS cmdlets:

```powershell
Mock Get-STSCallerIdentity {
    [PSCustomObject]@{ Account = '111111111111'; Arn = 'arn:aws:iam::111111111111:user/test' }
}

Mock Get-EC2SecurityGroup { return @($mockSecurityGroup) }
```

#### Test Guidelines

- Mock all external dependencies (AWS cmdlets, network calls, file system when appropriate)
- Test both success and failure paths
- Test pipeline behavior (pipeline input, streaming output)
- Test parameter validation (allowed values, mandatory params)
- Use `@()` to wrap results when testing `.Count` to handle single-item vs array differences
- Use `3>&1` to capture warning stream when testing warning output
- Keep tests independent — no test should depend on another test's state

#### When to Write Tests

- New public functions added to the module should have tests
- Bug fixes should include a regression test
- Tests are not required for trivial one-liner helpers or interactive-only functions

### Quick Test (Source)

```powershell
# Remove old version if loaded
Remove-Module CharlandCustomizations -ErrorAction SilentlyContinue

# Import from source location
Import-Module ./src/CharlandCustomizations/CharlandCustomizations.psd1 -Force

# Test your functions
Get-Command -Module CharlandCustomizations
```

## Publishing Updates

1. Update version in `.psd1`
2. Run PSScriptAnalyzer
3. Run Pester tests
4. Test import and functionality
5. Commit and tag the release
