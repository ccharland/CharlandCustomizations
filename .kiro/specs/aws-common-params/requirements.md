# Feature: AWS Common Credential and Region Parameter Splatting

## Overview

Create a reusable private helper function that builds a splat hashtable from the standard AWS Tools for PowerShell common credential and region parameters. This eliminates repetitive parameter-building code across all AWS functions in the module.

## Problem Statement

Currently, every AWS function in the module repeats this pattern:

```powershell
$AwsParams = @{ Region = $Region }
if ($ProfileName) { $AwsParams.ProfileName = $ProfileName }
```

This only handles `Region` and `ProfileName`, ignoring other valid credential parameters like `AccessKey`, `SecretKey`, `SessionToken`, `Credential`, `ProfileLocation`, and `EndpointUrl`. Adding support for all common parameters requires modifying every function individually.

## Requirements

### REQ-1: Private Helper Function
- Create `New-AWSParamSplat` as a private helper function in `src/CharlandCustomizations/Private/`
- The function accepts `$PSBoundParameters` from the calling function
- It returns a hashtable containing only the AWS common credential/region keys that were actually provided
- Keys with null or empty values are excluded from the output

### REQ-2: Supported AWS Common Parameters
The helper must support all standard AWS Tools for PowerShell common parameters:
- `Region` (string) — AWS region
- `ProfileName` (string) — Named credential profile
- `AccessKey` (string) — Explicit IAM access key
- `SecretKey` (string) — Explicit IAM secret key
- `SessionToken` (string) — Temporary session token
- `Credential` (AWSCredentials object) — Pre-built credential object
- `ProfileLocation` (string) — Custom credential file path
- `EndpointUrl` (string) — Custom service endpoint URL

### REQ-3: Standard Parameter Block Pattern
- Document a standard parameter block that AWS functions should include
- Parameters should use the same types and names as the native AWS cmdlets
- All credential/region parameters should be optional (not mandatory)

### REQ-4: Filtering Behavior
- The helper only includes keys present in `$PSBoundParameters` (i.e., explicitly passed by the caller)
- This prevents overriding AWS session defaults when a parameter is not specified
- Non-AWS parameters from the calling function are excluded from the output

### REQ-5: Update Steering Documentation
- Update the `powershell-module-development.md` steering file to document the new pattern
- Replace the existing `$awsParams` splatting section with the new helper-based approach

### REQ-6: Refactor All Existing AWS Functions
- All existing AWS functions in the module must be updated to use `New-AWSParamSplat`
- Replace all manual `$AwsParams` / `$awsParams` hashtable construction with the helper
- Add the full set of AWS common parameters to every function that calls AWS cmdlets
- This is a big-bang refactor while the module is in pre-release stage for consistency

## Out of Scope
- Supporting AWS credential resolution order or fallback logic
- Validating that credentials are actually valid (that's the AWS cmdlet's job)
