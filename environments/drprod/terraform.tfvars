# ====================================================================
# Disaster Recovery Environment Configuration
# ====================================================================
# NOTE: This environment uses the SEPARATE dr-infrastructure workspace
# for RDS. The dr-infrastructure workspace creates:
# - Cross-region RDS read replica (from prod)
# - DR VPC and EKS cluster
#
# This tfvars is for the main workspace if you need to deploy
# supplementary resources in the DR region.
# ====================================================================

# Project Configuration
project_name = "pipeops"
environment  = "drprod"
region       = "us-east-1" # DR region

# Network Configuration (matches dr-infrastructure VPC)
vpc_cidr              = "10.1.0.0/16"
availability_zones    = ["us-east-1a", "us-east-1b", "us-east-1c"]
private_subnet_cidrs  = ["10.1.1.0/24", "10.1.2.0/24", "10.1.3.0/24"]
public_subnet_cidrs   = ["10.1.101.0/24", "10.1.102.0/24", "10.1.103.0/24"]
database_subnet_cidrs = ["10.1.201.0/24", "10.1.202.0/24", "10.1.203.0/24"]

# EKS Configuration
kubernetes_version = "1.33"
cluster_exists     = false

# ====================================================================
# RDS - NOT CREATED HERE
# ====================================================================
# DR RDS is a cross-region READ REPLICA managed by dr-infrastructure/
# See: dr-infrastructure/environments/prod/terraform.tfvars
#
# To deploy DR RDS replica:
# 1. cd dr-infrastructure
# 2. terraform init -backend-config="environments/prod/backend.conf"
# 3. Set primary_rds_arn in environments/prod/terraform.tfvars
# 4. terraform apply -var-file="environments/prod/terraform.tfvars"
# ====================================================================

# Minimal RDS config (not actually used - DR uses replica)
db_instance_class              = "db.r6g.large"
db_allocated_storage           = 400
db_backup_retention            = 7
db_multi_az                    = false
db_create_read_replica         = false
db_read_replica_count          = 0
db_read_replica_instance_class = "db.r6g.large"
db_replica_availability_zones  = []
db_monitoring_sns_topic_arn    = ""
db_apply_immediately           = true

# No DR from DR
dr_region                      = "us-west-2"
db_enable_cross_region_dr      = false
db_enable_cross_region_backups = false

# ECR Repositories - Same as prod (receives replicated images)
ecr_repository_names   = ["titanic-api"]
ecr_enable_replication = false # Images replicated FROM prod, not TO anywhere

# Feature Flags - Standby mode
enable_argocd     = true
enable_monitoring = false # Enable during DR activation
enable_logging    = false # Enable during DR activation

# StorageClasses to create (optional).
# If omitted, Terraform creates a single default gp3 StorageClass named:
#   "<project_name>-<environment>-gp3-storageclass"
storage_classes = [
  {
    name     = "pipeops-drprod-gp3-storageclass"
    ebs_type = "gp3"
  }
]

# Tags
tags = {
  Project     = "pipeops"
  Environment = "drprod"
  ManagedBy   = "terraform"
  GitOps      = "argocd"
  DRStatus    = "standby"
  Criticality = "high"
  DRRegion    = "us-east-1"
}
