# Quick Reference

## Common Commands

### AWS Authentication

```powershell
# Get MFA session
$creds = Get-CHARAWSMFASession -TokenCode 123456
$creds = Get-CHARAWSMFASession -TokenCode 123456
Set-AWSCredential -Credential $creds

# Set profile with MFA
Set-CHARAWSProfileWithMFA -ProfileName myprofile -TokenCode 123456
Set-CHARAWSProfileWithMFA -ProfileName myprofile -TokenCode 123456

# Export to environment variables
Set-CHARAWSEnv
Set-CHARAWSEnv

# Assume a role
Use-CHARAssumedRole -Role "MyRoleName"
Use-CHARAssumedRole -Role "MyRoleName"
```

### CloudFormation

```powershell
# Create a stack working directory from a template body
New-CHARCFNStackDirectory -StackName "MyStack" -TemplateBody (Get-Content ./template.yaml -Raw)
New-CHARCFNStackDirectory -StackName "MyStack" -TemplateBody (Get-Content ./template.yaml -Raw)

# Validate a stack directory
Test-CHARCFNStackFromDirectory -StackName "MyStack"
Test-CHARCFNStackFromDirectory -StackName "MyStack"

# Create a stack from a directory containing template.template, parameters.json, tags.json, and capabilities.json
New-CHARCFNStackFromDirectory -StackName "MyStack"
New-CHARCFNStackFromDirectory -StackName "MyStack"

# Create a change set from a stack directory
Update-CHARCFNStackFromDirectory -StackName "MyStack"
Update-CHARCFNStackFromDirectory -StackName "MyStack"

# Create and execute the change set
Update-CHARCFNStackFromDirectory -StackName "MyStack" -ExecuteChangeSet
Update-CHARCFNStackFromDirectory -StackName "MyStack" -ExecuteChangeSet

# Export an existing stack to an account/region/stack directory
Out-CHARCFNStackInfo -StackName "MyStack" -RootPath ./accounts
Out-CHARCFNStackInfo -StackName "MyStack" -RootPath ./accounts

# Find stacks with errors
Find-CHARCFNStackError
Find-CHARCFNStackError

# Find errors in specific stack tree
Find-CHARCFNStackError -RootStackName "MyStack"
Find-CHARCFNStackError -RootStackName "MyStack"

# Validate template
Test-CFNTemplateFromFile -Path ./template.yaml

# Detect drift on all stacks
Get-CFNStack | Start-CHARMultiStackDriftDetection
Get-CFNStack | Start-CHARMultiStackDriftDetection

# List drifted resources
Get-CHARAWSAccountListOfDriftedResource
```

### AWS Account Audit

```powershell
# Show security groups and associated resources
Get-CHAREC2SGInUse -Region us-east-1
Get-CHAREC2SGInUse -Region us-east-1

# Report unattached and attached EBS volumes
Get-CHAREC2VolumeReport
Get-CHAREC2VolumeReport

# Report snapshots owned by the account
Get-CHAREC2SnapshotReport
Get-CHAREC2SnapshotReport

# Check required EC2 resource tags
Get-CHAREC2KeyTagNameStatus -TagKey "Name"
Get-CHAREC2KeyTagNameStatus -TagKey "Name"

# Export account supporting information
Out-CHARAWSSupportingInfo -Region us-east-1 -RootPath ./accounts
Out-CHARAWSSupportingInfo -Region us-east-1 -RootPath ./accounts

# Export VPC/networking inventory
Out-CHARAWSNetworkingComponent -Region us-east-1 -RootPath ./accounts
Out-CHARAWSNetworkingComponent -Region us-east-1 -RootPath ./accounts
```

### Account Management

```powershell
# List accounts from profiles
Get-CHARAccountListFromProfile

# Clean up expired credentials
Remove-CHARExpiredAWSProfile

# Quick resource scan by region
Get-CHARAWSObjectCount
Get-CHARAWSObjectCount -Region us-east-1
Get-CHARAWSObjectCount
Get-CHARAWSObjectCount -Region us-east-1
```

### S3

```powershell
# Preview emptying a versioned bucket
Clear-CHARS3Bucket -BucketName "my-bucket" -Region us-east-1 -WhatIf
Clear-CHARS3Bucket -BucketName "my-bucket" -Region us-east-1 -WhatIf

# Empty a bucket after typed confirmation
Clear-CHARS3Bucket -BucketName "my-bucket" -Region us-east-1
Clear-CHARS3Bucket -BucketName "my-bucket" -Region us-east-1

# Empty and delete the bucket
Clear-CHARS3Bucket -BucketName "my-bucket" -Region us-east-1 -DeleteBucket
Clear-CHARS3Bucket -BucketName "my-bucket" -Region us-east-1 -DeleteBucket
```

### Git Utilities

```powershell
# Validate commit signatures
Test-CHARCommitSignature

# Check last 10 commits
Test-CHARCommitSignature -Count 10
```

## Module Management

```powershell
# Import module
Import-Module CharlandCustomizations

# Reload module
Remove-Module CharlandCustomizations
Import-Module CharlandCustomizations -Force

# List all functions
Get-Command -Module CharlandCustomizations

# Get help
Get-Help <FunctionName> -Full
Get-Help Get-CHARAWSMFASession -Examples
Get-Help Get-CHARAWSMFASession -Examples
```

## Build and Deploy

```powershell
# Build and install
./Scripts/Build-Module.ps1 -Install

# Build without signing (development only)
./Scripts/Build-Module.ps1 -SkipSigning -Install

# Create distribution package (requires signing)
./Scripts/Build-Module.ps1 -Package

# Clean build with package
./Scripts/Build-Module.ps1 -Clean -Package

# Just validate
./Scripts/Build-Module.ps1
```

## File Locations

```
src/CharlandCustomizations/         # Main module source
Scripts/                            # Build and deployment scripts
tests/                              # Pester tests
docs/                               # Documentation
build/                              # Build output (gitignored)
```

## Environment Variables

```powershell
# AWS credentials (set by Set-CHARAWSEnv)
# AWS credentials (set by Set-CHARAWSEnv)
$env:AWS_ACCESS_KEY_ID
$env:AWS_SECRET_ACCESS_KEY
$env:AWS_SESSION_TOKEN
$env:AWS_DEFAULT_REGION

# PowerShell paths
$PROFILE                            # Current profile path
$HOME/Documents/PowerShell/Modules  # User modules
```

## Useful Aliases

Add to your profile for quick access:

```powershell
# AWS shortcuts
Set-Alias -Name mfa -Value Get-CHARAWSMFASession
Set-Alias -Name awsenv -Value Set-CHARAWSEnv
Set-Alias -Name mfa -Value Get-CHARAWSMFASession
Set-Alias -Name awsenv -Value Set-CHARAWSEnv

# Module shortcuts
Set-Alias -Name reload-module -Value {
    Remove-Module CharlandCustomizations
    Import-Module CharlandCustomizations -Force
}
```
