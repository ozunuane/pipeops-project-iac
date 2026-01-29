# Development Environment Configuration
# Cost-optimized setup without Multi-AZ

# Project Configuration
project_name = "pipeops"
environment  = "dev"
region       = "us-west-2"

# Network Configuration
vpc_cidr              = "10.2.0.0/16"
availability_zones    = ["us-west-2a", "us-west-2b", "us-west-2c"]
private_subnet_cidrs  = ["10.2.1.0/24", "10.2.2.0/24", "10.2.3.0/24"]
public_subnet_cidrs   = ["10.2.101.0/24", "10.2.102.0/24", "10.2.103.0/24"]
database_subnet_cidrs = ["10.2.201.0/24", "10.2.202.0/24", "10.2.203.0/24"]

# EKS Configuration
kubernetes_version = "1.33"
cluster_exists     = true  # Set to true after EKS cluster is created
create_eks         = true  # Set false to skip EKS and all EKS-dependent resources
create_rds         = false # Set false to skip RDS and DB-related resources
use_eks_exec_role  = false # Local dev: use your AWS identity for EKS (avoids "aws failed 254" when you can't assume exec role)
# aws_profile        = "myprofile" # Uncomment if using a named profile for Terraform/Helm

enable_aws_load_balancer_controller_addon = true # Helm LBC + Gateway API (IngressClass alb, GatewayClass alb)

# EKS access: CI uses eks-exec (use_eks_exec_role=true override in workflow). Local dev uses your identity; add your principal_arn here if needed.
cluster_access_entries = {
  "eks-exec" = {
    principal_arn = "arn:aws:iam::742890864997:role/pipeops-dev-eks-terraform-exec"
    level         = "admin"
  }
}

# RDS Configuration - DEVELOPMENT (Cost-optimized, Single-AZ)
db_instance_class              = "db.t4g.medium" # Burstable instance for cost savings
db_allocated_storage           = 50              # 50 GB storage
db_backup_retention            = 7               # 7 days backup retention
db_multi_az                    = false           # ❌ Single-AZ for cost optimization
db_create_read_replica         = false           # ❌ No read replicas
db_read_replica_count          = 0
db_read_replica_instance_class = "db.t4g.medium"
db_replica_availability_zones  = []
db_iops                        = null # Use baseline performance
db_monitoring_sns_topic_arn    = ""   # No alarms in dev
db_apply_immediately           = true # Apply changes immediately

# Multi-Region Disaster Recovery (Dev - Disabled)
dr_region                      = "us-east-1" # DR region
db_enable_cross_region_dr      = false       # ❌ Disabled for dev
db_dr_instance_class           = "db.t4g.medium"
db_dr_multi_az                 = false
db_enable_cross_region_backups = false # ❌ Disabled for dev

# ECR Repositories
ecr_repository_names = [
  "titanic-api"

]
ecr_enable_replication = false # No DR replication in dev


# Feature Flags
enable_argocd     = true
enable_monitoring = true # Disable monitoring in dev to save costs
enable_logging    = true # Disable logging in dev

# StorageClasses to create (optional).
# If omitted, Terraform creates a single default gp3 StorageClass named:
#   "<project_name>-<environment>-gp3-storageclass"
storage_classes = [
  # Main gp3 StorageClass used by Prometheus/Alertmanager PVCs
  {
    name     = "pipeops-dev-gp3-storageclass"
    ebs_type = "gp3"
  },

  # Grafana-only StorageClass (separate name)
  {
    name     = "grafana-storage-class"
    ebs_type = "gp3"
  }

  # Example: additional StorageClass (uncomment if needed)
  # {
  #   name       = "pipeops-dev-gp2-storageclass"
  #   provisioner = "kubernetes.io/aws-ebs"
  #   parameters  = { type = "gp2" }
  #   allow_volume_expansion = false
  # }
]

# Monitoring storage:
# Use the repo-managed dev StorageClass name.
# If you are switching from an older StorageClass name, you must delete/recreate existing PVCs
# because PVC.spec.storageClassName is immutable.
grafana_storage_class_name = "grafana-storage-class"

# Tags
# AWS Backup Configuration (minimal for dev)
enable_eks_backup               = false
backup_schedule                 = "cron(0 6 * * ? *)" # Daily at 6:00 AM UTC
backup_retention_days           = 7                   # Keep daily backups for 7 days only
backup_weekly_retention_days    = 30                  # Keep weekly backups for 30 days
backup_cold_storage_after       = 0                   # Disable cold storage
enable_backup_cross_region_copy = false               # No cross-region copy for dev

tags = {
  Project      = "pipeops"
  Environment  = "dev"
  ManagedBy    = "terraform"
  GitOps       = "argocd"
  CostCenter   = "engineering"
  Owner        = "platform-team"
  Criticality  = "low"
  AutoShutdown = "enabled" # Can be shut down outside business hours
}

