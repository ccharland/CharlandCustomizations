# CI Dependencies

## Why AWS PowerShell Modules Are Required in CI

The GitHub Actions runners do not include AWS PowerShell tools by default.
This module and its tests depend on AWS cmdlet definitions being available in the session.

### The Problem

- The module's `.psm1` loader throws if `Set-AWSCredential` is not found.
- Pester cannot mock a command that doesn't exist in the session. Tests that `Mock Get-STSCallerIdentity` or `Mock Get-EC2Instance` will fail with `CommandNotFoundException` unless the module providing that command is installed.

### What Gets Installed

The `pr-quality-gate.yml` and `main-status-checks.yml` workflows install **`AWSPowerShell.NetCore`** (the monolithic AWS PowerShell module) before running Pester tests. This single module provides all AWS cmdlets needed for mocking and module loading.

```yaml
- name: Install and import AWSPowerShell.NetCore
  shell: pwsh
  run: |
    Install-Module -Name AWSPowerShell.NetCore -Scope CurrentUser -Force
    Import-Module AWSPowerShell.NetCore -ErrorAction Stop
```

The monolithic module is used instead of modular `AWS.Tools.*` packages because:
- It simplifies CI setup to a single install command
- All AWS cmdlets are available for mocking without tracking individual sub-modules
- The Pester tests job runs on `windows-latest` where the install completes quickly

### Key Cmdlets Provided

The monolithic `AWSPowerShell.NetCore` module provides all of the following (and more):

| Cmdlet Area          | Examples                                                         |
| -------------------- | ---------------------------------------------------------------- |
| Core session         | `Set-AWSCredential`, `Get-AWSRegion`                             |
| STS                  | `Get-STSCallerIdentity`                                          |
| EC2                  | `Get-EC2Instance`, `Get-EC2SecurityGroup`, `Get-EC2Volume`       |
| S3                   | `Get-S3Bucket`, `Write-S3Object`, `Get-S3PreSignedURL`           |
| CloudFormation       | `Get-CFNStack`, `Get-CFNTemplate`, `New-CFNChangeSet`            |
| IAM                  | `Get-IAMUser`, `Get-IAMRole`                                     |
| ELB                  | `Get-ELB2LoadBalancer`                                           |
| RDS                  | `Get-RDSDBInstance`                                              |
| Lambda               | `Get-LMFunctionList`                                             |
| ElastiCache          | `Get-ECCacheCluster`                                             |
| Auto Scaling         | `Get-ASAutoScalingGroup`                                         |
| CloudWatch           | `Get-CWAlarm`, `Get-CWMetricStatistic`                           |

### Help Validation Job

The `help-validation` job installs `AWS.Tools.Common` (modular) rather than the full monolithic module. It only needs enough for `Import-Module CharlandCustomizations` to succeed — the module loader checks for `Set-AWSCredential` at import time. The job doesn't run AWS commands or mock AWS cmdlets.

```yaml
- name: Install AWS.Tools.Common
  shell: pwsh
  run: Install-Module -Name AWS.Tools.Common -Scope CurrentUser -Force
```

### Manifest Validation Job

The `manifest-validation` job does **not** require any AWS module. `Test-ManifestCompliance.ps1` uses AST parsing on the source files and reads the `.psd1` directly — it never imports the module.

### Local Development

Locally you likely already have AWS tools installed. Either variant works:

```powershell
# Option 1: Monolithic (matches CI Pester job)
Install-Module -Name AWSPowerShell.NetCore -Scope CurrentUser

# Option 2: Modular (install only what you need)
Install-Module -Name AWS.Tools.Installer -Scope CurrentUser
Install-AWSToolsModule -Name AWS.Tools.Common, AWS.Tools.SecurityToken, AWS.Tools.EC2, AWS.Tools.S3, AWS.Tools.CloudFormation -Scope CurrentUser
```

### When to Update CI

If the module loader starts requiring cmdlets from a service not covered by `AWSPowerShell.NetCore` (unlikely — it includes everything), or if you switch to modular `AWS.Tools.*` in CI, update the workflow install steps and this document.
