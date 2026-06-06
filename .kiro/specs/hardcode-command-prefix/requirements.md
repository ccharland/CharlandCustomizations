# Requirements Document

## Introduction

This feature removes the `DefaultCommandPrefix = 'CC'` setting from the PowerShell module manifest and instead hardcodes the "CC" prefix directly into the noun portion of every public function name. Currently, PowerShell automatically prepends "CC" to the noun at import time (e.g., `Find-CFNStackError` becomes `Find-CCCFNStackError`). After this change, the source code itself will use the prefixed names, making the exported command names explicit and discoverable without relying on the implicit prefix mechanism.

## Glossary

- **Module_Manifest**: The `CharlandCustomizations.psd1` file that declares module metadata, exports, and the `DefaultCommandPrefix` setting
- **Root_Module**: The `CharlandCustomizations.psm1` file that dot-sources public and private function scripts
- **Nested_Module**: A `.psm1` file listed in the manifest's `NestedModules` array that defines and exports its own functions
- **Noun**: The second part of a PowerShell Verb-Noun function name (e.g., "CFNStackError" in `Find-CFNStackError`)
- **CC_Prefix**: The two-character string "CC" prepended to the noun portion of every public function name
- **Export_ModuleMember**: The PowerShell cmdlet used within nested modules to declare which functions are publicly available
- **FunctionsToExport**: The manifest key that lists all function names exported by the module

## Requirements

### Requirement 1: Remove DefaultCommandPrefix from Module Manifest

**User Story:** As a module maintainer, I want to remove the implicit `DefaultCommandPrefix` setting, so that function names in source code match what users actually type at the command line.

#### Acceptance Criteria

1. WHEN the module manifest is loaded, THE Module_Manifest SHALL NOT contain a `DefaultCommandPrefix` key
2. WHEN the module is imported without the `-Prefix` parameter, THE Module_Manifest SHALL export functions with the CC_Prefix already embedded in the noun

### Requirement 2: Rename All Public Function Definitions

**User Story:** As a module maintainer, I want all public function definitions to include the CC_Prefix in the noun, so that the source code is explicit about the final command names.

#### Acceptance Criteria

1. WHEN a public function is defined in a standalone `.ps1` file, THE Root_Module SHALL contain a function definition with "CC" prepended to the original noun (e.g., `Clear-AuthenticodeSignature` becomes `Clear-CCAuthenticodeSignature`)
2. WHEN a public function is defined in a Nested_Module, THE Nested_Module SHALL contain a function definition with "CC" prepended to the original noun (e.g., `Find-CFNStackError` becomes `Find-CCCFNStackError`)
3. THE Module_Manifest SHALL list all renamed functions in the `FunctionsToExport` array using the new CC-prefixed names

### Requirement 3: Rename Standalone Function Files

**User Story:** As a module maintainer, I want standalone `.ps1` filenames to match their function names, so that the file-naming convention remains consistent.

#### Acceptance Criteria

1. WHEN a standalone public function file exists in the `Public/` directory, THE file SHALL be renamed to match the new CC-prefixed function name (e.g., `Clear-AuthenticodeSignature.ps1` becomes `Clear-CCAuthenticodeSignature.ps1`)
2. WHEN a standalone function file is renamed, THE file SHALL contain a function definition whose name matches the new filename

### Requirement 4: Update Export-ModuleMember Calls in Nested Modules

**User Story:** As a module maintainer, I want `Export-ModuleMember` calls to reference the new CC-prefixed names, so that nested modules correctly export the renamed functions.

#### Acceptance Criteria

1. WHEN a Nested_Module uses `Export-ModuleMember` with an explicit function list, THE Nested_Module SHALL reference the new CC-prefixed function names in that list
2. WHEN a Nested_Module uses `Export-ModuleMember -Function *`, THE Nested_Module SHALL continue to export all functions (no change needed since function definitions are already renamed)

### Requirement 5: Update Help Documentation Within Functions

**User Story:** As a module user, I want help examples and documentation to show the correct CC-prefixed command names, so that I can copy-paste examples directly.

#### Acceptance Criteria

1. WHEN a function contains comment-based help with `.EXAMPLE` sections, THE function help SHALL reference the new CC-prefixed command name in all examples
2. WHEN a function's help references other module functions by name, THE help text SHALL use the new CC-prefixed names for those references

### Requirement 6: Update Test Files

**User Story:** As a module developer, I want test files to use the new CC-prefixed function names, so that tests continue to pass after the rename.

#### Acceptance Criteria

1. WHEN a test file calls a module function by name, THE test file SHALL use the new CC-prefixed function name
2. WHEN a test file references a function in `Describe` or `Context` blocks, THE test file SHALL use the new CC-prefixed function name
3. WHEN a test file dot-sources a standalone function file, THE test file SHALL reference the renamed file path
4. WHEN a test filename matches a function name, THE test file SHALL be renamed to match the new CC-prefixed function name (e.g., `Find-CFNStackError.Tests.ps1` becomes `Find-CCCFNStackError.Tests.ps1`)

### Requirement 7: Update Documentation Files

**User Story:** As a module user, I want documentation to reference the correct CC-prefixed command names, so that I can find and use commands as documented.

#### Acceptance Criteria

1. WHEN a documentation file references a module function by its old name, THE documentation file SHALL be updated to use the new CC-prefixed name
2. WHEN a documentation file contains usage examples, THE documentation file SHALL show the new CC-prefixed command names in those examples

### Requirement 8: Update Internal Cross-References

**User Story:** As a module maintainer, I want internal function calls between module functions to use the correct names, so that the module operates correctly after the rename.

#### Acceptance Criteria

1. WHEN a module function calls another module function by name (e.g., in pipeline examples or direct invocation), THE calling function SHALL use the new CC-prefixed name for the referenced function
2. IF a function references another module function in string literals or script blocks, THEN THE function SHALL use the new CC-prefixed name in those references

### Requirement 9: Preserve Module Import Behavior

**User Story:** As a module user, I want the module to import and function identically after the rename, so that my existing scripts using CC-prefixed names continue to work.

#### Acceptance Criteria

1. WHEN a user imports the module without any prefix parameter, THE module SHALL export functions with the same CC-prefixed names that were previously generated by `DefaultCommandPrefix`
2. WHEN a user calls a function by its CC-prefixed name (e.g., `Find-CCCFNStackError`), THE module SHALL execute the function correctly
3. IF a user imports the module with `-Prefix` parameter, THEN THE module SHALL apply the user-specified prefix to the already-CC-prefixed noun (this is expected changed behavior that should be documented)
