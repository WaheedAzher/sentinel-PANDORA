# Zero Trust pillar map - Phase 0

Principles: **verify explicitly**, **use least privilege**, **assume breach**. Phase 0 is a network foundation, so the Network pillar is where it delivers. Identity and Device are mostly deferred, and this map says so rather than overclaiming.

Status key: **Delivered** (built and tested), **Partial**, **Deferred** (planned for a later phase).

## Network

| Principle | Control in Phase 0 | Status |
|---|---|---|
| Least privilege | NSG allows inbound SSH only from the Bastion subnet; other VNet-sourced inbound denied | Delivered |
| Least privilege | Egress default-deny; only Ubuntu package mirrors allowed (FQDN application rule) | Delivered |
| Assume breach | East-west denied: spokes cannot reach each other (firewall RFC1918 deny) | Delivered |
| Assume breach | Workload VMs have no public IP; admin only through Bastion | Delivered |
| Verify explicitly / visibility | Firewall and Bastion logs in Log Analytics (1 GB/day cap) | Delivered |
| Assume breach | Spoke to hub-subnet traffic bypasses the firewall (peering route) | Partial - documented limitation (ADR-0003) |
| Assume breach | Threat intelligence in alert mode only; no IDPS or TLS inspection (Basic tier) | Partial - accepted trade-off (ADR-0001) |

## Identity

| Principle | Control in Phase 0 | Status |
|---|---|---|
| Verify explicitly | VMs use SSH key authentication; password login disabled | Delivered |
| Least privilege | Bastion access is governed by Azure RBAC on the Azure side | Partial - not yet reviewed or tested with a restricted role |
| Verify explicitly | Entra ID sign-in to VMs, Conditional Access, MFA | Deferred (Phase 1; check licensing first) |
| Least privilege | PIM / just-in-time admin access | Deferred (needs Entra ID P2) |

## Device

| Principle | Control in Phase 0 | Status |
|---|---|---|
| Verify explicitly | Device compliance checks (Intune) | Deferred |
| Assume breach | Endpoint telemetry (Defender for Endpoint / agents) | Deferred |
| Least privilege | Hardened baseline images | Deferred |

## Reading this map
The point for a reviewer: network controls are real and tested; identity and device claims are limited to what exists today. Each deferred item has an owner phase.
