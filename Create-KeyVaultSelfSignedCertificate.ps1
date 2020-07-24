
function Get-SelfSignedKeyVaultCert {
    param(
        [string]$CertificateName,
        [string]$keyvaultName
    )

    # Test if the certificate already exists
    $cert = Get-AzKeyVaultCertificate -VaultName $keyvaultName -Name $CertificateName

    # If the cert isn't found, then create a policy and certificate
    if (!$cert) {
        $policy = New-AzKeyVaultCertificatePolicy -SubjectName "CN=$CertificateName" `
            -IssuerName "Self" `
            -KeyType "RSA" `
            -KeyUsage "DigitalSignature" `
            -ValidityInMonths 24 `
            -RenewAtNumberOfDaysBeforeExpiry 60 `
            -KeyNotExportable:$False `
            -ReuseKeyOnRenewal:$False

        if ($policy) {
            Write-Host "Key Vault certificate policy generated, proceeding with cert creation"
            $cert = Add-AzKeyVaultCertificate -VaultName $keyvaultName `
                -Name $CertificateName `
                -CertificatePolicy $policy
            Write-Host "Waiting for certificate generation to complete"
            Start-Sleep 25

        }
        if ($cert) {
            Write-Host "Certificate generation completed, returning object."
            $cert = Get-AzKeyVaultCertificate -VaultName $keyvaultName -Name $CertificateName
            return $cert
        }
    }
    else {
        # If the cert already existed, return it
        Write-Host "Certificate found, returning object. "
        return $cert
    }
}