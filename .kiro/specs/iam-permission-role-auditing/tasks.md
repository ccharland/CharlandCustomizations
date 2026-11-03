# Implementation Plan: IAM Permission Role Auditing

## Overview

Implement `Get-CHARPrincipalPermission` and its private helpers inside
`src/CharlandCustomizations/Public/AWS/IAM/IAM-Customizations.psm1`, then export the
public function and register it in the module manifest. The build proceeds
bottom-up: pure helpers first (ARN parsing, glob overlap), then policy aggregation,
then the public function's matching/verdict/output logic, then wiring/export, then
Pester tests. Each step builds on the previous so there is no orphaned code.

Language: PowerShell (matches the existing module). All new code carries the Kiro
attribution note. Property tests are included because the design defines a
Correctness Properties section.

## Tasks

- [x] 1. Implement ARN parsing helper
  - [x] 1.1 Add `Resolve-CHARPrincipalArn` private helper to `IAM-Customizations.psm1`
    - Parse `arn:aws:iam::<12-digit-account>:(role|user|group)/<path><name>` with a regex
    - Return `[PSCustomObject]@{ Type = Role|User|Group ; Name = <trailing name segment> }`, TitleCasing the resource keyword
    - `throw` a terminating error for malformed / non-IAM ARNs, naming the supplied value and the expected role/user/group formats
    - Include comment-based help with `.NOTES` Kiro attribution
    - _Requirements: 1.1, 1.2, 1.3, 1.4_

  - [x]* 1.2 Write property + example tests for ARN parsing
    - **Property 1: Principal type derivation from ARN** — random account ids, paths, and name chars for role/user/group ARNs
    - **Property 2: Invalid ARN produces a terminating error** — assert `{ ... } | Should -Throw` and message contains the value + expected formats
    - **Validates: Requirements 1.1, 1.2, 1.3, 1.4**

- [x] 2. Implement bidirectional wildcard overlap helper
  - [x] 2.1 Add `Test-CHARGlobIntersect` private helper implementing the memoized glob-intersection recurrence
    - Decide whether two `*`/`?` glob patterns share at least one concrete string via the `Intersect(i, j)` dynamic program from the design
    - Operate on lowercased patterns; `O(len(A) * len(B))`, no action-space enumeration
    - _Requirements: 3.1, 3.2, 3.6_

  - [x] 2.2 Add `Test-CHARIamActionOverlap` private helper wrapping the intersection
    - Lowercase both patterns (case-insensitive service prefix + action name), fast-path bare `*`, delegate to `Test-CHARGlobIntersect`
    - Return `[bool]`; symmetric by construction
    - Include comment-based help with `.NOTES` Kiro attribution
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6_

  - [x]* 2.3 Write property tests for wildcard overlap
    - **Property 6: Bidirectional wildcard overlap match** — overlapping pairs match, disjoint pairs do not, and `A,B == B,A`
    - **Property 7: Case-insensitive action matching** — re-casing either pattern does not change the result
    - **Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5, 3.6**

  - [x]* 2.4 Write example tests for the required overlap cases
    - `ec2:GetInstance` vs `ec2:Get*` → match; `ec2:GetInstance` vs `*` → match; `ec2:Describe*` vs `ec2:*` → match; `ec2:GetInstance` vs `s3:Get*` → no match
    - _Requirements: 3.3, 3.4, 3.5_

- [x] 3. Checkpoint - Ensure helper tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 4. Implement policy aggregation helper
  - [x] 4.1 Add `Get-CHARPrincipalPolicyDocument` private helper to `IAM-Customizations.psm1`
    - Select the Role/User/Group cmdlet family once from `Principal_Type`
    - Managed: `Get-IAM{Role|User|Group}AttachedPolicyList` → `Get-IAMPolicy` (DefaultVersionId) → `Get-IAMPolicyVersion` (default doc)
    - Inline: `Get-IAM{Role|User|Group}PolicyList` → `Get-IAM{Role|User|Group}Policy` (doc)
    - URL-decode with `[System.Web.HttpUtility]::UrlDecode`, then `ConvertFrom-Json`; forward `@awsParams`
    - Never call `Get-IAMGroupForUser`; never read permissions-boundary attributes
    - Emit normalized statements tagged with `PolicyName` and `PolicyType` (`Managed`|`Inline`)
    - Include comment-based help with `.NOTES` Kiro attribution
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6_

  - [x] 4.2 Add per-policy failure resilience to `Get-CHARPrincipalPolicyDocument`
    - Wrap each document retrieval/parse in `try/catch` with `-ErrorAction Stop`
    - On failure `Write-Warning` including the policy identifier and `continue` to the next policy
    - _Requirements: 2.7_

  - [x]* 4.3 Write property tests for aggregation
    - **Property 3: Policy aggregation completeness** — every attached managed + inline policy contributes ≥ 1 record; nothing from group-inherited policies or boundaries
    - **Property 4: Policy document decode/parse round-trip** — URL-encoded docs decode/parse to equivalent statements
    - **Validates: Requirements 2.1, 2.2, 2.3, 2.4, 2.5, 2.6**

  - [x]* 4.4 Write property test for failure resilience
    - **Property 5: Per-policy failure resilience** — one failing document yields a warning with its identifier and records for all others
    - **Validates: Requirements 2.7**

- [x] 5. Implement the public function skeleton, statement normalization, and matching
  - [x] 5.1 Add `Get-CHARPrincipalPermission` public function signature and pipeline scaffolding
    - `[CmdletBinding()]`, `[OutputType([PSCustomObject])]`; mandatory pipeline-bound `-PrincipalArn` (alias `Arn`, `PrincipalArn`), optional `-Action`, `-Effect` (`ValidateSet('Allow','Deny')`), and the full AWS common parameter set
    - Build `$awsParams` via `New-AWSParamSplat -BoundParameters $PSBoundParameters`
    - Call `Resolve-CHARPrincipalArn`, then `Get-CHARPrincipalPolicyDocument`
    - Include comment-based help: `.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER` per parameter, `.OUTPUTS`, ≥ 1 `.EXAMPLE`, `.NOTES` Kiro attribution
    - _Requirements: 7.1, 7.2, 7.3, 7.5_

  - [x] 5.2 Implement statement normalization and action matching
    - Normalize `Statement`, `Action`, `Resource` to arrays; read scalar `Effect`
    - When `-Action` supplied, match statements via `Test-CHARIamActionOverlap`; when omitted, treat every statement as reported
    - _Requirements: 3.1, 3.2, 3.7_

  - [x]* 5.3 Write example + property tests for matching / no-query behavior
    - Example: type derivation feeds matching for Role/User/Group ARNs (mocked cmdlets)
    - **Property 8: No query reports all statements** — omitting `-Action` yields a record per aggregated statement
    - **Validates: Requirements 3.7, 8.2, 8.4**

- [x] 6. Implement effect filtering and verdict computation
  - [x] 6.1 Implement Effect filtering that always surfaces Deny
    - `Allow` → matching Allow + all matching Deny; `Deny` → matching Deny; unset → both effects
    - _Requirements: 4.1, 4.2, 4.3, 4.4_

  - [x] 6.2 Implement `Effective_Access_Verdict` over the matching set (pre-display-filter)
    - `Deny` if any matching Deny; else `Allow` if any matching Allow; else `ImplicitDeny`; only when `-Action` supplied
    - _Requirements: 5.1, 5.2, 5.3, 5.4_

  - [x]* 6.3 Write property tests for filtering and verdict
    - **Property 9: Effect filtering always surfaces Deny**
    - **Property 10: Effective-access verdict precedence**
    - **Validates: Requirements 4.1, 4.2, 4.3, 4.4, 5.1, 5.2, 5.3, 5.4, 6.4**

  - [x]* 6.4 Write example tests for the required verdict cases
    - Verdict `Deny` when a matching Deny coexists with a matching Allow; verdict `ImplicitDeny` when nothing matches the query
    - _Requirements: 8.5, 8.6_

- [x] 7. Implement structured Permission_Record output
  - [x] 7.1 Emit `Permission_Record` PSCustomObjects
    - Build `[PSCustomObject]` with `PSTypeName = 'AWS.IAM.PrincipalPermission'` and fields `PrincipalArn`, `PrincipalType`, `PolicyName`, `PolicyType`, `Effect`, `Action` (matched Policy_Action), `Resource` (array); set `Verdict` only when `-Action` supplied
    - Wire verdict from task 6.2 into the emitted records
    - _Requirements: 6.1, 6.2, 6.3, 6.4_

  - [x]* 7.2 Write property test for record structure
    - **Property 11: Permission_Record structure completeness** — each item is a `[PSCustomObject]` bearing the PSTypeName with all required fields populated
    - **Validates: Requirements 6.1, 6.2, 6.3**

- [x] 8. Wire up export and manifest registration
  - [x] 8.1 Add `Get-CHARPrincipalPermission` to `Export-ModuleMember` in `IAM-Customizations.psm1`
    - Export only the public function; keep helpers private
    - _Requirements: 7.4_

  - [x] 8.2 Register `Get-CHARPrincipalPermission` in the module manifest `FunctionsToExport`
    - Keep the manifest in sync so `Test-ManifestCompliance` stays green
    - _Requirements: 7.4_

  - [x]* 8.3 Write convention/wiring tests
    - Assert `-PrincipalArn` is mandatory; assert supplying `-ProfileName`/`-Region` forwards them to the mocked AWS cmdlets
    - _Requirements: 7.2, 7.5_

- [x] 9. Final checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional test sub-tasks and can be skipped for a faster MVP.
- Each task references specific requirements (and design properties where applicable) for traceability.
- Property tests use in-test random generators driving a `1..100 | ForEach-Object` loop inside a Pester `It`, tagged `Feature: iam-permission-role-auditing, Property N: <text>`; PowerShell has no first-class PBT framework in this repo.
- All AWS cmdlets are mocked in tests via Pester `Mock`; no live AWS calls occur. `New-AWSParamSplat` remains real so splat wiring is exercised.
- Checkpoints ensure incremental validation after the pure helpers and again at the end.
- Every new file/function carries the Kiro attribution note per module standards.

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1", "2.1"] },
    { "id": 1, "tasks": ["1.2", "2.2"] },
    { "id": 2, "tasks": ["2.3", "2.4", "4.1"] },
    { "id": 3, "tasks": ["4.2", "4.3", "4.4"] },
    { "id": 4, "tasks": ["5.1"] },
    { "id": 5, "tasks": ["5.2"] },
    { "id": 6, "tasks": ["5.3", "6.1"] },
    { "id": 7, "tasks": ["6.2"] },
    { "id": 8, "tasks": ["6.3", "6.4", "7.1"] },
    { "id": 9, "tasks": ["7.2", "8.1"] },
    { "id": 10, "tasks": ["8.2"] },
    { "id": 11, "tasks": ["8.3"] }
  ]
}
```

---
Authored by Kiro (Claude Opus 4.8), reviewed by ccharland, on 2026-08-06.
