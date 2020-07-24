#!Requires -RunAsAdministrator
Param (
    [Parameter(Mandatory = $true)]
    [String] $ResourceGroup,

    [Parameter(Mandatory = $true)]
    [String] $AutomationAccountName,

    [Parameter(Mandatory = $true)]
    [String] $SubscriptionId,

    [Parameter(Mandatory = $false)]
    [String] $ApplicationDisplayName = "$($AutomationAccountName)-runasAccount",

    [Parameter(Mandatory = $false)]
    [String] $SelfSignedCertPlainPassword = [Guid]::NewGuid(),

    [Parameter(Mandatory = $false)]
    [ValidateSet("AzureCloud", "AzureUSGovernment")]
    [string]$EnvironmentName = "AzureCloud"
)
function CreateServicePrincipal([System.Security.Cryptography.X509Certificates.X509Certificate2] $PfxCert, [string] $applicationDisplayName) {
    $keyValue = [System.Convert]::ToBase64String($PfxCert.GetRawCertData())
    $keyId = (New-Guid).Guid

    # Create an Azure AD application, AD App Credential, AD ServicePrincipal

    # Requires Application Developer Role, but works with Application administrator or GLOBAL ADMIN
    $Application = New-AzADApplication -DisplayName $ApplicationDisplayName -HomePage ("http://" + $applicationDisplayName) -IdentifierUris ("http://" + $keyId)
    # Requires Application administrator or GLOBAL ADMIN
    $ApplicationCredential = New-AzADAppCredential -ApplicationId $Application.ApplicationId -CertValue $keyValue -StartDate $PfxCert.NotBefore -EndDate $PfxCert.NotAfter
    # Requires Application administrator or GLOBAL ADMIN
    $ServicePrincipal = New-AzADServicePrincipal -ApplicationId $Application.ApplicationId
    $GetServicePrincipal = Get-AzADServicePrincipal -ObjectId $ServicePrincipal.Id

    # Sleep here for a few seconds to allow the service principal application to become active (ordinarily takes a few seconds)
    Start-Sleep -s 25
    # Requires User Access Administrator or Owner.
    $role = Get-AzRoleAssignment -ServicePrincipalName $Application.ApplicationId
    if (!$role) {
        $NewRole = New-AzRoleAssignment -RoleDefinitionName Contributor -ServicePrincipalName $Application.ApplicationId -ErrorAction SilentlyContinue
        }
        return $Application.ApplicationId.ToString();
    }

function CreateAutomationCertificateAsset ([string] $resourceGroup, [string] $automationAccountName, [string] $certifcateAssetName, [string] $certPath, [string] $certPlainPassword, [Boolean] $Exportable) {
    $CertPassword = ConvertTo-SecureString $certPlainPassword -AsPlainText -Force
    Remove-AzAutomationCertificate -ResourceGroupName $resourceGroup -AutomationAccountName $automationAccountName -Name $certifcateAssetName -ErrorAction SilentlyContinue
    New-AzAutomationCertificate -ResourceGroupName $resourceGroup -AutomationAccountName $automationAccountName -Path $certPath -Name $certifcateAssetName -Password $CertPassword -Exportable:$Exportable | write-verbose
}

function CreateAutomationConnectionAsset ([string] $resourceGroup, [string] $automationAccountName, [string] $connectionAssetName, [string] $connectionTypeName, [System.Collections.Hashtable] $connectionFieldValues ) {
    Remove-AzAutomationConnection -ResourceGroupName $resourceGroup -AutomationAccountName $automationAccountName -Name $connectionAssetName -Force -ErrorAction SilentlyContinue
    New-AzAutomationConnection -ResourceGroupName $ResourceGroup -AutomationAccountName $automationAccountName -Name $connectionAssetName -ConnectionTypeName $connectionTypeName -ConnectionFieldValues $connectionFieldValues
}

Select-AzSubscription -SubscriptionId $SubscriptionId

Write-Host "Include Create-KeyVaultSelfSignedCertificate"
# Get or Set the self-signed certificate from Key Vault
. .\Create-KeyVaultSelfSignedCertificate.ps1
Start-Sleep -Seconds 10 # wait for cert to be available from within API
# This object is used for the service principal
Write-Host "Generate or find certificate from KeyVault. Requires appropriate access policy to complete"
$pfxcert = (Get-SelfSignedKeyVaultCert -CertificateName "$($automationAccountName)RunAsAccountCert" -keyvaultName "$keyvaultName").Certificate
if ($pfxcert) {
    Write-Host "Certificate retrieved"
} else {
    Write-Host "Problem retrieving certificate."
}
# Need to write cert to file in order to upload to Automation Certificate Asset
# Only works with Get-AzureKeyVaultSecret, not certificate
Write-Host "Getting KeyVault secret again for local storage"
$kvcert = Get-AzKeyVaultSecret -Name "$($automationAccountName)RunAsAccountCert" -vaultName "$keyvaultName"
Write-Host "Convert into object x509 certificate object"
$pfxCertObject = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList @([Convert]::FromBase64String($kvcert.SecretValueText), "", [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable)
Write-Host "Saving certificate to local PFX, in order to upload to Automation asset."
[System.io.file]::WriteAllBytes((Get-Location).Path + '\pfxcert.pfx', $pfxCertObject.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Pkcs12, $SelfSignedCertPlainPassword))

# Create a Run As account by using a service principal
$CertifcateAssetName = "AzureRunAsCertificate"
$ConnectionAssetName = "AzureRunAsConnection"
$ConnectionTypeName = "AzureServicePrincipal"

# Create a service principal
Write-Host "Create the Service Principal for runas account"
$ApplicationId = CreateServicePrincipal $PfxCert $ApplicationDisplayName

# Create the Automation certificate asset
Write-Host "Create the Automation Certificate Asset"
CreateAutomationCertificateAsset $ResourceGroup $AutomationAccountName $CertifcateAssetName ".\pfxcert.pfx" $SelfSignedCertPlainPassword $true

# Populate the ConnectionFieldValues
$SubscriptionInfo = Get-AzSubscription -SubscriptionId $SubscriptionId
$TenantID = $SubscriptionInfo | Select-Object TenantId -First 1
$Thumbprint = $PfxCert.Thumbprint
$ConnectionFieldValues = @{"ApplicationId" = $ApplicationId; "TenantId" = $TenantID.TenantId; "CertificateThumbprint" = $Thumbprint; "SubscriptionId" = $SubscriptionId }

# Create an Automation connection asset named AzureRunAsConnection in the Automation account. This connection uses the service principal.
Write-Host "Create the Automation Connection asset"
CreateAutomationConnectionAsset $ResourceGroup $AutomationAccountName $ConnectionAssetName $ConnectionTypeName $ConnectionFieldValues

Write-Host "Removing local copy of pfx file"
Remove-Item ".\pfxcert.pfx" -Force