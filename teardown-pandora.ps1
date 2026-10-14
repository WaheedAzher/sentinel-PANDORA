#requires -Version 5.1
<# Deletes the entire Phase 0 resource group (firewall, bastion, VMs, VNets, workspace - everything). #>
param([string]$Rg = "RG-PANDORA-P0-01")
$ErrorActionPreference = "Stop"

$exists = & az group exists -n $Rg
if ($LASTEXITCODE -ne 0) { throw "az group exists failed." }
if ($exists.Trim() -ne "true") { Write-Host "$Rg does not exist. Nothing to delete."; return }

$c = Read-Host "This permanently deletes $Rg and everything in it. Type DELETE to continue"
if ($c -cne "DELETE") { throw "Cancelled." }

& az group delete -n $Rg --yes --no-wait
if ($LASTEXITCODE -ne 0) { throw "Delete request failed." }
Write-Host "Deletion started (runs in background). Check: az group exists -n $Rg"
