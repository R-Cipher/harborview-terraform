variable "subscription_id" {
  description = "subscription id for Azure"
  type        = string
}

variable "location" {
  description = "location for resource deployments"
  type        = string
  default     = "eastus"
}