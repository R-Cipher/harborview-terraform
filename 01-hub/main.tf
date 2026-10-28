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
    key                  = "hub.tfstate"
    use_azuread_auth     = true
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

resource "azurerm_resource_group" "hub" {
  name     = "rg-harborview-hub-eus"
  location = var.location
}

resource "azurerm_virtual_network" "hub" {
  name                = "vnet-harborview-hub-eus"
  location            = azurerm_resource_group.hub.location
  resource_group_name = azurerm_resource_group.hub.name
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "gateway" {
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.hub.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = ["10.0.0.0/27"]
}

resource "azurerm_subnet" "firewall" {
  name                 = "AzureFirewallSubnet"
  resource_group_name  = azurerm_resource_group.hub.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = ["10.0.1.0/26"]
}

resource "azurerm_subnet" "management" {
  name                            = "snet-management"
  resource_group_name             = azurerm_resource_group.hub.name
  virtual_network_name            = azurerm_virtual_network.hub.name
  address_prefixes                = ["10.0.2.0/24"]
  default_outbound_access_enabled = false
}

resource "azurerm_subnet" "shared_services" {
  name                            = "snet-shared-services"
  resource_group_name             = azurerm_resource_group.hub.name
  virtual_network_name            = azurerm_virtual_network.hub.name
  address_prefixes                = ["10.0.3.0/24"]
  default_outbound_access_enabled = false
}

resource "azurerm_public_ip" "firewall" {
  name                = "pip-harborview-hub-fw-eus"
  location            = azurerm_resource_group.hub.location
  resource_group_name = azurerm_resource_group.hub.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]
}

resource "azurerm_firewall_policy" "hub" {
  name                = "fwp-harborview-hub-eus"
  location            = azurerm_resource_group.hub.location
  resource_group_name = azurerm_resource_group.hub.name
  sku                 = "Standard"

  dns {
    proxy_enabled = true
  }
}

resource "azurerm_firewall" "hub" {
  name                = "afw-harborview-hub-eus"
  location            = azurerm_resource_group.hub.location
  resource_group_name = azurerm_resource_group.hub.name
  sku_name            = "AZFW_VNet"
  sku_tier            = "Standard"
  zones               = ["1", "2", "3"]
  firewall_policy_id  = azurerm_firewall_policy.hub.id

  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_subnet.firewall.id
    public_ip_address_id = azurerm_public_ip.firewall.id
  }
}

resource "azurerm_firewall_policy_rule_collection_group" "afw_rules" {
  name               = "rcg-harborview-hub"
  firewall_policy_id = azurerm_firewall_policy.hub.id
  priority           = 100

  network_rule_collection {
    name     = "nrc-deny-spoke-isolation"
    priority = 200
    action   = "Deny"

    rule {
      name                  = "deny-prod-to-nonprod"
      protocols             = ["Any"]
      source_addresses      = ["10.1.0.0/16"]
      destination_addresses = ["10.2.0.0/16"]
      destination_ports     = ["*"]
    }

    rule {
      name                  = "deny-nonprod-to-prod"
      protocols             = ["Any"]
      source_addresses      = ["10.2.0.0/16"]
      destination_addresses = ["10.1.0.0/16"]
      destination_ports     = ["*"]
    }
  }

  network_rule_collection {
    name     = "nrc-allow-dns"
    priority = 210
    action   = "Allow"

    rule {
      name                  = "allow-dns-from-spokes"
      protocols             = ["TCP", "UDP"]
      source_addresses      = ["10.1.0.0/16", "10.2.0.0/16"]
      destination_addresses = ["10.0.1.4"]
      destination_ports     = ["53"]
    }
  }

  network_rule_collection {
    name     = "nrc-allow-azmonitor"
    priority = 220
    action   = "Allow"

    rule {
      name                  = "allow-azmonitor-from-spokes"
      protocols             = ["TCP"]
      source_addresses      = ["10.1.0.0/16", "10.2.0.0/16"]
      destination_addresses = ["AzureMonitor"]
      destination_ports     = ["443"]
    }
  }

  application_rule_collection {
    name     = "arc-allow-web-egress"
    priority = 300
    action   = "Allow"

    rule {
      name = "allow-web-egress"
      protocols {
        type = "Https"
        port = 443
      }

      source_addresses      = ["10.1.0.0/16", "10.2.0.0/16"]
      destination_fqdn_tags = ["WindowsUpdate"]
      destination_fqdns     = ["login.microsoftonline.com", "management.azure.com", "packages.microsoft.com"]
    }
  }
}

data "azurerm_log_analytics_workspace" "afw_logs" {
  name                = "log-harborview-eus"
  resource_group_name = "rg-harborview-monitoring-eus"
}

resource "azurerm_monitor_diagnostic_setting" "afw_log_settings" {
  name                           = "afw-log-settings"
  target_resource_id             = azurerm_firewall.hub.id
  log_analytics_destination_type = "Dedicated"
  log_analytics_workspace_id     = data.azurerm_log_analytics_workspace.afw_logs.id

  enabled_log {
    category = "AZFWNetworkRule"
  }

  enabled_log {
    category = "AZFWApplicationRule"
  }

  enabled_log {
    category = "AZFWDnsQuery"
  }

  enabled_log {
    category = "AZFWThreatIntel"
  }
}