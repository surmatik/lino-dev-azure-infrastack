Configuration ActiveDirectoryConfig {
    param (
        [Parameter(Mandatory=$true)]
        [PSCredential]$SafeModeCredential
    )

    # DSC modules
    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Import-DscResource -ModuleName ActiveDirectoryDsc
    Import-DscResource -ModuleName xDnsServer

    Node "localhost" {

        # LCM Settings
        LocalConfigurationManager {
            RebootNodeIfNeeded = $true
            ActionAfterReboot  = 'ContinueConfiguration'
        }

        # Install ADDS Role
        WindowsFeature ADDS {
            Ensure = "Present"
            Name   = "AD-Domain-Services"
        }

        # Create the Forest
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

        # DNS Configuration
        xDnsServerForwarder AzureDNS {
            IPAddress = @("168.63.129.16", "9.9.9.9")
            DependsOn = "[ADForest]CreateForest"
        }

        xDnsServerPrimaryZone ReverseZone {
            Name      = "0.0.10.in-addr.arpa"
            Ensure    = "Present"
            DependsOn = "[ADForest]CreateForest"
        }

        # Organizational Unit Structure
        ADOrganizationalUnit LinoOU {
            Name       = "Lino"
            Path       = "DC=corp,DC=dev,DC=surmatik,DC=ch"
            Ensure     = "Present"
            DependsOn  = "[ADForest]CreateForest"
        }

        $SubOUs = @("Servers", "Users", "Groups", "Computers")
        foreach ($OUName in $SubOUs) {
            ADOrganizationalUnit "OU_$OUName" {
                Name       = $OUName
                Path       = "OU=Lino,DC=corp,DC=dev,DC=surmatik,DC=ch"
                Ensure     = "Present"
                DependsOn  = "[ADOrganizationalUnit]LinoOU"
            }
        }

        ADOrganizationalUnit AVD_OU {
            Name       = "AVD"
            Path       = "OU=Servers,OU=Lino,DC=corp,DC=dev,DC=surmatik,DC=ch"
            Ensure     = "Present"
            DependsOn  = "[ADOrganizationalUnit]OU_Servers"
        }

        ADOrganizationalUnit Autopilot_OU {
            Name       = "Autopilot"
            Path       = "OU=Computers,OU=Lino,DC=corp,DC=dev,DC=surmatik,DC=ch"
            Ensure     = "Present"
            DependsOn  = "[ADOrganizationalUnit]OU_Computers"
        }

        # Groups and Users
        ADGroup AVDUsersGroup {
            GroupName    = "G_AVD-Users"
            Category     = "Security"
            Scope        = "Global"
            Path         = "OU=Groups,OU=Lino,DC=corp,DC=dev,DC=surmatik,DC=ch"
            Ensure       = "Present"
            DependsOn    = "[ADOrganizationalUnit]OU_Groups"
        }

        ADUser TestUser01 {
            UserName            = "tuser01"
            UserPrincipalName   = "tuser01@dev.surmatik.ch"
            GivenName           = "Test"
            Surname             = "User01"
            Path                = "OU=Users,OU=Lino,DC=corp,DC=dev,DC=surmatik,DC=ch"
            Password            = $SafeModeCredential
            Ensure              = "Present"
            DependsOn           = "[ADOrganizationalUnit]OU_Users"
        }

        ADUser TestUser02 {
            UserName            = "tuser02"
            UserPrincipalName   = "tuser02@dev.surmatik.ch"
            GivenName           = "Test"
            Surname             = "User02"
            Path                = "OU=Users,OU=Lino,DC=corp,DC=dev,DC=surmatik,DC=ch"
            Password            = $SafeModeCredential
            Ensure              = "Present"
            DependsOn           = "[ADOrganizationalUnit]OU_Users"
        }

        # Install Entra Cloud Sync
        Script InstallEntraCloudSync {
            SetScript = {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                $url = "https://go.microsoft.com/fwlink/?linkid=2109613"
                $dest = "C:\Windows\Temp\AADConnectProvisioningAgentSetup.exe"
                if (!(Test-Path $dest)) {
                    Invoke-WebRequest -Uri $url -OutFile $dest
                }
                Start-Process -FilePath $dest -ArgumentList "/quiet /install" -Wait
            }
            TestScript = {
                return Test-Path "C:\Program Files\Microsoft Azure AD Connect Provisioning Agent"
            }
            GetScript = { @{ Result = "EntraCloudSyncInstalled" } }
            DependsOn = "[ADForest]CreateForest"
        }
    }
}