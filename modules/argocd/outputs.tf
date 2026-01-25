output "argocd_namespace" {
  description = "ArgoCD namespace"
  value       = kubernetes_namespace.argocd.metadata[0].name
}

output "argocd_server_service_name" {
  description = "ArgoCD server service name"
  value       = "argocd-server"
}

output "argocd_server_url" {
  description = "ArgoCD server URL"
  value       = var.enable_ingress ? "https://${var.argocd_domain}" : "http://argocd-server.argocd.svc.cluster.local"
}

output "argocd_iam_role_arn" {
  description = "IAM role ARN for ArgoCD"
  value       = aws_iam_role.argocd.arn
}

output "argocd_admin_password" {
  description = "ArgoCD admin password"
  value       = var.admin_password
  sensitive   = true
}

# Multi-Cluster Management Outputs
output "multi_cluster_enabled" {
  description = "Whether multi-cluster management is enabled"
  value       = var.enable_multi_cluster
}

output "managed_clusters" {
  description = "List of managed cluster names"
  value       = var.enable_multi_cluster ? [for cluster in var.managed_clusters : cluster.name] : []
}

output "appproject_name" {
  description = "ArgoCD AppProject name for multi-cluster deployments"
  value       = var.enable_multi_cluster ? var.project_name : null
}

output "cluster_registration_guide" {
  description = "Guide for registering additional clusters"
  value       = var.enable_multi_cluster ? "To register clusters, add them to managed_clusters variable. Get cluster info: aws eks describe-cluster --name CLUSTER_NAME --query 'cluster.{endpoint,ca:certificateAuthority.data}'" : null
}