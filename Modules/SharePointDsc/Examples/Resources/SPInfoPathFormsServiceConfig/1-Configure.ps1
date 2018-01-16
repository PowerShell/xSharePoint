<#
.EXAMPLE
    This example shows how to deploy Access Services 2010 to the local SharePoint farm.
#>

    Configuration Example
    {
        param(
            [Parameter(Mandatory = $true)]
            [PSCredential]
            $SetupAccount
        )
        Import-DscResource -ModuleName SharePointDsc

        node localhost {
            SPInfoPathFormsServiceConfig InfoPathFormsServiceConfig
            {
                Ensure                                   = "Present"
                AllowUserFormBrowserEnabling             = $true
                AllowUserFormBrowserRendering            = $true
                MaxDataConnectionTimeout                 = 20000
                DefaultDataConnectionTimeout             = 10000
                MaxDataConnectionResponseSize            = 1500
                RequireSslForDataConnections             = $true
                AllowEmbeddedSqlForDataConnections       = $false
                AllowUdcAuthenticationForDataConnections = $false
                AllowUserFormCrossDomainDataConnections  = $false
                MaxPostbacksPerSession                   = 75
                MaxUserActionsPerPostback                = 200
                ActiveSessionsTimeout                    = 1440
                MaxSizeOfUserFormState                   = 4096
            }
        }
    }