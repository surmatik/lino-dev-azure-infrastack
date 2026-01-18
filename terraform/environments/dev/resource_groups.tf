# --- Resource Groups ---

resource "azurerm_resource_group" "mgmt" {
  name     = "rg-lino-mgmt-dev"
  location = var.location
  tags     = var.tags
  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_resource_group" "infra" {
  name     = "rg-lino-infra-dev"
  location = var.location
  tags     = merge(var.tags, { Component = "Infrastructure" })
}

resource "azurerm_resource_group" "apps" {
  name     = "rg-lino-apps-dev"
  location = var.location
  tags     = merge(var.tags, { Component = "Applications" })
}

resource "azurerm_resource_group" "avd" {
  name     = "rg-lino-avd-dev"
  location = var.location
  tags     = merge(var.tags, { Component = "AVD" })
}
