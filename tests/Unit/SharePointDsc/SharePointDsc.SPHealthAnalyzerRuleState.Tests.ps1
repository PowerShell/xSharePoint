[CmdletBinding()]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingConvertToSecureStringWithPlainText", "")]
param
(
    [Parameter()]
    [string]
    $SharePointCmdletModule = (Join-Path -Path $PSScriptRoot `
            -ChildPath "..\Stubs\SharePoint\15.0.4805.1000\Microsoft.SharePoint.PowerShell.psm1" `
            -Resolve)
)

$script:DSCModuleName = 'SharePointDsc'
$script:DSCResourceName = 'SPHealthAnalyzerRuleState'
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
                Invoke-Command -Scriptblock $Global:SPDscHelper.InitializeScript -NoNewScope

                # Initialize tests
                Add-Type -TypeDefinition "namespace Microsoft.SharePoint { public class SPQuery { public string Query { get; set; } } }"

                # Mocks for all contexts
                Mock -CommandName Get-SPFarm -MockWith {
                    return @{ }
                }

                Mock -CommandName Get-SPWebapplication -MockWith {
                    return @{
                        Url                            = ""
                        IsAdministrationWebApplication = $true
                    }
                }

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
            Context -Name "The server is not part of SharePoint farm" -Fixture {
                BeforeAll {
                    $testParams = @{
                        Name             = "Drives are at risk of running out of free space."
                        Enabled          = $true
                        RuleScope        = "All Servers"
                        Schedule         = "Daily"
                        FixAutomatically = $false
                    }

                    Mock -CommandName Get-SPFarm -MockWith { throw "Unable to detect local farm" }
                }

                It "Should return null from the get method" {
                    (Get-TargetResource @testParams).Name | Should -BeNullOrEmpty
                }

                It "Should return false from the test method" {
                    Test-TargetResource @testParams | Should -Be $false
                }

                It "Should throw an exception in the set method to say there is no local farm" {
                    { Set-TargetResource @testParams } | Should -Throw "No local SharePoint farm was detected"
                }
            }

            Context -Name "The server is in a farm, but no central admin site is found" -Fixture {
                BeforeAll {
                    $testParams = @{
                        Name             = "Drives are at risk of running out of free space."
                        Enabled          = $true
                        RuleScope        = "All Servers"
                        Schedule         = "Daily"
                        FixAutomatically = $false
                    }

                    Mock -CommandName Get-SPWebapplication -MockWith {
                        return $null
                    }
                }

                It "Should return null from the get method" {
                    (Get-TargetResource @testParams).Name | Should -BeNullOrEmpty
                }

                It "Should return false from the test method" {
                    Test-TargetResource @testParams | Should -Be $false
                }

                It "Should throw an exception in the set method" {
                    { Set-TargetResource @testParams } | Should -Throw "No Central Admin web application was found. Health Analyzer Rule settings will not be applied"
                }
            }

            Context -Name "The server is in a farm, CA found, but no health analyzer rules list is found" -Fixture {
                BeforeAll {
                    $testParams = @{
                        Name             = "Drives are at risk of running out of free space."
                        Enabled          = $true
                        RuleScope        = "All Servers"
                        Schedule         = "Daily"
                        FixAutomatically = $false
                    }

                    Mock -CommandName Get-SPWeb -MockWith {
                        return @{
                            Lists = $null
                        }
                    }
                }

                It "Should return null from the get method" {
                    (Get-TargetResource @testParams).Name | Should -BeNullOrEmpty
                }

                It "Should return false from the test method" {
                    Test-TargetResource @testParams | Should -Be $false
                }

                It "Should throw an exception in the set method" {
                    { Set-TargetResource @testParams } | Should -Throw "Could not find Health Analyzer Rules list. Health Analyzer Rule settings will not be applied"
                }
            }

            Context -Name "The server is in a farm, CA found, Health Rules list found, but no rules match the specified rule name" -Fixture {
                BeforeAll {
                    $testParams = @{
                        Name             = "Drives are at risk of running out of free space."
                        Enabled          = $true
                        RuleScope        = "All Servers"
                        Schedule         = "Daily"
                        FixAutomatically = $false
                    }

                    Mock -CommandName Get-SPWeb -MockWith {
                        $web = @{
                            Lists = @{
                                BaseTemplate = "HealthRules"
                            } | Add-Member -MemberType ScriptMethod -Name GetItems -Value {
                                return , @()
                            } -PassThru
                        }
                        return $web
                    }

                    Mock -CommandName Get-SPFarm -MockWith { return @{ } }
                }

                It "Should return null from the get method" {
                    (Get-TargetResource @testParams).Name | Should -BeNullOrEmpty
                }

                It "Should return false from the test method" {
                    Test-TargetResource @testParams | Should -Be $false
                }

                It "Should throw an exception in the set method" {
                    { Set-TargetResource @testParams } | Should -Throw "Could not find specified Health Analyzer Rule. Health Analyzer Rule settings will not be applied"
                }
            }

            Context -Name "The server is in a farm, CA/Health Rules list/Health Rule found, but the incorrect settings have been applied" -Fixture {
                BeforeAll {
                    $testParams = @{
                        Name             = "Drives are at risk of running out of free space."
                        Enabled          = $true
                        RuleScope        = "All Servers"
                        Schedule         = "Daily"
                        FixAutomatically = $false
                    }

                    Mock -CommandName Get-SPWeb -MockWith {
                        $web = @{
                            Lists = @{
                                BaseTemplate = "HealthRules"
                            } | Add-Member -MemberType ScriptMethod -Name GetItems -Value {
                                $itemcol = @(@{
                                        HealthRuleCheckEnabled      = $false;
                                        HealthRuleScope             = "Any Server";
                                        HealthRuleSchedule          = "Weekly";
                                        HealthRuleAutoRepairEnabled = $true
                                    } | Add-Member -MemberType ScriptMethod -Name Update -Value {
                                        $Global:SPDscHealthRulesUpdated = $true
                                    } -PassThru )
                                return , $itemcol
                            } -PassThru
                        }
                        return $web
                    }
                }

                It "Should return values from the get method" {
                    $result = Get-TargetResource @testParams
                    $result.Enabled | Should -Be $false
                    $result.RuleScope | Should -Be 'Any Server'
                    $result.Schedule | Should -Be 'Weekly'
                    $result.FixAutomatically | Should -Be $true
                }

                It "Should return false from the test method" {
                    Test-TargetResource @testParams | Should -Be $false
                }

                $Global:SPDscHealthRulesUpdated = $false
                It "set the configured values for the specific Health Analyzer Rule" {
                    Set-TargetResource @testParams
                    $Global:SPDscHealthRulesUpdated | Should -Be $true
                }
            }

            Context -Name "The server is in a farm and the correct settings have been applied" -Fixture {
                BeforeAll {
                    $testParams = @{
                        Name             = "Drives are at risk of running out of free space."
                        Enabled          = $true
                        RuleScope        = "All Servers"
                        Schedule         = "Daily"
                        FixAutomatically = $false
                    }

                    Mock -CommandName Get-SPWeb -MockWith {
                        $web = @{
                            Lists = @{
                                BaseTemplate = "HealthRules"
                            } | Add-Member -MemberType ScriptMethod -Name GetItems -Value {
                                $itemcol = @(@{
                                        HealthRuleCheckEnabled      = $true;
                                        HealthRuleScope             = "All Servers";
                                        HealthRuleSchedule          = "Daily";
                                        HealthRuleAutoRepairEnabled = $false
                                    } | Add-Member -MemberType ScriptMethod -Name Update -Value {
                                        $Global:SPDscHealthRulesUpdated = $true
                                    } -PassThru )
                                return , $itemcol
                            } -PassThru
                        }
                        return $web
                    }
                }

                It "Should return values from the get method" {
                    $result = Get-TargetResource @testParams
                    $result.Enabled | Should -Be $true
                    $result.RuleScope | Should -Be 'All Servers'
                    $result.Schedule | Should -Be 'Daily'
                    $result.FixAutomatically | Should -Be $false
                }

                It "Should return true from the test method" {
                    Test-TargetResource @testParams | Should -Be $true
                }
            }

            Context -Name "Running ReverseDsc Export" -Fixture {
                BeforeAll {
                    Import-Module (Join-Path -Path (Split-Path -Path (Get-Module SharePointDsc -ListAvailable).Path -Parent) -ChildPath "Modules\SharePointDSC.Reverse\SharePointDSC.Reverse.psm1")

                    Mock -CommandName Write-Host -MockWith { }

                    Mock -CommandName Get-TargetResource -MockWith {
                        return @{
                            Name             = "Drives are running out of free space"
                            Enabled          = $true
                            RuleScope        = "All Servers"
                            Schedule         = "Daily"
                            FixAutomatically = $false
                        }
                    }

                    Mock -CommandName Get-SPWebApplication -MockWith {
                        $spWebApp = [PSCustomObject]@{
                            DisplayName                    = "Central Administration"
                            IsAdministrationWebApplication = $true
                            Url                            = "http://ca.contoso.com"
                        }
                        return $spWebApp
                    }

                    Mock -CommandName Get-SPWeb -MockWith {
                        $spWeb = [PSCustomObject]@{
                            DisplayName = "Central Administration"
                            Lists       = @(
                                @{
                                    BaseTemplate = "HealthRules"
                                    Items        = @(
                                        @{
                                            Title = "Drives are running out of free space"
                                        }
                                    )
                                }
                            )
                        }
                        return $spWeb
                    }

                    if ($null -eq (Get-Variable -Name 'spFarmAccount' -ErrorAction SilentlyContinue))
                    {
                        $mockPassword = ConvertTo-SecureString -String "password" -AsPlainText -Force
                        $Global:spFarmAccount = New-Object -TypeName System.Management.Automation.PSCredential ("contoso\spfarm", $mockPassword)
                    }

                    $result = @'
        SPHealthAnalyzerRuleState [0-9A-Fa-f]{8}[-][0-9A-Fa-f]{4}[-][0-9A-Fa-f]{4}[-][0-9A-Fa-f]{4}[-][0-9A-Fa-f]{12}
        {
            Enabled              = \$True;
            FixAutomatically     = \$False;
            Name                 = "Drives are running out of free space";
            PsDscRunAsCredential = \$Credsspfarm;
            RuleScope            = "All Servers";
            Schedule             = "Daily";
        }

'@
                }

                It "Should return valid DSC block from the Export method" {
                    Export-TargetResource | Should -Match $result
                }
            }
        }
    }
}
finally
{
    Invoke-TestCleanup
}
