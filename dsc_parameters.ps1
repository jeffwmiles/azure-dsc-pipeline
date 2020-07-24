$subscriptionid             = "3d22393a"
$resourceGroupName          = "testpipe-rg"
$azureLocation              = "EastUS2"
$automationAccountName      = "automation-july2020-1"
$dscConfigurationname       = "dsc_baseconfig"
$dscConfigurationFile       = "dsc_baseconfig.ps1"
$keyvaultName               = "devops-kv"

#This list contains all modules to import into the AzureAutomationAccount
$DSCModuleList              = "Az.Compute,Az.Network,PSDscResources,xWebAdministration,ComputerManagementDSC,xRemoteDesktopAdmin,xDSCDomainJoin,StorageDSC,cCDROMdriveletter,CertificateDSC,NetworkingDSC,cMoveAzureTempDrive,xActiveDirectory,xPendingReboot,cChoco,xSmbShare".Split(',')

# ConfigData variable is directly used for DSC, and should be updated according to the specific environment.
$ConfigData = @{
    AllNodes    = @(
        @{
            NodeName                    = "*";
            TimeZone                    = "Mountain Standard Time";
            PSDscAllowPlainTextPassword = $True;
            # Above line safe in Azure Automation as referenced here:
            # https://docs.microsoft.com/en-us/azure/automation/automation-dsc-compile#credential-assets
        },

        @{
            NodeName          = "web1";
            Role              = "WebServer";
            BGInfoDescription = "Web VM";
            Direction         = "Int";
        },
        @{
            NodeName          = "db1";
            Role              = "Database";
            BGInfoDescription = "DB VM";
            Direction         = "Int";
        },
        @{
            NodeName          = "rdp1";
            Role              = "Standard";
            BGInfoDescription = "RDP Host VM";
            Direction         = "Int";
        }
    );
    NonNodeData = ""
}