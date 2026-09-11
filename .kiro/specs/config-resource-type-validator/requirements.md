# Requirements Document

## Introduction

AWS Config resource types are case-sensitive strings that follow the pattern `AWS::ServiceName::ResourceType` (e.g., `AWS::EC2::Instance`). Passing a mis-cased or malformed value produces silent failures or cryptic API errors. This feature adds a correction-first validation helper to `Config-Operations.psm1` that always attempts to fix common input mistakes before failing. When the input is fixable, the corrected string is returned for immediate use; when unfixable, `$false` is returned so the caller can handle the error on its own terms. The validator also checks corrected values against a dynamically fetched and cached list of known AWS Config resource types, catching typos that pass structural validation but don't correspond to real resource types.

## Glossary

- **Validator**: The `Test-CHARConfigResourceType` PowerShell function that attempts to correct and validate AWS Config resource type strings.
- **ResourceType**: A string identifying an AWS resource class in the format `AWS::ServiceName::ResourceType` (e.g., `AWS::EC2::Instance`, `AWS::S3::Bucket`).
- **Format_Pattern**: The regex pattern `^AWS::[A-Z][a-zA-Z0-9]+::[A-Z][a-zA-Z0-9]+$` that defines a structurally valid resource type.
- **ResourceType_Enum**: The dynamically fetched and module-scope cached set of valid AWS Config resource type strings, populated on first use from the AWS Config service API.
- **PascalCase**: Capitalizing the first character of a segment while preserving the remaining characters (e.g., `ec2` → `Ec2`, `instance` → `Instance`).

## Requirements

### Requirement 1: Correction-First Behavior

**User Story:** As a module consumer, I want the validator to always attempt to correct my ResourceType input before failing, so that common typos are fixed automatically rather than causing cryptic API errors.

#### Acceptance Criteria

1. WHEN a valid ResourceType string matching the Format_Pattern is provided, THE Validator SHALL return the input string unchanged.
2. WHEN a ResourceType string has capitalization errors but correct three-segment `::` delimited structure, THE Validator SHALL normalize each segment to PascalCase and return the corrected string.
3. WHEN a ResourceType string is missing the `AWS::` prefix but contains two valid segments separated by `::` (e.g., `EC2::Instance`), THE Validator SHALL prepend `AWS::` and apply PascalCase normalization, then return the corrected string.
4. WHEN a ResourceType string uses single colons instead of double colons as separators (e.g., `AWS:EC2:Instance`), THE Validator SHALL replace single-colon separators with `::` and apply PascalCase normalization, then return the corrected string.
5. WHEN a ResourceType string contains a mix of single and double colon separators (e.g., `AWS::EC2:Instance`), THE Validator SHALL normalize all separators to `::` and apply PascalCase normalization, then return the corrected string.
6. WHEN a ResourceType string has leading or trailing whitespace, THE Validator SHALL trim the whitespace before attempting any other corrections.
7. WHEN all corrections have been applied and the resulting string matches the Format_Pattern, THE Validator SHALL return the corrected string.
8. WHEN corrections cannot produce a valid Format_Pattern match (e.g., fewer than two meaningful segments after the `AWS::` prefix, segments containing non-alphanumeric characters, segments beginning with a digit, or completely unparseable input), THE Validator SHALL return `$false`.
9. WHEN a `$null` value, empty string, or whitespace-only string is provided, THE Validator SHALL return `$false`.
10. THE Validator SHALL NOT throw terminating errors for invalid ResourceType input. THE Validator SHALL always return either a valid ResourceType string or `$false`.
11. THE Validator SHALL apply corrections in the following order: trim whitespace (criterion 6), normalize separators (criteria 4 and 5), prepend missing `AWS::` prefix (criterion 3), apply PascalCase normalization (criterion 2), then validate the result against the Format_Pattern (criterion 7 or 8).

### Requirement 2: Dynamic Enum Caching and Validation

**User Story:** As a module consumer, I want the validator to dynamically fetch and cache the known set of valid AWS Config resource types, so that typos beyond simple casing errors are caught and corrected using an always-current list without embedding a static array that goes stale.

#### Acceptance Criteria

1. THE module SHALL maintain a module-scoped variable (`$script:ConfigResourceTypeCache`) that holds the cached list of valid resource type strings.
2. WHEN the Validator is called and `$script:ConfigResourceTypeCache` is `$null` or empty, THE Validator SHALL attempt to populate the cache by calling `Get-CFGDiscoveredResourceCount` using any provided AWS common parameters via `New-AWSParamSplat`.
3. THE Validator SHALL extract unique resource type strings from the `ResourceType` property of the `Get-CFGDiscoveredResourceCount` results and store them in `$script:ConfigResourceTypeCache`.
4. WHEN the cache has been populated, subsequent calls to the Validator SHALL reuse the cached list without making additional API calls.
5. WHERE the `-RefreshCache` switch is specified, THE Validator SHALL discard the existing cache and re-fetch the resource type list from the API.
6. IF the API call to populate the cache fails (access denied, no connectivity, service error), THEN THE Validator SHALL write a non-terminating warning explaining the enum could not be loaded, set the cache to an empty array (preventing repeated failed calls), and fall back to format-only validation for the current and subsequent calls until `-RefreshCache` is used.
7. AFTER format correction produces a structurally valid string AND the cache is populated (non-empty), THE Validator SHALL check whether the result exists in the cached list (case-sensitive exact match).
8. WHEN the corrected string matches an entry in the cached list exactly, THE Validator SHALL return the matched string.
9. WHEN the corrected string does NOT match any entry exactly, THE Validator SHALL attempt a case-insensitive match against the cached list.
10. WHEN a case-insensitive match finds exactly one candidate, THE Validator SHALL return that candidate string (the correctly-cased value from the cache).
11. WHEN a case-insensitive match finds zero candidates, THE Validator SHALL return `$false`.
12. WHEN a case-insensitive match finds multiple candidates (ambiguous), THE Validator SHALL return `$false`.
13. WHEN the cache is empty (API call failed or not yet populated without credentials), THE Validator SHALL skip enum validation and return the format-corrected string directly (format-only mode).

### Requirement 3: Public Export and Pipeline Support

**User Story:** As a module consumer, I want to use the validator both as a standalone pre-flight check and through the pipeline, so that I can validate and correct resource types before passing them to Config functions.

#### Acceptance Criteria

1. THE Validator SHALL be exported as a public function from `Config-Operations.psm1` via `Export-ModuleMember` and listed in the `FunctionsToExport` array in `CharlandCustomizations.psd1`.
2. THE Validator SHALL accept a mandatory `-ResourceType` parameter of type `[string]` from pipeline input using both `ValueFromPipeline` and `ValueFromPipelineByPropertyName`.
3. THE Validator SHALL accept AWS common parameters (Region, ProfileName, AccessKey, SecretKey, SessionToken, Credential, ProfileLocation, EndpointUrl) needed for cache population via `Get-CFGDiscoveredResourceCount`. These parameters are only used when the cache needs to be populated; once cached, they are ignored on subsequent calls.
4. THE Validator SHALL accept a `-RefreshCache` switch parameter that forces re-fetching the resource type list from the API regardless of current cache state.
5. WHEN multiple ResourceType values are piped to the Validator, THE Validator SHALL process each value independently in the `process` block, producing one output object per input value.
6. WHEN processing multiple piped ResourceType values, THE Validator SHALL return a corrected string or `$false` for each value independently without terminating the pipeline, because the function never throws terminating errors for invalid input.
7. THE Validator SHALL declare `[OutputType([object])]` to indicate it may return either a `[string]` or `[bool]` value.
8. THE Validator SHALL include comment-based help with Synopsis, Description, Parameter descriptions, at least 2 Examples (one standalone call, one pipeline call), and a Notes section containing the Kiro attribution line.

### Requirement 4: Internal Integration with Existing Functions

**User Story:** As the module maintainer, I want the existing Config-Operations functions to call the validator internally, so that all resource type inputs are validated and corrected consistently before reaching the AWS API.

#### Acceptance Criteria

1. WHEN `Get-CHARConfigResourceCreationDate` is called, THE function SHALL invoke `Test-CHARConfigResourceType -ResourceType $ResourceType` in its `process` block before making AWS API calls.
2. WHEN `Get-CHARConfigResourceDeleteDate` is called, THE function SHALL invoke `Test-CHARConfigResourceType -ResourceType $ResourceType` in its `process` block before making AWS API calls.
3. WHEN `Get-CHARConfigResourceComplianceReport` is called, THE function SHALL invoke `Test-CHARConfigResourceType -ResourceType $ResourceType` in its `process` block before making AWS API calls.
4. WHEN an existing function calls the Validator and receives a string result that differs from the original input, THE function SHALL assign the corrected value to the local `$ResourceType` variable used in all subsequent AWS API calls and write a `Write-Verbose` message containing both the original value and the corrected value.
5. WHEN an existing function calls the Validator and receives a string result equal to the original input, THE function SHALL proceed without writing a correction verbose message.
6. WHEN an existing function calls the Validator and receives `$false`, THE function SHALL write a terminating error whose message includes the original input value and states that the resource type could not be corrected to a valid format.

### Requirement 5: Pester Tests

**User Story:** As the module maintainer, I want comprehensive Pester test coverage of the validator function, so that correction logic and edge cases are verified and regressions are caught early.

#### Acceptance Criteria

1. THE test file SHALL be located at `tests/Test-CHARConfigResourceType.Tests.ps1` and use Pester 5 syntax with `Describe`/`Context`/`It` blocks.
2. THE tests SHALL verify that already-valid input (e.g., `AWS::EC2::Instance`) is returned unchanged.
3. THE tests SHALL verify capitalization correction for all three segments (e.g., `aws::ec2::instance` returns `AWS::EC2::Instance`).
4. THE tests SHALL verify missing `AWS::` prefix correction (e.g., `EC2::Instance` returns `AWS::EC2::Instance`).
5. THE tests SHALL verify single-colon separator correction (e.g., `AWS:EC2:Instance` returns `AWS::EC2::Instance`).
6. THE tests SHALL verify mixed separator correction (e.g., `AWS::EC2:Instance` returns `AWS::EC2::Instance`).
7. THE tests SHALL verify whitespace trimming combined with other corrections.
8. THE tests SHALL verify that unfixable input returns `$false` for cases including: `$null`, empty string, whitespace-only string, single segment with no separators, segments with special characters, and segments beginning with digits.
9. THE tests SHALL verify pipeline processing of multiple values produces independent results per input.
10. THE tests SHALL verify cache population by mocking `Get-CFGDiscoveredResourceCount` to return known resource types and confirming the Validator matches against the cached list.
11. THE tests SHALL verify case-insensitive correction via the cached enum (e.g., `AWS::ec2::instance` corrected via cache to `AWS::EC2::Instance`).
12. THE tests SHALL verify that a structurally valid but non-existent type returns `$false` when the cache is populated (e.g., `AWS::EC2::FakeResource`).
13. THE tests SHALL verify that ambiguous case-insensitive matches return `$false`.
14. THE tests SHALL verify the correction order: trim → normalize separators → prepend prefix → PascalCase → enum validation.
15. THE tests SHALL verify that the `-RefreshCache` switch discards the existing cache and re-fetches from the API (mock called a second time).
16. THE tests SHALL verify fallback to format-only validation when the API call fails: mock `Get-CFGDiscoveredResourceCount` to throw, confirm a warning is written, and confirm the format-corrected string is returned without enum checking.
17. THE tests SHALL verify that subsequent calls reuse the cached list without additional API calls (mock `Get-CFGDiscoveredResourceCount` is invoked exactly once across multiple Validator calls).
18. THE tests SHALL NOT call live AWS APIs; all AWS cmdlet calls SHALL be mocked.
