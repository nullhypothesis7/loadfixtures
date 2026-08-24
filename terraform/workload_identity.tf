# ── User-assigned managed identity for the app workload ──────────────────────
# Separate from the AKS system-assigned identity so its permissions are scoped
# to only what the application needs (Key Vault read).

resource "azurerm_user_assigned_identity" "app" {
  name                = "id-${local.prefix}-app-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = local.tags
}

# ── Key Vault access ──────────────────────────────────────────────────────────
# Secrets User = read secret values only; cannot create, update, or delete.

resource "azurerm_role_assignment" "app_kv_secrets_user" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.app.principal_id
}

# ── Federated identity credential ─────────────────────────────────────────────
# Links a specific Kubernetes service account (namespace + name) to this
# managed identity via the AKS OIDC issuer. When a pod presents the KSA token,
# Azure AD validates it against the issuer and returns an access token for the
# managed identity — no secrets leave the cluster.

resource "azurerm_federated_identity_credential" "app" {
  name                = "fedcred-${local.prefix}-app"
  resource_group_name = azurerm_resource_group.main.name
  parent_id           = azurerm_user_assigned_identity.app.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.main.oidc_issuer_url
  subject             = "system:serviceaccount:${var.app_namespace}:${var.app_service_account_name}"
}

