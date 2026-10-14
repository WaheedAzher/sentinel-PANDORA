locals {
  firewall_subnet_cidr   = cidrsubnet(var.hub_address_space, 6, 0) # 10.10.0.0/26
  firewall_mgmt_cidr     = cidrsubnet(var.hub_address_space, 6, 1) # 10.10.0.64/26
  bastion_subnet_cidr    = cidrsubnet(var.hub_address_space, 6, 2) # 10.10.0.128/26
}

# ---------- Hub ----------
resource "azurerm_virtual_network" "hub" {
  name                = "vnet-pandora-hub-01"
  resource_group_name = var.resource_group_name
  location            = var.location
  address_space       = [var.hub_address_space]
}

resource "azurerm_subnet" "firewall" {
  name                 = "AzureFirewallSubnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [local.firewall_subnet_cidr]
}

resource "azurerm_subnet" "firewall_management" {
  name                 = "AzureFirewallManagementSubnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [local.firewall_mgmt_cidr]
}

resource "azurerm_subnet" "bastion" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [local.bastion_subnet_cidr]
}

# ---------- Spokes ----------
resource "azurerm_virtual_network" "spoke" {
  for_each = var.spokes

  name                = "vnet-pandora-spk-${each.key}-01"
  resource_group_name = var.resource_group_name
  location            = var.location
  address_space       = [each.value]
}

resource "azurerm_subnet" "workload" {
  for_each = var.spokes

  name                 = "snet-workload-01"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.spoke[each.key].name
  address_prefixes     = [cidrsubnet(each.value, 4, 0)] # /20 -> first /24
}

# ---------- Peering (both directions) ----------
resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  for_each = var.spokes

  name                         = "peer-hub-to-${each.key}"
  resource_group_name          = var.resource_group_name
  virtual_network_name         = azurerm_virtual_network.hub.name
  remote_virtual_network_id    = azurerm_virtual_network.spoke[each.key].id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  for_each = var.spokes

  name                         = "peer-${each.key}-to-hub"
  resource_group_name          = var.resource_group_name
  virtual_network_name         = azurerm_virtual_network.spoke[each.key].name
  remote_virtual_network_id    = azurerm_virtual_network.hub.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}
