# ====================================================================
# DR Infrastructure Outputs
# ====================================================================

# VPC Outputs
output "dr_vpc_id" {
  description = "ID of the DR VPC"
  value       = module.dr_vpc.vpc_id
}

output "dr_vpc_cidr_block" {
  description = "CIDR block of the DR VPC"
  value       = module.dr_vpc.vpc_cidr_block
}

output "dr_public_subnet_ids" {
  description = "IDs of the DR public subnets"
  value       = module.dr_vpc.public_subnet_ids
}

output "dr_private_subnet_ids" {
  description = "IDs of the DR private subnets"
  value       = module.dr_vpc.private_subnet_ids
}

output "dr_database_subnet_ids" {
  description = "IDs of the DR database subnets"
  value       = module.dr_vpc.database_subnet_ids
}

# EKS Outputs
output "dr_cluster_name" {
  description = "Name of the DR EKS cluster"
  value       = module.dr_eks.cluster_name
}

output "dr_cluster_endpoint" {
  description = "Endpoint for DR EKS control plane"
  value       = module.dr_eks.cluster_endpoint
}

output "dr_cluster_version" {
  description = "The Kubernetes server version for the DR EKS cluster"
  value       = module.dr_eks.cluster_version
}

output "dr_cluster_arn" {
  description = "ARN of the DR EKS cluster"
  value       = module.dr_eks.cluster_arn
}

output "dr_cluster_oidc_issuer_url" {
  description = "The URL on the DR EKS cluster for the OpenID Connect identity provider"
  value       = module.dr_eks.cluster_oidc_issuer_url
}

output "dr_node_security_group_id" {
  description = "ID of the DR EKS node group security group"
  value       = module.dr_eks.node_security_group_id
}

# Configuration Commands
output "dr_kubectl_config_command" {
  description = "Command to configure kubectl for DR cluster"
  value       = "aws eks update-kubeconfig --region ${var.dr_region} --name ${module.dr_eks.cluster_name}"
}

output "dr_cluster_info" {
  description = "DR cluster information summary"
  value = {
    cluster_name  = module.dr_eks.cluster_name
    region        = var.dr_region
    vpc_cidr      = var.dr_vpc_cidr
    node_count    = "${var.dr_min_capacity}-${var.dr_max_capacity}"
    mode          = var.dr_cluster_mode
    primary_env   = var.primary_environment
    primary_region = var.primary_region
  }
}

# Quick Start Commands
output "quick_start_commands" {
  description = "Quick start commands for DR cluster"
  value = {
    "1_configure_kubectl" = "aws eks update-kubeconfig --region ${var.dr_region} --name ${module.dr_eks.cluster_name}"
    "2_get_nodes"         = "kubectl get nodes"
    "3_get_namespaces"    = "kubectl get namespaces"
    "4_check_addons"      = "kubectl get pods -n kube-system"
    "5_check_secrets"     = "kubectl get pods -n external-secrets-system"
  }
}

# Cost Information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost for DR infrastructure"
  value = {
    eks_cluster   = "$73 (1 cluster)"
    ec2_nodes     = "$${var.dr_desired_capacity * 30} (${var.dr_desired_capacity}x t3.medium @ ~$30/month)"
    nat_gateways  = "$${length(var.dr_availability_zones) * 33} (${length(var.dr_availability_zones)} NAT Gateways @ ~$33/month)"
    data_transfer = "$10-20 (estimated)"
    total         = "$${73 + (var.dr_desired_capacity * 30) + (length(var.dr_availability_zones) * 33) + 15}/month (standby mode)"
  }
}

# DR Status
# DR RDS Outputs
output "dr_rds_replica_endpoint" {
  description = "Endpoint of the DR RDS replica"
  value       = var.enable_rds_dr_replica && var.primary_rds_arn != "" ? aws_db_instance.dr_replica[0].endpoint : null
}

output "dr_rds_replica_id" {
  description = "ID of the DR RDS replica"
  value       = var.enable_rds_dr_replica && var.primary_rds_arn != "" ? aws_db_instance.dr_replica[0].id : null
}

output "dr_rds_replica_arn" {
  description = "ARN of the DR RDS replica"
  value       = var.enable_rds_dr_replica && var.primary_rds_arn != "" ? aws_db_instance.dr_replica[0].arn : null
}

output "dr_rds_multi_az" {
  description = "Whether DR RDS replica is Multi-AZ"
  value       = var.enable_rds_dr_replica && var.primary_rds_arn != "" ? aws_db_instance.dr_replica[0].multi_az : null
}

output "dr_rds_security_group_id" {
  description = "Security group ID for DR RDS replica"
  value       = var.enable_rds_dr_replica && var.primary_rds_arn != "" ? aws_security_group.dr_rds[0].id : null
}

output "dr_status" {
  description = "DR infrastructure deployment status"
  value = {
    deployed           = true
    region             = var.dr_region
    cluster_mode       = var.dr_cluster_mode
    vpc_id             = module.dr_vpc.vpc_id
    cluster_name       = module.dr_eks.cluster_name
    rds_replica_enabled = var.enable_rds_dr_replica && var.primary_rds_arn != ""
    rds_replica_endpoint = var.enable_rds_dr_replica && var.primary_rds_arn != "" ? aws_db_instance.dr_replica[0].endpoint : "Not deployed"
    ready_for_failover = var.dr_cluster_mode == "standby" ? "Requires scale-up" : "Ready"
  }
}
