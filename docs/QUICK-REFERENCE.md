# Quick Reference

## Common Commands

### AWS Authentication

```powershell
# Get MFA session
$creds = Get-CCAWSMFASession -TokenCode 123456
$creds = Get-CCAWSMFASession -TokenCode 123456
Set-AWSCredential -Credential $creds

# Set profile with MFA
Set-CCAWSProfileWithMFA -ProfileName myprofile -TokenCode 123456
Set-CCAWSProfileWithMFA -ProfileName myprofile -TokenCode 123456

# Export to environment variables
Set-CCAWSEnv
Set-CCAWSEnv

# Assume a role
Use-CCAssumedRole -Role "MyRoleName"
Use-CCAssumedRole -Role "MyRoleName"
```

### CloudFormation

```powershell
# Create a stack working directory from a template body
New-CCCFNStackDirectory -StackName "MyStack" -TemplateBody (Get-Content ./template.yaml -Raw)
New-CCCFNStackDirectory -StackName "MyStack" -TemplateBody (Get-Content ./template.yaml -Raw)

# Validate a stack directory
Test-CCCFNStackFromDirectory -StackName "MyStack"
Test-CCCFNStackFromDirectory -StackName "MyStack"

# Create a stack from a directory containing template.template, parameters.json, tags.json, and capabilities.json
New-CCCFNStackFromDirectory -StackName "MyStack"
New-CCCFNStackFromDirectory -StackName "MyStack"

# Create a change set from a stack directory
Update-CCCFNStackFromDirectory -StackName "MyStack"
Update-CCCFNStackFromDirectory -StackName "MyStack"

# Create and execute the change set
Update-CCCFNStackFromDirectory -StackName "MyStack" -ExecuteChangeSet
Update-CCCFNStackFromDirectory -StackName "MyStack" -ExecuteChangeSet

# Export an existing stack to an account/region/stack directory
Out-CCCFNStackInfo -StackName "MyStack" -RootPath ./accounts
Out-CCCFNStackInfo -StackName "MyStack" -RootPath ./accounts

# Find stacks with errors
Find-CCCFNStackError
Find-CCCFNStackError

# Find errors in specific stack tree
Find-CCCFNStackError -RootStackName "MyStack"
Find-CCCFNStackError -RootStackName "MyStack"

# Validate template
Test-CFNTemplateFromFile -Path ./template.yaml

# Detect drift on all stacks
Get-CFNStack | Start-CCMultiStackDriftDetection
Get-CFNStack | Start-CCMultiStackDriftDetection

# List drifted resources
Get-CCAWSAccountListOfDriftedResources
```

### AWS Account Audit

```powershell
# Show security groups and associated resources
Get-CCEC2SGInUse -Region us-east-1
Get-CCEC2SGInUse -Region us-east-1

# Report unattached and attached EBS volumes
Get-CCEC2VolumeReport
Get-CCEC2VolumeReport

# Report snapshots owned by the account
Get-CCEC2SnapshotReport
Get-CCEC2SnapshotReport

# Check required EC2 resource tags
Get-CCEC2KeyTagNameStatus -TagKey "Name"
Get-CCEC2KeyTagNameStatus -TagKey "Name"

# Export account supporting information
Out-CCAWSSupportingInfo -Region us-east-1 -RootPath ./accounts
Out-CCAWSSupportingInfo -Region us-east-1 -RootPath ./accounts

# Export VPC/networking inventory
Out-CCAWSNetworkingComponent -Region us-east-1 -RootPath ./accounts
Out-CCAWSNetworkingComponent -Region us-east-1 -RootPath ./accounts
```

### Account Management

```powershell
# List accounts from profiles
Get-CCAccountListFromProfiles

# Clean up expired credentials
Remove-CCExpiredAWSProfiles

# Quick resource scan by region
Get-CCAWSObjectCount
Get-CCAWSObjectCount -Region us-east-1
Get-CCAWSObjectCount
Get-CCAWSObjectCount -Region us-east-1
```

### S3

```powershell
# Preview emptying a versioned bucket
Clear-CCS3Bucket -BucketName "my-bucket" -Region us-east-1 -WhatIf
Clear-CCS3Bucket -BucketName "my-bucket" -Region us-east-1 -WhatIf

# Empty a bucket after typed confirmation
Clear-CCS3Bucket -BucketName "my-bucket" -Region us-east-1
Clear-CCS3Bucket -BucketName "my-bucket" -Region us-east-1

# Empty and delete the bucket
Clear-CCS3Bucket -BucketName "my-bucket" -Region us-east-1 -DeleteBucket
Clear-CCS3Bucket -BucketName "my-bucket" -Region us-east-1 -DeleteBucket
```

### Git Utilities

```powershell
# Validate commit signatures
Test-CCCommitSignature

# Check last 10 commits
Test-CCCommitSignature -Count 10
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
Get-Help Get-CCAWSMFASession -Examples
Get-Help Get-CCAWSMFASession -Examples
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
# AWS credentials (set by Set-CCAWSEnv)
# AWS credentials (set by Set-CCAWSEnv)
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
Set-Alias -Name mfa -Value Get-CCAWSMFASession
Set-Alias -Name awsenv -Value Set-CCAWSEnv
Set-Alias -Name mfa -Value Get-CCAWSMFASession
Set-Alias -Name awsenv -Value Set-CCAWSEnv

# Module shortcuts
Set-Alias -Name reload-module -Value {
    Remove-Module CharlandCustomizations
    Import-Module CharlandCustomizations -Force
}
```
