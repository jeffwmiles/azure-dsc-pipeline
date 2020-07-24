Configuration baseline {

    Import-DscResource -ModuleName PSDscResources
    Import-DscResource -ModuleName cChoco
    Import-DSCResource -ModuleName StorageDSC
    Import-DscResource -ModuleName ComputerManagementDSC
    Import-DscResource -ModuleName xRemoteDesktopAdmin
    Import-DscResource -ModuleName NetworkingDSC
    Import-DscResource -moduleName cMoveAzureTempDrive
    Import-DscResource -moduleName cCDROMdriveletter

    cChocoInstaller installChoco
        {
            InstallDir = "C:\ProgramData\choco"
        }
    File CTemp {
            Type = "Directory"
            DestinationPath = "C:\Temp"
            Ensure = "Present"
        }
    cCDROMdriveletter cdrom
        {
            DriveLetter = "Z"
            Ensure      = "Present"
        }
    cMoveAzureTempDrive MoveAzureTempDrive
        {
            Name = $Node.NodeName
            TempDriveLetter = "X"
        }
    NetAdapterRss EnableRss1
        {
            Name = "Ethernet"
            Enabled = $True
        }
    Registry DisableVmictimeprovider
        {
            Ensure = "Present"
            Key = "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\TimeProviders\VMICTimeProvider"
            Force = $true
            ValueName = "EnableLUA"
            ValueData = "0"
            ValueType = "Dword"
        }
    Registry CrashDumpDisabled {
            Ensure    = "Present"
            Key       = "HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl"
            Force     = $true
            ValueName = "CrashDumpEnabled"
            ValueData = "0"
            ValueType = "Dword"
        }
    Registry AlwaysKeepMemoryDumpDisabled {
            Ensure    = "Present"
            Key       = "HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl"
            Force     = $true
            ValueName = "AlwaysKeepMemoryDump"
            ValueData = "0"
            ValueType = "Dword"
        }

    TimeZone SetTimeZone {
            IsSingleInstance = 'Yes'
            TimeZone = "$($Node.TimeZone)"
        }

    FirewallProfile FirewallProfilePrivate
        {
            Name = 'Private'
            Enabled = 'True'
        }
    FirewallProfile FirewallProfileDomain
        {
            Name = 'Domain'
            Enabled = 'True'
        }
    FirewallProfile FirewallProfilePublic
        {
            Name = 'Public'
            Enabled = 'True'
        }
    Registry DoNotStartServerManager {
            Ensure    = "Present"
            Key       = "HKLM:\SOFTWARE\Microsoft\ServerManager"
            Force     = $true
            ValueName = "DoNotOpenServerManagerAtLogon"
            ValueData = "1"
            ValueType = "Dword"
        }
    Registry disableIESC1 {
            Ensure    = "Present"
            Key       = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}"
            Force     = $true
            ValueName = "IsInstalled"
            ValueData = "0"
            ValueType = "Dword"
        }
    Registry disableIESC2 {
            Ensure    = "Present"
            Key       = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}"
            Force     = $true
            ValueName = "IsInstalled"
            ValueData = "0"
            ValueType = "Dword"
        }
    Script ApplyDefaultUserSettings {
            # Sets IE home page to about:blank and always show file extensions
            GetScript  = {
                Return @{
                    Result = [string]$(Get-Content -Path C:\programdata\UserSettings.txt)
                }
            }
            # Must return a boolean: $true or $false
            TestScript = {
                $LogFileExists = Test-Path -Path C:\programdata\UserSettings.txt
                if ($LogFileExists) {
                    $CheckLogFile = Get-Content -Path C:\programdata\UserSettings.txt
                    if ($CheckLogFile -ceq "complete") {
                        Write-Verbose "User Settings already set"
                        Return $true
                    }
                    Else {
                        Write-Verbose "User Settings needs to be set"
                        Return $false
                    }
                }
                else {
                    Write-Verbose "User Settings needs to be set"
                    Return $false
                }
            }
            # Returns nothing
            SetScript  = {

                # ***** Configure Default User
                # *** Load Default User hive
                reg load "hkey_users\Test" "C:\users\Default\NTUSER.DAT"
                # *** Set HomePage to About:Blank
                reg add "hkey_users\Test\Software\Microsoft\Internet Explorer\Main" /v "Start Page" /t REG_SZ /d "about:blank" /f
                # *** Set "always show file extensions"
                reg add "hkey_users\Test\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v "HideFileExt" /t REG_DWORD /d 0 /f

                # *** Unload Default User hive
                reg unload "hkey_users\Test"

                Set-Content -Path C:\programdata\UserSettings.txt -Value 'complete' -force
            }
        }

    WindowsFeature SNMP
        {
          Ensure = "Present"
          Name = "SNMP-Service"
        }
    WindowsFeature SnmpManagementTools
        {
          Ensure = "Present"
          Name = "RSAT-SNMP"
        }
    Registry AuthTraps
        {
            Ensure = "Present"
            Key = "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\SNMP\Parameters"
            Force = $true
            ValueName = "EnableAuthenticationTraps"
            ValueType = 'DWORD'
            ValueData = "0"
        }

    Registry SNMPPermittedManager
        {
            Ensure = "Present"
            Key = "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\SNMP\Parameters\PermittedManagers"
            Force = $true
            ValueName = "1"
            ValueType = "String"
            ValueData = "*"
        }

    cChocoPackageInstaller chocoCoreExtension
        {
            Name = "chocolatey-core.extension"
            DependsOn = "[cChocoInstaller]installChoco"
        }
    cChocoPackageInstaller notepadplusplus
        {
            Name = "notepadplusplus.install"
            DependsOn = "[cChocoInstaller]installChoco"
        }
    cChocoPackageInstaller googlechrome
        {
            Name = "googlechrome"
            DependsOn = "[cChocoInstaller]installChoco"
        }
    Registry PreferIPv4
        {
            Ensure = "Present"
            Key = "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters"
            Force = $true
            ValueName = "DisabledComponents"
            ValueType = 'DWORD'
            ValueData = "32"
        }

    # RDP Enabled
    xRemoteDesktopAdmin RemoteDesktopSettings
        {
        Ensure = 'Present'
        UserAuthentication = 'Secure'
        }

    # Power CFG
    Script PowerCFG
        {
            GetScript = {
                Return @{
                    Result = [string]$(Powercfg -GetActiveScheme)
                }
            }
            # Must return a boolean: $true or $false
            TestScript = {
            $activescheme = Powercfg /getactivescheme
                if ($activescheme -like '*High Performance*')
                {
                    Write-Verbose "PowerCFG is already configured"
                    Return $true
                } Else {
                    Write-Verbose "PowerCFG needs to be configured"
                    Return $false
                }
            }
            # Returns nothing
            SetScript = {
                Powercfg -SETACTIVE SCHEME_MIN
            }
        }
}