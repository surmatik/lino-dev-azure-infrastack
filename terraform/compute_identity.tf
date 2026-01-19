# --- Domain Controller Identity ---

resource "azurerm_user_assigned_identity" "dc_identity" {
  name                = "id-lino-dc-dev"
  location            = azurerm_resource_group.infra.location
  resource_group_name = azurerm_resource_group.infra.name
}

# --- Domain Controller Network Interface ---

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

  tags = var.tags
}

# --- Domain Controller Virtual Machine ---

resource "azurerm_windows_virtual_machine" "dc01" {
  name                = "vm-lino-dc01"
  resource_group_name = azurerm_resource_group.infra.name
  location            = azurerm_resource_group.infra.location
  size                = "Standard_B2s"
  admin_username      = "linoadmin"
  admin_password      = azurerm_key_vault_secret.admin_password.value
  network_interface_ids = [
    azurerm_network_interface.dc_nic.id
  ]

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.dc_identity.id]
  }

  os_disk {
    name                 = "osdisk-lino-dc01"
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-Datacenter"
    version   = "latest"
  }

  lifecycle {
    ignore_changes = [
      admin_password
    ]
  }

  tags = merge(var.tags, {
    Role = "DomainController"
  })
}

# --- Upload PowerShell Script to Storage Account ---

resource "azurerm_storage_account" "scripts" {
  name                     = "stlinoscripts${random_string.storage_suffix.result}"
  resource_group_name      = azurerm_resource_group.infra.name
  location                 = azurerm_resource_group.infra.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  
  tags = var.tags
}

resource "random_string" "storage_suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "azurerm_storage_container" "scripts" {
  name                  = "scripts"
  storage_account_name  = azurerm_storage_account.scripts.name
  container_access_type = "private"
}

resource "azurerm_storage_blob" "ad_install_script" {
  name                   = "Install-ActiveDirectory.ps1"
  storage_account_name   = azurerm_storage_account.scripts.name
  storage_container_name = azurerm_storage_container.scripts.name
  type                   = "Block"
  source                 = "${path.module}/scripts/Install-ActiveDirectory.ps1"
}

data "azurerm_storage_account_blob_container_sas" "scripts" {
  connection_string = azurerm_storage_account.scripts.primary_connection_string
  container_name    = azurerm_storage_container.scripts.name
  https_only        = true

  start  = timestamp()
  expiry = timeadd(timestamp(), "24h")

  permissions {
    read   = true
    add    = false
    create = false
    write  = false
    delete = false
    list   = true
  }
}

# --- Custom Script Extension for AD Installation ---

resource "azurerm_virtual_machine_extension" "ad_install" {
  name                       = "InstallActiveDirectory"
  virtual_machine_id         = azurerm_windows_virtual_machine.dc01.id
  publisher                  = "Microsoft.Compute"
  type                       = "CustomScriptExtension"
  type_handler_version       = "1.10"
  auto_upgrade_minor_version = true

  settings = jsonencode({
    fileUris = [
      "${azurerm_storage_blob.ad_install_script.url}${data.azurerm_storage_account_blob_container_sas.scripts.sas}"
    ]
  })

  protected_settings = jsonencode({
    commandToExecute = "powershell -ExecutionPolicy Unrestricted -File Install-ActiveDirectory.ps1"
  })

  tags = var.tags
}