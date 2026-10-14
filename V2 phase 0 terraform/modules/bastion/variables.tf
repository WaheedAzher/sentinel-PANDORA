variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "sku" {
  description = "Basic supports peered VNets. Developer SKU does not."
  type        = string
  default     = "Basic"
}

variable "subnet_id" {
  description = "AzureBastionSubnet ID (/26 or larger)."
  type        = string
}
