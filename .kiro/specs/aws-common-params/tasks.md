# Tasks: AWS Common Credential and Region Parameter Splatting

## Task 1: Create `New-AWSParamSplat` private helper function
- [ ] Create `src/CharlandCustomizations/Private/New-AWSParamSplat.ps1`
- [ ] Implement filtering logic against known AWS common parameter names
- [ ] Include comment-based help with synopsis, description, parameters, and examples
- [ ] Verify the function is dot-sourced by the module loader (Private/*.ps1)

## Task 2: Create Pester tests for `New-AWSParamSplat`
- [ ] Create `tests/New-AWSParamSplat.Tests.ps1`
- [ ] Test: returns only AWS common keys when mixed parameters are passed
- [ ] Test: returns empty hashtable when no AWS params are in BoundParameters
- [ ] Test: handles all 8 supported parameter names
- [ ] Test: excludes non-AWS parameters (e.g., StackName, Force)

## Task 3: Update steering documentation
- [ ] Update `.kiro/steering/powershell-module-development.md`
- [ ] Replace the existing splatting section with the new `New-AWSParamSplat` pattern
- [ ] Include the standard parameter block template
- [ ] Note backward compatibility with the old pattern

## Task 4: Demonstrate migration on one existing function
- [ ] Pick one function (e.g., `Find-CFNStackErrors` in AWSCustomizations.psm1)
- [ ] Add the full set of AWS common parameters
- [ ] Replace manual `$AwsParams` building with `New-AWSParamSplat`
- [ ] Verify function still works with just `-Region` and `-ProfileName`
