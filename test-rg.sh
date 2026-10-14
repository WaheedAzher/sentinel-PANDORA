
#!/usr/bin/env bash
set -e

# ------------------------------
# Configuration
# ------------------------------

LOCATION="centralindia"
PROJECT="Pandora"
METHOD="AZURE-CLI"
# ------------------------------
# Resource Groups
# ------------------------------

RESOURCE_GROUPS=(
  "RG-PANDORA-HUB-01"
  "RG-PANDORA-SPOKE-MGMT-01"
  "RG-PANDORA-SPOKE-WKLD-01"
  "RG-PANDORA-SPOKE-SEC-01"
)

# ------------------------------
# Deployment
# ------------------------------

for RG_NAME in "${RESOURCE_GROUPS[@]}"; do

  echo "Checking Resource Group: $RG_NAME"

  if az group show --name "$RG_NAME" --output none 2>/dev/null; then
    echo "Already exists. Skipping: $RG_NAME"
  else
    echo "Creating: $RG_NAME"

    az group create \
      --name "$RG_NAME" \
      --location "$LOCATION" \
      --tags Project="$PROJECT" Method="$METHOD"

    echo "Created: $RG_NAME"
  fi

done

echo "Resource Group deployment completed."
