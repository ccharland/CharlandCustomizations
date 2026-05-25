# Code Quality

## PSScriptAnalyzer

PSScriptAnalyzer is a static code checker for PowerShell that helps identify common issues and enforce best practices.

## Installation

```powershell
Install-Module -Name PSScriptAnalyzer -Scope CurrentUser
```

## Running Analysis

### Quick Check

```powershell
# Run the test script
./Scripts/Test-CodeQuality.ps1
```

### Manual Analysis

```powershell
# Analyze entire module
Invoke-ScriptAnalyzer -Path ./src/CharlandCustomizations/ -Recurse

# Only show errors
Invoke-ScriptAnalyzer -Path ./src/CharlandCustomizations/ -Recurse -Severity Error

# Analyze specific file
Invoke-ScriptAnalyzer -Path ./src/CharlandCustomizations/Public/AWS/AWSCustomizations.psm1
```

### Auto-Fix Issues

```powershell
# Automatically fix issues where possible
./Scripts/Test-CodeQuality.ps1 -Fix
```

## Integration with Build

The build script automatically runs PSScriptAnalyzer:

```powershell
./Scripts/Build-Module.ps1
```

- Errors will fail the build
- Warnings are displayed but don't fail the build
- If PSScriptAnalyzer isn't installed, analysis is skipped

## Common Rules

### ShouldProcess Support

Functions that modify system state should support `-WhatIf` and `-Confirm`:

```powershell
function Set-Something {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )
    
    if ($PSCmdlet.ShouldProcess($Name, "Set something")) {
        # Make changes here
    }
}
```

**When to use:**
- Modifying files
- Changing environment variables
- Deleting resources
- Modifying configuration
- Any destructive operation

**ConfirmImpact levels:**
- `Low` - Minor changes, rarely needs confirmation
- `Medium` - Moderate changes, may need confirmation
- `High` - Significant changes, should prompt for confirmation

### Parameter Validation

```powershell
# Required parameter
[Parameter(Mandatory)]
[ValidateNotNullOrEmpty()]
[string]$Name

# Validate from set
[Parameter()]
[ValidateSet('Low', 'Medium', 'High')]
[string]$Priority = 'Medium'

# Validate path exists
[Parameter()]
[ValidateScript({ Test-Path $_ })]
[string]$Path

# Validate range
[Parameter()]
[ValidateRange(1, 100)]
[int]$Percentage
```

### Error Handling

```powershell
try {
    # Risky operation
    $result = Get-Something -ErrorAction Stop
}
catch {
    Write-Error "Operation failed: $_"
    throw
}
```

### Output Types

```powershell
function Get-MyData {
    [OutputType([PSCustomObject])]
    param()
    
    return [PSCustomObject]@{
        Name = "Value"
        Count = 42
    }
}
```

### Cmdlet Naming

Follow PowerShell verb-noun naming:

```powershell
# Good
Get-AWSRole
Set-AWSEnv
Remove-ExpiredProfile

# Bad
FetchRole
ConfigureAWS
DeleteOldProfiles
```

Approved verbs: `Get-Verb`

### Comment-Based Help

```powershell
function Get-Something {
    <#
    .SYNOPSIS
        Brief description
        
    .DESCRIPTION
        Detailed description
        
    .PARAMETER Name
        Description of Name parameter
        
    .EXAMPLE
        PS> Get-Something -Name "Test"
        Description of example
        
    .NOTES
        Additional information
    #>
    param([string]$Name)
}
```

## Common Issues and Fixes

### PSAvoidUsingWriteHost

**Issue**: `Write-Host` doesn't support output redirection

**Fix**: Use `Write-Output`, `Write-Verbose`, or `Write-Information`

```powershell
# Bad
Write-Host "Processing..."

# Good
Write-Verbose "Processing..."
Write-Information "Processing..." -InformationAction Continue
```

### PSUseShouldProcessForStateChangingFunctions

**Issue**: Function modifies state but doesn't support `-WhatIf`

**Fix**: Add `SupportsShouldProcess`

```powershell
[CmdletBinding(SupportsShouldProcess)]
param()

if ($PSCmdlet.ShouldProcess($target, $action)) {
    # Make changes
}
```

### PSAvoidUsingCmdletAliases

**Issue**: Using aliases in scripts reduces readability

**Fix**: Use full cmdlet names

```powershell
# Bad
gci | ? { $_.Length -gt 1MB }

# Good
Get-ChildItem | Where-Object { $_.Length -gt 1MB }
```

## Suppressing Rules

Sometimes you need to suppress a rule for valid reasons:

```powershell
function Write-UserMessage {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Write-Host required for real-time progress display')]
    param(
        [string]$Message
    )
    
    Write-Host $Message -ForegroundColor Green
}
```

Best practices for suppression:
1. Use sparingly — fix the issue if possible
2. Always include a justification
3. Be specific — suppress only the rule you need
4. Review regularly during refactoring

## Pre-Commit Workflow

```powershell
# Before committing
./Scripts/Test-CodeQuality.ps1

# If issues found, fix them
# Then test again
./Scripts/Test-CodeQuality.ps1

# Commit when clean
git add .
git commit -m "Fix code quality issues"
```

## CI/CD Integration

For automated builds:

```powershell
# In CI pipeline
$results = Invoke-ScriptAnalyzer -Path ./src/CharlandCustomizations/ -Recurse -Severity Error

if ($results) {
    $results | Format-Table
    throw "PSScriptAnalyzer found errors"
}
```

## Configuration File

Create `.pssa-settings.psd1` for custom rules:

```powershell
@{
    Severity = @('Error', 'Warning')
    ExcludeRules = @(
        'PSAvoidUsingWriteHost'  # We use Write-Host for user feedback
    )
    IncludeRules = @(
        'PSUseShouldProcessForStateChangingFunctions'
        'PSProvideCommentHelp'
    )
}
```

Use with:
```powershell
Invoke-ScriptAnalyzer -Path ./src/CharlandCustomizations/ -Settings ./.pssa-settings.psd1
```

## See Also

- `Scripts/Test-CodeQuality.ps1` - Analysis script
- `Scripts/Build-Module.ps1` - Build with analysis
- `.kiro/steering/powershell-module-development.md` - Development guidelines
