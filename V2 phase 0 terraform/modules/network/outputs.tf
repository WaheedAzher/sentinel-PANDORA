output "firewall_subnet_id" {
  value = azurerm_subnet.firewall.id
}

output "firewall_management_subnet_id" {
  value = azurerm_subnet.firewall_management.id
}

output "bastion_subnet_id" {
  value = azurerm_subnet.bastion.id
}

output "bastion_subnet_cidr" {
  value = local.bastion_subnet_cidr
}

output "spoke_workload_subnet_ids" {
  description = "Spoke name => workload subnet ID."
  value       = { for k, s in azurerm_subnet.workload : k => s.id }
}
