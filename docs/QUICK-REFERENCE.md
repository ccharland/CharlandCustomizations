# Quick Reference

## Common Commands

### AWS Authentication

```powershell
# Get MFA session
$creds = Get-AWSMFASession -TokenCode 123456
Set-AWSCredential -Credential $creds

# Set profile with MFA
Set-AWSProfileWithMFA -ProfileName myprofile -TokenCode 123456

# Export to environment variables
Set-AWSEnv

# Assume a role
Use-AssumedRole -Role "MyRoleName"
```

### CloudFormation

```powershell
# Create a stack working directory from a template body
New-CFNStackDirectory -StackName "MyStack" -TemplateBody (Get-Content ./template.yaml -Raw)

# Validate a stack directory
Test-CFNStackFromDirectory -StackName "MyStack"

# Create a stack from a directory containing template.template, parameters.json, tags.json, and capabilities.json
New-CFNStackFromDirectory -StackName "MyStack"

# Create a change set from a stack directory
Update-CFNStackFromDirectory -StackName "MyStack"

# Create and execute the change set
Update-CFNStackFromDirectory -StackName "MyStack" -ExecuteChangeSet

# Export an existing stack to an account/region/stack directory
Out-CFNStackInfo -StackName "MyStack" -RootPath ./accounts

# Find stacks with errors
Find-CFNStackErrors

# Find errors in specific stack tree
Find-CFNStackErrors -RootStackName "MyStack"

# Validate template
Test-CFNTemplateFromFile -Path ./template.yaml

# Detect drift on all stacks
Get-CFNStack | Start-MultiStackDriftDetection

# List drifted resources
Get-AWSAccountListOfDriftedResources
```

### AWS Account Audit

```powershell
# Show security groups and associated resources
Get-EC2SGInUse -Region us-east-1

# Report unattached and attached EBS volumes
Get-EC2VolumeReport

# Report snapshots owned by the account
Get-EC2SnapshotReport

# Check required EC2 resource tags
Get-EC2KeyTagNameStatus -TagKey "Name"

# Export account supporting information
Out-AWSSupportingInfo -Region us-east-1 -RootPath ./accounts

# Export VPC/networking inventory
Out-AWSNetworkingComponent -Region us-east-1 -RootPath ./accounts
```

### Account Management

```powershell
# List accounts from profiles
Get-AccountListFromProfiles

# Clean up expired credentials
Remove-ExpiredAWSProfiles

# Quick resource scan by region
Get-AWSObjectCount
Get-AWSObjectCount -Region us-east-1
```

### S3

```powershell
# Preview emptying a versioned bucket
Clear-S3Bucket -BucketName "my-bucket" -Region us-east-1 -WhatIf

# Empty a bucket after typed confirmation
Clear-S3Bucket -BucketName "my-bucket" -Region us-east-1

# Empty and delete the bucket
Clear-S3Bucket -BucketName "my-bucket" -Region us-east-1 -DeleteBucket
```

### Git Utilities

```powershell
# Validate commit signatures
Test-CommitSignatures

# Check last 10 commits
Test-CommitSignatures -Count 10
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
Get-Help Get-AWSMFASession -Examples
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
# AWS credentials (set by Set-AWSEnv)
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
Set-Alias -Name mfa -Value Get-AWSMFASession
Set-Alias -Name awsenv -Value Set-AWSEnv

# Module shortcuts
Set-Alias -Name reload-module -Value {
    Remove-Module CharlandCustomizations
    Import-Module CharlandCustomizations -Force
}
```
