#requires -Version 5.1
<#
Project Sentinel Forge - Phase 0: hub-and-spoke network foundation (Azure CLI quick-deploy)

  .\deploy-pandora.ps1              # network + firewall + bastion + 2 test VMs + validation
  .\deploy-pandora.ps1 -SkipVms     # network only

Everything lives in ONE resource group so teardown = one deletion (see teardown-pandora.ps1).
Firewall and Bastion bill hourly while they exist. Tear down when the exercise is done.
Fail-fast: any failing az command stops the script.
#>
param([switch]$SkipVms)

$ErrorActionPreference = "Stop"

# -------------------- Settings --------------------
$Location   = "centralindia"
$Rg         = "RG-PANDORA-P0-01"

$FwTier     = "Basic"               # Basic | Standard  (Basic is far cheaper)
$BastionSku = "Basic"               # Basic supports peered VNets; Developer SKU does NOT
# x64 sizes tried in order; first one your subscription allows in $Location is used.
# (ARM64 sizes like Standard_B2pts_v2 would need an ARM64 image - don't mix.)
$VmSizeCandidates = @("Standard_B2ats_v2","Standard_B1s","Standard_B1ms","Standard_B2s","Standard_B2ls_v2","Standard_D2as_v5")
$VmSize     = $null
$VmImage    = "Canonical:ubuntu-24_04-lts:server:latest"
$ShutdownUtc = "1830"               # 18:30 UTC = 00:00 IST

$VnetHub = "vnet-pandora-hub-01"
$Hub     = @{ Cidr = "10.10.0.0/20"; FwSubnet = "10.10.0.0/26"; FwMgmtSubnet = "10.10.0.64/26"; BastionSubnet = "10.10.0.128/26" }

# Add or remove spokes here; everything below loops over this list.
$Spokes = @(
    @{ Name = "mgmt"; Prefix = "10.11" },
    @{ Name = "sec";  Prefix = "10.12" }
)

$FwName = "fw-pandora-hub-01";  $FwPolicy = "fwp-pandora-01"
$FwPip  = "pip-pandora-fw-01";  $FwMgmtPip = "pip-pandora-fwmgmt-01"
$BastionName = "bas-pandora-hub-01"; $BastionPip = "pip-pandora-bas-01"
$Workspace = "law-pandora-p0-01"
$NsgName = "nsg-spoke-workload"; $RtName = "rt-spoke-to-hub"

$SshKey = Join-Path $HOME ".ssh\pandora_rsa"
$SshPub = "$SshKey.pub"

# -------------------- Helpers --------------------
function Invoke-Az {
    param([Parameter(Mandatory=$true)][string[]]$AzArgs)
    & az @AzArgs
    if ($LASTEXITCODE -ne 0) { throw "az failed: az $($AzArgs -join ' ')" }
}
function Get-AzValue {
    param([Parameter(Mandatory=$true)][string[]]$AzArgs)
    $r = & az @AzArgs
    if ($LASTEXITCODE -ne 0) { throw "az query failed: az $($AzArgs -join ' ')" }
    return (($r | Out-String).Trim())
}

# -------------------- Preflight --------------------
if (-not (Get-Command az -ErrorAction SilentlyContinue)) { throw "Azure CLI not found." }

$SubName = Get-AzValue @("account","show","--query","name","-o","tsv")
$SubId   = Get-AzValue @("account","show","--query","id","-o","tsv")
$SubState = Get-AzValue @("account","show","--query","state","-o","tsv")
if ($SubState -ne "Enabled") { throw "Selected subscription is not Enabled." }

# 'az network firewall' and 'policy' sub-commands live in an extension.
Invoke-Az @("extension","add","--name","azure-firewall","--upgrade","--yes","-o","none")

if (-not $SkipVms) {
    # Filter in PowerShell: JMESPath with ( ) ` breaks when az.cmd hands args to cmd.exe.
    foreach ($cand in $VmSizeCandidates) {
        $SkuJson = Get-AzValue @("vm","list-skus","-l",$Location,"--size",$cand,"--resource-type","virtualMachines","-o","json")
        $Found = @($SkuJson | ConvertFrom-Json) | Where-Object { $_.name -eq $cand }
        # Only a 'Location' restriction blocks the size. 'Zone' restrictions don't matter for non-zonal VMs.
        $Blocked = @($Found.restrictions) | Where-Object { $_.type -eq "Location" }
        if ($Found -and -not $Blocked) { $VmSize = $cand; break }
        if (-not $Found) { $why = "not offered in region" }
        else { $why = (@($Found.restrictions) | ForEach-Object { "$($_.type):$($_.reasonCode)" }) -join ", " }
        Write-Host "Size $cand rejected ($why), trying next..."
    }
    if (-not $VmSize) { throw "None of the candidate VM sizes are available in $Location. Try another region or run with -SkipVms." }
    Write-Host "VM size selected: $VmSize"
}

Write-Host ""
Write-Host "Subscription : $SubName ($SubId)"
Write-Host "Region       : $Location"
Write-Host "Resource grp : $Rg"
Write-Host "Billable     : Azure Firewall ($FwTier) + Bastion ($BastionSku) accrue hourly until deleted."
$c = Read-Host "Type DEPLOY to continue"
if ($c -cne "DEPLOY") { throw "Cancelled." }

foreach ($ns in "Microsoft.Network","Microsoft.OperationalInsights","Microsoft.Insights","Microsoft.Compute") {
    Invoke-Az @("provider","register","--namespace",$ns,"--wait")
}

if (-not $SkipVms -and -not (Test-Path $SshPub)) {
    if (-not (Get-Command ssh-keygen -ErrorAction SilentlyContinue)) { throw "ssh-keygen not found. Enable Windows OpenSSH Client." }
    New-Item -ItemType Directory -Force -Path (Split-Path $SshKey) | Out-Null
    # RSA/PEM: the format Bastion's portal SSH key upload is known to accept.
    & ssh-keygen -t rsa -b 4096 -m PEM -f $SshKey -C "pandora-lab"
    if ($LASTEXITCODE -ne 0) { throw "ssh-keygen failed." }
}

# -------------------- Resource group + monitoring --------------------
Invoke-Az @("group","create","-n",$Rg,"-l",$Location,"-o","none")

# Small workspace for firewall/bastion logs, 1 GB/day cap. Sentinel foundation is Phase 2 (Bicep).
Invoke-Az @("monitor","log-analytics","workspace","create","-g",$Rg,"-n",$Workspace,"-l",$Location,"--retention-time","30","--quota","1","-o","none")
$WorkspaceId = Get-AzValue @("monitor","log-analytics","workspace","show","-g",$Rg,"-n",$Workspace,"--query","id","-o","tsv")

# -------------------- VNets, subnets, peering --------------------
Invoke-Az @("network","vnet","create","-g",$Rg,"-n",$VnetHub,"-l",$Location,"--address-prefixes",$Hub.Cidr,"-o","none")
Invoke-Az @("network","vnet","subnet","create","-g",$Rg,"--vnet-name",$VnetHub,"-n","AzureFirewallSubnet","--address-prefixes",$Hub.FwSubnet,"-o","none")
Invoke-Az @("network","vnet","subnet","create","-g",$Rg,"--vnet-name",$VnetHub,"-n","AzureFirewallManagementSubnet","--address-prefixes",$Hub.FwMgmtSubnet,"-o","none")
Invoke-Az @("network","vnet","subnet","create","-g",$Rg,"--vnet-name",$VnetHub,"-n","AzureBastionSubnet","--address-prefixes",$Hub.BastionSubnet,"-o","none")

foreach ($s in $Spokes) {
    $s.VNet = "vnet-pandora-spk-$($s.Name)-01"
    Invoke-Az @("network","vnet","create","-g",$Rg,"-n",$s.VNet,"-l",$Location,"--address-prefixes","$($s.Prefix).0.0/20","-o","none")
    Invoke-Az @("network","vnet","subnet","create","-g",$Rg,"--vnet-name",$s.VNet,"-n","snet-workload-01","--address-prefixes","$($s.Prefix).0.0/24","-o","none")
}

$HubId = Get-AzValue @("network","vnet","show","-g",$Rg,"-n",$VnetHub,"--query","id","-o","tsv")
foreach ($s in $Spokes) {
    $SpokeId = Get-AzValue @("network","vnet","show","-g",$Rg,"-n",$s.VNet,"--query","id","-o","tsv")
    Invoke-Az @("network","vnet","peering","create","-g",$Rg,"--vnet-name",$VnetHub,"-n","peer-hub-to-$($s.Name)","--remote-vnet",$SpokeId,"--allow-vnet-access","true","--allow-forwarded-traffic","true","-o","none")
    Invoke-Az @("network","vnet","peering","create","-g",$Rg,"--vnet-name",$s.VNet,"-n","peer-$($s.Name)-to-hub","--remote-vnet",$HubId,"--allow-vnet-access","true","--allow-forwarded-traffic","true","-o","none")
}

# -------------------- Firewall policy + rules --------------------
$SpokeCidrs = @($Spokes | ForEach-Object { "$($_.Prefix).0.0/20" })

Invoke-Az @("network","firewall","policy","create","-g",$Rg,"-n",$FwPolicy,"-l",$Location,"--sku",$FwTier,"--threat-intel-mode","Alert","-o","none")
Invoke-Az @("network","firewall","policy","rule-collection-group","create","-g",$Rg,"--policy-name",$FwPolicy,"-n","rcg-pandora-egress","--priority","100","-o","none")

# 1) Block spoke -> any private range (no east-west through the hub unless you add an allow above this).
Invoke-Az (@("network","firewall","policy","rule-collection-group","collection","add-filter-collection",
    "-g",$Rg,"--policy-name",$FwPolicy,"--rcg-name","rcg-pandora-egress",
    "--name","Deny-Spoke-To-Private","--collection-priority","100","--action","Deny",
    "--rule-name","Deny-RFC1918","--rule-type","NetworkRule","--source-addresses") + $SpokeCidrs +
    @("--destination-addresses","10.0.0.0/8","172.16.0.0/12","192.168.0.0/16","--destination-ports","*","--ip-protocols","Any","-o","none"))

# 2) Allow spoke web egress (80/443) to the internet.
Invoke-Az (@("network","firewall","policy","rule-collection-group","collection","add-filter-collection",
    "-g",$Rg,"--policy-name",$FwPolicy,"--rcg-name","rcg-pandora-egress",
    "--name","Allow-Spoke-Web","--collection-priority","200","--action","Allow",
    "--rule-name","Allow-HTTP-HTTPS","--rule-type","NetworkRule","--source-addresses") + $SpokeCidrs +
    @("--destination-addresses","*","--destination-ports","80","443","--ip-protocols","TCP","-o","none"))

# -------------------- Firewall --------------------
Invoke-Az @("network","public-ip","create","-g",$Rg,"-n",$FwPip,"-l",$Location,"--sku","Standard","--allocation-method","Static","-o","none")
$PolicyId = Get-AzValue @("network","firewall","policy","show","-g",$Rg,"-n",$FwPolicy,"--query","id","-o","tsv")

$FwArgs = @("network","firewall","create","-g",$Rg,"-n",$FwName,"-l",$Location,
    "--sku","AZFW_VNet","--tier",$FwTier,"--firewall-policy",$PolicyId,
    "--vnet-name",$VnetHub,"--conf-name","fw-ipconfig","--public-ip",$FwPip)
if ($FwTier -eq "Basic") {
    # Basic requires a management subnet + management public IP.
    Invoke-Az @("network","public-ip","create","-g",$Rg,"-n",$FwMgmtPip,"-l",$Location,"--sku","Standard","--allocation-method","Static","-o","none")
    $FwArgs += @("--m-conf-name","fw-mgmt-ipconfig","--m-public-ip",$FwMgmtPip)
}
Invoke-Az ($FwArgs + @("-o","none"))

$FwPrivateIp = Get-AzValue @("network","firewall","show","-g",$Rg,"-n",$FwName,"--query","ipConfigurations[0].privateIPAddress","-o","tsv")
if (-not $FwPrivateIp) { throw "Could not read firewall private IP." }
Write-Host "Firewall private IP: $FwPrivateIp"

# -------------------- NSG + UDR, attached to spoke workload subnets --------------------
Invoke-Az @("network","nsg","create","-g",$Rg,"-n",$NsgName,"-l",$Location,"-o","none")
Invoke-Az @("network","nsg","rule","create","-g",$Rg,"--nsg-name",$NsgName,"-n","Allow-SSH-From-Bastion","--priority","100",
    "--direction","Inbound","--access","Allow","--protocol","Tcp","--source-address-prefixes",$Hub.BastionSubnet,
    "--source-port-ranges","*","--destination-address-prefixes","*","--destination-port-ranges","22","-o","none")
Invoke-Az @("network","nsg","rule","create","-g",$Rg,"--nsg-name",$NsgName,"-n","Deny-VNet-Inbound","--priority","4000",
    "--direction","Inbound","--access","Deny","--protocol","*","--source-address-prefixes","VirtualNetwork",
    "--source-port-ranges","*","--destination-address-prefixes","*","--destination-port-ranges","*","-o","none")

Invoke-Az @("network","route-table","create","-g",$Rg,"-n",$RtName,"-l",$Location,"--disable-bgp-route-propagation","true","-o","none")
Invoke-Az @("network","route-table","route","create","-g",$Rg,"--route-table-name",$RtName,"-n","default-to-firewall",
    "--address-prefix","0.0.0.0/0","--next-hop-type","VirtualAppliance","--next-hop-ip-address",$FwPrivateIp,"-o","none")

$NsgId = Get-AzValue @("network","nsg","show","-g",$Rg,"-n",$NsgName,"--query","id","-o","tsv")
$RtId  = Get-AzValue @("network","route-table","show","-g",$Rg,"-n",$RtName,"--query","id","-o","tsv")
foreach ($s in $Spokes) {
    Invoke-Az @("network","vnet","subnet","update","-g",$Rg,"--vnet-name",$s.VNet,"-n","snet-workload-01","--network-security-group",$NsgId,"--route-table",$RtId,"-o","none")
}

# -------------------- Bastion --------------------
Invoke-Az @("network","public-ip","create","-g",$Rg,"-n",$BastionPip,"-l",$Location,"--sku","Standard","--allocation-method","Static","-o","none")
Invoke-Az @("network","bastion","create","-g",$Rg,"-n",$BastionName,"-l",$Location,"--vnet-name",$VnetHub,"--public-ip-address",$BastionPip,"--sku",$BastionSku,"-o","none")

# -------------------- Diagnostics (firewall + bastion -> Log Analytics) --------------------
# JSON goes through a temp file: Windows PowerShell 5.1 strips embedded double quotes passed to native commands.
$FwLogsFile  = Join-Path $env:TEMP "pandora-fw-logs.json"
$BasLogsFile = Join-Path $env:TEMP "pandora-bas-logs.json"
Set-Content -Path $FwLogsFile  -Value '[{"categoryGroup":"allLogs","enabled":true}]' -Encoding ascii
Set-Content -Path $BasLogsFile -Value '[{"category":"BastionAuditLogs","enabled":true}]' -Encoding ascii

$FwId  = Get-AzValue @("network","firewall","show","-g",$Rg,"-n",$FwName,"--query","id","-o","tsv")
$BasId = Get-AzValue @("network","bastion","show","-g",$Rg,"-n",$BastionName,"--query","id","-o","tsv")
Invoke-Az @("monitor","diagnostic-settings","create","--name","diag-fw","--resource",$FwId,"--workspace",$WorkspaceId,"--logs","@$FwLogsFile","--export-to-resource-specific","true","-o","none")
Invoke-Az @("monitor","diagnostic-settings","create","--name","diag-bastion","--resource",$BasId,"--workspace",$WorkspaceId,"--logs","@$BasLogsFile","-o","none")

Write-Host ""
Write-Host "Network, firewall, bastion and diagnostics deployed."

# -------------------- Test VMs + validation --------------------
if ($SkipVms) { Write-Host "VMs skipped. Done."; return }

$Vms = @()
foreach ($s in $Spokes) { $Vms += @{ Name = "vm-pandora-$($s.Name)-01"; Nic = "nic-pandora-$($s.Name)-01"; VNet = $s.VNet; IP = "$($s.Prefix).0.4" } }

foreach ($v in $Vms) {
    # Pre-made NIC => no public IP and no auto-created NSG (avoids passing empty strings to az).
    Invoke-Az @("network","nic","create","-g",$Rg,"-n",$v.Nic,"-l",$Location,"--vnet-name",$v.VNet,"--subnet","snet-workload-01","--private-ip-address",$v.IP,"-o","none")
    Invoke-Az @("vm","create","-g",$Rg,"-n",$v.Name,"-l",$Location,"--nics",$v.Nic,"--image",$VmImage,"--size",$VmSize,
        "--admin-username","pandoraadmin","--ssh-key-values",$SshPub,"--storage-sku","Standard_LRS","-o","none")
    Invoke-Az @("vm","auto-shutdown","-g",$Rg,"-n",$v.Name,"--time",$ShutdownUtc,"-o","none")
}

Write-Host ""
Write-Host "==== Validation: spoke egress must leave via the firewall public IP ===="
$ExpectedIp = Get-AzValue @("network","public-ip","show","-g",$Rg,"-n",$FwPip,"--query","ipAddress","-o","tsv")
Write-Host "Firewall public IP: $ExpectedIp"

foreach ($v in $Vms) {
    Write-Host ""
    Write-Host "-- $($v.Name): effective routes --"
    Invoke-Az @("network","nic","show-effective-route-table","-g",$Rg,"-n",$v.Nic,"-o","table")

    $out = Get-AzValue @("vm","run-command","invoke","-g",$Rg,"-n",$v.Name,"--command-id","RunShellScript",
        "--scripts","curl -s --max-time 15 https://ifconfig.me","--query","value[0].message","-o","tsv")
    $seen = if ($out -match '(\d{1,3}(\.\d{1,3}){3})') { $Matches[1] } else { "none" }
    if ($seen -eq $ExpectedIp) { Write-Host "PASS: $($v.Name) egress IP = $seen" -ForegroundColor Green }
    else                       { Write-Host "FAIL: $($v.Name) egress IP = $seen (expected $ExpectedIp)" -ForegroundColor Red }
}

Write-Host ""
Write-Host "Connect: Portal > VM > Connect > Bastion, user pandoraadmin, upload $SshKey"
Write-Host "Next: record costs in your running log, then run teardown-pandora.ps1 when finished."