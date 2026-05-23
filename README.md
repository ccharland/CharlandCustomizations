# CharlandCustomizations

Public release home for my PowerShell module and related automation.

## Repository baseline

This repository is prepared to import the existing module code from:
https://github.com/ccharland/MyPowershellCustomizations

```text
.
├── src/
│   └── CharlandCustomizations/
│       ├── CharlandCustomizations.psd1
│       ├── CharlandCustomizations.psm1
│       ├── Public/
│       └── Private/
├── tests/
└── README.md
```

## Import workflow

1. Copy public functions into `src/CharlandCustomizations/Public/`.
2. Copy internal helper functions into `src/CharlandCustomizations/Private/`.
3. Update `src/CharlandCustomizations/CharlandCustomizations.psd1`:
   - `ModuleVersion`
   - `FunctionsToExport`
   - `AliasesToExport`
4. Run your Pester tests from `tests/`.
5. Import the module from source:

```powershell
Import-Module ./src/CharlandCustomizations/CharlandCustomizations.psd1 -Force
```
