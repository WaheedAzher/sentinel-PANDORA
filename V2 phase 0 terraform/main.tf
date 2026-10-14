resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
}

# ---------- Network: hub, spokes, peering ----------
module "network" {
  source = "./modules/network"

  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  hub_address_space   = var.hub_address_space
  spokes              = var.spokes
}

# ---------- Firewall: policy, rules, firewall ----------
module "firewall" {
  source = "./modules/firewall"

  resource_group_name  = azurerm_resource_group.this.name
  location             = var.location
  sku_tier             = var.firewall_sku_tier
  firewall_subnet_id   = module.network.firewall_subnet_id
  management_subnet_id = module.network.firewall_management_subnet_id
  spoke_cidrs          = values(var.spokes)
  allowed_fqdns        = var.allowed_egress_fqdns
  test_fqdns           = var.egress_test_fqdns
}

# ---------- Routing: NSG + UDR on spoke workload subnets ----------
module "routing" {
  source = "./modules/routing"

  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  firewall_private_ip = module.firewall.private_ip
  bastion_subnet_cidr = module.network.bastion_subnet_cidr
  workload_subnet_ids = module.network.spoke_workload_subnet_ids
}

# ---------- Bastion ----------
module "bastion" {
  source = "./modules/bastion"

  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  sku                 = var.bastion_sku
  subnet_id           = module.network.bastion_subnet_id
}

# ---------- Monitoring: small workspace, 1 GB/day cap. Sentinel foundation is Phase 2 (Bicep). ----------
resource "azurerm_log_analytics_workspace" "this" {
  name                = "law-pandora-p0-01"
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  daily_quota_gb      = 1
}

resource "azurerm_monitor_diagnostic_setting" "firewall" {
  name                           = "diag-fw"
  target_resource_id             = module.firewall.id
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.this.id
  log_analytics_destination_type = "Dedicated" # resource-specific tables, not AzureDiagnostics

  enabled_log {
    category_group = "allLogs"
  }
}

resource "azurerm_monitor_diagnostic_setting" "bastion" {
  name                       = "diag-bastion"
  target_resource_id         = module.bastion.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category = "BastionAuditLogs"
  }
}

# ---------- Test VMs (one per spoke, no public IP) ----------
locals {
  test_vms = var.deploy_test_vms ? var.spokes : {}
}

resource "azurerm_network_interface" "test" {
  for_each = local.test_vms

  name                = "nic-pandora-${each.key}-01"
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = module.network.spoke_workload_subnet_ids[each.key]
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "test" {
  for_each = local.test_vms

  name                            = "vm-pandora-${each.key}-01"
  resource_group_name             = azurerm_resource_group.this.name
  location                        = var.location
  size                            = var.vm_size
  admin_username                  = "pandoraadmin"
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.test[each.key].id]

  admin_ssh_key {
    username   = "pandoraadmin"
    public_key = file(pathexpand(var.ssh_public_key_path))
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  # Make sure the UDR/NSG are attached before the VM boots and tries to reach the internet.
  depends_on = [module.routing]
}

resource "azurerm_dev_test_global_vm_shutdown_schedule" "test" {
  for_each = local.test_vms

  virtual_machine_id    = azurerm_linux_virtual_machine.test[each.key].id
  location              = var.location
  enabled               = true
  daily_recurrence_time = "0000"
  timezone              = "India Standard Time"

  notification_settings {
    enabled = false
  }
}
