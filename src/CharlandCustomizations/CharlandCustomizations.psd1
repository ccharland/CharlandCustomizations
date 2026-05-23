@{
    RootModule           = 'CharlandCustomizations.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = '1f7e3e80-b770-4587-a1a0-9e45c839b50a'
    Author               = 'Christopher Charland'
    CompanyName          = ''
    Copyright            = '(c) Christopher Charland. All rights reserved.'
    Description          = 'Public PowerShell module and scripts for daily customization and automation tasks.'
    PowerShellVersion    = '7.2'
    CompatiblePSEditions = @('Core')
    DefaultCommandPrefix = 'CC'
    FunctionsToExport    = '*'
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()

    PrivateData = @{
        PSData = @{
            Tags         = @('PowerShell', 'AWS', 'Automation', 'CloudFormation', 'Utilities')
            ProjectUri   = 'https://github.com/ccharland/CharlandCustomizations'
            LicenseUri   = 'https://github.com/ccharland/CharlandCustomizations/blob/main/LICENSE'
            ReleaseNotes = 'Initial public release - module structure and steering files.'
            Prerelease   = 'beta1'
        }
    }
}
