[CmdletBinding()]
param(
    [string] $SharePointCmdletModule = (Join-Path $PSScriptRoot "..\Stubs\SharePoint\15.0.4693.1000\Microsoft.SharePoint.PowerShell.psm1" -Resolve)
)

$ErrorActionPreference = 'stop'
Set-StrictMode -Version latest

$RepoRoot = (Resolve-Path $PSScriptRoot\..\..).Path
$Global:CurrentSharePointStubModule = $SharePointCmdletModule 
    
$ModuleName = "MSFT_xSPUserProfileSyncConnection"
Import-Module (Join-Path $RepoRoot "Modules\xSharePoint\DSCResources\$ModuleName\$ModuleName.psm1")


## New-Object Microsoft.Office.Server.UserProfiles.UserProfileConfigManager($context)
## New-Object Microsoft.Office.Server.UserProfiles.DirectoryServiceNamingContext
## Mock New-Object { return $zipMock } -ParameterFilter { $ComObject -eq 'Shell.Application' }


Describe "xSPUserProfileSyncConnection" {
    InModuleScope $ModuleName {
        $testParams = @{
            UserProfileService = "User Profile Service Application"
            Forest = "contoso.com"
            Name = "Contoso"
            ConnectionCredentials = New-Object System.Management.Automation.PSCredential ("domain\username", (ConvertTo-SecureString "password" -AsPlainText -Force))
            Server = "server.contoso.com"
            UseSSL = $false
            IncludedOUs = @("OU=SharePoint Users,DC=Contoso,DC=com")
            ConnectionType = "ActiveDirectory"
        }
        
        try { [Microsoft.Office.Server.UserProfiles] }
        catch {
            Add-Type @"
                namespace Microsoft.Office.Server.UserProfiles {
                public enum ConnectionType { ActiveDirectory, BusinessDataCatalog };
                }        
"@
        }    
        $connection = @(@{ DisplayName = "Contoso" })


        ## connection exist, forest is the same
        $connection = $connection  | Add-Member ScriptMethod RefreshSchema {
                            $Global:xSPUPSSyncConnectionRefreshSchemaCalled = $true
                        } -PassThru | Add-Member ScriptMethod Update {
                            $Global:xSPUPSSyncConnectionUpdateCalled = $true
                        } -PassThru| Add-Member ScriptMethod SetCredentials {
                                param($userAccount,$securePassword )
                            $Global:xSPUPSSyncConnectionSetCredentialsCalled  = $true
                        } -PassThru
        #connection exist, different forest, force provided
        $connection = $connection  | Add-Member ScriptMethod Delete {
                            $Global:xSPUPSSyncConnectionDeleteCalled = $true
                        } -PassThru

                        #connection exist, different forest, force not provided
                            #throw exception





        $namingContext =@( @{ AccountUserName = "TestAccount" 
                            IncludedOUs = @("OU=com, OU=Contoso, OU=Included")
                            ExcludedOUs = @("OU=com, OU=Contoso, OU=Excluded")
                            })
        $namingContext = $namingContext  | Add-Member ScriptMethod Update {
                            $Global:xSPWebApplicationUpdateCalled = $true
                        } -PassThru | Add-Member ScriptMethod UpdateWorkflowConfigurationSettings {
                            $Global:xSPWebApplicationUpdateWorkflowCalled = $true
                        } -PassThru
        
        
        $ConnnectionManager = New-Object System.Collections.ArrayList | Add-Member ScriptMethod  AddActiveDirectoryConnection{ `
                                                param([Microsoft.Office.Server.UserProfiles.ConnectionType] $connectionType,  `
                                                $name, `
                                                $forest, `
                                                $useSSL, `
                                                $userName, `
                                                $securePassword, `
                                                $namingContext, `
                                                $p1, $p2 `
                                            )

        $Global:xSPUPSAddActiveDirectoryConnectionCalled =$true
        } -PassThru

        Import-Module (Join-Path ((Resolve-Path $PSScriptRoot\..\..).Path) "Modules\xSharePoint")
        
        Mock Get-xSharePointServiceContext {return @{}}

        Mock Invoke-xSharePointCommand { 
            return Invoke-Command -ScriptBlock $ScriptBlock -ArgumentList $Arguments -NoNewScope
        }
        
        Import-Module $Global:CurrentSharePointStubModule -WarningAction SilentlyContinue 
        
        Mock New-PSSession { return $null } -ModuleName "xSharePoint.Util"

        
        Context "When connection doesn't exist" {
           $userProfileServiceNoConnections =  @{
                Name = "User Profile Service Application"
                ApplicationPool = "SharePoint Service Applications"
                FarmAccount = New-Object System.Management.Automation.PSCredential ("domain\username", (ConvertTo-SecureString "password" -AsPlainText -Force))
                ServiceApplicationProxyGroup = "Proxy Group"
                ConnnectionManager = @()
            }

            Mock Get-SPServiceApplication { return $userProfileServiceNoConnections }

            Mock New-Object -MockWith {
            return (@{
            ConnectionManager = $ConnnectionManager  
            } | Add-Member ScriptMethod IsSynchronizationRunning {
                $Global:UpsSyncIsSynchronizationRunning=$true;
                return $false; 
            } -PassThru   )
            } -ParameterFilter { $TypeName -eq "Microsoft.Office.Server.UserProfiles.UserProfileConfigManager" } 
            
            Mock New-Object -MockWith {return @{}
            
            }  -ParameterFilter { $TypeName -eq "Microsoft.Office.Server.UserProfiles.DirectoryServiceNamingContext"}
            It "returns null from the Get method" {
                Get-TargetResource @testParams | Should BeNullOrEmpty
                Assert-MockCalled Get-SPServiceApplication -ParameterFilter { $Name -eq $testParams.UserProfileService } 
            }
            
            It "returns false when the Test method is called" {
                Test-TargetResource @testParams | Should Be $false
            }

            It "creates a new service application in the set method" {
                $Global:xSPUPSAddActiveDirectoryConnectionCalled =$false
                Set-TargetResource @testParams
                $Global:xSPUPSAddActiveDirectoryConnectionCalled | Should be $true
            }
        }

        Context "When connection exists and account is different" {
            $namingContext =@{ AccountUserName = "TestAccount" 
                    IncludedOUs = New-Object System.Collections.ArrayList 
                    ExcludedOUs = New-Object System.Collections.ArrayList 
                  }
            $namingContext.IncludedOUs.Add("OU=com, OU=Contoso, OU=Included")
            $namingContext.ExcludedOUs.Add("OU=com, OU=Contoso, OU=Excluded")


            $connection = @{ DisplayName = "Contoso" 
                            Server = "contoso.com"
                              NamingContexts=  New-Object System.Collections.ArrayList
                            }
            
            $connection.NamingContexts.Add($namingContext);
            $connection = $connection  | Add-Member ScriptMethod RefreshSchema {
                    $Global:xSPUPSSyncConnectionRefreshSchemaCalled = $true
                } -PassThru | Add-Member ScriptMethod Update {
                    $Global:xSPUPSSyncConnectionUpdateCalled = $true
                } -PassThru| Add-Member ScriptMethod SetCredentials {
                     param($userAccount,$securePassword )
                    $Global:xSPUPSSyncConnectionSetCredentialsCalled  = $true
                } -PassThru

            $userProfileServiceValidConnection =  @{
                Name = "User Profile Service Application"
                TypeName = "User Profile Service Application"
                ApplicationPool = "SharePoint Service Applications"
                FarmAccount = New-Object System.Management.Automation.PSCredential ("domain\username", (ConvertTo-SecureString "password" -AsPlainText -Force))
                ServiceApplicationProxyGroup = "Proxy Group"
                ConnectionManager=  New-Object System.Collections.ArrayList
                
            }
            $userProfileServiceValidConnection.ConnectionManager.Add($connection);
            Mock Get-SPServiceApplication { return $userProfileServiceValidConnection }
            
            
            $ConnnectionManager.Add($connection)
            Mock New-Object -MockWith {
            return (@{} | Add-Member ScriptMethod IsSynchronizationRunning {
                $Global:UpsSyncIsSynchronizationRunning=$true;
                return $false; 
            } -PassThru   |  Add-Member  ConnectionManager $ConnnectionManager  -PassThru )
            } -ParameterFilter { $TypeName -eq "Microsoft.Office.Server.UserProfiles.UserProfileConfigManager" } 
         


            It "returns service instance from the Get method" {
                Get-TargetResource @testParams | Should Not BeNullOrEmpty
                Assert-MockCalled Get-SPServiceApplication -ParameterFilter { $Name -eq $testParams.UserProfileService } 
            }
            
            It "returns false when the Test method is called" {
                Test-TargetResource @testParams | Should Be $false
            }

            It "execute update credentials" {
                $Global:xSPUPSSyncConnectionSetCredentialsCalled=$false
                $Global:xSPUPSSyncConnectionRefreshSchemaCalled=$false
                Set-TargetResource @testParams
                $Global:xSPUPSSyncConnectionSetCredentialsCalled | Should be $true
                $Global:xSPUPSSyncConnectionRefreshSchemaCalled | Should be $true
            }
        }

        Context "When connection exists and forest is different" {
        ###//TODO: execute integration test
            $namingContext =@{ AccountUserName = "TestAccount" 
                    IncludedOUs = New-Object System.Collections.ArrayList 
                    ExcludedOUs = New-Object System.Collections.ArrayList 
                  }
            $namingContext.IncludedOUs.Add("OU=com, OU=Contoso, OU=Included")
            $namingContext.ExcludedOUs.Add("OU=com, OU=Contoso, OU=Excluded")
            
            $connection = @{ DisplayName = "Contoso" 
                              NamingContexts=  New-Object System.Collections.ArrayList
                              Server =   "Litware.net"         
                            }
            $connection.NamingContexts.Add($namingContext);
            $connection = $connection  | Add-Member ScriptMethod Delete {
                    $Global:xSPUPSSyncConnectionDeleteCalled = $true
                } -PassThru
            $userProfileServiceValidConnection =  @{
                Name = "User Profile Service Application"
                TypeName = "User Profile Service Application"
                ApplicationPool = "SharePoint Service Applications"
                FarmAccount = New-Object System.Management.Automation.PSCredential ("domain\username", (ConvertTo-SecureString "password" -AsPlainText -Force))
                ServiceApplicationProxyGroup = "Proxy Group"
                ConnectionManager=  New-Object System.Collections.ArrayList
            }

            $userProfileServiceValidConnection.ConnectionManager.Add($connection);
            Mock Get-SPServiceApplication { return $userProfileServiceValidConnection }
            $ConnnectionManager = New-Object System.Collections.ArrayList | Add-Member ScriptMethod  AddActiveDirectoryConnection{ `
                                                    param([Microsoft.Office.Server.UserProfiles.ConnectionType] $connectionType,  `
                                                    $name, `
                                                    $forest, `
                                                    $useSSL, `
                                                    $userName, `
                                                    $securePassword, `
                                                    $namingContext, `
                                                    $p1, $p2 `
                                                )

            $Global:xSPUPSAddActiveDirectoryConnectionCalled =$true
            } -PassThru            
            $ConnnectionManager.Add($connection)
            Mock New-Object -MockWith {
                return (@{} | Add-Member ScriptMethod IsSynchronizationRunning {
                    $Global:UpsSyncIsSynchronizationRunning=$true;
                    return $false; 
                } -PassThru   |  Add-Member  ConnectionManager $ConnnectionManager  -PassThru )
            } -ParameterFilter { $TypeName -eq "Microsoft.Office.Server.UserProfiles.UserProfileConfigManager" } 
            Mock New-Object -MockWith {return @{}
            }  -ParameterFilter { $TypeName -eq "Microsoft.Office.Server.UserProfiles.DirectoryServiceNamingContext"}

            It "returns service instance from the Get method" {
                Get-TargetResource @testParams | Should Not BeNullOrEmpty
                Assert-MockCalled Get-SPServiceApplication -ParameterFilter { $Name -eq $testParams.UserProfileService } 
            }

            It "returns false when the Test method is called" {
                Test-TargetResource @testParams | Should Be $false
            }
            It "throws exception as force isn't specified" {
                $Global:xSPUPSSyncConnectionDeleteCalled=$false
                {Set-TargetResource @testParams} | should throw
                $Global:xSPUPSSyncConnectionDeleteCalled | Should be $false
            }

            $forceTestParams = @{
                UserProfileService = "User Profile Service Application"
                Forest = "contoso.com"
                Name = "Contoso"
                ConnectionCredentials = New-Object System.Management.Automation.PSCredential ("domain\username", (ConvertTo-SecureString "password" -AsPlainText -Force))
                Server = "server.contoso.com"
                UseSSL = $false
                Force = $true
                IncludedOUs = @("OU=SharePoint Users,DC=Contoso,DC=com")
                ConnectionType = "ActiveDirectory"
            }
         
             It "delete and create as force is specified" {
                $Global:xSPUPSSyncConnectionDeleteCalled=$false
                $Global:xSPUPSAddActiveDirectoryConnectionCalled =$false
                Set-TargetResource @forceTestParams 
                $Global:xSPUPSSyncConnectionDeleteCalled | Should be $true
                $Global:xSPUPSAddActiveDirectoryConnectionCalled | Should be $true
            }
        }

        Context "When synchronization is running" {
           #needs service application
            Mock Get-SPServiceApplication { 
                return @(
                    New-Object Object|Add-Member NoteProperty ServiceApplicationProxyGroup "Proxy Group" -PassThru 
                )
            }
            Mock New-Object -MockWith {
                return (@{} | Add-Member ScriptMethod IsSynchronizationRunning {
                    $Global:UpsSyncIsSynchronizationRunning=$true;
                    return $true;
                } -PassThru)
            } -ParameterFilter { $TypeName -eq "Microsoft.Office.Server.UserProfiles.UserProfileConfigManager" } 

            It "attempts to execute method but synchronization is running" {
                $Global:UpsSyncIsSynchronizationRunning=$false
                $Global:xSPUPSAddActiveDirectoryConnectionCalled =$false
                {Set-TargetResource @testParams }| Should throw
                Assert-MockCalled Get-SPServiceApplication
                Assert-MockCalled New-Object -ParameterFilter { $TypeName -eq "Microsoft.Office.Server.UserProfiles.UserProfileConfigManager" } 
                $Global:UpsSyncIsSynchronizationRunning| Should be $true;
                $Global:xSPUPSAddActiveDirectoryConnectionCalled | Should be $false;
            }

        }
        
        Context "When connection exists and Excluded and Included OUs are different. force parameter provided" {
            $namingContext =@{ AccountUserName = "TestAccount" 
                IncludedOUs = New-Object System.Collections.ArrayList 
                ExcludedOUs = New-Object System.Collections.ArrayList 
            }
            $namingContext.IncludedOUs.Add("OU=com, OU=Contoso, OU=Included")
            $namingContext.ExcludedOUs.Add("OU=com, OU=Contoso, OU=Excluded")


            $connection = @{ DisplayName = "Contoso" 
                            Server = "contoso.com"
                              NamingContexts=  New-Object System.Collections.ArrayList
            }
            
            $connection.NamingContexts.Add($namingContext);
            $connection = $connection  | Add-Member ScriptMethod RefreshSchema {
                    $Global:xSPUPSSyncConnectionRefreshSchemaCalled = $true
                } -PassThru | Add-Member ScriptMethod Update {
                    $Global:xSPUPSSyncConnectionUpdateCalled = $true
                } -PassThru| Add-Member ScriptMethod SetCredentials {
                     param($userAccount,$securePassword )
                    $Global:xSPUPSSyncConnectionSetCredentialsCalled  = $true
                } -PassThru

            $userProfileServiceValidConnection =  @{
                Name = "User Profile Service Application"
                TypeName = "User Profile Service Application"
                ApplicationPool = "SharePoint Service Applications"
                FarmAccount = New-Object System.Management.Automation.PSCredential ("domain\username", (ConvertTo-SecureString "password" -AsPlainText -Force))
                ServiceApplicationProxyGroup = "Proxy Group"
                ConnectionManager=  New-Object System.Collections.ArrayList
                
            }
            $userProfileServiceValidConnection.ConnectionManager.Add($connection);
            Mock Get-SPServiceApplication { return $userProfileServiceValidConnection }

            Mock New-Object -MockWith {
                return (@{
                    ConnectionManager = $ConnnectionManager  
                        } | Add-Member ScriptMethod IsSynchronizationRunning {
                $Global:UpsSyncIsSynchronizationRunning=$true;
                return $false; 
                } -PassThru   )
            } -ParameterFilter { $TypeName -eq "Microsoft.Office.Server.UserProfiles.UserProfileConfigManager" } 
            
            $difOUsTestParams = @{
                UserProfileService = "User Profile Service Application"
                Forest = "contoso.com"
                Name = "Contoso"
                ConnectionCredentials = New-Object System.Management.Automation.PSCredential ("domain\username", (ConvertTo-SecureString "password" -AsPlainText -Force))
                Server = "server.contoso.com"
                UseSSL = $false
                Force = $false
                IncludedOUs = @("OU=SharePoint Users,DC=Contoso,DC=com","OU=Notes Users,DC=Contoso,DC=com")
                ExcludedOUs = @("OU=Excluded, OU=SharePoint Users,DC=Contoso,DC=com")
                ConnectionType = "ActiveDirectory"
            }

            It "returns values from the get method" {
                Get-TargetResource @difOUsTestParams | Should Not BeNullOrEmpty
                Assert-MockCalled Get-SPServiceApplication -ParameterFilter { $Name -eq $testParams.UserProfileService } 
            }

            It "returns false when the Test method is called" {
                Test-TargetResource @difOUsTestParams | Should Be $false
            }


            It "updates OU lists" {
                $Global:xSPUPSSyncConnectionUpdateCalled= $false
                $Global:xSPUPSSyncConnectionSetCredentialsCalled  = $false
                $Global:xSPUPSSyncConnectionRefreshSchemaCalled =$false
                Set-TargetResource @difOUsTestParams
                $Global:xSPUPSSyncConnectionUpdateCalled | Should be $true
                $Global:xSPUPSSyncConnectionSetCredentialsCalled  | Should be $true
                $Global:xSPUPSSyncConnectionRefreshSchemaCalled | Should be $true
            }
        }
    }    
}
