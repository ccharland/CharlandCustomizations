# AWS Account Audit

These commands are now exported by the main `CharlandCustomizations` module. Import `CharlandCustomizations` and use these functions directly; you do not need to import a separate audit module.

This module provides a collection of PowerShell functions for auditing AWS accounts and resources. It includes functions for analyzing EC2 instances, security groups, IAM resources, S3 buckets, and other AWS services **without working with CloudFormation templates**.

## Overview

The `audit-AWSAccount.psm1` module was created by extracting and consolidating non-CloudFormation PowerShell scripts from the aws-templates-tools-snippets repository. CloudFormation template processing functions are available separately in the `TemplateProcessing.psm1` module.

## Functions Included

### Security and EC2 Functions

- **`Get-CCEC2SGInUse`** - Shows resources associated with each EC2 Security Group in a region
- **`Get-CCEC2KeyTagNameStatus`** - Checks if EC2 resources have required tags like "Name" or "Environment"
- **`Get-CCEC2SnapshotReport`** - Gets a detailed listing of EC2 snapshots with batch processing
- **`Get-CCEC2VolumeReport`** - Reports on all EC2 volumes and their attachment status
- **`Start-CCEC2RetryLoop`** - Implements retry logic for EC2 operations

### Account and IAM Auditing

- **`Get-CCIAMAuditList`** - Consolidated IAM credential report from multiple accounts
- **`Get-CCGlobalAuditReportItem`** - Creates a count of various AWS resources across regions
- **`Out-CCAWSSupportingInfo`** - Collects and saves AWS account-specific supporting information
- **`Out-CCAWSNetworkingComponent`** - Exports VPC, subnet, route table, VPN, prefix list, and transit gateway details

## Prerequisites

- AWS PowerShell module (`AWSPowerShell.NetCore` or `AWSPowerShell`)
- Valid AWS credentials configured
- PowerShell 7.2 or later

## Installation

1. Install or copy the `CharlandCustomizations` module to one of your PowerShell modules directories:

   ```powershell
   # Find your modules path
   $env:PSModulePath -split [IO.Path]::PathSeparator

   # Copy the CharlandCustomizations module folder to one of the module paths
   # For example: C:\Users\<username>\Documents\PowerShell\Modules\CharlandCustomizations\
   ```

2. Import the main module, which exports these audit functions:
   ```powershell
   Import-Module CharlandCustomizations
   ```

## Usage Examples

### Security Group Analysis

```powershell
# Get all security groups and their associated resources
Get-CCEC2SGInUse

# Check specific security group
Get-CCEC2SGInUse -GroupId "sg-12345678" -Region "us-west-2"

# Find unused security groups
Get-CCEC2SGInUse | Where-Object UsedByCount -eq 0
```

### Tag Compliance Check

```powershell
# Check if all EC2 resources have a "Name" tag
Get-CCEC2KeyTagNameStatus -TagKey "Name"

# Check for "Environment" tag with custom filter
$filter = @{name='resource-type';values='instance'}
Get-CCEC2KeyTagNameStatus -TagKey "Environment" -filter $filter
```

### Account Auditing

```powershell
# Get resource counts across multiple regions
Get-CCGlobalAuditReportItem -Region @("us-east-1", "us-west-2")

# Export supporting information for current account
Out-CCAWSSupportingInfo -Region "us-east-1" -RootPath "C:\AWSReports"

# Export networking information for current account
Out-CCAWSNetworkingComponent -Region "us-east-1" -RootPath "C:\AWSReports"
```

### Snapshot and Volume Reports

```powershell
# Get detailed snapshot report
Get-CCEC2SnapshotReport | Export-Csv -Path "snapshots.csv" -NoTypeInformation

# Get volume attachment status
Get-CCEC2VolumeReport | Where-Object InstanceID -eq "NoInstance"
```

### Multi-Account IAM Audit

```powershell
# Audit multiple AWS profiles
$profiles = @('Profile1', 'Profile2', 'Profile3')
Get-CCIAMAuditList -ProfileName $profiles | Out-File -Path "iam-audit.csv"
```

## Function Details

Each function includes comprehensive help documentation. Use `Get-Help` to learn more:

```powershell
Get-Help Get-CCEC2SGInUse -Detailed
Get-Help Get-CCGlobalAuditReportItem -Examples
```

## Source Scripts

This module consolidates the following scripts from the original repository:

- `Get-CCEC2SGInUse.ps1`
- `Out-CCAWSSupportingInfo.ps1`
- `Get-CCIAMAuditList.ps1`
- `Get-CCGlobalAuditReportItem.ps1`
- `Get-CCEC2KeyTagNameStatus.ps1`
- `Get-CCEC2SnapshotReport.ps1`
- `Get-CCEC2VolumeReport.ps1`
- `Start-CCEC2RetryLoop.ps1`

## Excluded Scripts

The following CloudFormation-related scripts are **NOT** included in this module:

- `New-CCCFNStackFromDirectory.ps1`
- `Test-CCCFNStackFromDirectory.ps1`
- `Update-CCCFNStackFromDirectory.ps1`
- `Out-CCCFNStackInfo.ps1`
- `New-CCCFNStackDirectory.ps1`
- `Edit-CCCFTTEbsVolume.ps1`

These are available separately in the `TemplateProcessing.psm1` module.

## Version History

- **v1.0.0** - Initial release with core audit functions extracted from aws-templates-tools-snippets repository

## Contributing

This module was generated from the aws-templates-tools-snippets repository. To contribute improvements:

1. Update the original `.ps1` scripts in the repository
2. Regenerate the module to incorporate changes
3. Test thoroughly in your environment

## License

This module follows the same license as the source repository: aws-templates-tools-snippets
