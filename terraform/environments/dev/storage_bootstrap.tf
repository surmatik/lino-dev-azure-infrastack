# Zip the DSC folder
data "archive_file" "dsc_zip" {
  type        = "zip"
  source_file = "${path.module}/dsc/ActiveDirectory.ps1"
  output_path = "${path.module}/dsc/ActiveDirectory.ps1.zip"
}

# Storage Account
resource "azurerm_storage_account" "bootstrap" {
  name                     = "stlinodevbootstrap"
  resource_group_name      = azurerm_resource_group.infra.name
  location                 = azurerm_resource_group.infra.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  
  public_network_access_enabled = true 

  network_rules {
    default_action             = "Allow"
    virtual_network_subnet_ids = [azurerm_subnet.identity.id]
    bypass                     = ["AzureServices"]
  }
}

# Storage Container
resource "azurerm_storage_container" "scripts" {
  name                  = "dsc"
  storage_account_id    = azurerm_storage_account.bootstrap.id
  container_access_type = "private"
}

# Upload the zip
resource "azurerm_storage_blob" "dsc_blob" {
  name                   = "ActiveDirectory.ps1.zip"
  storage_account_name   = azurerm_storage_account.bootstrap.name
  storage_container_name = azurerm_storage_container.scripts.name
  type                   = "Block"
  source                 = data.archive_file.dsc_zip.output_path
  content_md5            = data.archive_file.dsc_zip.output_md5
}

# Generate SAS token
data "azurerm_storage_account_sas" "bootstrap_sas" {
  connection_string = azurerm_storage_account.bootstrap.primary_connection_string
  https_only        = true

  resource_types {
    service   = false
    container = false
    object    = true
  }

  services {
    blob = true
    queue = false
    table = false
    file  = false
  }

  start  = "2023-01-01T00:00:00Z"
  expiry = "2027-01-01T00:00:00Z"

  permissions {
    read    = true
    write   = false
    delete  = false
    list    = false
    add     = false
    create  = false
    update  = false
    process = false
    tag     = false
    filter  = false
  }
}