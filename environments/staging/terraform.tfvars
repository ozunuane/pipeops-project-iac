# Staging Environment Configuration
# Balanced setup with Multi-AZ but no read replicas

# Project Configuration
project_name = "pipeops"
environment  = "staging"
region       = "us-west-2"

# Network Configuration
vpc_cidr              = "10.1.0.0/16"
availability_zones    = ["us-west-2a", "us-west-2b", "us-west-2c"]
private_subnet_cidrs  = ["10.1.1.0/24", "10.1.2.0/24", "10.1.3.0/24"]
public_subnet_cidrs   = ["10.1.101.0/24", "10.1.102.0/24", "10.1.103.0/24"]
database_subnet_cidrs = ["10.1.201.0/24", "10.1.202.0/24", "10.1.203.0/24"]

# EKS Configuration
kubernetes_version = "1.33"
cluster_exists     = false # Set to true after EKS cluster is created

# RDS Configuration - STAGING with Multi-AZ (no read replicas)
db_instance_class              = "db.r6g.large" # Standard instance
db_allocated_storage           = 100            # 100 GB storage
db_backup_retention            = 14             # 14 days backup retention
db_multi_az                    = true           # ✅ Multi-AZ ENABLED for failover testing
db_create_read_replica         = false          # ❌ No read replicas (cost optimization)
db_read_replica_count          = 0
db_read_replica_instance_class = "db.r6g.large"
db_replica_availability_zones  = []
db_iops                        = null # Use baseline gp3 performance
db_monitoring_sns_topic_arn    = ""   # TODO: Add SNS topic ARN after creation
db_apply_immediately           = true # Apply changes immediately in staging

# Multi-Region Disaster Recovery (Staging - Optional)
dr_region                      = "us-east-1" # DR region
db_enable_cross_region_dr      = false       # ❌ Disabled for cost savings
db_dr_instance_class           = "db.r6g.large"
db_dr_multi_az                 = false # Single-AZ in DR for staging
db_enable_cross_region_backups = false # ❌ Disabled for cost savings

# ECR Repositories
ecr_repository_names = [
  "titanic-api",
  "frontend",
  "backend"
]
ecr_enable_replication = false # No DR replication in staging

# Feature Flags
enable_argocd     = true
enable_monitoring = true
enable_logging    = true

# Tags
tags = {
  Project     = "pipeops"
  Environment = "staging"
  ManagedBy   = "terraform"
  GitOps      = "argocd"
  CostCenter  = "engineering"
  Owner       = "platform-team"
  Criticality = "medium"
}
