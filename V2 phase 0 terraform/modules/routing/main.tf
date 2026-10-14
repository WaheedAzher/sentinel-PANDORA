resource "azurerm_network_security_group" "workload" {
  name                = "nsg-spoke-workload"
  resource_group_name = var.resource_group_name
  location            = var.location
}

resource "azurerm_network_security_rule" "allow_ssh_from_bastion" {
  name                        = "Allow-SSH-From-Bastion"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.workload.name
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = var.bastion_subnet_cidr
  destination_address_prefix  = "*"
}

resource "azurerm_network_security_rule" "deny_vnet_inbound" {
  name                        = "Deny-VNet-Inbound"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.workload.name
  priority                    = 4000
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "VirtualNetwork"
  destination_address_prefix  = "*"
}

resource "azurerm_route_table" "spoke_to_hub" {
  name                          = "rt-spoke-to-hub"
  resource_group_name           = var.resource_group_name
  location                      = var.location
  bgp_route_propagation_enabled = false
}

resource "azurerm_route" "default_to_firewall" {
  name                   = "default-to-firewall"
  resource_group_name    = var.resource_group_name
  route_table_name       = azurerm_route_table.spoke_to_hub.name
  address_prefix         = "0.0.0.0/0"
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = var.firewall_private_ip
}

resource "azurerm_subnet_network_security_group_association" "workload" {
  for_each = var.workload_subnet_ids

  subnet_id                 = each.value
  network_security_group_id = azurerm_network_security_group.workload.id
}

resource "azurerm_subnet_route_table_association" "workload" {
  for_each = var.workload_subnet_ids

  subnet_id      = each.value
  route_table_id = azurerm_route_table.spoke_to_hub.id

  # Route must exist before subnets start using the table.
  depends_on = [azurerm_route.default_to_firewall]
}
