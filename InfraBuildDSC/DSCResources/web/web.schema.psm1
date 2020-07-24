Configuration web {

    Import-DscResource -ModuleName PSDscResources
    Import-DscResource -ModuleName cChoco
    Import-DSCResource -ModuleName StorageDSC
    Import-DscResource -ModuleName xWebAdministration

    WaitforDisk Disk2
        {
            DiskId = 2
            RetryIntervalSec = 60
            RetryCount = 60
        }
    Disk DVolume
        {
            DiskId = 2
            DriveLetter = "E"
            FSLabel = "Websites"
        }

    cChocoPackageInstaller iiscrypto-cli
        {
            Name = "iiscrypto-cli"
            DependsOn = "[cChocoInstaller]installChoco"
        }
    cChocoPackageInstaller iis-urlrewrite
        {
            Name = "UrlRewrite"
            DependsOn = "[cChocoInstaller]installChoco","[WindowsFeatureSet]IISComponents"
        }
    Script IISCryptoApplication
        {
            # Must return a hashtable with at least one key
            # named 'Result' of type String
            GetScript = {
                Return @{
                    Result = [string]$(get-itemproperty -path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL")
                }
            }
            # Must return a boolean: $true or $false
            TestScript = {
                $ssl2 = get-itempropertyvalue -path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 2.0\Server" -name Enabled -ErrorAction SilentlyContinue
                If ($ssl2 -eq 0) {
                    Write-Verbose "IISCrypto already set"
                    Return $true
                } Else {
                    Write-Verbose "IISCrypto needs to be set"
                    Return $false
                }
            }
            # Returns nothing
            SetScript = {
                Write-Verbose "Applying IISCrypto settings"
                iiscryptocli /template best
            }
            DependsOn = '[cChocoPackageInstaller]iiscrypto-cli'
        }
    Script GenerateSelfSignedCert
        {
            GetScript = {
                Return @{
                    Result = [string]$(Get-ChildItem "Cert:\LocalMachine\My")
                }
            }
            # Must return a boolean: $true or $false
            TestScript = {
                $myHost=(Get-WmiObject win32_computersystem).DNSHostName

                If ((Get-ChildItem "Cert:\LocalMachine\My") -like "*$myHost*") {

                            Write-Verbose "SSL cert generated"
                            Return $true
                        }
                        Else {
                            Write-Verbose "SSL cert not generated"
                            Return $false
                        }
            }
            SetScript = {
                Write-Verbose "Generating Self-Signed Certificate"
                $myHost=(Get-WmiObject win32_computersystem).DNSHostName # Hostname, not FQDN
                New-SelfSignedCertificate -certstorelocation cert:\localmachine\my -dnsname $myHost -NotAfter (Get-Date).AddYears(5) -KeyAlgorithm RSA -KeyLength 2048
            }
        }

    WindowsFeatureSet IISComponents
        {
            Name    = @("Web-App-Dev", "Web-Net-Ext45", "Web-Asp-Net45", "Web-ISAPI-Ext", "Web-ISAPI-Filter", "Web-Mgmt-Tools", "Web-Server","Web-WebSockets","Web-Http-Logging","Web-Stat-Compression","Web-Http-Redirect","Web-Http-Errors","Web-Dir-Browsing","Web-Default-Doc","Web-Static-Content")
            Ensure  = 'Present'
        }

    File C_AppsSite
        {
            Ensure = "Present"  # You can also set Ensure to "Absent"
            Type = "Directory" # Default is "File".
            DestinationPath = "E:\inetpub\AppsSite"
        }
    File C_AppsSiteLogs
        {
            Ensure = "Present"  # You can also set Ensure to "Absent"
            Type = "Directory" # Default is "File".
            DestinationPath = "E:\inetpub\logs\AppsSite"
        }
    xWebAppPool RemoveDefaultAppPool      { Name = "DefaultAppPool";       Ensure = "Absent"}
    xWebSite    RemoveDefaultWebSite      { Name = "Default Web Site";     Ensure = "Absent"; PhysicalPath = "E:\inetpub\wwwroot"}
    xWebAppPool Apps {
            Name = "Apps"
            Ensure = "Present"
            State="Started" }
    xWebSite Apps {
            Name            = "Apps"
            PhysicalPath    = "E:\inetpub\AppsSite"
            State           = "Started"
            ApplicationPool = "Apps"
            Ensure          = "Present"
            BindingInfo     = @(
                <#@(MSFT_xWebBindingInformation
                    {
                        IPAddress = "*"
                        Protocol  = "HTTPS"
                        Port      = 443
                        CertificateStoreName  = 'MY'
                        CertificateSubject = "$($Node.ClientCode)-$($Node.NodeName).cc$($Node.ClientCode).local" # Hostname of the servername
                        SSLFlags = '0'
                    }); #>
                @(MSFT_xWebBindingInformation {
                        # IPAddress = "*" # Default value is *, so we don't need to specify it.
                        Protocol  = "HTTP"
                        Port      = 80
                    }
                )
            )
            LogPath         = "E:\inetpub\logs\AppsSite"
            DependsOn       = "[File]C_AppsSite", "[Script]GenerateSelfSignedCert"
        }

    # Have to use Script to apply SSL cert, since we won't know what it is going to be named
    Script WebsiteApps
        {
            # Must return a hashtable with at least one key
            # named 'Result' of type String
            GetScript = {
                Return @{
                    Result = [string]$(Get-ChildItem "Cert:\LocalMachine\My")
                }
            }
            # Must return a boolean: $true or $false
            TestScript = {
                Import-Module WebAdministration
                # Grab the IP based on the interface name, which is previously set in DSC
                # Find out if we've got anything bound on this IP for port 443
                $bindcheckhttps = get-webbinding -name "Apps" -Port 443
                # if IP bound on port 443
                if ($bindcheckhttps)
                {
                    Write-Verbose "443 is bound for Apps."
                    #if SSL certificate bound
                    if (Test-path "IIS:\SslBindings\0.0.0.0!443")
                    {
                         Write-Verbose "SSL Certificate is bound for Apps"

                             Return $true
                    }
                    else
                    {
                        Write-Verbose "SSL Certificate is NOT bound for Apps"
                        Return $false
                    }
                }
                else
                {
                    Write-Verbose "IP not bound on 443 for Apps."
                    Return $false
                }
            }

            # Returns nothing
            SetScript = {
                $computerName = $Env:Computername
                $apps = Get-Item "IIS:\Sites\Apps"
                $bindcheckhttps = get-webbinding -name "Apps" -Port 443

                    # if port 443 not bound
                    if (-not ($bindcheckhttps))
                    {
                        Write-Verbose "Binding port 443"
                        $apps = Get-Item "IIS:\Sites\Apps"
                        New-WebBinding -Name $apps.Name -protocol "https" -Port 443
                    }
                    #if SSL certificate not bound
                    if (-not (Test-path "IIS:\SslBindings\0.0.0.0!443"))
                        {
                            Write-Verbose "Binding SSL certificate"
                            Get-ChildItem cert:\LocalMachine\My | where-object { $_.Subject -match "CN\=$Computername" } | select -First 1 | New-Item IIS:\SslBindings\0.0.0.0!443
                        }
                    # if log file setting correct
                    if (-not ((get-itemproperty "IIS:\Sites\Apps" -name logfile).directory -ieq "E:\inetpub\logs\AppsSite"))
                        {
                            Write-Verbose "Setting log file to the proper directory"
                            Set-ItemProperty "IIS:\Sites\Apps" -name logFile -value @{directory="E:\inetpub\logs\AppsSite"}
                        }
            }
            DependsOn = "[xWebSite]Apps","[Script]GenerateSelfSignedCert"
        } # End script webApps
}