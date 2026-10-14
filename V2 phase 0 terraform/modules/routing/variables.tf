variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "firewall_private_ip" {
  description = "Next hop for 0.0.0.0/0."
  type        = string
}

variable "bastion_subnet_cidr" {
  description = "Only source allowed to reach workloads (SSH)."
  type        = string
}

variable "workload_subnet_ids" {
  description = "Spoke name => workload subnet ID. NSG and route table attach to each."
  type        = map(string)
}
