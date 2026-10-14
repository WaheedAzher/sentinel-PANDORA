# ADR-0002: One resource group per phase

- Status: Accepted
- Phase: 0

## Context
The first CLI script created four resource groups (hub plus one per spoke). That made teardown multi-step and meant more cross-group references (NSG and route table in one group, subnets in another).

## Decision
Put all of Phase 0 in a single resource group, `RG-PANDORA-P0-01`. Each later phase gets its own group.

## Consequences
- Teardown is one `terraform destroy`; cost attribution per phase is one filter in Cost Management.
- Simpler Terraform: no cross-group IDs for the NSG, route table or peerings.
- Lifecycle or RBAC separation between hub and spokes is not demonstrated in Phase 0. A production landing zone would separate them.
