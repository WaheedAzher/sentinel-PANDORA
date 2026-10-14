# Phase 0 validation

Run after `terraform apply`. Record the result and attach a screenshot or pasted output for each. Variables used below:

```powershell
$rg = "RG-PANDORA-P0-01"
```

Run VM-side commands in a **Bastion SSH session** on the VM (portal -> VM -> Connect -> Bastion, user `pandoraadmin`, upload `~/.ssh/pandora_rsa`). Running them there avoids Windows quoting problems.

| # | Test | Command | Expected | Result | Evidence |
|---|---|---|---|---|---|
| 1 | Peering connected | `az network vnet peering list -g $rg --vnet-name vnet-pandora-hub-01 -o table` | Both peerings `Connected` | | |
| 2 | No public IP on VMs | `az network public-ip list -g $rg --query "[].name" -o tsv` | Only `pip-pandora-fw-01`, `pip-pandora-fwmgmt-01`, `pip-pandora-bas-01` | | |
| 3 | NSG rules | `az network nsg rule list -g $rg --nsg-name nsg-spoke-workload -o table` | Allow SSH from `10.10.0.128/26` (100), deny VNet inbound (4000) | | |
| 4 | Effective routes | Portal -> VM NIC -> Effective routes, or `az network nic show-effective-route-table -g $rg -n nic-pandora-mgmt-01 -o table` | `0.0.0.0/0` -> VirtualAppliance (firewall private IP) | | |
| 5 | Bastion access | Connect to a VM through Bastion | Shell opens | | |
| 6 | Egress IP = firewall IP (VM) | `curl -s --max-time 15 https://ifconfig.me` then `terraform output firewall_public_ip` | Both addresses identical | | |
| 7 | Allowed FQDN works (VM) | `curl -sI --max-time 15 http://azure.archive.ubuntu.com/ubuntu/ \| head -1` | `HTTP/1.1 200` or a redirect | | |
| 8 | Non-allowed FQDN blocked (VM) | `curl -sS --max-time 10 -o /dev/null https://www.google.com; echo exit=$?` | Fails (non-zero exit / timeout) | | |
| 9 | Non-web egress blocked (VM) | `nc -zv -w 5 8.8.8.8 53` | Times out / fails | | |
| 10 | Spoke isolation (mgmt VM -> sec VM) | `curl --max-time 5 http://<sec VM private IP>` (IP: `az vm list-ip-addresses -g $rg -o table`) | Fails | | |
| 11 | Logs prove it (Log Analytics) | KQL below | Allow rows for ubuntu FQDN and ifconfig.me, Deny rows for google.com | | |

## KQL (resource-specific tables; wait 5-15 minutes for logs)

```kusto
AZFWApplicationRule
| where TimeGenerated > ago(1h)
| project TimeGenerated, SourceIp, Fqdn, DestinationPort, Action, Rule, RuleCollection
| order by TimeGenerated desc
```

```kusto
AZFWNetworkRule
| where TimeGenerated > ago(1h)
| project TimeGenerated, SourceIp, DestinationIp, DestinationPort, Protocol, Action, Rule
| order by TimeGenerated desc
```

Column names can differ slightly by schema version. If a query errors, open the table in the portal and adjust the projected columns.

## After testing
Remove the test-only egress rule if you want strict least privilege: set `egress_test_fqdns = []` in `terraform.tfvars` and apply, or simply destroy (see README).
