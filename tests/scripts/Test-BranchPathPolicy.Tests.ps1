BeforeAll {
    $script:ScriptPath = "$PSScriptRoot/../../Scripts/Test-BranchPathPolicy.ps1"

    function Invoke-BranchPolicyScript {
        param(
            [Parameter(Mandatory)]
            [string]$BranchName,

            [Parameter(Mandatory)]
            [AllowEmptyCollection()]
            [string[]]$ChangedPath
        )

            $quotedChangedPath = $ChangedPath | ForEach-Object {
                "'" + ($_ -replace "'", "''") + "'"
            }
            $changedPathLiteral = "@(" + ($quotedChangedPath -join ', ') + ")"
            $command = "& { & '$script:ScriptPath' -BranchName '$BranchName' -ChangedPath $changedPathLiteral }"

            $null = & pwsh -NoProfile -ExecutionPolicy Bypass -Command $command 2>&1
        return $LASTEXITCODE
    }
}

Describe 'Test-BranchPathPolicy' -Tag 'Unit' {

    Context 'Branch name format validation' {

        It 'Blocks all changes when branch name has no forward slash' {
            {
                & $script:ScriptPath -BranchName 'my-branch-no-slash' -ChangedPath @('src/CharlandCustomizations/Public/Test-Thing.ps1')
            } | Should -Throw '*unrecognized prefix*'
        }

        It 'Blocks workflow changes when branch name has no forward slash' {
            {
                & $script:ScriptPath -BranchName 'update-workflows' -ChangedPath @('.github/workflows/publish.yml')
            } | Should -Throw '*unrecognized prefix*'
        }

        It 'Passes when branch name contains a forward slash' {
            {
                & $script:ScriptPath -BranchName 'feature/add-command' -ChangedPath @(
                    'src/CharlandCustomizations/Public/Test-Thing.ps1'
                )
            } | Should -Not -Throw
        }

        It 'Returns exit code 0 for passing policy checks' {
            (Invoke-BranchPolicyScript -BranchName 'feature/add-command' -ChangedPath @(
                'src/CharlandCustomizations/Public/Test-Thing.ps1'
            )) | Should -Be 0
        }

        It 'Blocks all changes when branch prefix is not approved' {
            {
                & $script:ScriptPath -BranchName 'experiment/new-policy' -ChangedPath @(
                    'src/CharlandCustomizations/Public/Test-Thing.ps1'
                )
            } | Should -Throw '*unrecognized prefix*'
        }

        It 'Allows approved AI branch prefix copilot-code' {
            {
                & $script:ScriptPath -BranchName 'copilot-code/test-improvements' -ChangedPath @(
                    'src/CharlandCustomizations/Public/Test-Thing.ps1'
                )
            } | Should -Not -Throw
        }
    }

    Context 'Path separation policy' {

        It 'Allows workflow configuration changes on normal code branches' {
            {
                & $script:ScriptPath -BranchName 'feature/add-command' -ChangedPath @('.github/workflows/pr-quality-gate.yml')
            } | Should -Not -Throw
        }

        It 'Returns exit code 1 when policy validation fails' {
            (Invoke-BranchPolicyScript -BranchName 'feature/add-command' -ChangedPath @('Scripts/Test-ManifestCompliance.ps1')) | Should -Be 1
        }

        It 'Blocks Scripts changes on normal code branches' {
            {
                & $script:ScriptPath -BranchName 'feature/add-command' -ChangedPath @('Scripts/Test-ManifestCompliance.ps1')
            } | Should -Throw '*normal code branch*'
        }

        It 'Allows source and tests/src changes on normal code branches' {
            {
                & $script:ScriptPath -BranchName 'feature/add-command' -ChangedPath @(
                    'src/CharlandCustomizations/Public/Test-Thing.ps1',
                    'tests/src/CharlandCustomizations/Public/Git/Test-Thing.Tests.ps1'
                )
            } | Should -Not -Throw
        }

        It 'Allows only the cSpell configuration under .vscode on normal code branches' {
            {
                & $script:ScriptPath -BranchName 'feature/add-command' -ChangedPath @('.vscode/cspell.json')
            } | Should -Not -Throw

            {
                & $script:ScriptPath -BranchName 'codex-code/add-command' -ChangedPath @('.vscode/cspell.json')
            } | Should -Not -Throw
        }

        It 'Allows neighboring VS Code configuration on normal code branches' {
            foreach ($path in @('.vscode/settings.json', '.vscode/tasks.json', '.vscode/other.json')) {
                {
                    & $script:ScriptPath -BranchName 'feature/add-command' -ChangedPath @($path)
                } | Should -Not -Throw
            }
        }

        It 'Allows tests/scripts changes on normal code branches' {
            {
                & $script:ScriptPath -BranchName 'feature/add-command' -ChangedPath @('tests/scripts/Build-Module.Tests.ps1')
            } | Should -Not -Throw
        }

        It 'Allows source changes on infrastructure branches' {
            {
                & $script:ScriptPath -BranchName 'infrastructure/update-ci' -ChangedPath @('src/CharlandCustomizations/Public/Test-Thing.ps1')
            } | Should -Not -Throw
        }

        It 'Allows tests/src changes on infrastructure branches' {
            {
                & $script:ScriptPath -BranchName 'infrastructure/update-ci' -ChangedPath @('tests/src/CharlandCustomizations/Public/Test-Thing.Tests.ps1')
            } | Should -Not -Throw
        }

        It 'Allows workflow configuration changes on infrastructure branches' {
            {
                & $script:ScriptPath -BranchName 'workflow/update-quality-gate' -ChangedPath @('.github/workflows/pr-quality-gate.yml')
            } | Should -Not -Throw
        }

        It 'Allows VS Code configuration changes on infrastructure branches' {
            {
                & $script:ScriptPath -BranchName 'infra/editor-config' -ChangedPath @(
                    '.vscode/cspell.json',
                    '.vscode/settings.json'
                )
            } | Should -Not -Throw
        }

        It 'Allows tests/scripts changes on infrastructure branches' {
            {
                & $script:ScriptPath -BranchName 'ci/update-tests' -ChangedPath @('tests/scripts/Build-Module.Tests.ps1')
            } | Should -Not -Throw
        }

        It 'Treats ci as a branch prefix, not a substring' {
            {
                & $script:ScriptPath -BranchName 'feature/concise-docs' -ChangedPath @('src/CharlandCustomizations/Public/Test-Thing.ps1')
            } | Should -Not -Throw

            {
                & $script:ScriptPath -BranchName 'chore/ci-config' -ChangedPath @('src/CharlandCustomizations/Public/Test-Thing.ps1')
            } | Should -Not -Throw
        }
    }

    Context 'Publish branch policy' {

        It 'Allows source changes on publish branches' {
            {
                & $script:ScriptPath -BranchName 'publish/v0.5.0' -ChangedPath @(
                    'src/CharlandCustomizations/CharlandCustomizations.psd1'
                )
            } | Should -Not -Throw
        }

        It 'Allows docs changes on publish branches' {
            {
                & $script:ScriptPath -BranchName 'publish/v0.5.0' -ChangedPath @(
                    'docs/CHANGELOG.md'
                )
            } | Should -Not -Throw
        }

        It 'Allows .github changes on publish branches' {
            {
                & $script:ScriptPath -BranchName 'publish/v0.5.0' -ChangedPath @('.github/workflows/publish.yml')
            } | Should -Not -Throw
        }

        It 'Blocks Scripts changes on publish branches' {
            {
                & $script:ScriptPath -BranchName 'publish/v0.5.0' -ChangedPath @('Scripts/Build-Module.ps1')
            } | Should -Throw '*publish/release branch*'
        }

        It 'Allows tests changes on publish branches' {
            {
                & $script:ScriptPath -BranchName 'publish/v0.5.0' -ChangedPath @('tests/src/Something.Tests.ps1')
            } | Should -Not -Throw
        }

        It 'Allows .kiro changes on publish branches' {
            {
                & $script:ScriptPath -BranchName 'publish/v0.5.0' -ChangedPath @('.kiro/settings/mcp.json')
            } | Should -Not -Throw
        }

        It 'Allows the cSpell configuration on publish branches' {
            {
                & $script:ScriptPath -BranchName 'publish/v0.6.0' -ChangedPath @('.vscode/cspell.json')
            } | Should -Not -Throw
        }

        It 'Allows root files on publish branches' {
            {
                & $script:ScriptPath -BranchName 'publish/v0.5.0' -ChangedPath @('README.md')
            } | Should -Not -Throw
        }
    }
}
