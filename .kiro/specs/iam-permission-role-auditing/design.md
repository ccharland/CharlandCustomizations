# Design Document

## Overview

`Get-CHARPrincipalPermission` is a new public function added to
`src/CharlandCustomizations/Public/AWS/IAM/IAM-Customizations.psm1`. It answers the
question "what can this one IAM principal do, and is a given action effectively
allowed?" by aggregating the policies attached *directly* to a single Role, User, or
Group and evaluating an optional queried action against them.

The function performs exactly one hop of resolution on the named principal. It does
**not** resolve group membership for users, and it does **not** consider permissions
boundaries, service control policies, session policies, or resource-based policies.
This bounded scope keeps the output deterministic and explainable: every emitted
record traces back to a policy that is literally attached to (or embedded in) the
named principal.

The design centers on four cooperating pieces:

1. **ARN parsing** — derive `Principal_Type` (Role/User/Group) and the principal name.
2. **Policy aggregation** — enumerate attached managed policies (resolving each to its
   default-version document) and inline policies, using the AWS Tools for PowerShell
   cmdlets, then URL-decode and parse each document into normalized statements.
3. **Bidirectional wildcard matching** — a helper that decides whether a queried IAM
   action pattern and a policy-side IAM action pattern overlap in at least one concrete
   action, with wildcards permitted on either side and case-insensitive comparison.
4. **Effect handling + verdict** — filter statements by `Effect` while always surfacing
   `Deny`, and compute a single `Effective_Access_Verdict` (`Deny` > `Allow` >
   `ImplicitDeny`).

The language is PowerShell, matching the existing module. Private helpers are defined
inside the same `.psm1` and are not exported.

## Architecture

```
Get-CHARPrincipalPermission (public)
│
├─ New-AWSParamSplat            (existing private) → $awsParams
│
├─ Resolve-CHARPrincipalArn     (new private helper)
│     └─ returns { Type = Role|User|Group ; Name = <principal name> }
│        or throws a terminating error for malformed ARNs   (Req 1)
│
├─ Get-CHARPrincipalPolicyDocument  (new private helper)
│     ├─ managed:  Get-IAM{Role|User|Group}AttachedPolicyList
│     │            → Get-IAMPolicy (DefaultVersionId)
│     │            → Get-IAMPolicyVersion (default doc)
│     ├─ inline:   Get-IAM{Role|User|Group}PolicyList
│     │            → Get-IAM{Role|User|Group}Policy (doc)
│     ├─ URL-decode → ConvertFrom-Json                        (Req 2.6)
│     └─ emit normalized statements; warn+continue on failure (Req 2.7)
│
├─ Test-CHARIamActionOverlap    (new private helper)
│     └─ bidirectional glob overlap, case-insensitive         (Req 3)
│
└─ per matched statement → build Permission_Record [PSCustomObject]
      + compute Effective_Access_Verdict                      (Req 4,5,6)
```

### Cmdlet mapping by principal type

The three principal types use parallel cmdlet families. The function selects the family
once, after ARN parsing, and reuses it for both managed and inline enumeration.

| Concern | Role | User | Group |
| --- | --- | --- | --- |
| Attached managed list | `Get-IAMAttachedRolePolicyList -RoleName` | `Get-IAMAttachedUserPolicyList -UserName` | `Get-IAMAttachedGroupPolicyList -GroupName` |
| Inline name list | `Get-IAMRolePolicyList -RoleName` | `Get-IAMUserPolicyList -UserName` | `Get-IAMGroupPolicyList -GroupName` |
| Inline document | `Get-IAMRolePolicy -RoleName -PolicyName` | `Get-IAMUserPolicy -UserName -PolicyName` | `Get-IAMGroupPolicy -GroupName -PolicyName` |
| Managed document | `Get-IAMPolicy` + `Get-IAMPolicyVersion` (shared across all types) | same | same |

`Get-IAMAttachedRolePolicyList` returns `{ PolicyName, PolicyArn }`. The managed
document is fetched by calling `Get-IAMPolicy -PolicyArn` to read `DefaultVersionId`,
then `Get-IAMPolicyVersion -PolicyArn -VersionId <default>` for the document. This
mirrors the existing `Find-CHARDeletedPrincipalPolicy` pattern (`Get-IAMPolicyVersion`
+ `[System.Web.HttpUtility]::UrlDecode` + `ConvertFrom-Json`), keeping the module
consistent.

Group membership resolution (`Get-IAMGroupForUser`) and permissions-boundary attributes
are deliberately **never** called or read (Req 2.3, 2.4).

## Components and Interfaces

### Public function signature

```powershell
function Get-CHARPrincipalPermission {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [Alias('Arn', 'PrincipalArn')]
        [string]$PrincipalArn,                       # Req 7.5 (mandatory)

        [Parameter()]
        [string]$Action,                             # Query_Action (Req 3, 5)

        [Parameter()]
        [ValidateSet('Allow', 'Deny')]
        [string]$Effect,                             # Effect filter (Req 4)

        # AWS common parameters (Req 7.2) — passed to New-AWSParamSplat
        [Parameter()] [string]$Region,
        [Parameter()] [string]$ProfileName,
        [Parameter()] [string]$AccessKey,
        [Parameter()] [string]$SecretKey,
        [Parameter()] [string]$SessionToken,
        [Parameter()] [object]$Credential,
        [Parameter()] [string]$ProfileLocation,
        [Parameter()] [string]$EndpointUrl
    )
}
```

Notes:
- `$Action` omitted ⇒ report all statements, no verdict is computed as a match filter
  (Req 3.7). The verdict field is only meaningful when `$Action` is supplied (Req 6.4).
- `$Effect` uses `ValidateSet('Allow','Deny')`. When set to `Allow`, `Deny` statements
  are still surfaced (Req 4.3); when omitted, both effects are included (Req 4.4).
- Comment-based help includes `.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER` for each
  parameter, `.OUTPUTS`, at least one `.EXAMPLE`, and a `.NOTES` Kiro attribution line
  (Req 7.3). The function is added to the module's `Export-ModuleMember` list (Req 7.4).

### Private helper: `Resolve-CHARPrincipalArn`

```powershell
function Resolve-CHARPrincipalArn {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param([Parameter(Mandatory)][string]$PrincipalArn)

    # IAM ARN: arn:aws:iam::<account>:<resourceType>/<path><name>
    # Match the resource segment to derive the principal type.
    $pattern = '^arn:aws:iam::\d{12}:(role|user|group)/(.+)$'
    $m = [regex]::Match($PrincipalArn, $pattern)

    if (-not $m.Success) {
        throw "Invalid IAM principal ARN: '$PrincipalArn'. Expected one of: " +
              "arn:aws:iam::<account-id>:role/<name>, " +
              "arn:aws:iam::<account-id>:user/<name>, " +
              "arn:aws:iam::<account-id>:group/<name>."
    }

    $resourceType = $m.Groups[1].Value            # role|user|group (lower)
    $resourcePath = $m.Groups[2].Value            # path + name, e.g. app/read-only
    $name         = ($resourcePath -split '/')[-1] # trailing name segment

    [PSCustomObject]@{
        Type = (Get-Culture).TextInfo.ToTitleCase($resourceType)  # Role|User|Group
        Name = $name
    }
}
```

`throw` produces a terminating error (Req 1.4). The message names both the supplied
value and the expected formats.

### Private helper: `Test-CHARIamActionOverlap`

This is the heart of the bidirectional match (Req 3). Two IAM action patterns overlap
when there exists at least one concrete action string matched by *both* patterns. IAM
action glob syntax supports `*` (zero-or-more chars) and `?` (single char); the only
metacharacters are `*` and `?`.

Rather than enumerate an infinite concrete-action space, the design decides overlap by
**glob intersection via regex**. A robust and simple approach that handles the IAM
cases in the requirements:

```powershell
function Test-CHARIamActionOverlap {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string]$PatternA,   # e.g. Query_Action  ec2:Describe*
        [Parameter(Mandatory)][string]$PatternB    # e.g. Policy_Action  ec2:*
    )

    # Normalize case: IAM service prefix + action name are case-insensitive (Req 3.6).
    $a = $PatternA.ToLowerInvariant()
    $b = $PatternB.ToLowerInvariant()

    # Fast path: a bare '*' overlaps everything.
    if ($a -eq '*' -or $b -eq '*') { return $true }

    # Convert an IAM glob to a .NET regex anchored to the whole string.
    $toRegex = {
        param($glob)
        $sb = [System.Text.StringBuilder]::new('^')
        foreach ($ch in $glob.ToCharArray()) {
            switch ($ch) {
                '*'     { [void]$sb.Append('.*') }
                '?'     { [void]$sb.Append('.') }
                default { [void]$sb.Append([regex]::Escape([string]$ch)) }
            }
        }
        [void]$sb.Append('$')
        $sb.ToString()
    }

    # Overlap test for two globs: build a matcher for B, then decide whether any string
    # accepted by A is also accepted by B. For IAM patterns (at most a handful of
    # wildcards, fixed literal segments), we synthesize concrete witnesses from the
    # literal segments of each pattern and test them against the other pattern's regex.
    $reA = [regex]::new(($toRegex.Invoke($a))[0], 'IgnoreCase')
    $reB = [regex]::new(($toRegex.Invoke($b))[0], 'IgnoreCase')

    # Witness generation: the literal (non-wildcard) form of each pattern is a concrete
    # action when the pattern has no wildcards; when it does, we substitute wildcards
    # with the other pattern's corresponding literal run. See "Wildcard overlap
    # algorithm" below for the precise procedure and why it is sound for IAM globs.
    return (Test-CHARGlobIntersect -RegexA $reA -RegexB $reB -PatternA $a -PatternB $b)
}
```

#### Wildcard overlap algorithm

The overlap of two globs each containing `*`/`?` is decided by a small dynamic-program
that walks both patterns simultaneously — the classic "do two wildcard patterns
intersect" problem. Define `Intersect(i, j)` = true if the suffix of pattern A starting
at `i` can share a concrete tail with the suffix of pattern B starting at `j`:

- If both suffixes are empty ⇒ true.
- If `A[i]` is `*` ⇒ `Intersect(i+1, j)` OR (`j < len(B)` AND `Intersect(i, j+1)`).
- Symmetric rule when `B[j]` is `*`.
- If `A[i]` and `B[j]` are both non-`*`: they must be compatible — either equal, or one
  is `?` — then `Intersect(i+1, j+1)`; otherwise false.
- If one suffix is empty and the other's remaining chars are all `*` ⇒ true, else false.

This runs in `O(len(A) * len(B))`, is exact for glob intersection, and needs no
enumeration of the action space. `Test-CHARGlobIntersect` implements this recurrence
(memoized). The regex forms above are retained only as a fast exact-literal shortcut;
the DP is the authoritative decision. Comparison is done on the lowercased patterns so
the service prefix and action name are case-insensitive (Req 3.6).

Worked examples from the requirements (all return `$true`):
- `ec2:getinstance` vs `ec2:get*` (policy-side wildcard) — Req 3.3
- `ec2:getinstance` vs `*` (fast path) — Req 3.4
- `ec2:describe*` vs `ec2:*` (both sides wildcard, query-side too) — Req 3.5

Disjoint example returning `$false`: `ec2:getinstance` vs `s3:get*`.

Symmetry holds by construction: `Intersect` is defined symmetrically, so
`Test-CHARIamActionOverlap A B == Test-CHARIamActionOverlap B A`.

### Statement normalization

AWS policy documents are irregular: `Action` and `Resource` may be a single string or
an array; `Statement` may be a single object or an array; `Effect` is always a scalar.
The aggregation helper normalizes each statement to arrays:

```powershell
$statements = @($parsed.Statement)               # force array
foreach ($stmt in $statements) {
    $actions   = @($stmt.Action)                 # normalize to array (Req 3)
    $resources = @($stmt.Resource)               # normalize to array (Req 6.3)
    $effect    = [string]$stmt.Effect            # 'Allow' | 'Deny'
    # ... matching + record emission ...
}
```

### Effect filtering + verdict computation

Given the normalized, matched statements for a query:

```
matches = statements where (no Action query) OR (any Policy_Action overlaps Action)

# Effect filtering (Req 4):
if Effect == 'Allow'  → keep Allow matches AND all Deny matches   # Req 4.1, 4.3
if Effect == 'Deny'   → keep Deny matches                          # Req 4.2
if Effect not set     → keep Allow and Deny matches                # Req 4.4

# Verdict (Req 5), only when Action supplied:
if any matched statement has Effect == 'Deny'      → 'Deny'         # Req 5.2
elseif any matched statement has Effect == 'Allow' → 'Allow'       # Req 5.3
else                                               → 'ImplicitDeny' # Req 5.4
```

The verdict is computed over the *matching* set before the Effect display filter is
applied, so filtering the *displayed* rows to `Allow` never changes the verdict — an
explicit Deny still wins (Req 4.3 + 5.2 together).

## Data Models

### Permission_Record (`[PSCustomObject]`, Req 6)

```powershell
[PSCustomObject]@{
    PSTypeName    = 'AWS.IAM.PrincipalPermission'  # Req 6.2
    PrincipalArn  = $PrincipalArn
    PrincipalType = $principal.Type                # Role|User|Group
    PolicyName    = $policyName                    # Req 6.3 source policy name
    PolicyType    = $policyType                    # 'Managed' | 'Inline'  (Req 6.3)
    Effect        = $effect                        # Allow|Deny            (Req 6.3)
    Action        = $matchedAction                 # matched Policy_Action (Req 6.3)
    Resource      = $resources                     # resource set (array)  (Req 6.3)
    Verdict       = $verdict                       # set when Action supplied (Req 6.4)
}
```

- When `-Action` is omitted, `Verdict` is `$null` and every statement is represented
  (Req 3.7); the `Action` field carries the statement's action pattern(s).
- `PSTypeName` on the hashtable makes PowerShell stamp the type name onto the object,
  enabling downstream `Format-*` and type-based filtering (Req 6.1, 6.2).

### Principal descriptor (internal)

```
{ Type : 'Role'|'User'|'Group' ; Name : <string> }
```

## Error Handling

| Condition | Behavior | Requirement |
| --- | --- | --- |
| Malformed / non-IAM ARN | `throw` a terminating error naming the value and the expected role/user/group formats | 1.4 |
| Single policy-document retrieval fails (managed or inline) | `Write-Warning` including the policy identifier; `continue` to the next policy | 2.7 |
| Policy document fails to parse as JSON after decode | `Write-Warning` with the policy identifier; `continue` | 2.7 (same resilience path) |
| AWS list cmdlet itself fails (e.g., no such principal) | Surfaces as a terminating AWS error from the cmdlet (not swallowed); this is outside the "single policy document" resilience scope | — |

All AWS document-retrieval calls use `-ErrorAction Stop` inside a `try/catch` so the
warn-and-continue path is reliable, mirroring the existing functions in the module.
AWS common parameters are always forwarded via `@awsParams` from
`New-AWSParamSplat -BoundParameters $PSBoundParameters` (Req 7.2).

## Testing Strategy

Tests live at `tests/src/Public/AWS/IAM/Get-CHARPrincipalPermission.Tests.ps1` (Req 8.1),
mirroring the repo's mirror-`src`-under-`tests` layout. Following the module's existing
Pester convention (e.g. `CFNPrivateFunctions.Tests.ps1`), the test file imports the IAM
module in `BeforeAll` and uses Pester `Mock` to stub the AWS cmdlets
(`Get-IAMAttachedRolePolicyList`, `Get-IAMRolePolicyList`, `Get-IAMRolePolicy`,
`Get-IAMPolicy`, `Get-IAMPolicyVersion`, and the User/Group equivalents) so no live AWS
calls occur. `New-AWSParamSplat` is dot-sourced/available so the real splat wiring is
exercised.

**Dual approach:**
- **Property tests** verify the universal properties below across generated inputs
  (≥ 100 iterations each). PowerShell has no first-class PBT framework in this repo, so
  generation is done with in-test random generators (random account IDs, principal
  names, action patterns, statement sets) driving a `1..100 | ForEach-Object` loop
  inside a Pester `It`. Each property test is tagged
  `Feature: iam-permission-role-auditing, Property N: <text>`.
- **Unit/example tests** cover the explicit required cases and edge/error conditions.

**Required example cases (Req 8.2–8.6):**
- Principal type derivation for Role, User, and Group ARNs (8.2).
- Invalid ARN produces a terminating error (8.3) — assert `{ ... } | Should -Throw`.
- Bidirectional match including a wildcard policy action (`ec2:Get*`) and a wildcard
  query action (`ec2:Describe*` vs `ec2:*`) (8.4).
- Verdict `Deny` when a matching Deny coexists with a matching Allow (8.5).
- Verdict `ImplicitDeny` when nothing matches the query (8.6).

**Convention checks (Req 7):** existing suites (`HelpDiscoverability.Tests.ps1`,
`Test-ManifestCompliance`) already enforce comment-based help and export/manifest sync
for every exported function; adding the function to `Export-ModuleMember` and the
manifest keeps those green. A focused test asserts `PrincipalArn` is mandatory and that
supplying `-ProfileName`/`-Region` forwards them to the mocked AWS cmdlets.

## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid
executions of a system — essentially, a formal statement about what the system should
do. Properties serve as the bridge between human-readable specifications and
machine-verifiable correctness guarantees.*

### Property 1: Principal type derivation from ARN

For any valid IAM principal ARN of the form
`arn:aws:iam::<12-digit-account>:<role|user|group>/<optional-path><name>`, the Function
derives a `Principal_Type` of `Role`, `User`, or `Group` respectively, matching the
ARN's resource keyword regardless of account id, path, or name characters.

**Validates: Requirements 1.1, 1.2, 1.3**

### Property 2: Invalid ARN produces a terminating error

For any string that is not a well-formed IAM role, user, or group ARN, the Function
terminates with an error, and the error message contains the supplied value and the
expected IAM ARN formats.

**Validates: Requirements 1.4**

### Property 3: Policy aggregation completeness

For any set of managed policies attached directly to the Principal and any set of
inline policies embedded on the Principal, every attached managed policy (resolved to
its default-version document) and every inline policy contributes at least one
Permission_Record to the aggregation, and no record originates from group-inherited
policies or permissions boundaries.

**Validates: Requirements 2.1, 2.2, 2.3, 2.4, 2.5**

### Property 4: Policy document decode/parse round-trip

For any policy document whose statements are known, when that document is URL-encoded
as AWS returns it, the Function URL-decodes and parses it into statements equivalent to
the original (same effects, actions, and resources).

**Validates: Requirements 2.6**

### Property 5: Per-policy failure resilience

For any set of policies in which retrieval of one policy document fails, the Function
emits a warning that includes the failing policy's identifier and still produces
Permission_Records for every policy whose document was retrieved successfully.

**Validates: Requirements 2.7**

### Property 6: Bidirectional wildcard overlap match

For any Query_Action pattern and any Policy_Action pattern that overlap in at least one
concrete action (with `*`/`?` wildcards permitted on either side), the Function reports
the statement as a match; for any pattern pair sharing no concrete action, it reports no
match. The relation is symmetric: swapping the two patterns yields the same result.

**Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5**

### Property 7: Case-insensitive action matching

For any matching Query_Action / Policy_Action pair, re-casing the service prefix or
action name of either pattern does not change the match result.

**Validates: Requirements 3.6**

### Property 8: No query reports all statements

For any Principal whose aggregated policy statements are known, when no Query_Action is
supplied, the Function reports a Permission_Record for every aggregated statement.

**Validates: Requirements 3.7**

### Property 9: Effect filtering always surfaces Deny

For any set of matched statements and any Effect filter setting: filtering to `Deny`
yields exactly the matching `Deny` statements; filtering to `Allow` yields the matching
`Allow` statements together with all matching `Deny` statements; supplying no filter
yields all matching statements of both effects.

**Validates: Requirements 4.1, 4.2, 4.3, 4.4**

### Property 10: Effective-access verdict precedence

For any Query_Action and any set of matched statements: if at least one matching
statement has Effect `Deny` the verdict is `Deny`; else if at least one matching
statement has Effect `Allow` the verdict is `Allow`; else the verdict is `ImplicitDeny`.
When a Query_Action is supplied the verdict is included in the output.

**Validates: Requirements 5.1, 5.2, 5.3, 5.4, 6.4**

### Property 11: Permission_Record structure completeness

For any emitted matched permission, the output item is a `[PSCustomObject]` bearing the
Function's `PSTypeName` and populated fields for the source policy name, source policy
type, Effect, matched Policy_Action, and the statement's resource set.

**Validates: Requirements 6.1, 6.2, 6.3**

---
Authored by Kiro (Claude Opus 4.8), reviewed by ccharland, on 2026-08-06.
