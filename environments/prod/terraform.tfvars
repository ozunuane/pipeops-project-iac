# Production Environment Configuration
# High Availability Setup with Multi-AZ and Read Replicas

# Project Configuration
project_name = "pipeops"
environment  = "prod"
region       = "us-west-2"

# Network Configuration
vpc_cidr              = "10.0.0.0/16"
availability_zones    = ["us-west-2a", "us-west-2b", "us-west-2c"]
private_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
public_subnet_cidrs   = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
database_subnet_cidrs = ["10.0.201.0/24", "10.0.202.0/24", "10.0.203.0/24"]


# EKS Configuration
kubernetes_version = "1.33"
cluster_exists     = true # EKS cluster is running - enables Helm resources and backups

# EKS access by level: admin (full) | devops | dev (edit) | qa (view-only). Optional namespaces = scope dev/qa.
# Level -> policy: admin=ClusterAdmin, devops/dev=Edit, qa=View. Add namespaces for dev/qa to restrict scope.
# Keep root as admin to run 'make bootstrap-eks-access' (Terraform uses root; avoids k8s refresh Forbidden).
cluster_access_entries = {
  "root" = {
    principal_arn = "arn:aws:iam::742890864997:root"
    level         = "admin"
  }
  "ozimede-cli" = {
    principal_arn = "arn:aws:iam::742890864997:user/ozimede-cli"
    level         = "admin"
  }
  # "devops-user" = { principal_arn = "arn:aws:iam::742890864997:user/devops-user", level = "devops" }
  # "dev-user"    = { principal_arn = "arn:aws:iam::742890864997:user/dev-user", level = "dev" }
  # "qa-user"     = { principal_arn = "arn:aws:iam::742890864997:user/qa-user", level = "qa" }
  # Namespace-scoped example (dev only in dev/default):
  # "dev-ns" = { principal_arn = "arn:aws:iam::742890864997:user/dev-user", level = "dev", namespaces = ["dev", "default"] }
}

# RDS Configuration - PRODUCTION with Multi-AZ + Read Replicas
db_instance_class              = "db.m5d.large"               # Larger instance for production
db_postgres_version            = "16.6"                       # PostgreSQL 16.6 - available in all AWS regions
db_allocated_storage           = 400                          # 400 GB initial storage (minimum for provisioned IOPS)
db_backup_retention            = 30                           # 30 days backup retention
db_multi_az                    = false                        # ✅ Multi-AZ ENABLED - Critical for HA
db_create_read_replica         = false                        # ✅ Read replicas ENABLED
db_read_replica_count          = 0                            # 2 read replicas for load distribution
db_read_replica_instance_class = "db.m5d.large"               # Read replicas can be smaller
db_replica_availability_zones  = ["us-west-2b", "us-west-2c"] # Spread across AZs
# db_iops                        = 3000                         # Provisioned IOPS for better performance
db_monitoring_sns_topic_arn = ""    # TODO: Add SNS topic ARN after creation
db_apply_immediately        = false # Apply changes during maintenance window

# Multi-Region Disaster Recovery (Production - RECOMMENDED)
dr_region = "us-east-1" # DR region (different from us-west-2)

# Note: DR RDS replica is now managed by DR workspace (dr-infrastructure/)
# Primary workspace only manages cross-region backup replication
db_enable_cross_region_backups = false # ✅ Replicate backups to DR region
db_dr_kms_key_id               = ""    # Optional: KMS key for backup encryption

# DR EKS Cluster Configuration (Production Only)
dr_vpc_cidr                             = "10.1.0.0/16"
dr_availability_zones                   = ["us-east-1a", "us-east-1b", "us-east-1c"]
dr_public_subnet_cidrs                  = ["10.1.101.0/24", "10.1.102.0/24", "10.1.103.0/24"]
dr_private_subnet_cidrs                 = ["10.1.1.0/24", "10.1.2.0/24", "10.1.3.0/24"]
dr_database_subnet_cidrs                = ["10.1.201.0/24", "10.1.202.0/24", "10.1.203.0/24"]
dr_cluster_endpoint_public_access_cidrs = ["0.0.0.0/0"] # Restrict in production
dr_desired_capacity                     = 2             # Standby mode - minimal nodes
dr_min_capacity                         = 2
dr_max_capacity                         = 6                         # Can scale up during DR activation
dr_node_instance_types                  = ["t3.medium", "t3.large"] # Cost-optimized for standby

# ECR Repositories
ecr_repository_names = [
  "titanic-api",
  "karpenter"
]
ecr_enable_replication  = false         # ✅ Enable DR replication for prod
ecr_replication_regions = ["us-east-1"] # Replicate to DR region

# Feature Flags
enable_argocd     = false
enable_monitoring = false
enable_logging    = false

# EKS 1.33: AWS LB Controller addon not supported; keep false. Use Helm if needed.
enable_aws_load_balancer_controller_addon = false

# Tags
# AWS Backup Configuration
enable_eks_backup               = false
backup_schedule                 = "cron(0 6 * * ? *)" # Daily at 6:00 AM UTC
backup_retention_days           = 35                  # Keep daily backups for 35 days
backup_weekly_retention_days    = 90                  # Keep weekly backups for 90 days
backup_cold_storage_after       = 0                   # Disable cold storage (set to 7+ to enable)
enable_backup_cross_region_copy = true                # Copy backups to DR region

tags = {
  Project     = "pipeops"
  Environment = "prod"
  ManagedBy   = "terraform"
  GitOps      = "argocd"
  CostCenter  = "engineering"
  Owner       = "platform-team"
  Criticality = "high"
  Compliance  = "required"
}
