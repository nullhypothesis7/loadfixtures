variable "subscription_id" {
  description = "Azure subscription ID to deploy resources into"
  type        = string
}

variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "eastus"
}

variable "environment" {
  description = "Environment name (used in resource naming)"
  type        = string
  default     = "dev"
}

variable "project" {
  description = "Project name (used in resource naming)"
  type        = string
  default     = "testfixtures"
}

# ── PostgreSQL ────────────────────────────────────────────────────────────────

variable "pg_admin_username" {
  description = "PostgreSQL flexible server administrator login"
  type        = string
  default     = "pgadmin"
}

variable "pg_admin_password" {
  description = "PostgreSQL flexible server administrator password"
  type        = string
  sensitive   = true
}

# ── AKS ───────────────────────────────────────────────────────────────────────

variable "aks_node_count" {
  description = "Initial node count for the default AKS node pool"
  type        = number
  default     = 2
}

variable "aks_vm_size" {
  description = "VM SKU for AKS nodes"
  type        = string
  default     = "Standard_B2s"
}

# ── Workload Identity ─────────────────────────────────────────────────────────

variable "app_namespace" {
  description = "Kubernetes namespace for the testfixtures application"
  type        = string
  default     = "testfixtures"
}

variable "app_service_account_name" {
  description = "Kubernetes service account name that will be federated to the workload managed identity"
  type        = string
  default     = "testfixtures-sa"
}

# ── Key Vault ─────────────────────────────────────────────────────────────────

variable "key_vault_sku" {
  description = "Key Vault pricing tier"
  type        = string
  default     = "standard"
}

# ── Secrets passed in at apply time ──────────────────────────────────────────
# These are written into Key Vault so nothing is committed to state in plaintext
# beyond what Terraform's state already stores. Use a remote backend with
# encryption (e.g. azurerm backend with storage account CMK) in production.

variable "redis_password" {
  description = "Redis AUTH password"
  type        = string
  sensitive   = true
  default     = ""
}

variable "kafka_username" {
  description = "Kafka SASL username"
  type        = string
  sensitive   = true
  default     = ""
}

variable "kafka_password" {
  description = "Kafka SASL password"
  type        = string
  sensitive   = true
  default     = ""
}
