terraform {
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  backend "azurerm" {
    resource_group_name  = "rg-harborview-tfstate"
    storage_account_name = "sthvtfstaterf307"
    container_name       = "tfstate"
    key                  = "monitoring.tfstate"
    use_azuread_auth     = true
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

resource "azurerm_resource_group" "monitoring" {
  name     = "rg-harborview-monitoring-eus"
  location = var.location
}

resource "azurerm_log_analytics_workspace" "hub_logs" {
  name                = "log-harborview-eus"
  location            = var.location
  resource_group_name = azurerm_resource_group.monitoring.name
  sku                 = "PerGB2018"
  retention_in_days   = 365
  daily_quota_gb      = 1
  tags = {
    managed_by  = "terraform-pipeline"
    environment = "lab"
  }
}
