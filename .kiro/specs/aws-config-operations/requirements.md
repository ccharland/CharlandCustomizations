# Requirements Document

## Introduction

This document specifies the requirements for a new PowerShell module (`Config-Operations.psm1`) providing AWS Config service operations within the CharlandCustomizations project. The module delivers four functions that query AWS Config for resource lifecycle data (creation/deletion dates with CloudTrail event correlation) and compliance status. All functions follow the established project patterns: `Verb-CHARNoun` naming, `New-AWSParamSplat` for credential splatting, `Test-CHARAWSCmdlet` for cmdlet validation, and PSCustomObject output for pipeline compatibility.

## Glossary

- **Config_Module**: The PowerShell module file `Config-Operations.psm1` located at `src/CharlandCustomizations/Public/AWS/Config/`.
- **AWS_Config**: The AWS Config service that records resource configurations and evaluates compliance rules.
- **CloudTrail**: The AWS CloudTrail service that logs API activity including resource creation and deletion events.
- **Config_Rule**: An AWS Config rule that evaluates resource compliance against a defined policy.
- **Resource_Identifier**: A combination of resource ID and resource type used to query AWS Config resource history.
- **AWSParamSplat**: The hashtable produced by `New-AWSParamSplat` containing only the AWS common credential/region parameters that were bound by the caller.
- **CmdletValidation**: The pre-flight check performed by `Test-CHARAWSCmdlet` that verifies required AWS Tools cmdlets are available and offers to install missing modules.
- **PSCustomObject**: A PowerShell custom object used as the standard output type for pipeline-friendly data.
- **Operator**: A PowerShell user running CharlandCustomizations functions to query AWS account resources.

## Requirements

### Requirement 1: Module File Structure

**User Story:** As an operator, I want the Config operations functions in a single module file following the established project pattern, so that the module integrates consistently with the rest of CharlandCustomizations.

#### Acceptance Criteria

1. THE Config_Module SHALL exist as a single `.psm1` file at `src/CharlandCustomizations/Public/AWS/Config/Config-Operations.psm1`.
2. THE Config_Module SHALL dot-source the `New-AWSParamSplat.ps1` private helper using a relative path from the module location.
3. THE Config_Module SHALL dot-source the `Test-CHARAWSCmdlet.ps1` public helper using a relative path from the module location.
4. THE Config_Module SHALL contain all four Config operation functions within the single file.
5. THE Config_Module SHALL include PowerShell comment-based help at the module level with Synopsis, Description, and Notes sections.

### Requirement 2: AWS Common Parameter Support

**User Story:** As an operator, I want each function to accept standard AWS credential and region parameters, so that I can target any account or region without modifying my session defaults.

#### Acceptance Criteria

1. WHEN an operator invokes any Config_Module function, THE Config_Module SHALL accept the following optional parameters: Region, ProfileName, AccessKey, SecretKey, SessionToken, Credential, ProfileLocation, EndpointUrl.
2. THE Config_Module SHALL pass the caller's `$PSBoundParameters` to `New-AWSParamSplat` in the `begin` block of each function to build the AWS parameter splat hashtable.
3. THE Config_Module SHALL apply the resulting splat hashtable to all AWS cmdlet calls within each function.
4. WHEN no AWS common parameters are provided, THE Config_Module SHALL rely on the caller's existing session defaults for authentication and region.

### Requirement 3: Cmdlet Validation

**User Story:** As an operator, I want the module to verify required AWS cmdlets are available before making API calls, so that I receive clear guidance on missing modules rather than cryptic errors.

#### Acceptance Criteria

1. THE Config_Module SHALL call `Test-CHARAWSCmdlet` in the `begin` block of each function, passing all AWS cmdlet names that function requires.
2. IF a required AWS cmdlet is unavailable, THEN THE Config_Module SHALL propagate the terminating error from `Test-CHARAWSCmdlet` without continuing execution.

### Requirement 4: Get-CHARConfigResourceCreationDate Function

**User Story:** As an operator, I want to determine when an AWS resource was created and by whom, so that I can perform resource lifecycle auditing and track resource ownership.

#### Acceptance Criteria

1. THE Config_Module SHALL export a function named `Get-CHARConfigResourceCreationDate`.
2. THE `Get-CHARConfigResourceCreationDate` function SHALL accept a mandatory `ResourceId` parameter of type string.
3. THE `Get-CHARConfigResourceCreationDate` function SHALL accept a mandatory `ResourceType` parameter of type string representing the AWS Config resource type (e.g., `AWS::EC2::Instance`).
4. WHEN invoked, THE `Get-CHARConfigResourceCreationDate` function SHALL query AWS Config resource history to identify the earliest recorded configuration item for the specified resource.
5. WHEN a creation record is found in AWS Config, THE `Get-CHARConfigResourceCreationDate` function SHALL query CloudTrail for the corresponding resource creation event to retrieve the principal name and API event details.
6. THE `Get-CHARConfigResourceCreationDate` function SHALL return a PSCustomObject with the following properties: ResourceId, ResourceType, CreationDate, PrincipalName, EventName, EventSource.
7. WHEN CloudTrail event data is unavailable for the resource creation, THE `Get-CHARConfigResourceCreationDate` function SHALL return the PSCustomObject with PrincipalName, EventName, and EventSource set to `$null`.
8. IF the specified resource has no configuration history in AWS Config, THEN THE `Get-CHARConfigResourceCreationDate` function SHALL write a warning message identifying the resource and return `$null`.
9. THE `Get-CHARConfigResourceCreationDate` function SHALL accept pipeline input for the `ResourceId` parameter.

### Requirement 5: Get-CHARConfigResourceDeleteDate Function

**User Story:** As an operator, I want to determine when an AWS resource was deleted and by whom, so that I can investigate unexpected resource removals and maintain audit trails.

#### Acceptance Criteria

1. THE Config_Module SHALL export a function named `Get-CHARConfigResourceDeleteDate`.
2. THE `Get-CHARConfigResourceDeleteDate` function SHALL accept a mandatory `ResourceId` parameter of type string.
3. THE `Get-CHARConfigResourceDeleteDate` function SHALL accept a mandatory `ResourceType` parameter of type string representing the AWS Config resource type.
4. WHEN invoked, THE `Get-CHARConfigResourceDeleteDate` function SHALL query AWS Config resource history to identify the configuration item with a `ResourceDeleted` status for the specified resource.
5. WHEN a deletion record is found in AWS Config, THE `Get-CHARConfigResourceDeleteDate` function SHALL query CloudTrail for the corresponding resource deletion event to retrieve the principal name and API event details.
6. THE `Get-CHARConfigResourceDeleteDate` function SHALL return a PSCustomObject with the following properties: ResourceId, ResourceType, DeletionDate, PrincipalName, EventName, EventSource.
7. WHEN CloudTrail event data is unavailable for the resource deletion, THE `Get-CHARConfigResourceDeleteDate` function SHALL return the PSCustomObject with PrincipalName, EventName, and EventSource set to `$null`.
8. IF the specified resource has no deletion record in AWS Config, THEN THE `Get-CHARConfigResourceDeleteDate` function SHALL write a warning message indicating the resource has not been deleted or has no deletion history, and return `$null`.
9. THE `Get-CHARConfigResourceDeleteDate` function SHALL accept pipeline input for the `ResourceId` parameter.

### Requirement 6: Get-CHARConfigNonCompliantResource Function

**User Story:** As an operator, I want to retrieve all non-compliant resources for a given AWS Config rule, so that I can quickly identify resources that violate compliance policies.

#### Acceptance Criteria

1. THE Config_Module SHALL export a function named `Get-CHARConfigNonCompliantResource`.
2. THE `Get-CHARConfigNonCompliantResource` function SHALL accept a mandatory `ConfigRuleName` parameter of type string.
3. WHEN invoked, THE `Get-CHARConfigNonCompliantResource` function SHALL query AWS Config for all resources evaluated as non-compliant by the specified Config rule.
4. THE `Get-CHARConfigNonCompliantResource` function SHALL return a collection of PSCustomObjects with the following properties: ResourceId, ResourceType, ComplianceType, ConfigRuleName.
5. IF the specified Config rule does not exist, THEN THE `Get-CHARConfigNonCompliantResource` function SHALL write an error message identifying the rule name and terminate.
6. WHEN the specified Config rule has no non-compliant resources, THE `Get-CHARConfigNonCompliantResource` function SHALL write a verbose message indicating full compliance and return an empty collection.
7. THE `Get-CHARConfigNonCompliantResource` function SHALL accept pipeline input for the `ConfigRuleName` parameter.

### Requirement 7: Get-CHARConfigResourceComplianceReport Function

**User Story:** As an operator, I want to see which Config rules a specific resource is compliant or non-compliant with, so that I can assess the overall compliance posture of an individual resource.

#### Acceptance Criteria

1. THE Config_Module SHALL export a function named `Get-CHARConfigResourceComplianceReport`.
2. THE `Get-CHARConfigResourceComplianceReport` function SHALL accept a mandatory `ResourceId` parameter of type string.
3. THE `Get-CHARConfigResourceComplianceReport` function SHALL accept a mandatory `ResourceType` parameter of type string representing the AWS Config resource type.
4. WHEN invoked, THE `Get-CHARConfigResourceComplianceReport` function SHALL query AWS Config for all compliance evaluation results associated with the specified resource.
5. THE `Get-CHARConfigResourceComplianceReport` function SHALL return a collection of PSCustomObjects with the following properties: ResourceId, ResourceType, ConfigRuleName, ComplianceType, LastEvaluatedTime.
6. WHEN the resource has no compliance evaluation results, THE `Get-CHARConfigResourceComplianceReport` function SHALL write a warning message indicating no Config rules have evaluated the resource and return an empty collection.
7. THE `Get-CHARConfigResourceComplianceReport` function SHALL accept pipeline input for the `ResourceId` parameter.

### Requirement 8: Output Format and Pipeline Compatibility

**User Story:** As an operator, I want all function outputs as PSCustomObjects, so that I can pipe results to standard PowerShell formatting, filtering, and export cmdlets.

#### Acceptance Criteria

1. THE Config_Module SHALL output PSCustomObjects from all four functions using ordered property hashtables for consistent property ordering.
2. THE Config_Module SHALL support pipeline chaining by outputting individual objects to the pipeline rather than collecting results into a single array before output.
3. WHEN multiple results are returned, THE Config_Module SHALL emit each PSCustomObject individually to the output stream.

### Requirement 9: Error Handling

**User Story:** As an operator, I want clear and actionable error messages when operations fail, so that I can quickly diagnose and resolve issues.

#### Acceptance Criteria

1. IF an AWS API call fails due to insufficient permissions, THEN THE Config_Module SHALL write an error message that includes the specific action that failed and the AWS error message.
2. IF an AWS API call fails due to a service exception, THEN THE Config_Module SHALL write an error message including the service name, operation, and exception detail.
3. THE Config_Module SHALL use `Write-Verbose` for operational progress messages within each function.
4. THE Config_Module SHALL use `Write-Warning` for conditions where expected data is absent but execution can continue.
5. THE Config_Module SHALL use `Write-Error` for conditions where the operation cannot produce meaningful results.

### Requirement 10: Function Documentation

**User Story:** As an operator, I want comprehensive comment-based help on each function, so that I can discover usage, parameters, and examples through `Get-Help`.

#### Acceptance Criteria

1. THE Config_Module SHALL include comment-based help for each exported function containing: Synopsis, Description, Parameter documentation for all parameters, at least two Example sections, and a Notes section with attribution.
2. THE Config_Module SHALL document the AWS common parameters (Region, ProfileName, AccessKey, SecretKey, SessionToken, Credential, ProfileLocation, EndpointUrl) in each function's help.
3. THE Config_Module SHALL include the Kiro attribution line in the Notes section of each function's comment-based help.
