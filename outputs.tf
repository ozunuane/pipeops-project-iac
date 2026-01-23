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

output "rds_dr_note" {
  description = "Note about RDS DR replica management"
  value       = "RDS DR replica is managed by the DR workspace (dr-infrastructure/). Use the primary RDS ARN to configure it."
}

# ArgoCD Outputs (conditional on cluster_exists)
output "argocd_namespace" {
  description = "ArgoCD namespace"
  value       = var.cluster_exists && var.enable_argocd ? module.argocd[0].argocd_namespace : null
}

output "argocd_server_url" {
  description = "ArgoCD server URL"
  value       = var.cluster_exists && var.enable_argocd ? module.argocd[0].argocd_server_url : null
}

output "argocd_admin_password" {
  description = "ArgoCD admin password"
  value       = var.cluster_exists && var.enable_argocd ? module.argocd[0].argocd_admin_password : null
  sensitive   = true
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
  value       = "kubectl port-forward svc/argocd-server -n argocd 8080:443 & argocd login localhost:8080 --username admin --password '${local.argocd_admin_password}' --insecure"
  sensitive   = true
}

# Quick start commands
output "quick_start_commands" {
  description = "Quick start commands after deployment"
  value = {
    "1_configure_kubectl"      = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
    "2_port_forward_argocd"    = "kubectl port-forward svc/argocd-server -n argocd 8080:80"
    "3_argocd_admin_password"  = "echo '${local.argocd_admin_password}'"
    "4_port_forward_grafana"   = var.enable_monitoring ? "kubectl port-forward svc/grafana -n monitoring 3000:80" : "Monitoring not enabled"
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