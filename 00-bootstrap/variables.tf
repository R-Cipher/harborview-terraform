variable "subscription_id" {
  type = string
}

variable "location" {
  type    = string
  default = "eastus"
}

variable "storage_account_name" {
  type        = string
  description = "Globally unique, 3-24 chars, lowercase letters and numbers only"
}

variable "my_public_ip" {
  type        = string
  description = "Public IPv4 address allowed to reach the state storage account"
}