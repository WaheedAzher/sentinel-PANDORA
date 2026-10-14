# Pandora - Phase 0: hub-and-spoke network foundation

Terraform for the Phase 0 lab network (Central India, single resource group `RG-PANDORA-P0-01`).

## What it deploys

| Area | Resources |
|---|---|
| Network | Hub VNet `10.10.0.0/20` (firewall, firewall-management and Bastion /26 subnets), spoke VNets `mgmt` `10.11.0.0/20` and `sec` `10.12.0.0/20`, peering both ways |
| Firewall | Azure Firewall **Basic** + policy. Spoke -> private ranges **denied**; egress **default-deny** with an FQDN allow-list (Ubuntu mirrors) |
| Routing | NSG (SSH only from the Bastion subnet) and a `0.0.0.0/0 -> firewall` route table on every spoke workload subnet |
| Access | Azure Bastion **Basic** (reaches peered VNets; the Developer SKU does not) |
| Monitoring | Log Analytics workspace (1 GB/day cap), firewall + Bastion diagnostics |
| Test VMs | One small Ubuntu VM per spoke, no public IP, auto-shutdown 00:00 IST |

Design notes and trade-offs: [docs/adr](docs/adr). Topology: [docs/topology.md](docs/topology.md). Tests: [docs/validation.md](docs/validation.md).

## Prerequisites

- Terraform >= 1.9, Azure CLI, `az login` done
- An SSH key pair at `~/.ssh/pandora_rsa(.pub)` (RSA/PEM): `ssh-keygen -t rsa -b 4096 -m PEM -f $HOME\.ssh\pandora_rsa`

## Deploy

```powershell
cd phase0-terraform
$env:ARM_SUBSCRIPTION_ID = (az account show --query id -o tsv)
Copy-Item terraform.tfvars.example terraform.tfvars   # set vm_size to a size your subscription allows
terraform init
terraform fmt -recursive
terraform validate
terraform plan -out tfplan
terraform apply tfplan
```

Expect roughly 15-25 minutes (Firewall and Bastion are the slow parts).

## Validate

Run the tests in [docs/validation.md](docs/validation.md), recording evidence as you go.

## Destroy (stops billing)

```powershell
terraform destroy
```

Always destroy with Terraform, not by deleting the resource group. Deleting the group can leave orphaned diagnostic settings that make the next `apply` fail (see [troubleshooting TS-004](docs/troubleshooting.md)).

## Cost warning

Azure Firewall and Bastion bill hourly while they exist. Record deploy/destroy times in [docs/cost-log.md](docs/cost-log.md).

## State and secrets

State is **local** (`terraform.tfstate`) - fine for a solo lab, never commit it. `terraform.tfvars` and `.terraform/` are git-ignored; **do** commit `.terraform.lock.hcl`.
