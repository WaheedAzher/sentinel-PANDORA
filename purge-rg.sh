#!/usr/bin/env bash
set -e
RESOURCE_GROUPS=(
    "RG-PANDORA-HUB-PROD-01"
    "RG-PANDORA-SPOKE-MANAGEMENT-01"
    "RG-PANDORA-SPOKE-SECURITY-01"
    "RG-PANDORA-SPOKE-DEVELOPER-01"
    "NetworkWatcherRG"
    "RG-PANDORA-HUB-01"
    "RG-PANDORA-SPK-MGMT-01"
    "RG-PANDORA-SPK-SEC-01"
    "RG-PANDORA-SPK-DEV-01"
)

# Confirm before deleting
echo "WARNING: This will delete the listed Resource Groups and their resources."
read -r -p "Type DELETE to continue: " CONFIRM

if [[ "$CONFIRM" != "DELETE" ]]; then
  echo "Deletion cancelled."
  exit 0
fi

# Delete Resource Groups
for RG_NAME in "${RESOURCE_GROUPS[@]}"; do
  echo "Deleting Resource Group: $RG_NAME"

  az group delete \
    --name "$RG_NAME" \
    --yes \
    --no-wait

  echo "Deletion requested for: $RG_NAME"
done

echo "Deletion requests submitted."

