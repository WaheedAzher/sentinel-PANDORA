# ADR-0001: Azure Firewall Basic over Standard

- Status: Accepted
- Phase: 0

## Context
The lab needs a central egress and east-west control point in the hub. Standard (or Premium) costs materially more per hour, and the lab runs on a small budget and a free-trial subscription. Lab traffic is a few test VMs.

## Decision
Use Azure Firewall **Basic** with a Basic-tier policy.

## Consequences
- Lower hourly cost. Basic needs a dedicated management subnet and management public IP (handled in the firewall module).
- Application (FQDN) rules, network rules, and logging to Log Analytics are available, which is all Phase 0 needs.
- Not available on Basic: IDPS, TLS inspection, URL filtering and web categories; threat intelligence is alert-only; throughput is capped (250 Mbps). None matter for Phase 0.
- Revisit if a later phase needs IDPS, TLS inspection or more throughput.

## Evidence / cost
See [cost-log.md](../cost-log.md).
