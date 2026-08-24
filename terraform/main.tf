locals {
  prefix = "${var.project}-${var.environment}"
  tags = {
    project     = var.project
    environment = var.environment
    managed_by  = "terraform"
  }
}

# ── Random suffix (keeps names globally unique across destroy/re-create) ──────

resource "random_string" "suffix" {
  length  = 5
  upper   = false
  special = false
}

# ── Resource Group ────────────────────────────────────────────────────────────

resource "azurerm_resource_group" "main" {
  name     = "rg-${local.prefix}-${random_string.suffix.result}"
  location = var.location
  tags     = local.tags
}

# ── Key Vault ─────────────────────────────────────────────────────────────────
# Name max 24 chars; must be globally unique.

resource "azurerm_key_vault" "main" {
  name                        = "kv-${substr(var.project, 0, 8)}-${var.environment}-${random_string.suffix.result}"
  location                    = azurerm_resource_group.main.location
  resource_group_name         = azurerm_resource_group.main.name
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  sku_name                    = var.key_vault_sku
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false # must be false so terraform destroy can purge
  enable_rbac_authorization   = true

  tags = local.tags
}

# Grant the Terraform caller full secrets management on the vault
resource "azurerm_role_assignment" "kv_tf_admin" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# ── Key Vault Secrets ─────────────────────────────────────────────────────────

resource "azurerm_key_vault_secret" "pg_admin_password" {
  name         = "pg-admin-password"
  value        = var.pg_admin_password
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_role_assignment.kv_tf_admin]
}

resource "azurerm_key_vault_secret" "redis_password" {
  count        = var.redis_password != "" ? 1 : 0
  name         = "redis-password"
  value        = var.redis_password
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_role_assignment.kv_tf_admin]
}

resource "azurerm_key_vault_secret" "kafka_username" {
  count        = var.kafka_username != "" ? 1 : 0
  name         = "kafka-username"
  value        = var.kafka_username
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_role_assignment.kv_tf_admin]
}

resource "azurerm_key_vault_secret" "kafka_password" {
  count        = var.kafka_password != "" ? 1 : 0
  name         = "kafka-password"
  value        = var.kafka_password
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_role_assignment.kv_tf_admin]
}

# ── NetworkWatcherRG cleanup ──────────────────────────────────────────────────
# Azure auto-creates NetworkWatcherRG when AKS provisions VNets. Terraform
# does not manage it, so terraform destroy leaves it behind. This resource
# deletes it during destroy via a local-exec provisioner.
# triggers_replace ties the lifecycle to the AKS cluster so it re-registers
# on every apply and the destroy provisioner runs on every destroy.

resource "terraform_data" "cleanup_network_watcher_rg" {
  triggers_replace = [azurerm_kubernetes_cluster.main.id]

  provisioner "local-exec" {
    when    = destroy
    command = "az group delete --name NetworkWatcherRG --yes 2>/dev/null || true"
  }
}
