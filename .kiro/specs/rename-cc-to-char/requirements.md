# Requirements Document

## Introduction

This feature renames the command prefix in all public function names from "CC" to "CHAR" across the CharlandCustomizations PowerShell module. The "CC" prefix was recently hardcoded into function names (replacing the old `DefaultCommandPrefix` mechanism). The "CHAR" prefix is more unique, clearly identifies these as Charland's custom functions, and avoids potential naming conflicts with AWS modules or other cmdlets that may use "CC".

The rename affects function definitions, file names, aliases, script-scoped variables, export lists, internal cross-references, tests, and documentation. Authenticode signature blocks embedded in files must be preserved unchanged.

## Glossary

- **Module_Manifest**: The `CharlandCustomizations.psd1` file that declares module metadata, exports, and nested modules
- **Root_Module**: The `CharlandCustomizations.psm1` file that dot-sources public and private function scripts
- **Nested_Module**: A `.psm1` file listed in the manifest's `NestedModules` array that defines and exports its own functions
- **CC_Prefix**: The two-character string "CC" currently prepended to the noun portion of every public function name
- **CHAR_Prefix**: The four-character string "CHAR" that will replace the CC_Prefix in the noun portion of every public function name
- **Signature_Block**: An Authenticode digital signature appended to PowerShell files as base64-encoded comment lines between `# SIG # Begin signature block` and `# SIG # End signature block` — these will be removed during the rename and re-applied later
- **Script_Variable**: A variable scoped with `$script:` that is accessible throughout the module but not exported
- **Export_ModuleMember**: The PowerShell cmdlet used within nested modules to declare which functions are publicly available
- **FunctionsToExport**: The manifest key that lists all function names exported by the module
- **AliasesToExport**: The manifest key that lists all aliases exported by the module

## Requirements

### Requirement 1: Rename All Public Function Definitions

**User Story:** As a module maintainer, I want all public function definitions to use the CHAR_Prefix instead of the CC_Prefix, so that exported command names are unique and do not conflict with other modules.

#### Acceptance Criteria

1. WHEN a public function is defined in a standalone `.ps1` file, THE Root_Module SHALL contain a function definition with "CHAR" replacing "CC" at the start of the noun (e.g., `Clear-CCAuthenticodeSignature` becomes `Clear-CHARAuthenticodeSignature`)
2. WHEN a public function is defined in a Nested_Module, THE Nested_Module SHALL contain a function definition with "CHAR" replacing "CC" at the start of the noun (e.g., `Find-CCCFNStackError` becomes `Find-CHARCFNStackError`)
3. THE Module_Manifest SHALL list all renamed functions in the `FunctionsToExport` array using the new CHAR-prefixed names

### Requirement 2: Rename Standalone Function Files

**User Story:** As a module maintainer, I want standalone `.ps1` filenames to match their new CHAR-prefixed function names, so that the file-naming convention remains consistent.

#### Acceptance Criteria

1. WHEN a standalone public function file exists in the `Public/` directory, THE file SHALL be renamed to match the new CHAR-prefixed function name (e.g., `Clear-CCAuthenticodeSignature.ps1` becomes `Clear-CHARAuthenticodeSignature.ps1`)
2. WHEN a standalone function file is renamed, THE file SHALL contain a function definition whose name matches the new filename

### Requirement 3: Update Module Manifest

**User Story:** As a module maintainer, I want the module manifest to reflect all CHAR-prefixed names, so that the module correctly exports the renamed commands.

#### Acceptance Criteria

1. THE Module_Manifest SHALL list all public functions in `FunctionsToExport` using the CHAR_Prefix (replacing every occurrence of the CC_Prefix)
2. THE Module_Manifest SHALL list all aliases in `AliasesToExport` using the CHAR_Prefix (e.g., `Set-CCFileSignature` becomes `Set-CHARFileSignature`, `Test-CCAuthenticodeSignatures` becomes `Test-CHARAuthenticodeSignatures`)

### Requirement 4: Update All Aliases

**User Story:** As a module maintainer, I want aliases to use the CHAR_Prefix, so that alias names are consistent with their target function names.

#### Acceptance Criteria

1. WHEN an alias is defined using `Set-Alias` or `New-Alias` within a module file, THE alias name SHALL use the CHAR_Prefix in place of the CC_Prefix
2. WHEN an alias targets a function by name, THE alias target SHALL reference the new CHAR-prefixed function name

### Requirement 5: Update Script-Scoped Variables

**User Story:** As a module maintainer, I want script-scoped variables that use the CC_Prefix to be simplified, since the `$script:` scope already provides sufficient namespacing.

#### Acceptance Criteria

1. WHEN a script-scoped variable uses the CC_Prefix in its name (e.g., `$script:CCIsWindows`), THE variable SHALL be renamed to remove the prefix entirely (e.g., `$script:IsWindows`)
2. WHEN a renamed script-scoped variable is referenced elsewhere in the same file, THE reference SHALL use the new simplified variable name

### Requirement 6: Update Export-ModuleMember Calls in Nested Modules

**User Story:** As a module maintainer, I want `Export-ModuleMember` calls to reference the new CHAR-prefixed names, so that nested modules correctly export the renamed functions.

#### Acceptance Criteria

1. WHEN a Nested_Module uses `Export-ModuleMember` with an explicit function list, THE Nested_Module SHALL reference the new CHAR-prefixed function names in that list
2. WHEN a Nested_Module uses `Export-ModuleMember` with an explicit alias list, THE Nested_Module SHALL reference the new CHAR-prefixed alias names in that list

### Requirement 7: Update Help and Examples Within Functions

**User Story:** As a module user, I want help examples and documentation within functions to show the correct CHAR-prefixed command names, so that I can copy-paste examples directly.

#### Acceptance Criteria

1. WHEN a function contains comment-based help with `.EXAMPLE` sections, THE function help SHALL reference the new CHAR-prefixed command name in all examples
2. WHEN a function's help references other module functions by name, THE help text SHALL use the new CHAR-prefixed names for those references
3. WHEN a private function's comment-based help references a public function by name, THE help text SHALL use the new CHAR-prefixed name

### Requirement 8: Update Internal Cross-References

**User Story:** As a module maintainer, I want internal function calls and references between module functions to use the CHAR_Prefix, so that the module operates correctly after the rename.

#### Acceptance Criteria

1. WHEN a module function calls another module function by name (e.g., in pipeline examples or direct invocation), THE calling function SHALL use the new CHAR-prefixed name for the referenced function
2. IF a function references another module function in string literals or script blocks, THEN THE function SHALL use the new CHAR-prefixed name in those references
3. WHEN a dot-source statement references a renamed `.ps1` file by path, THE dot-source statement SHALL use the new CHAR-prefixed filename

### Requirement 9: Update Test Files

**User Story:** As a module developer, I want test files to use the new CHAR-prefixed function names, so that tests continue to pass after the rename.

#### Acceptance Criteria

1. WHEN a test file calls a module function by name, THE test file SHALL use the new CHAR-prefixed function name
2. WHEN a test file references a function in `Describe` or `Context` blocks, THE test file SHALL use the new CHAR-prefixed function name
3. WHEN a test file dot-sources a standalone function file, THE test file SHALL reference the renamed file path
4. WHEN a test filename matches a function name, THE test file SHALL be renamed to match the new CHAR-prefixed function name (e.g., `Find-CCCFNStackError.Tests.ps1` becomes `Find-CHARCFNStackError.Tests.ps1`)

### Requirement 10: Update Documentation Files

**User Story:** As a module user, I want documentation to reference the correct CHAR-prefixed command names, so that I can find and use commands as documented.

#### Acceptance Criteria

1. WHEN a documentation file references a module function by its CC-prefixed name, THE documentation file SHALL be updated to use the new CHAR-prefixed name
2. WHEN a documentation file contains usage examples, THE documentation file SHALL show the new CHAR-prefixed command names in those examples

### Requirement 11: Remove Authenticode Signature Blocks

**User Story:** As a module maintainer, I want all existing Authenticode signature blocks removed during the rename, since all files will be re-signed after the rename is complete.

#### Acceptance Criteria

1. WHEN a file contains a Signature_Block (content between `# SIG # Begin signature block` and `# SIG # End signature block`), THE rename process SHALL remove the entire Signature_Block from the file
2. WHEN the Signature_Block is removed, THE file SHALL NOT have trailing blank lines where the block was previously located

### Requirement 12: Preserve Module Import Behavior

**User Story:** As a module user, I want the module to import and function identically after the rename (with CHAR-prefixed names replacing CC-prefixed names), so that I can update my scripts with a simple find-and-replace.

#### Acceptance Criteria

1. WHEN a user imports the module without any prefix parameter, THE module SHALL export functions with CHAR-prefixed names that are functionally identical to the previous CC-prefixed functions
2. WHEN a user calls a function by its new CHAR-prefixed name, THE module SHALL execute the function correctly
3. THE module SHALL export the same total number of public functions after the rename as before the rename

---

*Generated by Kiro, reviewed by ccharland*
