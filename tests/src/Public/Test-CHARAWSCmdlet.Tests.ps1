BeforeAll {
    . "$PSScriptRoot/../../../src/CharlandCustomizations/Public/Test-CHARAWSCmdlet.ps1"
}

Describe 'Test-CHARAWSCmdlet' -Tag 'Unit' {
    BeforeEach {
        Mock Find-Command
        Mock Find-Module
        Mock Install-Module

        Mock Get-Command {
            [PSCustomObject]@{
                Name       = 'Get-EC2Instance'
                ModuleName = 'AWS.Tools.EC2'
            }
        } -ParameterFilter { $Name -eq 'Get-EC2Instance' }
    }

    It 'returns true without discovery or installation when the cmdlet is available' {
        Test-CHARAWSCmdlet -Name 'Get-EC2Instance' | Should -BeTrue

        Should -Not -Invoke Find-Command
        Should -Not -Invoke Find-Module
        Should -Not -Invoke Install-Module
    }

    Context 'when the cmdlet is unavailable' {
        BeforeEach {
            $script:GetCommandCallCount = 0

            Mock Get-Command {
                $script:GetCommandCallCount++
                if ($script:GetCommandCallCount -gt 1) {
                    return [PSCustomObject]@{
                        Name       = 'Get-EC2Instance'
                        ModuleName = 'AWS.Tools.EC2'
                    }
                }
            } -ParameterFilter { $Name -eq 'Get-EC2Instance' }

            Mock Get-Module {
                [PSCustomObject]@{
                    Name    = 'AWS.Tools.Common'
                    Version = [version]'5.2.0'
                }
            } -ParameterFilter { $Name -eq 'AWS.Tools.Common' -and $ListAvailable }

            Mock Find-Command {
                [PSCustomObject]@{
                    Name       = 'Get-EC2Instance'
                    ModuleName = 'AWS.Tools.EC2'
                }
            } -ParameterFilter { $Name -eq 'Get-EC2Instance' -and $Repository -eq 'PSGallery' }

            Mock Find-Module {
                [PSCustomObject]@{
                    Name    = 'AWS.Tools.EC2'
                    Version = [version]'5.2.0'
                }
            } -ParameterFilter {
                $Name -eq 'AWS.Tools.EC2' -and
                $Repository -eq 'PSGallery' -and
                $RequiredVersion -eq '5.2.0'
            }

            Mock Install-Module
        }

        It 'discovers and installs the owning module at the AWS.Tools.Common version' {
            Test-CHARAWSCmdlet -Name 'Get-EC2Instance' -Force | Should -BeTrue

            Should -Invoke Find-Command -Times 1 -Exactly -ParameterFilter {
                $Name -eq 'Get-EC2Instance' -and $Repository -eq 'PSGallery'
            }
            Should -Invoke Find-Module -Times 1 -Exactly -ParameterFilter {
                $Name -eq 'AWS.Tools.EC2' -and $RequiredVersion -eq '5.2.0'
            }
            Should -Invoke Install-Module -Times 1 -Exactly -ParameterFilter {
                $Name -eq 'AWS.Tools.EC2' -and
                $Repository -eq 'PSGallery' -and
                $RequiredVersion -eq '5.2.0' -and
                $Scope -eq 'CurrentUser'
            }
        }

        It 'throws when AWS.Tools.Common is unavailable' {
            Mock Get-Module { $null } -ParameterFilter { $Name -eq 'AWS.Tools.Common' -and $ListAvailable }

            { Test-CHARAWSCmdlet -Name 'Get-EC2Instance' -Force } |
                Should -Throw '*AWS.Tools.Common is not installed*'

            Should -Not -Invoke Install-Module
        }

        It 'throws when no AWS.Tools module contains the cmdlet' {
            Mock Find-Command { $null } -ParameterFilter {
                $Name -eq 'Get-EC2Instance' -and $Repository -eq 'PSGallery'
            }

            { Test-CHARAWSCmdlet -Name 'Get-EC2Instance' -Force } |
                Should -Throw "*No AWS.Tools module containing cmdlet 'Get-EC2Instance'*"

            Should -Not -Invoke Install-Module
        }

        It 'throws when multiple AWS.Tools modules contain the cmdlet' {
            Mock Find-Command {
                @(
                    [PSCustomObject]@{ ModuleName = 'AWS.Tools.EC2' }
                    [PSCustomObject]@{ ModuleName = 'AWS.Tools.S3' }
                )
            } -ParameterFilter {
                $Name -eq 'Get-EC2Instance' -and $Repository -eq 'PSGallery'
            }

            { Test-CHARAWSCmdlet -Name 'Get-EC2Instance' -Force } |
                Should -Throw "*More than one AWS.Tools module containing cmdlet 'Get-EC2Instance'*"

            Should -Not -Invoke Install-Module
        }

        It 'throws when the matching module version is not published' {
            Mock Find-Module { throw 'No match was found' } -ParameterFilter {
                $Name -eq 'AWS.Tools.EC2' -and
                $Repository -eq 'PSGallery' -and
                $RequiredVersion -eq '5.2.0'
            }

            { Test-CHARAWSCmdlet -Name 'Get-EC2Instance' -Force } |
                Should -Throw '*No match was found*'

            Should -Not -Invoke Install-Module
        }

        It 'throws when the cmdlet remains unavailable after installation' {
            Mock Get-Command { $null } -ParameterFilter { $Name -eq 'Get-EC2Instance' }

            { Test-CHARAWSCmdlet -Name 'Get-EC2Instance' -Force } |
                Should -Throw "*unavailable after installing AWS.Tools.EC2 version 5.2.0*"

            Should -Invoke Install-Module -Times 1 -Exactly
        }
    }

    It 'rejects invalid cmdlet names' {
        { Test-CHARAWSCmdlet -Name 'not a cmdlet' } | Should -Throw
    }
}
