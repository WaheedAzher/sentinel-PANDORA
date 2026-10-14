variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "sku_tier" {
  description = "Basic or Standard. Basic requires the management subnet + public IP."
  type        = string
}

variable "firewall_subnet_id" {
  type = string
}

variable "management_subnet_id" {
  description = "AzureFirewallManagementSubnet ID (used only when sku_tier is Basic)."
  type        = string
}

variable "spoke_cidrs" {
  description = "Spoke VNet CIDRs allowed through the firewall."
  type        = list(string)
}

variable "allowed_fqdns" {
  description = "FQDNs spokes may reach over HTTP (80) and HTTPS (443). Everything else is denied by default."
  type        = list(string)
}

variable "test_fqdns" {
  description = "Test-only HTTPS destinations (for the egress-IP check). Empty list removes the rule."
  type        = list(string)
  default     = []
}
