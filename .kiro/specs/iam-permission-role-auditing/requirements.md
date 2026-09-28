# Requirements Document

## Introduction

This feature adds a new public function, `Get-CHARPrincipalPermission`, to the
`IAM-Customizations.psm1` module. The function reports and formats the permissions
assigned to a single IAM principal (Role, User, or Group) by aggregating the
principal's directly attached managed policies and inline policies. It derives the
principal type from the supplied ARN, supports bidirectional wildcard matching of a
queried action against policy-side actions, and computes an effective-access verdict
that mirrors AWS IAM's rule that an explicit Deny overrides any Allow.

Scope is intentionally limited to a single hop of policy resolution on the named
principal: the function does not resolve group memberships for users, does not
evaluate permissions boundaries, service control policies, session policies, or
resource-based policies.

## Glossary

- **Function**: The `Get-CHARPrincipalPermission` PowerShell function defined in this specification.
- **Principal**: An IAM identity — a Role, User, or Group — identified by an ARN.
- **Principal_Type**: The classification of the Principal as `Role`, `User`, or `Group`, derived from the ARN resource segment.
- **Principal_ARN**: The Amazon Resource Name supplied as input identifying the Principal (for example `arn:aws:iam::123456789012:role/example`).
- **Managed_Policy**: An IAM managed policy attached directly to the Principal.
- **Inline_Policy**: An IAM inline policy embedded directly on the Principal.
- **Policy_Statement**: A single statement element within a policy document, containing an Effect, Action set, and Resource set.
- **Policy_Action**: An action pattern present in a Policy_Statement, which may contain wildcard characters (for example `ec2:Get*`, `ec2:*`, `*`).
- **Query_Action**: The action pattern supplied by the caller to test against the Principal's permissions, which may contain wildcard characters.
- **Effect**: The value of a Policy_Statement's Effect element, either `Allow` or `Deny`.
- **Effective_Access_Verdict**: The computed access outcome for a Query_Action, expressed as `Allow`, `Deny`, or `ImplicitDeny`, where an explicit Deny overrides any Allow.
- **Bidirectional_Match**: A wildcard comparison that reports a match when the Query_Action pattern and the Policy_Action pattern overlap in at least one concrete action, regardless of which side contains the wildcard.
- **AWS_Common_Parameter**: A shared AWS connection parameter (Region, ProfileName, AccessKey, SecretKey, SessionToken, Credential, ProfileLocation, EndpointUrl) supplied to AWS API calls via `New-AWSParamSplat`.
- **Permission_Record**: A `[PSCustomObject]` output item with a `PSTypeName` describing one matched Policy_Statement's contribution to the Principal's permissions.

## Requirements

### Requirement 1: Principal type derivation from ARN

**User Story:** As an AWS operator, I want the Function to determine the Principal type from the supplied ARN, so that I do not have to specify the type separately.

#### Acceptance Criteria

1. WHEN the Principal_ARN resource segment begins with `role/`, THE Function SHALL set the Principal_Type to `Role`.
2. WHEN the Principal_ARN resource segment begins with `user/`, THE Function SHALL set the Principal_Type to `User`.
3. WHEN the Principal_ARN resource segment begins with `group/`, THE Function SHALL set the Principal_Type to `Group`.
4. IF the Principal_ARN does not match a Role, User, or Group IAM ARN format, THEN THE Function SHALL terminate with an error message stating the supplied ARN value and the expected IAM ARN formats.

### Requirement 2: Policy aggregation on the principal

**User Story:** As an AWS operator, I want the Function to collect all policies attached directly to the Principal, so that I can review the Principal's permissions in one place.

#### Acceptance Criteria

1. WHEN the Function retrieves permissions for a Principal, THE Function SHALL enumerate every Managed_Policy attached directly to the Principal.
2. WHEN the Function retrieves permissions for a Principal, THE Function SHALL enumerate every Inline_Policy embedded directly on the Principal.
3. THE Function SHALL exclude policies inherited through Group membership from the aggregation.
4. THE Function SHALL exclude permissions boundaries from the aggregation.
5. WHEN the Function processes a Managed_Policy, THE Function SHALL retrieve the policy document for the default policy version.
6. WHEN the Function reads a policy document, THE Function SHALL URL-decode the policy document before parsing.
7. IF retrieval of a single policy document fails, THEN THE Function SHALL emit a warning that includes the policy identifier and SHALL continue processing the remaining policies.

### Requirement 3: Action matching with bidirectional wildcards

**User Story:** As an AWS operator, I want to test whether a specific action is permitted using wildcard patterns on either side, so that I can find matching permissions regardless of how the policy authors expressed the action.

#### Acceptance Criteria

1. WHERE a Query_Action is supplied, THE Function SHALL evaluate each Policy_Action against the Query_Action using a Bidirectional_Match.
2. WHEN the Query_Action pattern and a Policy_Action pattern overlap in at least one concrete action, THE Function SHALL report the Policy_Statement as a match.
3. WHEN the Query_Action is `ec2:GetInstance` and a Policy_Action is `ec2:Get*`, THE Function SHALL report a match.
4. WHEN the Query_Action is `ec2:GetInstance` and a Policy_Action is `*`, THE Function SHALL report a match.
5. WHEN the Query_Action is `ec2:Describe*` and a Policy_Action is `ec2:*`, THE Function SHALL report a match.
6. WHEN the wildcard comparison is performed, THE Function SHALL treat the service prefix and action name as case-insensitive.
7. WHERE no Query_Action is supplied, THE Function SHALL report all Policy_Statement records for the Principal.

### Requirement 4: Effect filtering and Deny surfacing

**User Story:** As an AWS operator, I want to optionally filter results by Effect while still always seeing Deny statements, so that I never overlook an explicit Deny when assessing access.

#### Acceptance Criteria

1. WHERE the Effect filter is set to `Allow`, THE Function SHALL include Policy_Statement records whose Effect is `Allow`.
2. WHERE the Effect filter is set to `Deny`, THE Function SHALL include Policy_Statement records whose Effect is `Deny`.
3. WHERE the Effect filter is set to `Allow`, THE Function SHALL also include matching Policy_Statement records whose Effect is `Deny`.
4. WHERE no Effect filter is supplied, THE Function SHALL include Policy_Statement records for both `Allow` and `Deny` effects.

### Requirement 5: Effective-access verdict

**User Story:** As an AWS operator, I want a single verdict summarizing whether the queried action is effectively allowed, so that I can quickly judge the Principal's access.

#### Acceptance Criteria

1. WHERE a Query_Action is supplied, THE Function SHALL compute an Effective_Access_Verdict for that Query_Action.
2. IF at least one matching Policy_Statement has an Effect of `Deny`, THEN THE Function SHALL set the Effective_Access_Verdict to `Deny`.
3. WHEN no matching Policy_Statement has an Effect of `Deny` AND at least one matching Policy_Statement has an Effect of `Allow`, THE Function SHALL set the Effective_Access_Verdict to `Allow`.
4. IF no Policy_Statement matches the Query_Action, THEN THE Function SHALL set the Effective_Access_Verdict to `ImplicitDeny`.

### Requirement 6: Structured output

**User Story:** As an AWS operator, I want structured, typed output objects, so that I can filter, format, and pipe the results in PowerShell.

#### Acceptance Criteria

1. WHEN the Function emits a matched permission, THE Function SHALL output a Permission_Record as a `[PSCustomObject]`.
2. THE Function SHALL assign a `PSTypeName` value to each Permission_Record.
3. WHEN the Function emits a Permission_Record, THE Permission_Record SHALL include the source policy name, the source policy type, the Effect, the matched Policy_Action, and the resource set of the Policy_Statement.
4. WHERE a Query_Action is supplied, THE Function SHALL include the Effective_Access_Verdict in the output.

### Requirement 7: AWS connection parameters and naming conventions

**User Story:** As a module maintainer, I want the Function to follow the module's established conventions, so that it integrates consistently with the rest of the module.

#### Acceptance Criteria

1. THE Function SHALL be named `Get-CHARPrincipalPermission` following the Verb-CHARNoun naming convention.
2. THE Function SHALL accept the AWS_Common_Parameter set and pass those parameters to AWS API calls via `New-AWSParamSplat`.
3. THE Function SHALL provide comment-based help that includes synopsis, description, parameter documentation, output documentation, at least one example, and a Kiro attribution note.
4. THE Function SHALL be exported through `Export-ModuleMember`.
5. WHEN the Principal_ARN is supplied, THE Function SHALL accept the Principal_ARN as a mandatory parameter.

### Requirement 8: Automated tests

**User Story:** As a module maintainer, I want Pester tests for the Function, so that its behavior is verified and protected against regressions.

#### Acceptance Criteria

1. THE Function SHALL be covered by Pester tests located at `tests/src/Public/AWS/IAM/`.
2. THE Pester tests SHALL cover Principal_Type derivation for Role, User, and Group ARNs.
3. THE Pester tests SHALL cover an invalid Principal_ARN producing a terminating error.
4. THE Pester tests SHALL cover Bidirectional_Match cases including a wildcard Policy_Action and a wildcard Query_Action.
5. THE Pester tests SHALL cover an Effective_Access_Verdict of `Deny` where a matching Deny statement coexists with a matching Allow statement.
6. THE Pester tests SHALL cover an Effective_Access_Verdict of `ImplicitDeny` where no Policy_Statement matches the Query_Action.

---
Authored by Kiro (Claude Opus 4.8), reviewed by ccharland, on 2026-08-06.
