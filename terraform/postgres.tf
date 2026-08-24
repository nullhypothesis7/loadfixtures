# ── Azure Database for PostgreSQL Flexible Server ─────────────────────────────
# Burstable B1ms = cheapest flexible server SKU; fine for dev load testing.

resource "azurerm_postgresql_flexible_server" "pgbank" {
  name                          = "psql-${local.prefix}-${random_string.suffix.result}"
  resource_group_name           = azurerm_resource_group.main.name
  location                      = azurerm_resource_group.main.location
  version                       = "16"
  administrator_login           = var.pg_admin_username
  administrator_password        = var.pg_admin_password
  zone                          = "1"
  public_network_access_enabled = false

  # Private VNet injection
  delegated_subnet_id = azurerm_subnet.postgres.id
  private_dns_zone_id = azurerm_private_dns_zone.postgres.id

  sku_name   = "B_Standard_B1ms" # 1 vCore, 2 GiB RAM — smallest burstable
  storage_mb = 32768              # 32 GB minimum

  backup_retention_days        = 7
  geo_redundant_backup_enabled = false

  tags = local.tags

  depends_on = [azurerm_private_dns_zone_virtual_network_link.postgres]
}

# ── Databases ─────────────────────────────────────────────────────────────────
# All six on the same B1ms instance — fine for dev load.

resource "azurerm_postgresql_flexible_server_database" "pgbank" {
  name      = "pgbank"
  server_id = azurerm_postgresql_flexible_server.pgbank.id
  collation = "en_US.utf8"
  charset   = "utf8"
}

resource "azurerm_postgresql_flexible_server_database" "testdb" {
  name      = "testdb"
  server_id = azurerm_postgresql_flexible_server.pgbank.id
  collation = "en_US.utf8"
  charset   = "utf8"
}

resource "azurerm_postgresql_flexible_server_database" "bankingdb" {
  name      = "bankingdb"
  server_id = azurerm_postgresql_flexible_server.pgbank.id
  collation = "en_US.utf8"
  charset   = "utf8"
}

resource "azurerm_postgresql_flexible_server_database" "healthcaredb" {
  name      = "healthcaredb"
  server_id = azurerm_postgresql_flexible_server.pgbank.id
  collation = "en_US.utf8"
  charset   = "utf8"
}

resource "azurerm_postgresql_flexible_server_database" "salesforcedb" {
  name      = "salesforcedb"
  server_id = azurerm_postgresql_flexible_server.pgbank.id
  collation = "en_US.utf8"
  charset   = "utf8"
}

resource "azurerm_postgresql_flexible_server_database" "salesforceenterprisedb" {
  name      = "salesforceenterprisedb"
  server_id = azurerm_postgresql_flexible_server.pgbank.id
  collation = "en_US.utf8"
  charset   = "utf8"
}

# ── Key Vault secrets — connection strings for all six databases ───────────────

locals {
  pg_base = "postgresql://${var.pg_admin_username}:${var.pg_admin_password}@${azurerm_postgresql_flexible_server.pgbank.fqdn}:5432"
}

resource "azurerm_key_vault_secret" "pg_connection_string" {
  name         = "pg-connection-string"
  value        = "${local.pg_base}/pgbank?sslmode=require"
  key_vault_id = azurerm_key_vault.main.id
  depends_on   = [azurerm_role_assignment.kv_tf_admin]
}

resource "azurerm_key_vault_secret" "pg_connection_string_testdb" {
  name         = "pg-connection-string-testdb"
  value        = "${local.pg_base}/testdb?sslmode=require"
  key_vault_id = azurerm_key_vault.main.id
  depends_on   = [azurerm_role_assignment.kv_tf_admin]
}

resource "azurerm_key_vault_secret" "pg_connection_string_bankingdb" {
  name         = "pg-connection-string-bankingdb"
  value        = "${local.pg_base}/bankingdb?sslmode=require"
  key_vault_id = azurerm_key_vault.main.id
  depends_on   = [azurerm_role_assignment.kv_tf_admin]
}

resource "azurerm_key_vault_secret" "pg_connection_string_healthcaredb" {
  name         = "pg-connection-string-healthcaredb"
  value        = "${local.pg_base}/healthcaredb?sslmode=require"
  key_vault_id = azurerm_key_vault.main.id
  depends_on   = [azurerm_role_assignment.kv_tf_admin]
}

resource "azurerm_key_vault_secret" "pg_connection_string_salesforcedb" {
  name         = "pg-connection-string-salesforcedb"
  value        = "${local.pg_base}/salesforcedb?sslmode=require"
  key_vault_id = azurerm_key_vault.main.id
  depends_on   = [azurerm_role_assignment.kv_tf_admin]
}

resource "azurerm_key_vault_secret" "pg_connection_string_salesforceenterprisedb" {
  name         = "pg-connection-string-salesforceenterprisedb"
  value        = "${local.pg_base}/salesforceenterprisedb?sslmode=require"
  key_vault_id = azurerm_key_vault.main.id
  depends_on   = [azurerm_role_assignment.kv_tf_admin]
}
