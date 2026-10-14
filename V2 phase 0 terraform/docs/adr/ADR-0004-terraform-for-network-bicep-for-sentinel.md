# ADR-0004: Terraform for the network foundation, Bicep reserved for Sentinel

- Status: Accepted
- Phase: 0

## Context
Phase 0 is networking; Phase 2 is the Sentinel foundation (workspace, onboarding, data collection rules). The project is IaC-first, and a CLI quick-deploy script was built first for speed and as a comparison to the Portal build.

## Decision
- Network, firewall, routing, Bastion and test VMs are defined in **Terraform** (root config + `network`, `firewall`, `routing`, `bastion` modules).
- Sentinel-specific resources are planned in **Bicep** in Phase 2.
- The PowerShell/`az` script is kept as a reference quick-deploy, not the source of truth.

## Consequences
- Two IaC tools in one project; shared naming conventions keep them consistent.
- `terraform plan` shows changes before they happen, unlike the CLI script.
- Terraform state is **local** for this solo lab. It is git-ignored and must not be committed. A remote backend would be needed for collaboration or CI.
- Deploy with Terraform and destroy with Terraform (see troubleshooting TS-004).
