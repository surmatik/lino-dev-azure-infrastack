# Bastion free

resource "azurerm_bastion_host" "bastion" {
  name                = "bst-lino-dev-westeu"
  location            = azurerm_resource_group.infra.location
  resource_group_name = azurerm_resource_group.infra.name
  
  sku                 = "Developer"

  virtual_network_id  = azurerm_virtual_network.hub.id

  tags = var.tags
}