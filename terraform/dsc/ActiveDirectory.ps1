$ModulePath = Join-Path $PSScriptRoot "modules"
if (Test-Path $ModulePath) {
    $env:PSModulePath = "$ModulePath;$env:PSModulePath"
}

Configuration ActiveDirectoryConfig {
    param (
        [Parameter(Mandatory=$true)]
        [PSCredential]$SafeModeCredential
    )

    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Import-DscResource -ModuleName ActiveDirectoryDsc
    Import-DscResource -ModuleName xDnsServer

    Node "localhost" {

        LocalConfigurationManager {
            RebootNodeIfNeeded = $true
            ActionAfterReboot  = 'ContinueConfiguration'
            ConfigurationMode  = 'ApplyAndAutoCorrect'
        }

        WindowsFeature ADDS {
            Ensure = "Present"
            Name   = "AD-Domain-Services"
        }

        ADForest CreateForest {
            DomainName             = "corp.dev.surmatik.ch"
            DomainNetbiosName      = "LINODEV"
            SafeModeAdminPassword  = $SafeModeCredential
            UPNSuffixes            = @("dev.surmatik.ch") 
            DatabasePath           = "C:\Windows\NTDS"
            LogPath                = "C:\Windows\NTDS"
            SysvolPath             = "C:\Windows\SYSVOL"
            DependsOn              = "[WindowsFeature]ADDS"
        }

        WaitForADDomain WaitInsideNode {
            DomainName       = "corp.dev.surmatik.ch"
            DependsOn        = "[ADForest]CreateForest"
        }

        $DN = "DC=corp,DC=dev,DC=surmatik,DC=ch"

        xDnsServerForwarder AzureDNS {
            IsSingleInstance = "Yes"
            IPAddresses      = @("168.63.129.16", "9.9.9.9")
            DependsOn        = "[WaitForADDomain]WaitInsideNode"
        }

        xDnsServerPrimaryZone ReverseZone {
            Name      = "0.0.10.in-addr.arpa"
            Ensure    = "Present"
            DependsOn = "[WaitForADDomain]WaitInsideNode"
        }

        ADOrganizationalUnit LinoOU {
            Name       = "Lino"
            Path       = $DN
            Ensure     = "Present"
            DependsOn  = "[WaitForADDomain]WaitInsideNode"
        }

        $SubOUs = @("Servers", "Users", "Groups", "Computers")
        foreach ($OUName in $SubOUs) {
            ADOrganizationalUnit "OU_$OUName" {
                Name       = $OUName
                Path       = "OU=Lino,$DN"
                Ensure     = "Present"
                DependsOn  = "[ADOrganizationalUnit]LinoOU"
            }
        }

        ADOrganizationalUnit AVD_OU {
            Name       = "AVD"
            Path       = "OU=Servers,OU=Lino,$DN"
            Ensure     = "Present"
            DependsOn  = "[ADOrganizationalUnit]OU_Servers"
        }

        ADOrganizationalUnit Autopilot_OU {
            Name       = "Autopilot"
            Path       = "OU=Computers,OU=Lino,$DN"
            Ensure     = "Present"
            DependsOn  = "[ADOrganizationalUnit]OU_Computers"
        }

        ADGroup AVDUsersGroup {
            GroupName    = "G_AVD-Users"
            Category     = "Security"
            GroupScope   = "Global"
            Path         = "OU=Groups,OU=Lino,$DN"
            Ensure       = "Present"
            DependsOn    = "[ADOrganizationalUnit]OU_Groups"
        }

        ADUser TestUser01 {
            UserName            = "tuser01"
            DomainName          = "corp.dev.surmatik.ch"
            UserPrincipalName   = "tuser01@dev.surmatik.ch"
            GivenName           = "Test"
            Surname             = "User01"
            Path                = "OU=Users,OU=Lino,$DN"
            Password            = $SafeModeCredential
            Ensure              = "Present"
            DependsOn           = "[ADOrganizationalUnit]OU_Users"
        }

        ADUser TestUser02 {
            UserName            = "tuser02"
            DomainName          = "corp.dev.surmatik.ch"
            UserPrincipalName   = "tuser02@dev.surmatik.ch"
            GivenName           = "Test"
            Surname             = "User02"
            Path                = "OU=Users,OU=Lino,$DN"
            Password            = $SafeModeCredential
            Ensure              = "Present"
            DependsOn           = "[ADOrganizationalUnit]OU_Users"
        }

        Script InstallEntraCloudSync {
            SetScript = {
                $exePath = Join-Path $using:PSScriptRoot "AADConnectProvisioningAgentSetup.exe"
                if (Test-Path $exePath) {
                    Start-Process -FilePath $exePath -ArgumentList "/quiet /install" -Wait
                } else {
                    throw "Installation file not found at $exePath."
                }
            }
            TestScript = {
                return Test-Path "C:\Program Files\Microsoft Azure AD Connect Provisioning Agent"
            }
            GetScript = { return @{ Result = "EntraCloudSyncStatus" } }
            DependsOn = "[WaitForADDomain]WaitInsideNode"
        }
    }
}