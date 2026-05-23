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

## Task 4: Refactor all existing AWS functions to use `New-AWSParamSplat`
- [ ] Update `Find-CFNStackErrors` in AWSCustomizations.psm1
- [ ] Update `Start-MultiStackDriftDetection` in AWSCustomizations.psm1
- [ ] Update `Get-AWSAccountListOfDriftedResources` in AWSCustomizations.psm1
- [ ] Update `Get-AWSObjectCount` in AWSCustomizations.psm1
- [ ] Update `Set-AWSProfileWithMFA` in AWSCustomizations.psm1
- [ ] Update `Update-SSOCredentialList` in AWSCustomizations.psm1
- [ ] Update `Invoke-ScriptMultiAccountRegion` in Public/Invoke-ScriptMultiAccountRegion.ps1
- [ ] Update all functions in CloudFormation-TemplateProcessing.psm1
- [ ] Update all functions in S3Customizations.psm1 (if present)
- [ ] Update all functions in Audit-AWSAccount.psm1 (if present)
- [ ] Add full AWS common parameter set to each updated function
- [ ] Remove all manual `$AwsParams` / `$awsParams` hashtable construction
- [ ] Verify each function still works with just `-Region` and `-ProfileName`
