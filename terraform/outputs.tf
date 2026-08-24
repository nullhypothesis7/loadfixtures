output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "key_vault_name" {
  description = "Name of the Key Vault"
  value       = azurerm_key_vault.main.name
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = azurerm_key_vault.main.vault_uri
}

output "acr_login_server" {
  description = "ACR login server hostname (for docker push / helm)"
  value       = azurerm_container_registry.main.login_server
}

output "acr_name" {
  description = "ACR resource name"
  value       = azurerm_container_registry.main.name
}

output "aks_cluster_name" {
  description = "AKS cluster name"
  value       = azurerm_kubernetes_cluster.main.name
}

output "aks_get_credentials" {
  description = "Command to configure kubectl"
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_kubernetes_cluster.main.name}"
}

output "postgres_fqdn" {
  description = "PostgreSQL flexible server FQDN (private)"
  value       = azurerm_postgresql_flexible_server.pgbank.fqdn
}

output "postgres_connection_string_secret" {
  description = "Key Vault secret name holding the pgbank connection string"
  value       = azurerm_key_vault_secret.pg_connection_string.name
}

output "workload_identity_client_id" {
  description = "Client ID of the app workload managed identity (used in pod annotations)"
  value       = azurerm_user_assigned_identity.app.client_id
}

output "workload_identity_object_id" {
  description = "Object ID of the app workload managed identity"
  value       = azurerm_user_assigned_identity.app.principal_id
}

output "app_namespace" {
  description = "Kubernetes namespace for the testfixtures app"
  value       = var.app_namespace
}

output "app_service_account" {
  description = "Kubernetes service account name to reference in pod specs"
  value       = var.app_service_account_name
}
