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