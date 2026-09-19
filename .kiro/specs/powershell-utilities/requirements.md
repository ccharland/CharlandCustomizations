# Requirements Document

## Introduction

This feature adds a new PowerShell utilities nested module (`PowerShell-Utilities.psm1`) to the CharlandCustomizations project. The initial function, `ConvertTo-CHARHashtable`, converts PSCustomObject instances into hashtables suitable for splatting. This addresses a common friction point where pipeline-produced PSCustomObjects cannot be used directly with the `@variable` splatting operator.

## Glossary

- **Module**: The PowerShell-Utilities nested module (`PowerShell-Utilities.psm1`) registered in the CharlandCustomizations manifest
- **Converter**: The `ConvertTo-CHARHashtable` function that transforms PSCustomObjects into hashtables
- **Source_Object**: A PSCustomObject instance provided as input to the Converter
- **Result_Hashtable**: The ordered hashtable produced by the Converter from a Source_Object
- **Property_Filter**: An optional list of property names used to limit which Source_Object properties appear in the Result_Hashtable

## Requirements

### Requirement 1: Module Structure

**User Story:** As a module maintainer, I want the PowerShell utilities to live in a dedicated nested module, so that the project stays organized by feature area.

#### Acceptance Criteria

1. THE Module SHALL exist at the path `src/CharlandCustomizations/Public/PowerShell/PowerShell-Utilities.psm1`
2. THE Module SHALL define its functions directly within the `.psm1` (or dot-source sibling `.ps1` files) and SHALL carry module-level comment-based help
3. THE Module SHALL call `Export-ModuleMember -Function` with an explicit, alphabetically sorted list of all functions it defines
4. THE manifest `NestedModules` array SHALL include the entry `Public/PowerShell/PowerShell-Utilities.psm1` in alphabetical position relative to existing entries
5. THE manifest `FunctionsToExport` array SHALL include `ConvertTo-CHARHashtable`

### Requirement 2: Basic PSCustomObject to Hashtable Conversion

**User Story:** As a PowerShell user, I want to convert a PSCustomObject to a hashtable, so that I can splat it against cmdlets.

#### Acceptance Criteria

1. WHEN a Source_Object is provided via the `-InputObject` parameter, THE Converter SHALL return a Result_Hashtable containing exactly one key-value pair for each NoteProperty on the Source_Object, with no additional or missing entries
2. WHEN a Source_Object is provided, THE Converter SHALL use each property name as the corresponding hashtable key, preserving exact case and spelling
3. WHEN a Source_Object is provided, THE Converter SHALL assign each property value to its corresponding hashtable entry without type conversion, such that the value's `.GetType()` in the Result_Hashtable matches the original property value's `.GetType()`
4. WHEN a Source_Object has properties with `$null` values, THE Converter SHALL include those properties in the Result_Hashtable with `$null` as the value
5. WHEN a Source_Object with one or more properties is converted to a Result_Hashtable and a new PSCustomObject is constructed from that hashtable, THE resulting object SHALL have the same property names and values as the original Source_Object, verified by property-by-property equality comparison
6. WHEN a Source_Object with zero properties is provided, THE Converter SHALL return an empty hashtable with a count of zero

### Requirement 3: Pipeline Input Support

**User Story:** As a PowerShell user, I want to pipe objects into the conversion function, so that it integrates naturally with existing pipelines.

#### Acceptance Criteria

1. WHEN one or more Source_Objects are piped to the Converter, THE Converter SHALL process each object in its `process` block and emit one Result_Hashtable per Source_Object as it is received (streaming output)
2. WHEN multiple Source_Objects are piped to the Converter, THE Converter SHALL emit Result_Hashtables in the same order as the input objects
3. THE Converter SHALL accept pipeline input by value on the `-InputObject` parameter using the `ValueFromPipeline` attribute
4. IF a pipeline contains a mix of valid Source_Objects and invalid types, THEN THE Converter SHALL write a non-terminating error for each invalid object and continue processing subsequent objects in the pipeline

### Requirement 4: Property Filtering

**User Story:** As a PowerShell user, I want to select which properties to include in the hashtable, so that I can build splatting hashtables with only the parameters a target cmdlet expects.

#### Acceptance Criteria

1. WHERE the `-Property` parameter is supplied with one or more property names, THE Converter SHALL include only those named properties in the Result_Hashtable, matching property names case-insensitively and preserving the original Source_Object casing for Result_Hashtable keys
2. WHERE the `-Property` parameter is supplied and a named property does not exist on the Source_Object, THE Converter SHALL omit that property name from the Result_Hashtable without writing an error record or warning
3. WHERE the `-Property` parameter is not supplied, THE Converter SHALL include all properties from the Source_Object
4. THE `-Property` parameter SHALL accept an array of strings typed as `[string[]]`
5. IF the `-Property` parameter is supplied with an empty array, THEN THE Converter SHALL return an empty Result_Hashtable

### Requirement 5: Property Exclusion

**User Story:** As a PowerShell user, I want to exclude specific properties from the resulting hashtable, so that I can remove unwanted properties without listing every property to keep.

#### Acceptance Criteria

1. WHERE the `-ExcludeProperty` parameter is supplied, THE Converter SHALL perform case-insensitive comparison of property names and omit any Source_Object properties whose names match an entry in the `-ExcludeProperty` array from the Result_Hashtable
2. WHERE both `-Property` and `-ExcludeProperty` are supplied, THE Converter SHALL first filter to the `-Property` set, then remove any properties whose names match an `-ExcludeProperty` entry (case-insensitive exact-string comparison, no wildcard expansion) from that filtered set
3. THE `-ExcludeProperty` parameter SHALL accept an array of strings
4. IF an `-ExcludeProperty` entry does not match any property on the Source_Object (or on the `-Property`-filtered set when both parameters are supplied), THEN THE Converter SHALL silently ignore that entry without producing an error or warning
5. WHERE `-ExcludeProperty` entries cause all properties to be excluded, THE Converter SHALL return an empty ordered hashtable

### Requirement 6: Error Handling and Edge Cases

**User Story:** As a PowerShell user, I want predictable behavior on invalid or unusual inputs, so that the function does not produce confusing failures.

#### Acceptance Criteria

1. IF a `$null` value is provided as InputObject, THEN THE Converter SHALL write a warning and produce no output
2. IF an empty Source_Object (zero properties) is provided, THEN THE Converter SHALL return an empty hashtable
3. IF a non-PSCustomObject type is provided (such as a plain hashtable or primitive), THEN THE Converter SHALL write a non-terminating error indicating the expected input type and continue processing the pipeline
4. THE Converter SHALL support `[CmdletBinding()]` with `-Verbose` output on each conversion describing the source object property count

### Requirement 7: Nested Object Handling

**User Story:** As a PowerShell user, I want clear behavior for nested objects, so that I know what to expect when properties contain complex values.

#### Acceptance Criteria

1. WHEN a Source_Object property value is itself a PSCustomObject, THE Converter SHALL include the nested PSCustomObject as-is in the Result_Hashtable (shallow conversion by default)
2. WHERE the `-Depth` parameter is supplied with a value greater than 1, THE Converter SHALL recursively convert nested PSCustomObject values into hashtables up to the specified depth
3. WHERE the `-Depth` parameter is not supplied, THE Converter SHALL default to a depth of 1 (shallow, no recursion)
4. WHERE recursive conversion reaches the specified depth limit, THE Converter SHALL leave any remaining nested PSCustomObjects unconverted at that level

### Requirement 8: Pester Tests

**User Story:** As a module maintainer, I want comprehensive Pester tests for the converter function, so that regressions are caught automatically.

#### Acceptance Criteria

1. THE test file SHALL exist at `tests/Unit/Core/ConvertTo-CHARHashtable.Tests.ps1` and SHALL use Pester v5 syntax with a `BeforeAll` block that dot-sources the function under test
2. THE tests SHALL include at minimum one `It` block for each of the following scenarios: basic conversion of a PSCustomObject to a hashtable, pipeline input producing equivalent output to parameter-bound input, property filtering that returns only specified property keys, exclusion filtering that omits specified property keys from the output, null input emitting a Warning-stream message, empty object (zero properties) returning an empty hashtable, invalid type input (non-object such as a raw string or integer) producing a non-terminating error, nested object at default depth returning the child object unconverted, and recursive depth parameter converting nested objects to the specified depth level
3. WHEN a test validates warning or error output, THE test SHALL capture the appropriate stream (Warning via `3>&1` or error via `Should -Throw` / `-ErrorVariable`) and assert on the presence of a descriptive message
4. WHEN all tests in the file pass with zero failures, THE Converter function SHALL be considered implementation-complete for merge acceptance
