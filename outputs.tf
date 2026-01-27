# VPC Outputs
output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = module.vpc.vpc_cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = module.vpc.private_subnet_ids
}

# EKS Outputs
output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = module.eks.cluster_endpoint
}

output "cluster_version" {
  description = "The Kubernetes server version for the EKS cluster"
  value       = module.eks.cluster_version
}

output "cluster_oidc_issuer_url" {
  description = "The URL on the EKS cluster for the OpenID Connect identity provider"
  value       = module.eks.cluster_oidc_issuer_url
}

output "node_security_group_id" {
  description = "ID of the EKS node group security group"
  value       = module.eks.node_security_group_id
}

output "region" {
  description = "AWS region (for eks update-kubeconfig, scripts)"
  value       = var.region
}

output "aws_region" {
  description = "AWS region (alias for scripts, e.g. deploy_karpenter.sh)"
  value       = var.region
}

# Karpenter / EKS node outputs (for deploy_karpenter.sh)
output "karpenter_controller_role_arn" {
  description = "IAM role ARN for Karpenter controller (IRSA)"
  value       = module.eks.karpenter_role_arn
}

output "node_instance_role_arn" {
  description = "IAM role ARN of the EKS node group"
  value       = module.eks.node_role_arn
}

output "node_instance_profile_name" {
  description = "Instance profile name for EKS nodes (Karpenter defaultInstanceProfile)"
  value       = module.eks.node_instance_profile_name
}

# RDS Outputs
output "rds_endpoint" {
  description = "RDS instance endpoint"
  value       = module.rds.db_instance_endpoint
}

output "rds_port" {
  description = "RDS instance port"
  value       = module.rds.db_instance_port
}

output "rds_database_name" {
  description = "RDS database name"
  value       = module.rds.db_instance_name
}

output "rds_secrets_manager_secret_arn" {
  description = "ARN of the Secrets Manager secret for RDS credentials"
  value       = module.rds.secrets_manager_secret_arn
}

output "rds_multi_az_enabled" {
  description = "Whether RDS Multi-AZ is enabled"
  value       = module.rds.db_instance_multi_az
}

output "rds_read_replica_endpoints" {
  description = "List of RDS read replica endpoints"
  value       = module.rds.db_read_replica_endpoints
}

output "rds_read_replica_count" {
  description = "Number of RDS read replicas"
  value       = module.rds.db_read_replica_count
}

output "rds_cloudwatch_alarms" {
  description = "ARNs of RDS CloudWatch alarms"
  value       = module.rds.cloudwatch_alarm_arns
}

# RDS ARN for DR Workspace
output "rds_arn" {
  description = "ARN of the primary RDS instance (needed for DR workspace)"
  value       = module.rds.db_instance_arn
}

output "rds_cross_region_backups_enabled" {
  description = "Whether cross-region backup replication is enabled"
  value       = module.rds.cross_region_backups_enabled
}

output "rds_dr_kms_key_arn" {
  description = "ARN of the KMS key in DR region (created for cross-region backups or DR replica). Use this in DR workspace via data source."
  value       = module.rds.dr_kms_key_arn
}

output "rds_dr_kms_key_id" {
  description = "ID of the KMS key in DR region (created for cross-region backups or DR replica). Use this in DR workspace via data source."
  value       = module.rds.dr_kms_key_id
}

output "rds_dr_note" {
  description = "Note about RDS DR replica management"
  value       = "RDS DR replica is managed by the DR workspace (dr-infrastructure/). Use the primary RDS ARN to configure it."
}

# ArgoCD Outputs (conditional on cluster_exists)
output "argocd_namespace" {
  description = "ArgoCD namespace"
  value       = var.cluster_exists && var.enable_argocd ? "argocd" : null
}

output "argocd_server_url" {
  description = "ArgoCD server URL (use port-forward or ingress)"
  value       = var.cluster_exists && var.enable_argocd ? (var.argocd_enable_ingress ? "https://${var.argocd_domain}" : "http://localhost:8080 (via port-forward)") : null
}

output "argocd_admin_password_command" {
  description = "Command to get ArgoCD initial admin password"
  value       = var.cluster_exists && var.enable_argocd ? "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d" : null
}

# Monitoring Outputs (conditional on cluster_exists)
output "prometheus_url" {
  description = "Prometheus URL"
  value       = var.cluster_exists && var.enable_monitoring ? module.monitoring[0].prometheus_url : null
}

output "grafana_url" {
  description = "Grafana URL"
  value       = var.cluster_exists && var.enable_monitoring ? module.monitoring[0].grafana_url : null
}

output "grafana_admin_password" {
  description = "Grafana admin password"
  value       = var.cluster_exists && var.enable_monitoring ? module.monitoring[0].grafana_admin_password : null
  sensitive   = true
}

# Generated passwords
output "database_password" {
  description = "Generated database password"
  value       = local.db_password
  sensitive   = true
}

# Kubectl configuration command
output "kubectl_config_command" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

# ArgoCD CLI login command
output "argocd_login_command" {
  description = "Command to login to ArgoCD CLI"
  value       = "kubectl port-forward svc/argocd-server -n argocd 8080:443 & argocd login localhost:8080 --username admin --insecure"
}

# Quick start commands
output "quick_start_commands" {
  description = "Quick start commands after deployment"
  value = {
    "1_configure_kubectl"      = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
    "2_port_forward_argocd"    = "kubectl port-forward svc/argocd-server -n argocd 8080:443"
    "3_argocd_admin_password"  = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
    "4_port_forward_grafana"   = var.enable_monitoring ? "kubectl port-forward svc/prometheus-grafana -n monitoring 3000:80" : "Monitoring not enabled"
    "5_grafana_admin_password" = var.enable_monitoring ? "echo '${local.grafana_admin_password}'" : "Monitoring not enabled"
  }
  sensitive = true
}

# Cost optimization information
output "cost_optimization_notes" {
  description = "Cost optimization recommendations"
  value = {
    "eks_node_groups" = "Consider using Spot instances for non-production workloads"
    "rds"             = "Enable automated backups with appropriate retention periods"
    "monitoring"      = "Use CloudWatch Container Insights for cost-effective monitoring"
    "storage"         = "Use gp3 volumes for better price-performance ratio"
    "nat_gateway"     = "Consider using NAT instances for lower cost in development"
    "load_balancers"  = "Use Application Load Balancers efficiently with multiple services"
    "dr_cluster"      = var.environment == "prod" ? "DR cluster is in standby mode with minimal nodes for cost optimization" : "DR cluster disabled for non-production"
  }
}

# ECR Outputs
output "ecr_repository_urls" {
  description = "Map of ECR repository names to their URLs"
  value       = module.ecr.repository_urls
}

output "ecr_registry_url" {
  description = "ECR registry URL for Docker login"
  value       = module.ecr.registry_url
}

output "ecr_docker_login_command" {
  description = "Command to authenticate Docker with ECR"
  value       = module.ecr.docker_login_command
}

output "ecr_replication_enabled" {
  description = "Whether ECR cross-region replication is enabled"
  value       = module.ecr.replication_enabled
}

output "ecr_replication_regions" {
  description = "Regions where ECR images are replicated"
  value       = module.ecr.replication_regions
}

# ====================================================================
# AWS Backup Outputs
# ====================================================================

output "backup_vault_arn" {
  description = "ARN of the AWS Backup vault for EKS"
  value       = var.cluster_exists && var.enable_eks_backup ? aws_backup_vault.eks[0].arn : null
}

output "backup_vault_name" {
  description = "Name of the AWS Backup vault for EKS"
  value       = var.cluster_exists && var.enable_eks_backup ? aws_backup_vault.eks[0].name : null
}

output "backup_plan_id" {
  description = "ID of the AWS Backup plan"
  value       = var.cluster_exists && var.enable_eks_backup ? aws_backup_plan.eks_daily[0].id : null
}

output "backup_schedule" {
  description = "Backup schedule (cron expression)"
  value       = var.backup_schedule
}

output "backup_dr_vault_arn" {
  description = "ARN of the DR backup vault (if cross-region copy enabled)"
  value       = var.cluster_exists && var.enable_eks_backup && var.enable_backup_cross_region_copy ? aws_backup_vault.eks_dr[0].arn : null
}
