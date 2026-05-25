# Design: AWS Common Credential and Region Parameter Splatting

## Architecture

### Component: `New-AWSParamSplat` (Private Function)

**Location:** `src/CharlandCustomizations/Private/New-AWSParamSplat.ps1`

**Signature:**
```powershell
function New-AWSParamSplat {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.Generic.Dictionary[string, object]]$BoundParameters
    )
}
```

**Logic:**
1. Define the set of known AWS common parameter names
2. Iterate over `$BoundParameters`
3. Include only keys that match the known AWS parameter names
4. Return the filtered hashtable

### Usage Pattern

Each AWS function adopts this standard structure:

```powershell
function Get-SomethingFromAWS {
    [CmdletBinding()]
    param(
        # Function-specific parameters
        [Parameter(Mandatory)]
        [string]$StackName,

        # AWS common parameters
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
        $Credential,

        [Parameter()]
        [string]$ProfileLocation,

        [Parameter()]
        [string]$EndpointUrl
    )

    begin {
        $awsParams = New-AWSParamSplat -BoundParameters $PSBoundParameters
    }

    process {
        Get-CFNStack -StackName $StackName @awsParams
    }
}
```

### Why `$PSBoundParameters` Instead of Individual Parameters

- Automatically excludes parameters the caller didn't provide
- No need for `if ($Region) { ... }` checks
- Adding new AWS common params in the future only requires updating the helper's known-keys list
- Prevents accidentally splatting function-specific params into AWS cmdlets

### File Layout

```
src/CharlandCustomizations/
├── Private/
│   └── New-AWSParamSplat.ps1    # Helper function
├── Public/
│   └── AWS/
│       └── ...                   # Functions using the helper
```

### Steering Update

The `AWS Cmdlet Parameter Splatting` section in `powershell-module-development.md` will be updated to show the new pattern with `New-AWSParamSplat` while noting that the old two-parameter pattern still works for simple cases.
