#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Zero-Touch Active Directory Installation with Reboot Handling
.DESCRIPTION
    Installs and configures Active Directory with automatic continuation after reboots
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Configuration
$ScriptPath = "C:\Temp\Install-ActiveDirectory.ps1"
$LogFile = "C:\Temp\AD-Installation.log"
$StatusFile = "C:\Temp\AD-Status.json"
$TaskName = "InstallActiveDirectory"

# Ensure temp directory exists
$null = New-Item -ItemType Directory -Path "C:\Temp" -Force

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp [$Level] - $Message"
    $logMessage | Tee-Object -FilePath $LogFile -Append | Write-Host
}

function Get-InstallationStatus {
    if (Test-Path $StatusFile) {
        return Get-Content $StatusFile | ConvertFrom-Json
    }
    return @{
        Stage = "NotStarted"
        LastUpdate = (Get-Date).ToString()
        RebootCount = 0
    }
}

function Set-InstallationStatus {
    param(
        [string]$Stage,
        [int]$RebootCount
    )
    $status = @{
        Stage = $Stage
        LastUpdate = (Get-Date).ToString()
        RebootCount = $RebootCount
    }
    $status | ConvertTo-Json | Set-Content $StatusFile
    Write-Log "Status updated: $Stage (Reboot Count: $RebootCount)"
}

function Register-ContinuationTask {
    Write-Log "Registering continuation task for post-reboot execution..."
    
    # Copy this script to C:\Temp if not already there
    if ($PSCommandPath -ne $ScriptPath) {
        Copy-Item -Path $PSCommandPath -Destination $ScriptPath -Force
    }
    
    $action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Bypass -NoProfile -File `"$ScriptPath`""
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
    
    $task = Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force
    Write-Log "Continuation task registered successfully"
}

function Remove-ContinuationTask {
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Log "Continuation task removed"
    }
}

function Install-ADDSRole {
    Write-Log "Installing AD Domain Services role..."
    
    Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools
    Install-WindowsFeature -Name DNS -IncludeManagementTools
    Install-WindowsFeature -Name RSAT-AD-Tools
    Install-WindowsFeature -Name RSAT-DNS-Server
    
    Write-Log "ADDS role installed"
}

function Install-ADForest {
    Write-Log "Creating new AD Forest..."
    
    $securePassword = ConvertTo-SecureString "P@ssw0rd123!ComplexEnough" -AsPlainText -Force
    
    Install-ADDSForest `
        -DomainName "corp.dev.surmatik.ch" `
        -DomainNetbiosName "LINODEV" `
        -SafeModeAdministratorPassword $securePassword `
        -InstallDns `
        -Force `
        -NoRebootOnCompletion:$false
    
    Write-Log "AD Forest creation initiated - System will reboot"
}

function Configure-ADStructure {
    Write-Log "Configuring AD Structure (OUs, Users, Groups)..."
    
    Import-Module ActiveDirectory
    
    $DN = "DC=corp,DC=dev,DC=surmatik,DC=ch"
    
    # Wait for AD to be ready
    $maxAttempts = 30
    $attempt = 0
    while ($attempt -lt $maxAttempts) {
        try {
            Get-ADDomain -ErrorAction Stop | Out-Null
            Write-Log "Active Directory is ready"
            break
        }
        catch {
            $attempt++
            Write-Log "Waiting for AD to be ready... (Attempt $attempt/$maxAttempts)"
            Start-Sleep -Seconds 10
        }
    }
    
    # Create OUs
    Write-Log "Creating Organizational Units..."
    
    $ous = @(
        @{Name="Lino"; Path=$DN},
        @{Name="Servers"; Path="OU=Lino,$DN"},
        @{Name="Users"; Path="OU=Lino,$DN"},
        @{Name="Groups"; Path="OU=Lino,$DN"},
        @{Name="Computers"; Path="OU=Lino,$DN"},
        @{Name="AVD"; Path="OU=Servers,OU=Lino,$DN"},
        @{Name="Autopilot"; Path="OU=Computers,OU=Lino,$DN"}
    )
    
    foreach ($ou in $ous) {
        try {
            $ouPath = "OU=$($ou.Name),$($ou.Path)"
            if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$ouPath'" -ErrorAction SilentlyContinue)) {
                New-ADOrganizationalUnit -Name $ou.Name -Path $ou.Path -ProtectedFromAccidentalDeletion $true
                Write-Log "Created OU: $($ou.Name)"
            }
        }
        catch {
            Write-Log "Error creating OU $($ou.Name): $_" -Level "ERROR"
        }
    }
    
    # Create Groups
    Write-Log "Creating Security Groups..."
    
    $groups = @(
        @{Name="G_AVD-Users"; Description="Users with access to Azure Virtual Desktop"},
        @{Name="G_AVD-Admins"; Description="Administrators for Azure Virtual Desktop"}
    )
    
    foreach ($group in $groups) {
        try {
            if (-not (Get-ADGroup -Filter "Name -eq '$($group.Name)'" -ErrorAction SilentlyContinue)) {
                New-ADGroup -Name $group.Name -GroupScope Global -GroupCategory Security `
                    -Path "OU=Groups,OU=Lino,$DN" -Description $group.Description
                Write-Log "Created group: $($group.Name)"
            }
        }
        catch {
            Write-Log "Error creating group $($group.Name): $_" -Level "ERROR"
        }
    }
    
    # Create Test Users
    Write-Log "Creating Test Users..."
    
    $securePassword = ConvertTo-SecureString "P@ssw0rd123!ComplexEnough" -AsPlainText -Force
    
    $users = @(
        @{UserName="tuser01"; GivenName="Test"; Surname="User01"; UPN="tuser01@dev.surmatik.ch"},
        @{UserName="tuser02"; GivenName="Test"; Surname="User02"; UPN="tuser02@dev.surmatik.ch"}
    )
    
    foreach ($user in $users) {
        try {
            if (-not (Get-ADUser -Filter "SamAccountName -eq '$($user.UserName)'" -ErrorAction SilentlyContinue)) {
                New-ADUser -SamAccountName $user.UserName `
                    -UserPrincipalName $user.UPN `
                    -GivenName $user.GivenName `
                    -Surname $user.Surname `
                    -DisplayName "$($user.GivenName) $($user.Surname)" `
                    -Name "$($user.GivenName) $($user.Surname)" `
                    -Path "OU=Users,OU=Lino,$DN" `
                    -AccountPassword $securePassword `
                    -Enabled $true `
                    -PasswordNeverExpires $true
                
                Add-ADGroupMember -Identity "G_AVD-Users" -Members $user.UserName
                Write-Log "Created user: $($user.UserName)"
            }
        }
        catch {
            Write-Log "Error creating user $($user.UserName): $_" -Level "ERROR"
        }
    }
    
    Write-Log "AD Structure configuration complete"
}

function Configure-DNS {
    Write-Log "Configuring DNS..."
    
    # Set DNS Forwarders
    Set-DnsServerForwarder -IPAddress "168.63.129.16","1.1.1.1" -UseRootHint $false
    
    # Create Reverse Lookup Zone
    if (-not (Get-DnsServerZone -Name "1.0.10.in-addr.arpa" -ErrorAction SilentlyContinue)) {
        Add-DnsServerPrimaryZone -NetworkId "10.0.1.0/24" -ReplicationScope Domain -DynamicUpdate Secure
        Write-Log "Created reverse DNS zone"
    }
    
    Write-Log "DNS configuration complete"
}

function Install-EntraCloudSync {
    Write-Log "Downloading Entra Cloud Sync Agent..."
    
    $destDir = "C:\Temp"
    $exePath = Join-Path $destDir "AADConnectProvisioningAgentSetup.exe"
    $downloadUrl = "https://github.com/surmatik/lino-dev-azure-infrastack/raw/refs/heads/main/terraform/dsc/AADConnectProvisioningAgentSetup.exe"
    
    try {
        if (-not (Test-Path $exePath)) {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $downloadUrl -OutFile $exePath -UseBasicParsing
            Write-Log "Download complete"
        }
        
        if (Test-Path "C:\Program Files\Microsoft Azure AD Connect Provisioning Agent\AADConnectProvisioningAgent.exe") {
            Write-Log "Entra Cloud Sync Agent already installed"
        }
        else {
            Write-Log "Installing Entra Cloud Sync Agent..."
            Start-Process -FilePath $exePath -ArgumentList "/quiet /norestart" -Wait
            Write-Log "Entra Cloud Sync Agent installed"
        }
    }
    catch {
        Write-Log "Error with Entra Cloud Sync: $_" -Level "ERROR"
    }
}

# =====================================
# MAIN EXECUTION FLOW
# =====================================

Write-Log "=========================================="
Write-Log "Active Directory Installation Script"
Write-Log "=========================================="

$status = Get-InstallationStatus
Write-Log "Current installation stage: $($status.Stage)"
Write-Log "Reboot count: $($status.RebootCount)"

switch ($status.Stage) {
    "NotStarted" {
        Write-Log "Starting new installation..."
        Register-ContinuationTask
        
        Set-InstallationStatus -Stage "InstallingRole" -RebootCount 0
        Install-ADDSRole
        
        Set-InstallationStatus -Stage "CreatingForest" -RebootCount 0
        Install-ADForest
        
        # Script will not reach here - system reboots during Install-ADForest
    }
    
    "CreatingForest" {
        Write-Log "Resuming after AD Forest creation reboot..."
        
        # Wait a bit for services to start
        Start-Sleep -Seconds 30
        
        Set-InstallationStatus -Stage "ConfiguringAD" -RebootCount ($status.RebootCount + 1)
        Configure-ADStructure
        Configure-DNS
        
        Set-InstallationStatus -Stage "InstallingEntraSync" -RebootCount $status.RebootCount
        Install-EntraCloudSync
        
        Set-InstallationStatus -Stage "Completed" -RebootCount $status.RebootCount
        Write-Log "Installation completed successfully!"
        
        Remove-ContinuationTask
    }
    
    "Completed" {
        Write-Log "Installation already completed"
        Remove-ContinuationTask
    }
    
    default {
        Write-Log "Unknown stage: $($status.Stage) - Cleaning up..." -Level "WARN"
        Remove-ContinuationTask
    }
}

Write-Log "=========================================="
Write-Log "Script execution finished"
Write-Log "=========================================="