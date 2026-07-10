# CloudFormation Template Processing

These commands are exported by the main `CharlandCustomizations` module. Import `CharlandCustomizations` and use these functions directly; you do not need to import a separate CloudFormation module.

## Overview

The CloudFormation command set provides PowerShell functions for working with AWS CloudFormation templates, stacks, and directory-based stack management. It complements the AWS account audit commands documented in [AWS-Account-Audit.md](AWS-Account-Audit.md).

## Functions Included

### Stack Management Functions
- **`New-CHARCFNStackFromDirectory`** - Creates CloudFormation stacks from directory structures
- **`Update-CHARCFNStackFromDirectory`** - Updates CloudFormation stacks using change sets
- **`Test-CHARCFNStackFromDirectory`** - Validates CloudFormation templates from directories
- **`Out-CHARCFNStackInfo`** - Exports stack information for backup and redeployment

### Template and Directory Utilities
- **`New-CHARCFNStackDirectory`** - Creates directory structure for new CloudFormation stacks
- **`Edit-CHARCFTTEbsVolume`** - Modifies EBS volume configuration in CloudFormation templates

## Directory Structure Convention

This module uses a standardized directory structure for CloudFormation stack management:

```
<account-number>/
  <Region>/      
    <StackName>/
      ├── template.yaml          # CloudFormation template file (or template.json)
      ├── parameters.json        # Stack parameters
      ├── capabilities.json      # Required capabilities (e.g., CAPABILITY_IAM)
      ├── tags.json              # Stack tags
      └── outputs.json           # Stack outputs (created by Out-CHARCFNStackInfo)
```

## Common Parameters

- `Region` — AWS Region
- `Path` — Path of directory containing stacks, typically `account-number/region/`
- `StackName` — Directory name to put stack-specific information into

## Usage Examples

### Stack Creation
```powershell
# Create a single stack from directory structure
New-CHARCFNStackFromDirectory -StackName "MyStack" -Path "C:\CloudFormation"

# Verify template without creating stack
New-CHARCFNStackFromDirectory -StackName "MyStack" -VerifyOnly

# Create all stacks in a directory
New-CHARCFNStackFromDirectory -Path "C:\CloudFormation"
```

### Stack Updates with Change Sets
```powershell
# Create change set for review
Update-CHARCFNStackFromDirectory -StackName "MyStack"

# Create and immediately execute change set
Update-CHARCFNStackFromDirectory -StackName "MyStack" -ExecuteChangeSet

# Verify what would change without creating change set
Update-CHARCFNStackFromDirectory -StackName "MyStack" -VerifyOnly
```

### Template Validation
```powershell
# Validate single template
Test-CHARCFNStackFromDirectory -StackName "MyStack"

# Validate multiple templates via pipeline
"Stack1", "Stack2", "Stack3" | Test-CHARCFNStackFromDirectory -Region us-west-2

# Use custom template filename
Test-CHARCFNStackFromDirectory -StackName "MyStack" -TemplateName "custom-template.yaml"
```

### Stack Information Export
```powershell
# Export single stack information
Out-CHARCFNStackInfo -StackName "MyStack" -RootPath "C:\Backups"

# Export all stacks via pipeline
Get-CFNStack | Out-CHARCFNStackInfo -RootPath "C:\Backups"

# Export to specific region directory
"Stack1", "Stack2" | Out-CHARCFNStackInfo -Region us-west-2 -RootPath "C:\Backups"
```

### Directory Setup
```powershell
# Create new stack directory with template
$templateContent = Get-Content "template.yaml" -Raw
New-CHARCFNStackDirectory -StackName "NewStack" -TemplateBody $templateContent

# Create directory and validate template
New-CHARCFNStackDirectory -StackName "NewStack" -TemplateBody $templateContent -Path "C:\Stacks"
```

## Advanced Workflows

### Complete Stack Lifecycle
```powershell
# 1. Create directory structure
$template = Get-Content "my-template.yaml" -Raw
New-CHARCFNStackDirectory -StackName "ProductionStack" -TemplateBody $template

# 2. Add parameters and tags (manually edit JSON files)
# Edit: ProductionStack/parameters.json
# Edit: ProductionStack/tags.json
# Edit: ProductionStack/capabilities.json

# 3. Validate template
Test-CHARCFNStackFromDirectory -StackName "ProductionStack"

# 4. Create stack
New-CHARCFNStackFromDirectory -StackName "ProductionStack"

# 5. Later, update stack with change set
Update-CHARCFNStackFromDirectory -StackName "ProductionStack"

# 6. Export stack info for backup
Out-CHARCFNStackInfo -StackName "ProductionStack" -RootPath "C:\StackBackups"
```

### Multi-Region Deployment
```powershell
$regions = @("us-east-1", "us-west-2", "eu-west-1")
$stackName = "GlobalStack"

foreach ($region in $regions) {
    Write-Host "Deploying to $region..."
    New-CHARCFNStackFromDirectory -StackName $stackName -Region $region
}
```

## Function Details

Each function includes comprehensive help documentation:

```powershell
Get-Help New-CHARCFNStackFromDirectory -Detailed
Get-Help Update-CHARCFNStackFromDirectory -Examples
Get-Help Test-CHARCFNStackFromDirectory -Full
```

## Error Handling and Best Practices

### S3 Template Storage
The module automatically uploads templates to S3 for CloudFormation operations. Ensure you have:
- An S3 bucket with naming pattern: `cf-templates-*<region>`
- Appropriate S3 permissions for template upload/download

### Change Set Management
- Always review change sets before execution
- Use `-VerifyOnly` flag for dry runs
- Change sets are automatically cleaned up on failure

### Template Validation
- Templates are validated before stack operations
- Parameter counts are verified against template requirements
- Capability requirements are checked

### Directory Structure Validation
- Required files are checked before operations
- Missing files result in clear error messages
- Optional files (like tags.json) are handled gracefully

## Troubleshooting

### Common Issues

1. **S3 Bucket Not Found**
   ```
   Error: No S3 bucket found for CloudFormation templates
   ```
   Solution: Ensure you have a CloudFormation template bucket in the target region.

2. **Template Parameter Mismatch**
   ```
   Warning: Template parameter counts do not match
   ```
   Solution: Review and update your parameters.json file.

3. **Stack Does Not Exist**
   ```
   Error: Stack does not exist in region
   ```
   Solution: Use `New-CHARCFNStackFromDirectory` to create new stacks, not `Update-CHARCFNStackFromDirectory`.

## Related

- [AWS-Account-Audit.md](AWS-Account-Audit.md) — Non-CloudFormation AWS audit functions
- [CONTRIBUTING.md](../CONTRIBUTING.md) — How to contribute changes
- [INSTALLATION.md](INSTALLATION.md) — Module installation
