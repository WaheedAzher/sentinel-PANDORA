terraform {
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# Subscription comes from the environment:
#   $env:ARM_SUBSCRIPTION_ID = (az account show --query id -o tsv)
provider "azurerm" {
  features {}
}
