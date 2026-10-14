output "firewall_public_ip" {
  description = "Spoke VM egress must equal this address."
  value       = module.firewall.public_ip
}

output "firewall_private_ip" {
  description = "Next hop used by the spoke route table."
  value       = module.firewall.private_ip
}

output "test_vm_names" {
  value = [for vm in azurerm_linux_virtual_machine.test : vm.name]
}

output "resource_group_name" {
  value = azurerm_resource_group.this.name
}
