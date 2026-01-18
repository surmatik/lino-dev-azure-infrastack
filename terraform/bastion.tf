# Bastion Developer SKU

resource "azurerm_bastion_host" "bastion" {
  name                = "bst-lino-dev-westeu"

  location            = azurerm_virtual_network.hub.location
  resource_group_name = azurerm_resource_group.infra.name
  
  sku                 = "Developer"
  virtual_network_id  = azurerm_virtual_network.hub.id

  tags = var.tags

  depends_on = [
    azurerm_virtual_network.hub
  ]
}