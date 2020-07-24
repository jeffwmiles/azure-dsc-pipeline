# Import parameters from common PowerShell file
param(
    [string]$paramFile = '.\dsc_parameters.ps1'
)

Write-Host "Check if running in pipeline. If so, set location for relative paths to work."
if ($ENV:BUILD_SOURCESDIRECTORY) {
    Set-Location "$ENV:BUILD_SOURCESDIRECTORY\"
}

# Dot-Source the parameters file
. $paramFile

# Set subscription properly
Select-AzSubscription $subscriptionid

# Create resource group just for Azure Automation if not exists
$rgtest = Get-AzResourceGroup $resourceGroupName -ErrorAction Ignore
if (-not $rgtest) {
    New-AzResourceGroup -Name $resourceGroupName -Location $azureLocation
    Write-Host "$resourceGroupName has been created."
    Start-Sleep -s 25 # wait 25 seconds so Automation Account can be created
}
else {
    Write-Host "$resourceGroupName exists already."
}

# Create Azure Automation account if not exists
$aatest = Get-AzAutomationAccount -resourceGroupName $resourceGroupName -Name $automationAccountName -ErrorAction Ignore
if (-not $aatest) {
    New-AzAutomationAccount -ResourceGroupName $resourceGroupName  -Location $azureLocation -Name $automationAccountName | out-null
    Write-Host "$automationAccountName has been created."
}
else {
    Write-Host "$automationAccountName exists already."
}

# Function to Import DSC modules if not already imported
function Import-AutomationModule {
    param(
        [Parameter(Mandatory = $true)]
        [String] $ResourceGroupName,

        [Parameter(Mandatory = $true)]
        [String] $AutomationAccountName,

        [Parameter(Mandatory = $true)]
        [String] $ModuleName,

        # if not specified latest version will be imported
        [Parameter(Mandatory = $false)]
        [String] $ModuleVersion
    )

    $Url = "https://www.powershellgallery.com/api/v2/Search()?`$filter=IsLatestVersion&searchTerm=%27$ModuleName $ModuleVersion%27&targetFramework=%27%27&includePrerelease=false&`$skip=0&`$top=40"

    # Assuming exact match of module name so take first result
    $SearchResult = Invoke-RestMethod -Method Get -Uri $Url | Select-Object -first 1

    if (!$SearchResult) {
        Write-Error "Could not find module '$ModuleName' on PowerShell Gallery."
    }

    else {
        $PackageDetails = Invoke-RestMethod -Method Get -Uri $SearchResult.id
        $ModuleExist = Get-AzAutomationModule -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName -Name $ModuleName -ErrorAction Ignore

        # If the module exists in the account, compare existing version and if it matches gallery version, stop
        if ($ModuleExist) {
            if ($ModuleExist.Version -eq $PackageDetails.entry.properties.version) {
                $Stop = $true
                Write-host "Module - $ModuleName exists and is at latest version"
            }
        }

        else {
            # else if the module not exists or is older version, proceed, which means nothing here
            $Stop = $false
        }

        $ModuleContentUrl = "https://www.powershellgallery.com/api/v2/package/$ModuleName/$ModuleVersion"

        if (!$Stop) {

            $ActualUrl = $ModuleContentUrl

            Write-Host "Module - $ModuleName is importing to latest version" -ForegroundColor Green

            New-AzAutomationModule `
                -ResourceGroupName $ResourceGroupName `
                -AutomationAccountName $AutomationAccountName `
                -Name $ModuleName `
                -ContentLink $ActualUrl

            #Return a true/false if rest of script needs to wait for modules to finish importing
            # This would be true if any module was new, inside this "if" block
            Return $true
        }
    }
}

#Import the Az.Accounts module first, and wait until it is finished
Write-Information "Find Az.Accounts from PowerShell Gallery" -InformationAction Continue
$galleryModule = find-module -Name "Az.Accounts"
$galleryRepoUri = (find-module -Name "Az.Accounts").RepositorySourceLocation
$moduleUri = '{0}{1}' -f $galleryRepoUri, '/package/Az.Accounts'
Write-Information "Check for Az.Accounts in Automation Account modules" -InformationAction Continue
$automationModule = Get-AzAutomationModule $resourceGroupName -AutomationAccountName $automationAccountName -Name "Az.Accounts" -ErrorAction Ignore

if ((!$automationModule) -or ($galleryModule.Version -ne $automationModule.Version)) {
    Write-Information "Az.Accounts doesn't exist or is out of date, need to import it" -InformationAction Continue
    $importmodule = New-AzAutomationModule $resourceGroupName -AutomationAccountName $automationAccountName -Name "Az.Accounts" -ContentLink $moduleUri

    while (($importmodule.ProvisioningState -eq "Creating") -or ($importmodule.ProvisioningState -eq "ContentValidated") -or ($importmodule.ProvisioningState -eq "ConnectionTypeImported")) {
        Write-Information "Import check shows it isn't done yet." -InformationAction Continue
        $importmodule = Get-AzAutomationModule $resourceGroupName -AutomationAccountName $automationAccountName -Name "Az.Accounts"
        Write-Information "Current state of module: $($importmodule.ProvisioningState)" -InformationAction Continue
        Start-Sleep -Seconds 25
    }
    $importmodule
    if ($importmodule.ProvisioningState -ne "Succeeded")
    {
        Write-Information "Az.Accounts module import failed." -InformationAction Continue
        Write-Host "##vso[task.complete result=Failed;]DONE"
        exit 1
    } else {
        Write-Information "$($moduleName) module import completed successfully." -InformationAction Continue
    }
}

$ImportedModule = $false
#For every module in the listed array, check it and import it if necessary
Write-Host "Modules are importing - if many are new (green) you may need to run this multiple times" -BackgroundColor "Yellow" -ForegroundColor "Black"
foreach ($module in $DSCModuleList) {
    $ImportedModule = Import-AutomationModule -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName -ModuleName $module
    Start-Sleep 5 # wait after each, when running in a pipeline
}

# Check for Azure Automation RunAs account
$runasAccount = Get-AzAutomationConnection -Name "AzureRunAsConnection" -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName -ErrorAction Ignore
if (-not $runasAccount) {
    Write-Host "Azure Automation RunAs account does not exist, creating..." -ForegroundColor Red -BackgroundColor "White"
    .\New-RunAsAccount.ps1 -ResourceGroup $resourceGroupName -AutomationAccountName $automationAccountName -SubscriptionId $subscriptionid
    $runasAccount = Get-AzAutomationConnection -Name "AzureRunAsConnection" -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName -ErrorAction Ignore
}

if ($RunAsAccount) {
    Write-Host "Azure Automation RunAs account already exists."
    #Check for UpdateModule automation runbook
    Write-Host "Checking for Update Module runbook"
    $runbookname = "Update-AutomationAzureModulesForAccount.ps1"
    $UpdateModuleRunbook = Get-AzAutomationRunbook -resourcegroupname $resourceGroupName -automationaccountname $automationAccountName -Name $runbookname -ErrorAction Ignore
    if (-not $UpdateModuleRunbook) {
        Write-Host "Update module runbook does not exist, downloading now."
        $sourceurl = "https://raw.githubusercontent.com/microsoft/AzureAutomation-Account-Modules-Update/master/Update-AutomationAzureModulesForAccount.ps1"
        invoke-webrequest $sourceurl -outfile "$runbookname.ps1"
        Write-Host "Importing the update module runbook into Azure Automation"
        Import-AzAutomationRunbook -Name $runbookname -Path ".\$runbookname.ps1" -Type PowerShell -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName
        Write-Host "Publishing the Az Automation runbook"
        Publish-AzAutomationRunbook -Name $runbookname -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName
        Write-Host "Update module runbook has been imported and published" -ForegroundColor "Green"
        Write-Host "Running Update Module runbook - this may take a 5-10 minutes."
        #Temporarily ignoring error, because of an AZ module bug: https://github.com/Azure/azure-powershell/issues/7977
        Start-AzAutomationRunbook -Name $runbookname -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName -Parameters @{"ResourceGroupName" = $resourceGroupName; "AutomationAccountName" = $automationAccountName } -wait -MaxWaitSeconds 1000 -ErrorAction Ignore
        Write-Host "Update module runbook has finished running" -ForegroundColor "Green"
    }
    else {
        Write-Host "Update module runbook exists, assuming it has been run once, not doing it again."
    }

}
else {
    Write-Host "RunAs Account did not successfully create, so the Update Module Runbook cannot complete. "
}