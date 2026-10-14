# Phase 0 cost log

Fill the timestamps from the Azure Activity Log or your terminal history, and the costs from **Cost Management -> Cost analysis** (filter by resource group `RG-PANDORA-P0-01`, group by resource type). Cost data lags by a day or so.

|#|Method|Firewall / Bastion|Deployed (IST)|Validated|Destroyed|Hours up|Actual cost|Notes|
|-|-|-|-|-|-|-|-|-|
|1|Portal (GUI path)|Premium|3:08 IST|4:00 IST|23:30|17:30|2570|firewall is expensive|
|2|PowerShell / az CLI|Basic / Basic|3.30|4.45|5.00|1:30|71||
|3|Terraform|Basic / Basic|3.00|4.00|5.45|1.45|116||

## Budget alerts

Create budgets before the next deploy: Cost Management -> Budgets -> Add. Scope the subscription, set the amount you are willing to burn on this lab, and add alert conditions at **50%** and **80%** of actual spend with your email as recipient.

## Notes

* Azure Firewall and Bastion bill hourly while they exist, even idle. Destroy right after validation.
* VM compute is minor; the auto-shutdown at 00:00 IST only stops compute billing, not the Firewall or Bastion.
* Free-trial credit is consumed by these resources; check the remaining credit on the subscription overview page.

