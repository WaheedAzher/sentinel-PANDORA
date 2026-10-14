# Phase 0 troubleshooting log

Real failures hit while building Phase 0. Format: symptom, cause, fix, lesson.

## TS-001: `az` query fails on Windows: "`0`].name was unexpected at this time."
- **Symptom:** `az vm list-skus ... --query [?length(restrictions)==`0`].name` failed in the preflight of the PowerShell script.
- **Cause:** On Windows, `az` is `az.cmd`, so arguments pass through `cmd.exe`. The parentheses and backticks in the JMESPath expression are parsed by `cmd.exe` before Azure CLI sees them.
- **Fix:** Fetch plain JSON (`-o json`), then filter in PowerShell with `ConvertFrom-Json` and `Where-Object`.
- **Lesson:** Keep `--query` expressions simple on Windows, or do the filtering in the shell. The same family of quirk affects JSON strings and empty-string arguments.

## TS-002: Every candidate VM size reported unavailable in `centralindia`
- **Symptom:** Preflight rejected all sizes ("None of the candidate VM sizes are available"), which suggested the free-trial subscription blocked VMs.
- **Cause:** The check rejected a size if it had **any** entry in `restrictions`. `az vm list-skus` also returns **Zone**-type restrictions for sizes that are fine for non-zonal VMs. Only a **Location** restriction blocks a size.
- **Fix:** Reject only `type == Location` restrictions, and print `type:reasonCode` when a size is rejected.
- **Lesson:** Look at the actual reason code before escalating. An upgrade to pay-as-you-go was not needed.

## TS-003: `unrecognized arguments: --m-vnet-name` on `az network firewall create`
- **Symptom:** Firewall creation failed with `unrecognized arguments: --m-vnet-name vnet-pandora-hub-01` (azure-firewall extension 2.4.0, Basic tier).
- **Cause:** The argument does not exist in that extension version. The management configuration finds `AzureFirewallManagementSubnet` in the same VNet given by `--vnet-name`.
- **Fix:** Remove `--m-vnet-name`; keep `--m-conf-name` and `--m-public-ip`.
- **Lesson:** Check `az network firewall create -h` for the installed extension version instead of assuming argument names. Re-running after a mid-script failure also requires removing already-created objects that are not idempotent (here, the firewall policy rule collections).

## TS-004: `terraform apply` fails: diagnostic setting "already exists ... needs to be imported"
- **Symptom:** After the Bastion and firewall were created, Terraform failed on `azurerm_monitor_diagnostic_setting` for both resources: `a resource with the ID ".../fw-pandora-hub-01|diag-fw" already exists`.
- **Cause (inferred; the fix confirmed it):** Diagnostic settings from the earlier CLI deployment were left behind after the resource group was deleted. They are keyed by `<resource ID>|<setting name>`, and the new resources had identical names and IDs, so Azure still returned the old settings.
- **Fix:** `az monitor diagnostic-settings delete --name diag-fw --resource <firewall id>` and the same for `diag-bastion`, then `terraform apply` again. The second apply resumed and created only what was missing.
- **Lesson:** Tear down with the tool that built it (`terraform destroy`). Extension resources such as diagnostic settings can outlive their parent when the group is deleted.

## TS-005: `terraform validate`: "there is no package for ... azurerm 4.81.0 cached in .terraform\providers"
- **Symptom:** `validate` and `state list` failed in the project parent folder after the earlier smoke test.
- **Cause:** A stale `.terraform.lock.hcl` was left in the wrong directory with no matching `.terraform` provider cache, and the Terraform files lived in a subfolder.
- **Fix:** Remove the leftover lock file, state and `.terraform` from the parent folder, then run `terraform init` inside `phase0-terraform`.
- **Lesson:** Run Terraform from the directory that holds the configuration, and keep one project per folder.
