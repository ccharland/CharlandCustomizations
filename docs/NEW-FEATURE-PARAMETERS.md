# New Feature Parameter Guide

This repository uses a shared AWS parameter pattern for new PowerShell functions. The helper that builds the splat is [src/CharlandCustomizations/Private/New-AWSParamSplat.ps1](../src/CharlandCustomizations/Private/New-AWSParamSplat.ps1).

## Purpose

New AWS-facing functions should expose the same common parameters so callers get a consistent experience and the module can forward only the values that were actually supplied.

The helper returns the parameters in a stable order when they exist:

1. `AccessKey`
2. `Credential`
3. `EndpointUrl`
4. `NetworkCredential`
5. `ProfileLocation`
6. `ProfileName`
7. `Region`
8. `SecretKey`
9. `SessionToken`

## Standard Parameter Set

Use these parameter names in new AWS module functions when the feature needs AWS context:

| Parameter | Type | Notes |
| --- | --- | --- |
| `AccessKey` | `string` | AWS access key. |
| `Credential` | `Amazon.Runtime.AWSCredentials` | AWS credential object. |
| `EndpointUrl` | `string` | Optional custom endpoint. |
| `NetworkCredential` | `PSCredential` | Used for SAML-based auth flows. |
| `ProfileLocation` | `string` | Custom credential file path. |
| `ProfileName` | `string` | AWS profile name. |
| `Region` | `string` or region object | AWS region or region name. |
| `SecretKey` | `string` | AWS secret key. |
| `SessionToken` | `string` | Temporary session token. |

## Recommended Function Pattern

```powershell
function Get-MyAwsThing {
  [CmdletBinding()]
  param(
    # Function Specific Parameters here
    [Parameter()]
    [string]$FunctionParam1,
    
    [Parameter()]
    [string]$FunctionParam2,

    # AWS Common Credential and regional parameters
    [Parameter()]
    [string]$Region,

    [Parameter()]
    [string]$ProfileName,

    [Parameter()]
    [string]$AccessKey,

    [Parameter()]
    [string]$SecretKey,

    [Parameter()]
    [string]$SessionToken,

    [Parameter()]
    [Amazon.Runtime.AWSCredentials]$Credential,

    [Parameter()]
    [string]$ProfileLocation,

    [Parameter()]
    [string]$EndpointUrl
  )

  begin {
    $awsParams = New-AWSParamSplat -BoundParameters $PSBoundParameters
  }

  process {
    Get-SomeAwsCmdlet @awsParams
  }
}
```

## Notes

- `New-AWSParamSplat` filters out any parameter that is not part of the shared AWS set.
- It excludes null values and empty strings.
- It returns an ordered splat so downstream calls see a predictable parameter order.
- Keep wrapper functions typed consistently as `Amazon.Runtime.AWSCredentials` to match AWS cmdlet help and avoid treating this value as a plain string.

## When To Use It

Use this pattern for new AWS component functions in:

- `src/CharlandCustomizations/Public/AWS/AWSCustomizations.psm1`
- `src/CharlandCustomizations/Public/AWS/CloudFormation/CloudFormation-TemplateProcessing.psm1`
- `src/CharlandCustomizations/Public/AWS/Audit/Audit-AWSAccount.psm1`
- `src/CharlandCustomizations/Public/AWS/S3/S3Customizations.psm1`

If a new feature does not need all of these parameters, only include the ones it actually uses, but keep the names and types consistent with the shared pattern.
