resource "azurerm_network_security_group" "workload" {
  name                = "nsg-workload-dev-westeu"
  location            = azurerm_resource_group.apps.location
  resource_group_name = azurerm_resource_group.apps.name
  tags                = var.tags
}

# Allow RDP only from within the Virtual Network
resource "azurerm_network_security_rule" "allow_rdp_vnet" {
  name                        = "AllowRDPVnetInbound"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "3389"
  source_address_prefix       = "VirtualNetwork"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.apps.name
  network_security_group_name = azurerm_network_security_group.workload.name
}

# Associate NSG
resource "azurerm_subnet_network_security_group_association" "apps" {
  subnet_id                 = azurerm_subnet.apps.id
  network_security_group_id = azurerm_network_security_group.workload.id
}

resource "azurerm_subnet_network_security_group_association" "avd" {
  subnet_id                 = azurerm_subnet.avd.id
  network_security_group_id = azurerm_network_security_group.workload.id
}