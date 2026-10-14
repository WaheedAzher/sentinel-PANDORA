variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "hub_address_space" {
  description = "Hub VNet CIDR (/20)."
  type        = string
}

variable "spokes" {
  description = "Spoke name => VNet CIDR (/20)."
  type        = map(string)
}
