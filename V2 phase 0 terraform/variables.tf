variable "location" {
  description = "Azure region."
  type        = string
  default     = "centralindia"
}

variable "resource_group_name" {
  description = "Single RG for all of Phase 0 so teardown is one destroy."
  type        = string
  default     = "RG-PANDORA-P0-01"
}

variable "hub_address_space" {
  description = "Hub VNet CIDR (/20). Firewall, firewall-mgmt and Bastion /26 subnets are carved from it."
  type        = string
  default     = "10.10.0.0/20"
}

variable "spokes" {
  description = "Spoke name => VNet CIDR (/20). Add a line to add a spoke."
  type        = map(string)
  default = {
    mgmt = "10.11.0.0/20"
    sec  = "10.12.0.0/20"
  }
}

variable "firewall_sku_tier" {
  description = "Basic or Standard. Basic needs a management subnet + public IP (handled in the module)."
  type        = string
  default     = "Basic"

  validation {
    condition     = contains(["Basic", "Standard"], var.firewall_sku_tier)
    error_message = "firewall_sku_tier must be Basic or Standard."
  }
}

variable "bastion_sku" {
  description = "Basic supports peered VNets. Developer SKU does not."
  type        = string
  default     = "Basic"
}

variable "deploy_test_vms" {
  description = "Create one small test VM per spoke for the egress validation."
  type        = bool
  default     = true
}

variable "vm_size" {
  description = "x64 size allowed on your subscription in the region (use the one the deploy script selected)."
  type        = string
  default     = "Standard_B2ats_v2"
}

variable "ssh_public_key_path" {
  description = "Public key for the test VMs (the RSA key the PowerShell script generated)."
  type        = string
  default     = "~/.ssh/pandora_rsa.pub"
}

variable "allowed_egress_fqdns" {
  description = "FQDNs the spokes may reach over HTTP/HTTPS (Ubuntu package mirrors). All other egress is denied."
  type        = list(string)
  default = [
    "azure.archive.ubuntu.com",
    "security.ubuntu.com",
    "archive.ubuntu.com",
    "changelogs.ubuntu.com",
  ]
}

variable "egress_test_fqdns" {
  description = "Test-only HTTPS destinations for the egress-IP check. Set to [] to remove after validation."
  type        = list(string)
  default     = ["ifconfig.me"]
}
