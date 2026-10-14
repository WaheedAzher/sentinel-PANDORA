# Phase 0 topology

```mermaid
flowchart LR
  Admin(("Admin<br/>browser"))
  Internet(("Internet"))
  LAW[("Log Analytics<br/>law-pandora-p0-01")]

  subgraph Hub["Hub VNet 10.10.0.0/20"]
    BAS["Bastion Basic<br/>10.10.0.128/26"]
    FW["Azure Firewall Basic<br/>10.10.0.0/26<br/>(mgmt NIC 10.10.0.64/26)"]
  end

  subgraph Mgmt["Spoke mgmt 10.11.0.0/20"]
    VM1["vm-pandora-mgmt-01<br/>snet-workload-01 10.11.0.0/24"]
  end

  subgraph Sec["Spoke sec 10.12.0.0/20"]
    VM2["vm-pandora-sec-01<br/>snet-workload-01 10.12.0.0/24"]
  end

  Admin -->|"HTTPS 443"| BAS
  BAS -->|"SSH 22 over peering"| VM1
  BAS -->|"SSH 22 over peering"| VM2
  VM1 -->|"UDR 0.0.0.0/0"| FW
  VM2 -->|"UDR 0.0.0.0/0"| FW
  FW -->|"Allow: Ubuntu FQDNs 80/443"| Internet
  FW -.->|"Deny: spoke to RFC1918"| Blocked["Spoke-to-spoke blocked"]
  FW -.->|"diagnostics"| LAW
  BAS -.->|"audit logs"| LAW
```

## Traffic flows

| Flow | Path | Control |
|---|---|---|
| Admin to VM | Browser -> Bastion (443) -> VM (SSH 22) over peering | NSG allows SSH only from `10.10.0.128/26` |
| VM to internet | VM -> UDR -> Firewall -> Internet | Allow-list of Ubuntu FQDNs; everything else default-deny; source NAT to the firewall public IP |
| Spoke to spoke | VM -> UDR -> Firewall | Denied (RFC1918 rule) |
| Spoke to hub subnet | Direct over peering (system route is more specific than the UDR) | **Bypasses the firewall.** Known limitation, see ADR-0003 |

All VMs have no public IP. Firewall and Bastion diagnostics go to Log Analytics.
