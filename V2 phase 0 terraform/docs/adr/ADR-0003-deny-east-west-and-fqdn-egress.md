# ADR-0003: Deny east-west through the hub; default-deny egress with an FQDN allow-list

- Status: Accepted
- Phase: 0

## Context
Spokes are workload networks. A compromised spoke VM should not reach other spokes, and should only reach the internet destinations it needs. The first designs allowed any destination on TCP 80/443, which is a weak egress control.

## Decision
- Every spoke workload subnet has a route table sending `0.0.0.0/0` to the firewall.
- The firewall policy **denies** spoke -> `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16` (no spoke-to-spoke traffic).
- Internet egress is **default deny**. An application rule allows only the Ubuntu package mirrors over HTTP/HTTPS. A separate, removable test rule allows `ifconfig.me` so the egress-IP check can run.
- NSG on spoke subnets allows inbound SSH only from the Bastion subnet and denies other VNet-sourced inbound.

## Consequences
- Least-privilege egress. Blocked destinations show up as `Deny` in the firewall logs.
- Application rules are matched on HTTP Host / TLS SNI, so no DNS proxy is required.
- **Known limitation:** peering adds a system route for the hub address space that is more specific than the `0.0.0.0/0` route, so spoke -> hub-subnet traffic goes directly over the peering and skips the firewall. Today the hub contains only the firewall and Bastion subnets, so risk is minimal. A UDR forcing the hub range through the firewall would break Bastion (reply traffic would be routed asymmetrically), so it would need a more specific exception for the Bastion subnet. Revisit before placing workloads in the hub.
