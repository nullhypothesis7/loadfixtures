# ── AKS Cluster ───────────────────────────────────────────────────────────────
# Single-node, Standard_B2s — enough for dev workload, minimal cost.
# Workload identity + Key Vault CSI driver let pods consume vault secrets
# without any credential files or environment variable secrets in manifests.

resource "azurerm_kubernetes_cluster" "main" {
  name                = "aks-${local.prefix}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = "${local.prefix}-${random_string.suffix.result}"
  kubernetes_version  = null # let Azure pick the latest stable patch

  # System-assigned identity for the control plane
  identity {
    type = "SystemAssigned"
  }

  default_node_pool {
    name           = "system"
    node_count     = var.aks_node_count
    vm_size        = var.aks_vm_size
    vnet_subnet_id = azurerm_subnet.aks.id
    os_disk_size_gb = 30
    os_disk_type    = "Managed"

    upgrade_settings {
      max_surge = "1"
    }
  }

  network_profile {
    network_plugin    = "kubenet"
    load_balancer_sku = "standard"
    pod_cidr          = "10.244.0.0/16"
    service_cidr      = "10.10.0.0/16"
    dns_service_ip    = "10.10.0.10"
  }

  # Workload identity enables pods to authenticate to Azure services via
  # federated credentials — no secrets stored in the cluster.
  workload_identity_enabled = true
  oidc_issuer_enabled       = true

  # Key Vault Secrets Store CSI Driver — pods can mount vault secrets as files
  key_vault_secrets_provider {
    secret_rotation_enabled = false # keep it simple for dev
  }

  tags = local.tags
}

# ── Grant AKS control-plane identity permission to join the VNet subnet ───────

resource "azurerm_role_assignment" "aks_network_contributor" {
  scope                = azurerm_virtual_network.main.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_kubernetes_cluster.main.identity[0].principal_id
}
