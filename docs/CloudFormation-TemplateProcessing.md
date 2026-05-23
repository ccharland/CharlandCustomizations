# CloudFormation Template Processing

These commands are now exported by the main `CharlandCustomizations` module. Import `CharlandCustomizations` and use these functions directly; you do not need to import a separate CloudFormation module.

This module provides a comprehensive collection of PowerShell functions for working with AWS CloudFormation templates, stacks, and directory-based stack management. It focuses specifically on CloudFormation operations and template processing workflows.

## Overview

The CloudFormation command set was created by extracting and consolidating CloudFormation-related PowerShell scripts from the aws-templates-tools-snippets repository. It complements the AWS account audit commands in `CharlandCustomizations`, which handle general AWS account auditing functions.

## Functions Included

### Stack Management Functions
- **`New-CFNStackFromDirectory`** - Creates CloudFormation stacks from directory structures
- **`Update-CFNStackFromDirectory`** - Updates CloudFormation stacks using change sets
- **`Test-CFNStackFromDirectory`** - Validates CloudFormation templates from directories
- **`Out-CFNStackInfo`** - Exports stack information for backup and redeployment

### Template and Directory Utilities
- **`New-CFNStackDirectory`** - Creates directory structure for new CloudFormation stacks


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
      └── outputs.json           # Stack outputs (created by Out-CFNStackInfo)
```

## Prerequisites

- AWS PowerShell module (`AWSPowerShell.NetCore` or `AWS.Tools`)
- Valid AWS credentials configured
- PowerShell 5.1 or later
- S3 bucket for CloudFormation templates (cf-templates-*<region>)

## Installation

1. Copy the module files to your PowerShell modules directory:
   ```powershell
   # Find your modules path
   $env:PSModulePath -split ';'
   
   # Copy module files to one of the module paths
   # For example: C:\Users\<username>\Documents\PowerShell\Modules\CloudFormation-TemplateProcessing\
   ```

2. Import the module:
   ```powershell
   Import-Module CloudFormation-TemplateProcessing
   ```

## Common Parameters
Region:  AWS Region
Path: Path of directory containing stacks , typically "account-number/region/"
StackName: directory name to put stack specific information into.

## Usage Examples



### Stack Creation
```powershell
# Create a single stack from directory structure
New-CFNStackFromDirectory -StackName "MyStack" -Path "C:\CloudFormation"

# Verify template without creating stack
New-CFNStackFromDirectory -StackName "MyStack" -VerifyOnly

# Create all stacks in a directory
New-CFNStackFromDirectory -Path "C:\CloudFormation"
```

### Stack Updates with Change Sets
```powershell
# Create change set for review
Update-CFNStackFromDirectory -StackName "MyStack"

# Create and immediately execute change set
Update-CFNStackFromDirectory -StackName "MyStack" -ExecuteChangeSet

# Verify what would change without creating change set
Update-CFNStackFromDirectory -StackName "MyStack" -VerifyOnly
```

### Template Validation
```powershell
# Validate single template
Test-CFNStackFromDirectory -StackName "MyStack"

# Validate multiple templates via pipeline
"Stack1", "Stack2", "Stack3" | Test-CFNStackFromDirectory -Region us-west-2

# Use custom template filename
Test-CFNStackFromDirectory -StackName "MyStack" -TemplateName "custom-template.yaml"
```

### Stack Information Export
```powershell
# Export single stack information
Out-CFNStackInfo -StackName "MyStack" -RootPath "C:\Backups"

# Export all stacks via pipeline
Get-CFNStack | Out-CFNStackInfo -RootPath "C:\Backups"

# Export to specific region directory
"Stack1", "Stack2" | Out-CFNStackInfo -Region us-west-2 -RootPath "C:\Backups"
```

### Directory Setup
```powershell
# Create new stack directory with template
$templateContent = Get-Content "template.yaml" -Raw
New-CFNStackDirectory -StackName "NewStack" -TemplateBody $templateContent

# Create directory and validate template
New-CFNStackDirectory -StackName "NewStack" -TemplateBody $templateContent -Path "C:\Stacks"
```


## Advanced Workflows

### Complete Stack Lifecycle
```powershell
# 1. Create directory structure
$template = Get-Content "my-template.yaml" -Raw
New-CFNStackDirectory -StackName "ProductionStack" -TemplateBody $template

# 2. Add parameters and tags (manually edit JSON files)
# Edit: ProductionStack/parameters.json
# Edit: ProductionStack/tags.json
# Edit: ProductionStack/capabilities.json

# 3. Validate template
Test-CFNStackFromDirectory -StackName "ProductionStack"

# 4. Create stack
New-CFNStackFromDirectory -StackName "ProductionStack"

# 5. Later, update stack with change set
Update-CFNStackFromDirectory -StackName "ProductionStack"

# 6. Export stack info for backup
Out-CFNStackInfo -StackName "ProductionStack" -RootPath "C:\StackBackups"
```

### Multi-Region Deployment
```powershell
$regions = @("us-east-1", "us-west-2", "eu-west-1")
$stackName = "GlobalStack"

foreach ($region in $regions) {
    Write-Host "Deploying to $region..."
    New-CFNStackFromDirectory -StackName $stackName -Region $region
}
```

## Function Details

Each function includes comprehensive help documentation. Use `Get-Help` to learn more:

```powershell
Get-Help New-CFNStackFromDirectory -Detailed
Get-Help Update-CFNStackFromDirectory -Examples
Get-Help Test-CFNStackFromDirectory -Full
```

## Source Scripts

This module consolidates the following CloudFormation-related scripts:
- `New-CFNStackFromDirectory.ps1`
- `Verify-CFNStackFromDirectory.ps1` (renamed to `Test-CFNStackFromDirectory`)
- `Update-CFNStackFromDirectory.ps1`
- `Out-CFNStackInfo.ps1`
- `New-CFNStackDirectory.ps1`
- `Edit-CFTTEbsVolumes.ps1`

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
   Solution: Use `New-CFNStackFromDirectory` to create new stacks, not `Update-CFNStackFromDirectory`.


## Version History

- **v1.0.0** - Initial release with core CloudFormation template processing functions

## Contributing

This module was generated from the aws-templates-tools-snippets repository. To contribute improvements:

1. Update the original `.ps1` scripts in the repository
2. Regenerate the module to incorporate changes
3. Test thoroughly in your environment

## License

This module follows the same license as the source repository: aws-templates-tools-snippets
