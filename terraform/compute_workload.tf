# --- App Server NIC ---
resource "azurerm_network_interface" "app01_nic" {
  name                = "nic-vm-lino-app01"
  location            = azurerm_resource_group.infra.location
  resource_group_name = azurerm_resource_group.infra.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.apps.id
    private_ip_address_allocation = "Dynamic"
  }
}

# --- App Server VM ---
resource "azurerm_windows_virtual_machine" "app01" {
  name                = "vm-lino-app01"
  resource_group_name = azurerm_resource_group.infra.name
  location            = azurerm_resource_group.infra.location
  size                = "Standard_B2s"
  admin_username      = "linoadmin"
  admin_password      = azurerm_key_vault_secret.admin_password.value
  network_interface_ids = [azurerm_network_interface.app01_nic.id]

  os_disk {
    name                 = "osdisk-vm-lino-app01"
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-Datacenter"
    version   = "latest"
  }

  tags = merge(var.tags, { Role = "AppServer" })
}

# --- Active Directory Domain Join ---
resource "azurerm_virtual_machine_extension" "domain_join" {
  name                       = "ad-domain-join"
  virtual_machine_id         = azurerm_windows_virtual_machine.app01.id
  publisher                  = "Microsoft.Compute"
  type                       = "JsonADDomainExtension"
  type_handler_version       = "1.3"
  auto_upgrade_minor_version = true

  settings = <<SETTINGS
    {
        "Name": "corp.dev.surmatik.ch",
        "OUString": "OU=Servers,OU=Lino,DC=corp,DC=dev,DC=surmatik,DC=ch",
        "User": "corp.dev.surmatik.ch\\linoadmin",
        "Restart": "true",
        "Options": "3"
    }
SETTINGS

  protected_settings = <<PROTECTED_SETTINGS
    {
        "Password": "${azurerm_key_vault_secret.admin_password.value}"
    }
PROTECTED_SETTINGS

  depends_on = [azurerm_virtual_machine_extension.ad_install]
}