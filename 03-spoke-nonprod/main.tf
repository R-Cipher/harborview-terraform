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
    key                  = "spoke-nonprod.tfstate"
    use_azuread_auth     = true
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

resource "azurerm_resource_group" "nonprod_spoke" {
  name     = "rg-harborview-nonprod-east"
  location = var.location
}

resource "azurerm_virtual_network" "nonprod_vnet" {
  name                = "vnet-harborview-nonprod-east"
  location            = var.location
  resource_group_name = azurerm_resource_group.nonprod_spoke.name
  address_space       = ["10.2.0.0/16"]
}

resource "azurerm_subnet" "nonprod_web_subnet" {
  name                            = "snet-web"
  resource_group_name             = azurerm_resource_group.nonprod_spoke.name
  virtual_network_name            = azurerm_virtual_network.nonprod_vnet.name
  address_prefixes                = ["10.2.1.0/24"]
  default_outbound_access_enabled = false
}

resource "azurerm_subnet" "nonprod_app_subnet" {
  name                            = "snet-app"
  resource_group_name             = azurerm_resource_group.nonprod_spoke.name
  virtual_network_name            = azurerm_virtual_network.nonprod_vnet.name
  address_prefixes                = ["10.2.2.0/24"]
  default_outbound_access_enabled = false
}

resource "azurerm_subnet" "nonprod_data_subnet" {
  name                            = "snet-data"
  resource_group_name             = azurerm_resource_group.nonprod_spoke.name
  virtual_network_name            = azurerm_virtual_network.nonprod_vnet.name
  address_prefixes                = ["10.2.3.0/24"]
  default_outbound_access_enabled = false
}

data "azurerm_virtual_network" "hub_vnet" {
  name                = "vnet-harborview-hub-eus"
  resource_group_name = "rg-harborview-hub-eus"
}

output "virtual_network_name" {
  value = data.azurerm_virtual_network.hub_vnet.id
}

resource "azurerm_virtual_network_peering" "nonprod_to_hub" {
  name                         = "peer-nonprod-to-hub"
  resource_group_name          = azurerm_resource_group.nonprod_spoke.name
  virtual_network_name         = azurerm_virtual_network.nonprod_vnet.name
  remote_virtual_network_id    = data.azurerm_virtual_network.hub_vnet.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

resource "azurerm_virtual_network_peering" "hub_to_nonprod" {
  name                         = "peer-hub-to-nonprod"
  resource_group_name          = data.azurerm_virtual_network.hub_vnet.resource_group_name
  virtual_network_name         = data.azurerm_virtual_network.hub_vnet.name
  remote_virtual_network_id    = azurerm_virtual_network.nonprod_vnet.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

data "azurerm_firewall" "hub_fw" {
  name                = "afw-harborview-hub-eus"
  resource_group_name = "rg-harborview-hub-eus"
}

resource "azurerm_route_table" "udr" {
  name                = "harborview-route-table-nonprod"
  location            = var.location
  resource_group_name = azurerm_resource_group.nonprod_spoke.name

  route {
    name                   = "udr-route-to-firewall"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = data.azurerm_firewall.hub_fw.ip_configuration[0].private_ip_address
  }
}

resource "azurerm_subnet_route_table_association" "web_udr" {
  subnet_id      = azurerm_subnet.nonprod_web_subnet.id
  route_table_id = azurerm_route_table.udr.id
}

resource "azurerm_subnet_route_table_association" "app_udr" {
  subnet_id      = azurerm_subnet.nonprod_app_subnet.id
  route_table_id = azurerm_route_table.udr.id
}

resource "azurerm_subnet_route_table_association" "data_udr" {
  subnet_id      = azurerm_subnet.nonprod_data_subnet.id
  route_table_id = azurerm_route_table.udr.id
}

resource "azurerm_network_security_group" "nonprod_web_nsg" {
  name                = "web-nonprodsubnet-nsg-eus"
  location            = var.location
  resource_group_name = azurerm_resource_group.nonprod_spoke.name
}

resource "azurerm_subnet_network_security_group_association" "nonprod_web_association" {
  subnet_id                 = azurerm_subnet.nonprod_web_subnet.id
  network_security_group_id = azurerm_network_security_group.nonprod_web_nsg.id
}

resource "azurerm_network_security_rule" "allow_nonprod_web_inbound" {
  name                        = "allow-nonprod-https-inbound"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = "Internet"
  destination_address_prefix  = "10.2.1.0/24"
  resource_group_name         = azurerm_resource_group.nonprod_spoke.name
  network_security_group_name = azurerm_network_security_group.nonprod_web_nsg.name
}

resource "azurerm_network_security_rule" "denyall_nonprod_web_inbound" {
  name                        = "deny-all-nonprod-inbound"
  priority                    = 4096
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "10.2.1.0/24"
  resource_group_name         = azurerm_resource_group.nonprod_spoke.name
  network_security_group_name = azurerm_network_security_group.nonprod_web_nsg.name
}

resource "azurerm_network_security_rule" "allow_nonprod_web_outbound" {
  name                        = "allow-nonprod-outbound"
  priority                    = 110
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = "10.2.1.0/24"
  destination_address_prefix  = "10.2.2.0/24"
  resource_group_name         = azurerm_resource_group.nonprod_spoke.name
  network_security_group_name = azurerm_network_security_group.nonprod_web_nsg.name
}

resource "azurerm_network_security_rule" "denyall_nonprod_web_outbound" {
  name                        = "deny-all-nonprod-outbound"
  priority                    = 4096
  direction                   = "Outbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.nonprod_spoke.name
  network_security_group_name = azurerm_network_security_group.nonprod_web_nsg.name
}

resource "azurerm_network_security_group" "nonprod_app_nsg" {
  name                = "app-nonprodsubnet-nsg-eus"
  location            = var.location
  resource_group_name = azurerm_resource_group.nonprod_spoke.name
}

resource "azurerm_subnet_network_security_group_association" "nonprod_app_association" {
  subnet_id                 = azurerm_subnet.nonprod_app_subnet.id
  network_security_group_id = azurerm_network_security_group.nonprod_app_nsg.id
}

resource "azurerm_network_security_rule" "allow_nonprod_app_inbound" {
  name                        = "allow-https-nonprod-app-inbound"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = "10.2.1.0/24"
  destination_address_prefix  = "10.2.2.0/24"
  resource_group_name         = azurerm_resource_group.nonprod_spoke.name
  network_security_group_name = azurerm_network_security_group.nonprod_app_nsg.name
}

resource "azurerm_network_security_rule" "allow_nonprod_app_outbound" {
  name                        = "allow-sql-nonprod-outbound"
  priority                    = 110
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "1433"
  source_address_prefix       = "10.2.2.0/24"
  destination_address_prefix  = "10.2.3.0/24"
  resource_group_name         = azurerm_resource_group.nonprod_spoke.name
  network_security_group_name = azurerm_network_security_group.nonprod_app_nsg.name
}

resource "azurerm_network_security_rule" "allow_nonprod_app_dns_outbound" {
  name                        = "allow-dns-nonprod-app-outbound"
  priority                    = 120
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "53"
  source_address_prefix       = "10.2.2.0/24"
  destination_address_prefix  = "10.0.1.4"
  resource_group_name         = azurerm_resource_group.nonprod_spoke.name
  network_security_group_name = azurerm_network_security_group.nonprod_app_nsg.name
}

resource "azurerm_network_security_rule" "allow_nonprod_app_monitor_outbound" {
  name                        = "allow-monitor-nonprod-app-outbound"
  priority                    = 130
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = "10.2.2.0/24"
  destination_address_prefix  = "AzureMonitor"
  resource_group_name         = azurerm_resource_group.nonprod_spoke.name
  network_security_group_name = azurerm_network_security_group.nonprod_app_nsg.name
}

resource "azurerm_network_security_rule" "denyall_nonprod_app_outbound" {
  name                        = "denyall-nonprod-app-outbound"
  priority                    = 4096
  direction                   = "Outbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.nonprod_spoke.name
  network_security_group_name = azurerm_network_security_group.nonprod_app_nsg.name
}

resource "azurerm_network_security_rule" "denyall_nonprod_app_inbound" {
  name                        = "denyall-nonprod-app-inbound"
  priority                    = 4096
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.nonprod_spoke.name
  network_security_group_name = azurerm_network_security_group.nonprod_app_nsg.name
}


resource "azurerm_network_security_group" "nonprod_data_nsg" {
  name                = "data-nonprodsubnet-nsg-eus"
  location            = var.location
  resource_group_name = azurerm_resource_group.nonprod_spoke.name
}

resource "azurerm_subnet_network_security_group_association" "nonprod_data_association" {
  subnet_id                 = azurerm_subnet.nonprod_data_subnet.id
  network_security_group_id = azurerm_network_security_group.nonprod_data_nsg.id
}

resource "azurerm_network_security_rule" "allow_nonprod_data_inbound" {
  name                        = "allow-sql-nonprod-data-inbound"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "1433"
  source_address_prefix       = "10.2.2.0/24"
  destination_address_prefix  = "10.2.3.0/24"
  resource_group_name         = azurerm_resource_group.nonprod_spoke.name
  network_security_group_name = azurerm_network_security_group.nonprod_data_nsg.name
}

resource "azurerm_network_security_rule" "denyall_nonprod_data_inbound" {
  name                        = "denyall-nonprod-data-inbound"
  priority                    = 4096
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.nonprod_spoke.name
  network_security_group_name = azurerm_network_security_group.nonprod_data_nsg.name
}

resource "azurerm_network_security_rule" "denyall_nonprod_data_outbound" {
  name                        = "denyall-nonprod-data-outbound"
  priority                    = 4096
  direction                   = "Outbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.nonprod_spoke.name
  network_security_group_name = azurerm_network_security_group.nonprod_data_nsg.name
}