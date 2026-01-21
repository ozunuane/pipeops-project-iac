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
kubernetes_version = "1.28"

# RDS Configuration - PRODUCTION with Multi-AZ + Read Replicas
db_instance_class              = "db.r6g.xlarge"              # Larger instance for production
db_allocated_storage           = 200                          # 200 GB initial storage
db_backup_retention            = 30                           # 30 days backup retention
db_multi_az                    = true                         # ✅ Multi-AZ ENABLED - Critical for HA
db_create_read_replica         = true                         # ✅ Read replicas ENABLED
db_read_replica_count          = 2                            # 2 read replicas for load distribution
db_read_replica_instance_class = "db.r6g.large"               # Read replicas can be smaller
db_replica_availability_zones  = ["us-west-2b", "us-west-2c"] # Spread across AZs
db_iops                        = 3000                         # Provisioned IOPS for better performance
db_monitoring_sns_topic_arn    = ""                           # TODO: Add SNS topic ARN after creation
db_apply_immediately           = false                        # Apply changes during maintenance window

# Multi-Region Disaster Recovery (Production - RECOMMENDED)
dr_region                      = "us-east-1"     # DR region (different from us-west-2)
db_enable_cross_region_dr      = true            # ✅ Enable DR replica in us-east-1
db_dr_instance_class           = "db.r6g.xlarge" # Same size as primary for production
db_dr_multi_az                 = true            # ✅ Multi-AZ in DR region
db_enable_cross_region_backups = true            # ✅ Also replicate backups

# Feature Flags
enable_argocd     = true
enable_monitoring = true
enable_logging    = true

# Tags
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
