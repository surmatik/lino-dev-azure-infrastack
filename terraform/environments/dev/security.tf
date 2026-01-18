data "azurerm_client_config" "current" {}

# Key Vault
resource "azurerm_key_vault" "vault" {
  name                        = "kv-lino-dev-westeu-001" 
  location                    = azurerm_resource_group.mgmt.location
  resource_group_name         = azurerm_resource_group.mgmt.name
  enabled_for_deployment      = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  sku_name                    = "standard"

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    secret_permissions = ["Get", "List", "Set", "Delete", "Purge", "Recover"]
  }

  tags = var.tags
}

# Password Generation
resource "random_password" "vm_password" {
  length           = 20
  special          = true
  override_special = "!#$%&*()-_=+[]{}?" 
}

# Vault Secret DC
resource "azurerm_key_vault_secret" "admin_password" {
  name         = "identity-dc01-admin-pwd"
  value        = random_password.vm_password.result
  key_vault_id = azurerm_key_vault.vault.id
  
  content_type = "VM Local Admin Password"
}