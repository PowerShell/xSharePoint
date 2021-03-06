[CmdletBinding()]
param
(
    [Parameter()]
    [string]
    $SharePointCmdletModule = (Join-Path -Path $PSScriptRoot `
            -ChildPath "..\Stubs\SharePoint\15.0.4805.1000\Microsoft.SharePoint.PowerShell.psm1" `
            -Resolve)
)

$script:DSCModuleName = 'SharePointDsc'
$script:DSCResourceName = 'SPServiceInstance'
$script:DSCResourceFullName = 'MSFT_' + $script:DSCResourceName

function Invoke-TestSetup
{
    try
    {
        Import-Module -Name DscResource.Test -Force

        Import-Module -Name (Join-Path -Path $PSScriptRoot `
                -ChildPath "..\UnitTestHelper.psm1" `
                -Resolve)

        $Global:SPDscHelper = New-SPDscUnitTestHelper -SharePointStubModule $SharePointCmdletModule `
            -DscResource $script:DSCResourceName
    }
    catch [System.IO.FileNotFoundException]
    {
        throw 'DscResource.Test module dependency not found. Please run ".\build.ps1 -Tasks build" first.'
    }

    $script:testEnvironment = Initialize-TestEnvironment `
        -DSCModuleName $script:DSCModuleName `
        -DSCResourceName $script:DSCResourceFullName `
        -ResourceType 'Mof' `
        -TestType 'Unit'
}

function Invoke-TestCleanup
{
    Restore-TestEnvironment -TestEnvironment $script:testEnvironment
}

Invoke-TestSetup

try
{
    InModuleScope -ModuleName $script:DSCResourceFullName -ScriptBlock {
        Describe -Name $Global:SPDscHelper.DescribeHeader -Fixture {
            BeforeAll {
                Invoke-Command -ScriptBlock $Global:SPDscHelper.InitializeScript -NoNewScope

                # Mocks for all contexts
                Mock -CommandName Start-SPServiceInstance -MockWith { }
                Mock -CommandName Stop-SPServiceInstance -MockWith { }

                function Add-SPDscEvent
                {
                    param (
                        [Parameter(Mandatory = $true)]
                        [System.String]
                        $Message,

                        [Parameter(Mandatory = $true)]
                        [System.String]
                        $Source,

                        [Parameter()]
                        [ValidateSet('Error', 'Information', 'FailureAudit', 'SuccessAudit', 'Warning')]
                        [System.String]
                        $EntryType,

                        [Parameter()]
                        [System.UInt32]
                        $EventID
                    )
                }
            }

            # Test contexts
            Context -Name "The service instance is not running but should be" -Fixture {
                BeforeAll {
                    $testParams = @{
                        Name   = "Service pool"
                        Ensure = "Present"
                    }

                    Mock -CommandName Get-SPServiceInstance -MockWith {
                        return @()
                    }
                }

                It "Should return absent from the get method" {
                    (Get-TargetResource @testParams).Ensure | Should -Be "Absent"
                }

                It "Should return false from the set method" {
                    Test-TargetResource @testParams | Should -Be $false
                }
            }

            Context -Name "The service instance is not running but should be" -Fixture {
                BeforeAll {
                    $testParams = @{
                        Name   = "Service pool"
                        Ensure = "Present"
                    }

                    Mock -CommandName Get-SPServiceInstance -MockWith {
                        return @(@{
                                TypeName = $testParams.Name
                                Status   = "Disabled"
                                Server   = @{
                                    Name = $env:COMPUTERNAME
                                }
                            })
                    }

                    Mock -CommandName Start-Sleep -MockWith {}
                }

                It "Should return absent from the get method" {
                    (Get-TargetResource @testParams).Ensure | Should -Be "Absent"
                }

                It "Should return false from the set method" {
                    Test-TargetResource @testParams | Should -Be $false
                }

                It "Should call the start service call from the set method" {
                    Set-TargetResource @testParams
                    Assert-MockCalled Start-SPServiceInstance
                }
            }

            Context -Name "The service instance is running and should be" -Fixture {
                BeforeAll {
                    $testParams = @{
                        Name   = "Service pool"
                        Ensure = "Present"
                    }

                    Mock -CommandName Get-SPServiceInstance -MockWith {
                        return @(@{
                                TypeName = $testParams.Name
                                Status   = "Online"
                            })
                    }
                }

                It "Should return present from the get method" {
                    (Get-TargetResource @testParams).Ensure | Should -Be "Present"
                }

                It "Should return true from the test method" {
                    Test-TargetResource @testParams | Should -Be $true
                }
            }

            Context -Name "An invalid service application is specified to start" -Fixture {
                BeforeAll {
                    $testParams = @{
                        Name   = "Service pool"
                        Ensure = "Present"
                    }

                    Mock -CommandName Get-SPServiceInstance {
                        return $null
                    }
                }

                It "Should throw when the set method is called" {
                    { Set-TargetResource @testParams } | Should -Throw
                }
            }

            Context -Name "The service instance is not running and should not be" -Fixture {
                BeforeAll {
                    $testParams = @{
                        Name   = "Service pool"
                        Ensure = "Absent"
                    }

                    Mock -CommandName Get-SPServiceInstance -MockWith {
                        return @(@{
                                TypeName = $testParams.Name
                                Status   = "Disabled"
                            })
                    }
                }

                It "Should return absent from the get method" {
                    (Get-TargetResource @testParams).Ensure | Should -Be "Absent"
                }

                It "Should return true from the test method" {
                    Test-TargetResource @testParams | Should -Be $true
                }
            }

            Context -Name "The service instance is running and should not be" -Fixture {
                BeforeAll {
                    $testParams = @{
                        Name   = "Service pool"
                        Ensure = "Absent"
                    }

                    Mock -CommandName Get-SPServiceInstance -MockWith {
                        return @(@{
                                TypeName = $testParams.Name
                                Status   = "Online"
                                Server   = @{
                                    Name = $env:COMPUTERNAME
                                }
                            })
                    }

                    Mock -CommandName Start-Sleep -MockWith {}
                }

                It "Should return present from the get method" {
                    (Get-TargetResource @testParams).Ensure | Should -Be "Present"
                }

                It "Should return false from the set method" {
                    Test-TargetResource @testParams | Should -Be $false
                }

                It "Should call the stop service call from the set method" {
                    Set-TargetResource @testParams
                    Assert-MockCalled Stop-SPServiceInstance
                }
            }

            Context -Name "An invalid service application is specified to stop" -Fixture {
                BeforeAll {
                    $testParams = @{
                        Name   = "Service pool"
                        Ensure = "Absent"
                    }

                    Mock -CommandName Get-SPServiceInstance {
                        return $null
                    }
                }

                It "Should throw when the set method is called" {
                    { Set-TargetResource @testParams } | Should -Throw
                }
            }
        }
    }
}
finally
{
    Invoke-TestCleanup
}
