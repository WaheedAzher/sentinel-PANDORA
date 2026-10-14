locals {
  is_basic = var.sku_tier == "Basic"
}

resource "azurerm_public_ip" "firewall" {
  name                = "pip-pandora-fw-01"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

# Basic tier requires a separate management public IP.
resource "azurerm_public_ip" "management" {
  count = local.is_basic ? 1 : 0

  name                = "pip-pandora-fwmgmt-01"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_firewall_policy" "this" {
  name                  = "fwp-pandora-01"
  resource_group_name   = var.resource_group_name
  location              = var.location
  sku                   = var.sku_tier
  threat_intelligence_mode = "Alert"
}

resource "azurerm_firewall_policy_rule_collection_group" "egress" {
  name               = "rcg-pandora-egress"
  firewall_policy_id = azurerm_firewall_policy.this.id
  priority           = 100

  # 1) Block spoke -> any private range (no east-west through the hub).
  network_rule_collection {
    name     = "Deny-Spoke-To-Private"
    priority = 100
    action   = "Deny"

    rule {
      name                  = "Deny-RFC1918"
      protocols             = ["Any"]
      source_addresses      = var.spoke_cidrs
      destination_addresses = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
      destination_ports     = ["*"]
    }
  }

  # 2) Egress is default-deny. Only these FQDNs are reachable (HTTP/HTTPS), via application rules.
  application_rule_collection {
    name     = "Allow-Spoke-FQDNs"
    priority = 300
    action   = "Allow"

    rule {
      name              = "Allow-Ubuntu-Repos"
      source_addresses  = var.spoke_cidrs
      destination_fqdns = var.allowed_fqdns

      protocols {
        type = "Http"
        port = 80
      }
      protocols {
        type = "Https"
        port = 443
      }
    }

    # Test-only rule so the egress-IP check (curl ifconfig.me) can run. Set test_fqdns = [] to remove.
    dynamic "rule" {
      for_each = length(var.test_fqdns) > 0 ? [1] : []
      content {
        name              = "Allow-Egress-Test"
        source_addresses  = var.spoke_cidrs
        destination_fqdns = var.test_fqdns

        protocols {
          type = "Https"
          port = 443
        }
      }
    }
  }
}

resource "azurerm_firewall" "this" {
  name                = "fw-pandora-hub-01"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku_name            = "AZFW_VNet"
  sku_tier            = var.sku_tier
  firewall_policy_id  = azurerm_firewall_policy.this.id

  ip_configuration {
    name                 = "fw-ipconfig"
    subnet_id            = var.firewall_subnet_id
    public_ip_address_id = azurerm_public_ip.firewall.id
  }

  dynamic "management_ip_configuration" {
    for_each = local.is_basic ? [1] : []
    content {
      name                 = "fw-mgmt-ipconfig"
      subnet_id            = var.management_subnet_id
      public_ip_address_id = azurerm_public_ip.management[0].id
    }
  }

  # Policy rules must exist before the firewall starts forwarding traffic.
  depends_on = [azurerm_firewall_policy_rule_collection_group.egress]
}
