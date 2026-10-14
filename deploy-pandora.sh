
#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# PANDORA HUB-AND-SPOKE LAB
# Region: Central India
# Run from Bash: WSL, Git Bash, or Azure Cloud Shell
#
# Phase 1: Resource groups, networking, security and monitoring
# Phase 2: Optional private Linux VMs
#
# WARNING: Azure Firewall Standard and Bastion Standard incur
# ongoing charges. Review pricing before deploying.
# ============================================================

LOCATION="centralindia"

RG_HUB="RG-PANDORA-HUB-01"
RG_MGMT="RG-PANDORA-SPK-MGMT-01"
RG_SEC="RG-PANDORA-SPK-SEC-01"
RG_DEV="RG-PANDORA-SPK-DEV-01"

VNET_HUB="vnet-pandora-hub-01"
VNET_MGMT="vnet-pandora-spk-mgmt-01"
VNET_SEC="vnet-pandora-spk-sec-01"
VNET_DEV="vnet-pandora-spk-dev-01"

FW_NAME="fw-pandora-hub-prod-01"
FW_POLICY="fw-policy-prod"
BASTION_NAME="bas-pandora-hub-01"
LAW_NAME="law-hub-security-prod-01"

NSG_NAME="nsg-spoke-workload"
RT_NAME="rt-spoke-to-hub"

SSH_KEY="$HOME/.ssh/pandora_id_ed25519"

# Stop if Azure CLI is missing or not logged in.
command -v az >/dev/null 2>&1 || {
    echo "ERROR: Install Azure CLI before running this script."
    exit 1
}

az account show >/dev/null 2>&1 || {
    echo "ERROR: Run az login first."
    exit 1
}

echo "Selected Azure subscription:"
az account show --query '{name:name,id:id}' --output table

read -r -p "Continue using this subscription? Type YES: " CONFIRM
[[ "$CONFIRM" == "YES" ]] || exit 1

# Preserve an existing SSH key; never overwrite it.
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

if [[ ! -f "$SSH_KEY" || ! -f "$SSH_KEY.pub" ]]; then
    echo "Generating an SSH key pair. Set a passphrase when prompted."
    ssh-keygen -t ed25519 -f "$SSH_KEY" -C "pandora-lab"
fi

# ============================================================
# PHASE 1 — RESOURCE GROUPS
# ============================================================

for RG in "$RG_HUB" "$RG_MGMT" "$RG_SEC" "$RG_DEV"; do
    az group create \
        --name "$RG" \
        --location "$LOCATION" \
        --output none
done

# Required resource providers.
az provider register --namespace Microsoft.Network
az provider register --namespace Microsoft.OperationalInsights
az provider register --namespace Microsoft.Insights
az provider register --namespace Microsoft.Storage

# ============================================================
# PHASE 2 — LOG ANALYTICS
# ============================================================

az monitor log-analytics workspace create \
    --resource-group "$RG_HUB" \
    --workspace-name "$LAW_NAME" \
    --location "$LOCATION" \
    --retention-time 30 \
    --output none

LAW_ID=$(az monitor log-analytics workspace show \
    --resource-group "$RG_HUB" \
    --workspace-name "$LAW_NAME" \
    --query id -o tsv)

# ============================================================
# PHASE 3 — VIRTUAL NETWORKS AND SUBNETS
# ============================================================

# Create VNets without default subnets. All subnet ranges are
# explicitly defined below.

az network vnet create \
    -g "$RG_HUB" -n "$VNET_HUB" \
    -l "$LOCATION" \
    --address-prefixes 10.10.0.0/20 \
    --output none

az network vnet create \
    -g "$RG_MGMT" -n "$VNET_MGMT" \
    -l "$LOCATION" \
    --address-prefixes 10.11.0.0/20 \
    --output none

az network vnet create \
    -g "$RG_SEC" -n "$VNET_SEC" \
    -l "$LOCATION" \
    --address-prefixes 10.12.0.0/20 \
    --output none

az network vnet create \
    -g "$RG_DEV" -n "$VNET_DEV" \
    -l "$LOCATION" \
    --address-prefixes 10.13.0.0/20 \
    --output none

# Hub subnets. Firewall and Bastion require their exact names.
az network vnet subnet create \
    -g "$RG_HUB" --vnet-name "$VNET_HUB" \
    -n AzureFirewallSubnet \
    --address-prefixes 10.10.0.0/26 \
    --output none

az network vnet subnet create \
    -g "$RG_HUB" --vnet-name "$VNET_HUB" \
    -n AzureFirewallManagementSubnet \
    --address-prefixes 10.10.0.64/26 \
    --output none

az network vnet subnet create \
    -g "$RG_HUB" --vnet-name "$VNET_HUB" \
    -n AzureBastionSubnet \
    --address-prefixes 10.10.0.128/26 \
    --output none

az network vnet subnet create \
    -g "$RG_HUB" --vnet-name "$VNET_HUB" \
    -n snet-management-01 \
    --address-prefixes 10.10.1.0/24 \
    --output none

# Spoke subnets.
for ENTRY in \
    "$RG_MGMT $VNET_MGMT 10.11" \
    "$RG_SEC $VNET_SEC 10.12" \
    "$RG_DEV $VNET_DEV 10.13"
do
    read -r RG VNET PREFIX <<< "$ENTRY"

    az network vnet subnet create \
        -g "$RG" --vnet-name "$VNET" \
        -n snet-workload-01 \
        --address-prefixes "${PREFIX}.0.0/24" \
        --output none

    az network vnet subnet create \
        -g "$RG" --vnet-name "$VNET" \
        -n snet-pe-01 \
        --address-prefixes "${PREFIX}.1.0/24" \
        --output none
done

# ============================================================
# PHASE 4 — HUB-AND-SPOKE PEERING
# ============================================================

HUB_ID=$(az network vnet show \
    -g "$RG_HUB" -n "$VNET_HUB" --query id -o tsv)

for ENTRY in \
    "$RG_MGMT $VNET_MGMT mgmt" \
    "$RG_SEC $VNET_SEC sec" \
    "$RG_DEV $VNET_DEV dev"
do
    read -r RG VNET SUFFIX <<< "$ENTRY"

    SPOKE_ID=$(az network vnet show \
        -g "$RG" -n "$VNET" --query id -o tsv)

    # Hub-side peering: allow forwarded traffic for NVA routing.
    az network vnet peering create \
        -g "$RG_HUB" --vnet-name "$VNET_HUB" \
        -n "peer-hub-to-$SUFFIX" \
        --remote-vnet "$SPOKE_ID" \
        --allow-vnet-access true \
        --allow-forwarded-traffic true \
        --allow-gateway-transit false \
        --output none

    # Spoke-side peering: allow forwarded traffic for the
    # firewall to forward traffic back to spoke workloads.
    az network vnet peering create \
        -g "$RG" --vnet-name "$VNET" \
        -n "peer-$SUFFIX-to-hub" \
        --remote-vnet "$HUB_ID" \
        --allow-vnet-access true \
        --allow-forwarded-traffic true \
        --use-remote-gateways false \
        --output none
done

# ============================================================
# PHASE 5 — NSG AND ROUTE TABLE
# ============================================================

az network nsg create \
    -g "$RG_HUB" -n "$NSG_NAME" \
    -l "$LOCATION" \
    --output none

# Allow SSH from Azure Bastion only.
az network nsg rule create \
    -g "$RG_HUB" --nsg-name "$NSG_NAME" \
    -n Allow-SSH-From-Bastion \
    --priority 100 \
    --direction Inbound --access Allow \
    --protocol Tcp \
    --source-address-prefixes 10.10.0.128/26 \
    --source-port-ranges '*' \
    --destination-address-prefixes '*' \
    --destination-port-ranges 22 \
    --output none

# Block direct inbound access from hub and spoke address ranges.
# The Bastion SSH allow rule above takes precedence.
az network nsg rule create \
    -g "$RG_HUB" --nsg-name "$NSG_NAME" \
    -n Deny-Direct-VNet-Inbound \
    --priority 200 \
    --direction Inbound --access Deny \
    --protocol '*' \
    --source-address-prefixes \
        10.10.0.0/16 10.11.0.0/16 \
        10.12.0.0/16 10.13.0.0/16 \
    --source-port-ranges '*' \
    --destination-address-prefixes '*' \
    --destination-port-ranges '*' \
    --output none

# Route table: disable BGP route propagation.
az network route-table create \
    -g "$RG_HUB" -n "$RT_NAME" \
    -l "$LOCATION" \
    --disable-bgp-route-propagation true \
    --output none

# Firewall IP is verified before the route is created.
# The firewall subnet starts at .0/26, so .4 is its first
# usable address. The deployment must verify the actual IP.

# ============================================================
# PHASE 6 — FIREWALL POLICY AND FIREWALL
# ============================================================

az network firewall policy create \
    -g "$RG_HUB" -n "$FW_POLICY" \
    -l "$LOCATION" \
    --sku Standard \
    --threat-intel-mode Alert \
    --enable-dns-proxy true \
    --output none

# Public IP for Azure Firewall.
az network public-ip create \
    -g "$RG_HUB" -n pip-pandora-firewall-01 \
    -l "$LOCATION" \
    --sku Standard \
    --allocation-method Static \
    --output none

# Create a Standard VNet firewall with one public IP.
az network firewall create \
    -g "$RG_HUB" -n "$FW_NAME" \
    -l "$LOCATION" \
    --vnet-name "$VNET_HUB" \
    --sku AZFW_VNet \
    --tier Standard \
    --public-ip-count 1 \
    --enable-dns-proxy true \
    --output none

# Attach the policy to the firewall.
POLICY_ID=$(az network firewall policy show \
    -g "$RG_HUB" -n "$FW_POLICY" \
    --query id -o tsv)

az network firewall update \
    -g "$RG_HUB" -n "$FW_NAME" \
    --firewall-policy "$POLICY_ID" \
    --enable-dns-proxy true \
    --output none

echo "Waiting for Azure Firewall provisioning..."
az network firewall wait \
    -g "$RG_HUB" -n "$FW_NAME" \
    --created --interval 30 --timeout 1800

FW_IP=$(az network firewall show \
    -g "$RG_HUB" -n "$FW_NAME" \
    --query "ipConfigurations[0].privateIPAddress" -o tsv)

if [[ "$FW_IP" != "10.10.0.4" ]]; then
    echo "ERROR: Expected firewall IP 10.10.0.4; actual IP is $FW_IP."
    echo "Stop here and configure the firewall IP before continuing."
    exit 1
fi

# ============================================================
# PHASE 7 — FIREWALL POLICY RULES
# ============================================================

# Azure Firewall Policy rule collection group is deployed using
# ARM through Azure CLI. This avoids using classic firewall rules
# that would not be the intended policy configuration.

TEMP_RULES=$(mktemp)
trap 'rm -f "$TEMP_RULES"' EXIT

cat > "$TEMP_RULES" <<'JSON'
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
  "contentVersion": "1.0.0.0",
  "resources": [
    {
      "type": "Microsoft.Network/firewallPolicies/ruleCollectionGroups",
      "apiVersion": "2023-09-01",
      "name": "fw-policy-prod/rcg-pandora-egress",
      "properties": {
        "priority": 100,
        "ruleCollections": [
          {
            "name": "Deny-Private-Networks",
            "ruleCollectionType": "FirewallPolicyFilterRuleCollection",
            "priority": 100,
            "action": { "type": "Deny" },
            "rules": [
              {
                "name": "Deny-Spoke-To-Private-Ranges",
                "ruleType": "NetworkRule",
                "ipProtocols": ["Any"],
                "sourceAddresses": [
                  "10.11.0.0/20",
                  "10.12.0.0/20",
                  "10.13.0.0/20"
                ],
                "destinationAddresses": [
                  "10.10.0.0/20",
                  "10.11.0.0/20",
                  "10.12.0.0/20",
                  "10.13.0.0/20"
                ],
                "destinationPorts": ["*"]
              }
            ]
          },
          {
            "name": "Allow-Spoke-Internet-Egress",
            "ruleCollectionType": "FirewallPolicyFilterRuleCollection",
            "priority": 200,
            "action": { "type": "Allow" },
            "rules": [
              {
                "name": "Allow-Outbound-Internet",
                "ruleType": "NetworkRule",
                "ipProtocols": ["Any"],
                "sourceAddresses": [
                  "10.11.0.0/20",
                  "10.12.0.0/20",
                  "10.13.0.0/20"
                ],
                "destinationAddresses": ["0.0.0.0/0"],
                "destinationPorts": ["*"]
              }
            ]
          }
        ]
      }
    }
  ]
}
JSON

az deployment group create \
    -g "$RG_HUB" \
    --name pandora-firewall-policy-rules \
    --template-file "$TEMP_RULES" \
    --output none

# ============================================================
# PHASE 8 — BASTION
# ============================================================

az network public-ip create \
    -g "$RG_HUB" -n pip-pandora-bastion-01 \
    -l "$LOCATION" \
    --sku Standard \
    --allocation-method Static \
    --output none

az network bastion create \
    -g "$RG_HUB" -n "$BASTION_NAME" \
    -l "$LOCATION" \
    --vnet-name "$VNET_HUB" \
    --public-ip-address pip-pandora-bastion-01 \
    --sku Standard \
    --output none

# ============================================================
# PHASE 9 — ROUTES, NSG ASSOCIATIONS AND DNS
# ============================================================

az network route-table route create \
    -g "$RG_HUB" --route-table-name "$RT_NAME" \
    -n default-to-firewall \
    --address-prefix 0.0.0.0/0 \
    --next-hop-type VirtualAppliance \
    --next-hop-ip-address "$FW_IP" \
    --output none

for ENTRY in \
    "$RG_MGMT $VNET_MGMT" \
    "$RG_SEC $VNET_SEC" \
    "$RG_DEV $VNET_DEV"
do
    read -r RG VNET <<< "$ENTRY"

    az network vnet subnet update \
        -g "$RG" --vnet-name "$VNET" \
        -n snet-workload-01 \
        --network-security-group "$NSG_NAME" \
        --route-table "$RT_NAME" \
        --output none

    # Spokes use the Azure Firewall DNS proxy.
    az network vnet update \
        -g "$RG" -n "$VNET" \
        --dns-servers "$FW_IP" \
        --output none
done

# ============================================================
# PHASE 10 — VIRTUAL NETWORK FLOW LOGS
# ============================================================

# NSG Flow Logs can no longer be newly created. Use VNet Flow Logs.
# The storage account name must be globally unique.

SUFFIX=$(date +%s)
STORAGE_NAME="stpandoraflow${SUFFIX}"

az storage account create \
    -g "$RG_HUB" -n "$STORAGE_NAME" \
    -l "$LOCATION" \
    --sku Standard_LRS \
    --kind StorageV2 \
    --min-tls-version TLS1_2 \
    --allow-blob-public-access false \
    --output none

STORAGE_ID=$(az storage account show \
    -g "$RG_HUB" -n "$STORAGE_NAME" \
    --query id -o tsv)

az network watcher configure \
    --locations "$LOCATION" \
    --enabled true \
    --resource-group "$RG_HUB" \
    --output none

for ENTRY in \
    "$RG_HUB $VNET_HUB hub" \
    "$RG_MGMT $VNET_MGMT mgmt" \
    "$RG_SEC $VNET_SEC sec" \
    "$RG_DEV $VNET_DEV dev"
do
    read -r RG VNET SUFFIX_NAME <<< "$ENTRY"

    VNET_ID=$(az network vnet show \
        -g "$RG" -n "$VNET" --query id -o tsv)

    az network watcher flow-log create \
        --location "$LOCATION" \
        --resource-group "$RG" \
        --name "fl-pandora-${SUFFIX_NAME}" \
        --vnet "$VNET_ID" \
        --storage-account "$STORAGE_ID" \
        --traffic-analytics true \
        --workspace "$LAW_ID" \
        --interval 10 \
        --output none
done

# ============================================================
# PHASE 11 — DIAGNOSTIC SETTINGS
# ============================================================

FW_ID=$(az network firewall show \
    -g "$RG_HUB" -n "$FW_NAME" --query id -o tsv)

BASTION_ID=$(az network bastion show \
    -g "$RG_HUB" -n "$BASTION_NAME" --query id -o tsv)

# Enable all supported Firewall log categories.
az monitor diagnostic-settings create \
    --name diag-pandora-firewall \
    --resource "$FW_ID" \
    --workspace "$LAW_ID" \
    --logs '[{"categoryGroup":"allLogs","enabled":true}]' \
    --output none

# Bastion audit logs.
az monitor diagnostic-settings create \
    --name diag-pandora-bastion \
    --resource "$BASTION_ID" \
    --workspace "$LAW_ID" \
    --logs '[{"category":"BastionAuditLogs","enabled":true}]' \
    --output none

echo "Network and monitoring deployment completed."
echo "Firewall private IP: $FW_IP"
echo "Log Analytics workspace: $LAW_NAME"
echo "Flow log storage account: $STORAGE_NAME"

# ============================================================
# PHASE 12 — OPTIONAL PRIVATE LINUX VMS
# ============================================================

read -r -p "Create the three Linux VMs now? [y/N]: " CREATE_VMS

if [[ "$CREATE_VMS" =~ ^[Yy]$ ]]; then

    az vm create \
        -g "$RG_MGMT" -n vm-pandora-mgmt-01 \
        -l "$LOCATION" \
        --image Canonical:ubuntu-24_04-lts:server:latest \
        --size Standard_B2ats_v2 \
        --admin-username pandoraadmin \
        --ssh-key-values "${SSH_KEY}.pub" \
        --public-ip-address "" \
        --nsg "" \
        --vnet-name "$VNET_MGMT" \
        --subnet snet-workload-01 \
        --private-ip-address 10.11.0.4 \
        --storage-sku Standard_LRS \
        --output none

    az vm create \
        -g "$RG_SEC" -n vm-pandora-sec-01 \
        -l "$LOCATION" \
        --image Canonical:ubuntu-24_04-lts:server:latest \
        --size Standard_B2ats_v2 \
        --admin-username pandoraadmin \
        --ssh-key-values "${SSH_KEY}.pub" \
        --public-ip-address "" \
        --nsg "" \
        --vnet-name "$VNET_SEC" \
        --subnet snet-workload-01 \
        --private-ip-address 10.12.0.4 \
        --storage-sku Standard_LRS \
        --output none

    az vm create \
        -g "$RG_DEV" -n vm-pandora-dev-01 \
        -l "$LOCATION" \
        --image Canonical:ubuntu-24_04-lts:server:latest \
        --size Standard_B2ats_v2 \
        --admin-username pandoraadmin \
        --ssh-key-values "${SSH_KEY}.pub" \
        --public-ip-address "" \
        --nsg "" \
        --vnet-name "$VNET_DEV" \
        --subnet snet-workload-01 \
        --private-ip-address 10.13.0.4 \
        --storage-sku Standard_LRS \
        --output none

    echo "VM creation completed."
    echo "Private key: $SSH_KEY"
    echo "Connect through Azure Bastion; do not share the private key."
fi

echo "Pandora deployment script finished."
