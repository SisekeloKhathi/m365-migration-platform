# Complete Terraform Configuration for M365 Migration Platform
# All resources in one file - no modules needed

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
}

# Variables
variable "environment" {
  description = "Environment name (dev, staging, production)"
  type        = string
  default     = "dev"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "eastus"
}

variable "tenant_id" {
  description = "Azure AD Tenant ID"
  type        = string
  sensitive   = true
}

variable "subscription_id" {
  description = "Azure Subscription ID"
  type        = string
  sensitive   = true
}

variable "vnet_address_space" {
  description = "VNet address space"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "subnet_prefixes" {
  description = "Subnet address prefixes"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.27.3"
}

variable "node_count" {
  description = "Number of AKS nodes"
  type        = number
  default     = 2
}

variable "node_size" {
  description = "AKS node VM size"
  type        = string
  default     = "Standard_D4s_v3"
}

variable "sql_admin_username" {
  description = "SQL Server admin username"
  type        = string
  default     = "migrationadmin"
}

variable "sql_admin_password" {
  description = "SQL Server admin password"
  type        = string
  sensitive   = true
}

variable "log_retention_days" {
  description = "Log retention in days"
  type        = number
  default     = 30
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default = {
    Project     = "M365-Migration"
    ManagedBy   = "Terraform"
    Environment = "dev"
  }
}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = "rg-m365-migration-${var.environment}"
  location = var.location
  tags     = var.tags
}

# Random suffix for unique names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Virtual Network
resource "azurerm_virtual_network" "main" {
  name                = "vnet-m365-migration-${var.environment}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = var.vnet_address_space
  tags                = var.tags
}

# Subnet for AKS
resource "azurerm_subnet" "aks" {
  name                 = "aks-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.subnet_prefixes[0]]
}

# AKS Cluster
resource "azurerm_kubernetes_cluster" "main" {
  name                = "aks-m365-migration-${var.environment}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = "aksm365"
  kubernetes_version  = var.kubernetes_version
  
  default_node_pool {
    name       = "default"
    node_count = var.node_count
    vm_size    = var.node_size
    vnet_subnet_id = azurerm_subnet.aks.id
  }
  
  identity { type = "SystemAssigned" }
  
  network_profile {
    network_plugin = "azure"
    network_policy = "azure"
  }
  
  tags = var.tags
}

# Key Vault
resource "azurerm_key_vault" "main" {
  name                       = "kv-m365-${var.environment}${random_string.suffix.result}"
  location                   = var.location
  resource_group_name        = azurerm_resource_group.main.name
  tenant_id                  = var.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7
  
  tags = var.tags
}

# Storage Account
resource "azurerm_storage_account" "main" {
  name                     = "stm365${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
  
  tags = var.tags
}

# SQL Server
resource "azurerm_mssql_server" "main" {
  name                         = "sql-m365-${random_string.suffix.result}"
  resource_group_name          = azurerm_resource_group.main.name
  location                     = var.location
  version                      = "12.0"
  administrator_login          = var.sql_admin_username
  administrator_login_password = var.sql_admin_password
  
  tags = var.tags
}

resource "azurerm_mssql_database" "main" {
  name           = "migrationdb-${var.environment}"
  server_id      = azurerm_mssql_server.main.id
  collation      = "SQL_Latin1_General_CP1_CI_AS"
  license_type   = "LicenseIncluded"
  sku_name       = "S0"
  
  tags = var.tags
}

# Log Analytics
resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-m365-${var.environment}${random_string.suffix.result}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  
  tags = var.tags
}

# Application Insights
resource "azurerm_application_insights" "main" {
  name                = "appi-m365-${var.environment}${random_string.suffix.result}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
  
  tags = var.tags
}

# Outputs
output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "aks_cluster_name" {
  value = azurerm_kubernetes_cluster.main.name
}

output "aks_kubeconfig" {
  value     = azurerm_kubernetes_cluster.main.kube_config_raw
  sensitive = true
}

output "keyvault_uri" {
  value     = azurerm_key_vault.main.vault_uri
  sensitive = true
}

output "storage_account_name" {
  value = azurerm_storage_account.main.name
}

output "sql_server_name" {
  value = azurerm_mssql_server.main.name
}

output "log_analytics_workspace_id" {
  value = azurerm_log_analytics_workspace.main.id
}

output "application_insights_key" {
  value     = azurerm_application_insights.main.instrumentation_key
  sensitive = true
}
