# ── Azure Container Registry ──────────────────────────────────────────────────
# Basic SKU is cheapest; no geo-replication or private endpoints needed for dev.

resource "azurerm_container_registry" "main" {
  name                = "acr${replace(local.prefix, "-", "")}${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Basic"
  admin_enabled       = false # AKS pulls via managed identity role assignment — no admin creds needed

  tags = local.tags
}

# Allow AKS kubelet identity to pull images from ACR
resource "azurerm_role_assignment" "aks_acr_pull" {
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id

  depends_on = [azurerm_kubernetes_cluster.main]
}
