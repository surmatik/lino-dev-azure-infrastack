# --- Networking VNET Hub---

resource "azurerm_virtual_network" "hub" {
  name                = "vnet-lino-hub-dev"
  location            = azurerm_resource_group.infra.location
  resource_group_name = azurerm_resource_group.infra.name
  address_space       = ["10.0.0.0/16"]
  tags                = var.tags
}

resource "azurerm_subnet" "identity" {
  name                 = "snet-identity"
  resource_group_name  = azurerm_resource_group.infra.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = ["10.0.1.0/24"]
  service_endpoints    = ["Microsoft.Storage"]
}

resource "azurerm_subnet" "mgmt_infra" {
  name                 = "snet-mgmt"
  resource_group_name  = azurerm_resource_group.infra.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = ["10.0.2.0/24"]
}

resource "azurerm_virtual_network_dns_servers" "dc_dns" {
  virtual_network_id = azurerm_virtual_network.hub.id
  dns_servers        = ["10.0.1.4", "168.63.129.16"] # DC and Azure provided DNS

  depends_on = [azurerm_virtual_machine_extension.ad_install]
}

# --- Networking VNET Workload ---

resource "azurerm_virtual_network" "workload" {
  name                = "vnet-lino-workload-dev-westeu"
  location            = azurerm_resource_group.apps.location
  resource_group_name = azurerm_resource_group.apps.name
  address_space       = ["10.1.0.0/16"]
  tags                = var.tags
}

resource "azurerm_subnet" "apps" {
  name                 = "snet-apps"
  resource_group_name  = azurerm_resource_group.apps.name
  virtual_network_name = azurerm_virtual_network.workload.name
  address_prefixes     = ["10.1.1.0/24"]
}

resource "azurerm_subnet" "avd" {
  name                 = "snet-avd"
  resource_group_name  = azurerm_resource_group.apps.name
  virtual_network_name = azurerm_virtual_network.workload.name
  address_prefixes     = ["10.1.2.0/24"]
}

resource "azurerm_virtual_network_dns_servers" "workload_dns" {
  virtual_network_id = azurerm_virtual_network.workload.id
  dns_servers        = ["10.0.1.4", "168.63.129.16"] # DC and Azure provided DNS

  depends_on = [azurerm_virtual_machine_extension.ad_install]
}

# --- Networking Peering  ---
resource "azurerm_virtual_network_peering" "hub_to_workload" {
  name                         = "peer-hub-to-workload"
  resource_group_name          = azurerm_resource_group.infra.name
  virtual_network_name         = azurerm_virtual_network.hub.name
  remote_virtual_network_id    = azurerm_virtual_network.workload.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

resource "azurerm_virtual_network_peering" "workload_to_hub" {
  name                         = "peer-workload-to-hub"
  resource_group_name          = azurerm_resource_group.apps.name
  virtual_network_name         = azurerm_virtual_network.workload.name
  remote_virtual_network_id    = azurerm_virtual_network.hub.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}