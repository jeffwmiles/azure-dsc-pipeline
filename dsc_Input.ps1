# Import parameters from common JSON for reuse
# This file cannot have comments in it!
param(
    [string]$paramFile = '.\dsc_parameters.ps1'
)

# This script assumes that "Create-AutomationAccount.ps1" has been successfully run.

# Dot-Source the parameters file
. $paramFile

# Set subscription properly
Select-AzSubscription $subscriptionid

if (!$Stop) {

    if ($ImportedModule) {
        Write-host "Wait 120 seconds since there were modules imported"
        Start-Sleep -s 120
    }

    # upload DSC configuration from local path
    # assumes this is running azure cloud shell, and that the latest version of the configuration file has been uploaded to your cloud drive
    write-host "Importing DSC configuration - $dscConfigurationname"
    Get-Location
    Write-Host $dscConfigurationFile
    Import-AzAutomationDscConfiguration -SourcePath $dscConfigurationFile -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName -Force -Published

    # Compile the node configurations from the configuration in Automation Account
    Write-Host "Starting compilation of DSC Configuration"
    Start-AzAutomationDscCompilationJob `
        -ResourceGroupName $resourceGroupName `
        -AutomationAccountName $automationAccountName `
        -ConfigurationName $dscConfigurationname   `
        -ConfigurationData $ConfigData | out-null

    # Loop and wait until the job is finished
    # Get the latest Compilation job that occurred today
    $today = (get-date).date
    $latestcompileJob = Get-AzAutomationDscCompilationJob -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName -ConfigurationName $dscConfigurationname | Where-Object CreationTime -ge $today | Sort-Object CreationTime -Descending | Select-Object -First 1
    do {
        Write-Information "Waiting for 25 seconds..." -InformationAction Continue
        Start-Sleep -Seconds 25
        Write-Information "Checking Compilation Status" -InformationAction Continue
        $latestcompileJob = Get-AzAutomationDscCompilationJob -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName -ConfigurationName $dscConfigurationname | Where-Object CreationTime -ge $today | Sort-Object CreationTime -Descending | Select-Object -First 1
        Write-Information "Status of Compile Job: $($latestcompileJob.Status)" -InformationAction Continue
    } until ((!$null -eq $latestcompileJob.EndTime) -or ($latestcompileJob.Status -eq "Suspended"))

    if ($latestcompileJob.Status -ne "Completed")
    {
        # Fail the pipeline task
        Write-Information "Compile operation failed." -InformationAction Continue
        Write-Host "##vso[task.complete result=Failed;]DONE"
        exit 1
    }
}