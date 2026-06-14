BeforeAll {
    $script:ScriptPath = "$PSScriptRoot/../../../Scripts/Test-BranchPathPolicy.ps1"
}

Describe 'Test-BranchPathPolicy' -Tag 'Unit' {

    Context 'Branch name format validation' {

        It 'Blocks all changes when branch name has no forward slash' {
            {
                & $script:ScriptPath -BranchName 'my-branch-no-slash' -ChangedPath @('src/CharlandCustomizations/Public/Test-Thing.ps1')
            } | Should -Throw '*does not contain a forward slash*'
        }

        It 'Blocks workflow changes when branch name has no forward slash' {
            {
                & $script:ScriptPath -BranchName 'update-workflows' -ChangedPath @('.github/workflows/publish.yml')
            } | Should -Throw '*does not contain a forward slash*'
        }

        It 'Passes when branch name contains a forward slash' {
            {
                & $script:ScriptPath -BranchName 'feature/add-command' -ChangedPath @(
                    'src/CharlandCustomizations/Public/Test-Thing.ps1'
                )
            } | Should -Not -Throw
        }
    }

    Context 'Path separation policy' {

        It 'Blocks workflow configuration changes on normal code branches' {
            {
                & $script:ScriptPath -BranchName 'feature/add-command' -ChangedPath @('.github/workflows/pr-quality-gate.yml')
            } | Should -Throw '*normal code branch*'
        }

        It 'Allows source and test changes on normal code branches' {
            {
                & $script:ScriptPath -BranchName 'feature/add-command' -ChangedPath @(
                    'src/CharlandCustomizations/Public/Test-Thing.ps1',
                    'tests/Unit/Git/Test-Thing.Tests.ps1'
                )
            } | Should -Not -Throw
        }

        It 'Blocks source changes on infrastructure branches' {
            {
                & $script:ScriptPath -BranchName 'infrastructure/update-ci' -ChangedPath @('src/CharlandCustomizations/Public/Test-Thing.ps1')
            } | Should -Throw '*workflow/infrastructure branch*'
        }

        It 'Allows workflow configuration changes on infrastructure branches' {
            {
                & $script:ScriptPath -BranchName 'workflow/update-quality-gate' -ChangedPath @('.github/workflows/pr-quality-gate.yml')
            } | Should -Not -Throw
        }

        It 'Treats ci as a branch token, not a substring' {
            {
                & $script:ScriptPath -BranchName 'feature/special-case' -ChangedPath @('src/CharlandCustomizations/Public/Test-Thing.ps1')
            } | Should -Not -Throw

            {
                & $script:ScriptPath -BranchName 'chore/ci-config' -ChangedPath @('src/CharlandCustomizations/Public/Test-Thing.ps1')
            } | Should -Throw '*workflow/infrastructure branch*'
        }
    }
}