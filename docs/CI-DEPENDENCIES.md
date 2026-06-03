# CI Dependencies

## Why AWS.Tools Modules Are Required in CI

The GitHub Actions runner (`ubuntu-latest`) does not include AWS PowerShell tools.
This module and its tests depend on AWS cmdlet definitions being available in the session.

### The Problem

- The module's `.psm1` loader throws if `Set-AWSCredential` (from `AWS.Tools.Common`) is not found.
- Pester cannot mock a command that doesn't exist in the session. Tests that `Mock Get-STSCallerIdentity` or `Mock Get-EC2Instance` will fail with `CommandNotFoundException` unless the module providing that command is installed.

### What Gets Installed

The `pr-quality-gate.yml` workflow installs these modules before running Pester tests:

| Module                             | Provides                                                         |
| ---------------------------------- | ---------------------------------------------------------------- |
| `AWS.Tools.Common`                 | `Set-AWSCredential`, core AWS session management                 |
| `AWS.Tools.SecurityToken`          | `Get-STSCallerIdentity`                                          |
| `AWS.Tools.EC2`                    | `Get-EC2Instance`, `Get-EC2SecurityGroup`, `Get-EC2Volume`, etc. |
| `AWS.Tools.S3`                     | `Get-S3Bucket`, `Write-S3Object`, `Get-S3PreSignedURL`           |
| `AWS.Tools.CloudFormation`         | `Get-CFNStack`, `Get-CFNTemplate`, `New-CFNChangeSet`, etc.      |
| `AWS.Tools.IdentityManagement`     | `Get-IAMUser`, `Get-IAMRole`, etc.                               |
| `AWS.Tools.ElasticLoadBalancingV2` | `Get-ELB2LoadBalancer`                                           |
| `AWS.Tools.RDS`                    | `Get-RDSDBInstance`                                              |
| `AWS.Tools.Lambda`                 | `Get-LMFunctionList`                                             |
| `AWS.Tools.ElastiCache`            | `Get-ECCacheCluster`                                             |
| `AWS.Tools.AutoScaling`            | `Get-ASAutoScalingGroup`                                         |
| `AWS.Tools.CloudWatch`             | `Get-CWAlarm`, `Get-CWMetricStatistic`                           |

### When to Update This List

If you add a new test that mocks an AWS cmdlet from a module not listed above, you need to:

1. Add the module to the `Install-AWSToolsModule` call in `.github/workflows/pr-quality-gate.yml`
2. Update this document

### How It Works

```yaml
- name: Install AWS.Tools modules
  shell: pwsh
  run: |
    Install-Module -Name AWS.Tools.Installer -Scope CurrentUser -Force
    Install-AWSToolsModule -Name @(
      'AWS.Tools.Common',
      'AWS.Tools.SecurityToken',
      ...
    ) -Scope CurrentUser -Force -CleanUp
```

`AWS.Tools.Installer` handles dependency resolution between sub-modules. The `-CleanUp` flag removes older versions to keep the runner lean.

### Help Validation Job

The help-validation job only needs `AWS.Tools.Common` — just enough for `Import-Module` to succeed. It doesn't run any AWS commands, it only needs the module loaded so `Get-Help` can discover function help.

### Local Development

Locally you likely already have AWS tools installed. If not:

```powershell
Install-Module -Name AWS.Tools.Installer -Scope CurrentUser
Install-AWSToolsModule -Name AWS.Tools.Common, AWS.Tools.SecurityToken, AWS.Tools.EC2, AWS.Tools.S3, AWS.Tools.CloudFormation -Scope CurrentUser
```
