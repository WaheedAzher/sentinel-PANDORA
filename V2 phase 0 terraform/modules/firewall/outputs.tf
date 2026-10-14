output "id" {
  value = azurerm_firewall.this.id
}

output "private_ip" {
  description = "Next hop for the spoke route table."
  value       = azurerm_firewall.this.ip_configuration[0].private_ip_address
}

output "public_ip" {
  description = "Spoke VM egress must equal this address."
  value       = azurerm_public_ip.firewall.ip_address
}
