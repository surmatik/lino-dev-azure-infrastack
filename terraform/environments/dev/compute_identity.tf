# Create the User-Assigned Identity
resource "azurerm_user_assigned_identity" "dc_identity" {
  name                = "id-lino-dc-dev"
  location            = azurerm_resource_group.infra.location
  resource_group_name = azurerm_resource_group.infra.name
}

# Grant the Identity "Reader" access to the Storage Account
resource "azurerm_role_assignment" "storage_reader" {
  scope                = azurerm_storage_account.bootstrap.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_user_assigned_identity.dc_identity.principal_id
}

# VM DC Network Interface
resource "azurerm_network_interface" "dc_nic" {
  name                = "nic-lino-dc01-dev"
  location            = azurerm_resource_group.infra.location
  resource_group_name = azurerm_resource_group.infra.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.identity.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.0.1.4"
  }
}

# VM DC
resource "azurerm_windows_virtual_machine" "dc01" {
  name                = "vm-lino-dc01"
  resource_group_name = azurerm_resource_group.infra.name
  location            = azurerm_resource_group.infra.location
  size                = "Standard_B2s"
  admin_username      = "linoadmin"
  admin_password      = azurerm_key_vault_secret.admin_password.value

  network_interface_ids = [azurerm_network_interface.dc_nic.id]

  # ATTACH THE IDENTITY
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.dc_identity.id]
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-Datacenter"
    version   = "latest"
  }
}

resource "azurerm_virtual_machine_extension" "dsc" {
  name                 = "Microsoft.Powershell.DSC"
  virtual_machine_id   = azurerm_windows_virtual_machine.dc01.id
  publisher            = "Microsoft.Powershell"
  type                 = "DSC"
  type_handler_version = "2.77"

  settings = <<SETTINGS
    {
        "configuration": {
            "url": "${azurerm_storage_blob.dsc_blob.url}${data.azurerm_storage_account_sas.bootstrap_sas.sas}",
            "script": "ActiveDirectory.ps1",
            "function": "ActiveDirectoryConfig"
        },
        "configurationArguments": {
            "SafeModeCredential": {
                "userName": "linoadmin",
                "password": "PrivateSettingsRef:SafeModePassword" 
            }
        },
        "modulesUrl": [
            "https://www.powershellgallery.com/api/v2/package/ActiveDirectoryDsc",
            "https://www.powershellgallery.com/api/v2/package/xDnsServer"
        ]
    }
SETTINGS

  protected_settings = <<PROTECTED_SETTINGS
    {
      "items": {
        "SafeModePassword": "${azurerm_key_vault_secret.admin_password.value}"
      }
    }
PROTECTED_SETTINGS
}