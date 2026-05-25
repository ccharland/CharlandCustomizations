# Tasks: AWS Common Credential and Region Parameter Splatting

## Task 1: Create `New-AWSParamSplat` private helper function
- [x] Create `src/CharlandCustomizations/Private/New-AWSParamSplat.ps1`
- [x] Implement filtering logic against known AWS common parameter names
- [x] Include comment-based help with synopsis, description, parameters, and examples
- [x] Verify the function is dot-sourced by the module loader (Private/*.ps1)

## Task 2: Create Pester tests for `New-AWSParamSplat`
- [x] Create `tests/New-AWSParamSplat.Tests.ps1`
- [x] Test: returns only AWS common keys when mixed parameters are passed
- [x] Test: returns empty hashtable when no AWS params are in BoundParameters
- [x] Test: handles all 8 supported parameter names
- [x] Test: excludes non-AWS parameters (e.g., StackName, Force)

## Task 3: Update steering documentation
- [x] Update `.kiro/steering/powershell-module-development.md`
- [x] Replace the existing splatting section with the new `New-AWSParamSplat` pattern
- [x] Include the standard parameter block template
- [x] Note backward compatibility with the old pattern

## Task 4: Refactor all existing AWS functions to use `New-AWSParamSplat`
- [x] Update `Find-CFNStackErrors` in AWSCustomizations.psm1
- [x] Update `Start-MultiStackDriftDetection` in AWSCustomizations.psm1
- [x] Update `Get-AWSAccountListOfDriftedResources` in AWSCustomizations.psm1
- [x] Update `Get-AWSObjectCount` in AWSCustomizations.psm1
- [x] Update `Set-AWSProfileWithMFA` in AWSCustomizations.psm1
- [x] Update `Update-SSOCredentialList` in AWSCustomizations.psm1
- [x] Update `Invoke-ScriptMultiAccountRegion` in Public/Invoke-ScriptMultiAccountRegion.ps1
- [x] Update all functions in CloudFormation-TemplateProcessing.psm1
- [x] Update all functions in S3Customizations.psm1 (if present)
- [x] Update all functions in Audit-AWSAccount.psm1 (if present)
- [x] Add full AWS common parameter set to each updated function
- [x] Remove all manual `$AwsParams` / `$awsParams` hashtable construction
- [x] Verify each function still works with just `-Region` and `-ProfileName`
