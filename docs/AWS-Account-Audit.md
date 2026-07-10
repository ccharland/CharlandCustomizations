# AWS Account Audit

These commands are exported by the main `CharlandCustomizations` module. Import `CharlandCustomizations` and use these functions directly; you do not need to import a separate audit module.

## Overview

The audit functions provide PowerShell tools for auditing AWS accounts and resources — EC2 instances, security groups, IAM resources, and more — **without working with CloudFormation templates**. CloudFormation template processing functions are documented separately in [CloudFormation-TemplateProcessing.md](CloudFormation-TemplateProcessing.md).

## Functions Included

### Security and EC2 Functions

- **`Get-CHAREC2SGInUse`** - Shows resources associated with each EC2 Security Group in a region
- **`Get-CHAREC2KeyTagNameStatus`** - Checks if EC2 resources have required tags like "Name" or "Environment"
- **`Get-CHAREC2SnapshotReport`** - Gets a detailed listing of EC2 snapshots with batch processing
- **`Get-CHAREC2VolumeReport`** - Reports on all EC2 volumes and their attachment status
- **`Start-CHAREC2RetryLoop`** - Implements retry logic for EC2 operations

### Account and IAM Auditing

- **`Get-CHARIAMAuditList`** - Consolidated IAM credential report from multiple accounts
- **`Get-CHARGlobalAuditReportItem`** - Creates a count of various AWS resources across regions
- **`Out-CHARAWSSupportingInfo`** - Collects and saves AWS account-specific supporting information
- **`Out-CHARAWSNetworkingComponent`** - Exports VPC, subnet, route table, VPN, prefix list, and transit gateway details

## Usage Examples

### Security Group Analysis

```powershell
# Get all security groups and their associated resources
Get-CHAREC2SGInUse

# Check specific security group
Get-CHAREC2SGInUse -GroupId "sg-12345678" -Region "us-west-2"

# Find unused security groups
Get-CHAREC2SGInUse | Where-Object UsedByCount -eq 0
```

### Tag Compliance Check

```powershell
# Check if all EC2 resources have a "Name" tag
Get-CHAREC2KeyTagNameStatus -TagKey "Name"

# Check for "Environment" tag with custom filter
$filter = @{name='resource-type';values='instance'}
Get-CHAREC2KeyTagNameStatus -TagKey "Environment" -filter $filter
```

### Account Auditing

```powershell
# Get resource counts across multiple regions
Get-CHARGlobalAuditReportItem -Region @("us-east-1", "us-west-2")

# Export supporting information for current account
Out-CHARAWSSupportingInfo -Region "us-east-1" -RootPath "C:\AWSReports"

# Export networking information for current account
Out-CHARAWSNetworkingComponent -Region "us-east-1" -RootPath "C:\AWSReports"
```

### Snapshot and Volume Reports

```powershell
# Get detailed snapshot report
Get-CHAREC2SnapshotReport | Export-Csv -Path "snapshots.csv" -NoTypeInformation

# Get volume attachment status
Get-CHAREC2VolumeReport | Where-Object InstanceID -eq "NoInstance"
```

### Multi-Account IAM Audit

```powershell
# Audit multiple AWS profiles
$profiles = @('Profile1', 'Profile2', 'Profile3')
Get-CHARIAMAuditList -ProfileName $profiles | Out-File -Path "iam-audit.csv"
```

## Function Details

Each function includes comprehensive help documentation. Use `Get-Help` to learn more:

```powershell
Get-Help Get-CHAREC2SGInUse -Detailed
Get-Help Get-CHARGlobalAuditReportItem -Examples
```

## Source Scripts

This module consolidates the following scripts from the original repository:

- `Get-CHAREC2SGInUse.ps1`
- `Out-CHARAWSSupportingInfo.ps1`
- `Get-CHARIAMAuditList.ps1`
- `Get-CHARGlobalAuditReportItem.ps1`
- `Get-CHAREC2KeyTagNameStatus.ps1`
- `Get-CHAREC2SnapshotReport.ps1`
- `Get-CHAREC2VolumeReport.ps1`
- `Start-CHAREC2RetryLoop.ps1`

## Related

- [CloudFormation-TemplateProcessing.md](CloudFormation-TemplateProcessing.md) — CloudFormation stack management functions
- [CONTRIBUTING.md](../CONTRIBUTING.md) — How to contribute changes
- [INSTALLATION.md](INSTALLATION.md) — Module installation
