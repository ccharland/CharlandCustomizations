# Implementation Plan

- [ ] 1. Create the PowerShell-Utilities nested module directory and loader
  - Create directory `src/CharlandCustomizations/Public/PowerShell/`
  - Create `PowerShell-Utilities.psm1` mirroring the `GitCustomizations.psm1` pattern:
    header comment, dot-source `ConvertTo-CHARHashtable.ps1` via `$PSScriptRoot`, and an
    explicit alphabetical `Export-ModuleMember -Function` list
  - _Requirements: 1.1, 1.2, 1.3_

- [ ] 2. Implement the ConvertTo-CHARHashtable function skeleton
  - Create `ConvertTo-CHARHashtable.ps1` with comment-based help (`.SYNOPSIS`,
    `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE`, `.NOTES` with attribution)
  - Declare `[CmdletBinding()]`, `[OutputType([System.Collections.Specialized.OrderedDictionary])]`,
    and the `begin`/`process`/`end` blocks
  - Define parameters: `InputObject` (`[object]`, `ValueFromPipeline`), `Property`
    (`[string[]]`), `ExcludeProperty` (`[string[]]`), `Depth` (`[int]`, default `1`,
    `ValidateRange(1,100)`)
  - _Requirements: 3.3, 4.4, 5.3, 6.4, 7.3_

- [ ] 3. Implement input validation and null/type handling in the process block
  - `$null` `InputObject` → `Write-Warning`, emit nothing
  - Non-`PSCustomObject` input → non-terminating `Write-Error` naming the expected type,
    then continue (no output for that item)
  - `Write-Verbose` the source property count for valid objects
  - _Requirements: 3.4, 6.1, 6.3, 6.4_

- [ ] 4. Implement core conversion (all properties, ordered, value fidelity)
  - Enumerate `psobject.Properties` in source order into an `[ordered]` hashtable
  - Use exact property names as keys; assign values by reference with no type coercion
  - Include `$null`-valued properties; zero-property object → empty ordered hashtable
  - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6_

- [ ] 5. Implement `-Property` inclusion filtering
  - Keep only named properties, case-insensitive match, preserving source-object casing
    for keys
  - Silently omit named properties that don't exist (no error/warning)
  - Empty `-Property` array → empty result
  - _Requirements: 4.1, 4.2, 4.3, 4.5_

- [ ] 6. Implement `-ExcludeProperty` exclusion filtering
  - Remove properties whose names match an exclude entry (case-insensitive exact string,
    no wildcards), applied *after* the `-Property` filter
  - Silently ignore exclude entries that match nothing
  - All properties excluded → empty ordered hashtable
  - _Requirements: 5.1, 5.2, 5.4, 5.5_

- [ ] 7. Implement nested-object handling and `-Depth` recursion
  - At default depth (1), leave nested `PSCustomObject` values unconverted (shallow)
  - When `-Depth > 1` and a value is a `PSCustomObject`, recurse converting one level per
    depth; leave remaining nested objects unconverted at the depth limit
  - Pass arrays, hashtables, and primitives through untouched
  - _Requirements: 7.1, 7.2, 7.3, 7.4_

- [ ] 8. Register the module and function in the manifest
  - Add `'Public/PowerShell/PowerShell-Utilities.psm1'` to `NestedModules` in alphabetical
    position (after the Git entry)
  - Add `'ConvertTo-CHARHashtable'` to `FunctionsToExport` in alphabetical position
  - Do **not** change `ModuleVersion`
  - _Requirements: 1.4, 1.5_

- [ ] 9. Write Pester v5 unit tests
  - Create `tests/Unit/Core/ConvertTo-CHARHashtable.Tests.ps1` with `.NOTES` attribution,
    a `BeforeAll` that dot-sources the function, and `Describe ... -Tag 'Unit'`
  - Cover the 12 scenarios from the design Testing Strategy: basic conversion, pipeline
    equivalence, streaming order, `-Property`, `-ExcludeProperty`, combined filters, null
    warning, empty object, invalid type error, nested default depth, `-Depth 2` recursion,
    value type fidelity + round-trip
  - Capture warnings via `3>&1` and errors via `-ErrorVariable`
  - _Requirements: 8.1, 8.2, 8.3, 8.4_

- [ ] 10. Run tests and code-quality checks; verify green
  - Run the Pester suite (`tests/Run-PesterTests.ps1` or targeted invocation) and confirm
    zero failures
  - Run the project quality/analyzer script (`Scripts/Test-CodeQuality.ps1`) and resolve
    any findings
  - Confirm the module imports cleanly and `ConvertTo-CHARHashtable` is exported
  - _Requirements: 8.4_

---
Authored by Kiro (Claude Opus 4.8) for the powershell-utilities spec, reviewed by ccharland, on 2026-09-19.
