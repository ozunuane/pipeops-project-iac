# ====================================================================
# DR Infrastructure Configuration - drprod
# ====================================================================
# This configuration is for the standalone DR workspace
# It provisions disaster recovery infrastructure in us-east-1
# Environment name: drprod (Disaster Recovery for Production)

# Project Configuration
project_name        = "pipeops"
primary_environment = "prod"
primary_region      = "us-west-2"
dr_region           = "us-east-1"

# DR VPC Configuration
dr_vpc_cidr              = "10.1.0.0/16"
dr_availability_zones    = ["us-east-1a", "us-east-1b", "us-east-1c"]
dr_public_subnet_cidrs   = ["10.1.101.0/24", "10.1.102.0/24", "10.1.103.0/24"]
dr_private_subnet_cidrs  = ["10.1.1.0/24", "10.1.2.0/24", "10.1.3.0/24"]
dr_database_subnet_cidrs = ["10.1.201.0/24", "10.1.202.0/24", "10.1.203.0/24"]

# DR EKS Configuration
kubernetes_version                      = "1.33"
cluster_exists                          = false # Set to true after EKS cluster is created
dr_cluster_endpoint_public_access_cidrs = ["0.0.0.0/0"] # TODO: Restrict to your IP ranges

# DR Cluster Sizing - Standby Mode (Cost-Optimized)
dr_desired_capacity    = 2 # Minimal nodes for standby
dr_min_capacity        = 2
dr_max_capacity        = 6 # Can scale up during DR activation
dr_node_instance_types = ["t3.medium", "t3.large"]
dr_cluster_mode        = "standby" # Options: standby, warm, active

# DR RDS Configuration
enable_rds_dr_replica = true
# primary_rds_arn will be provided from primary infrastructure output
# Format: arn:aws:rds:us-west-2:ACCOUNT_ID:db:pipeops-prod-postgres
primary_rds_arn       = "" # Set this after primary RDS is deployed
dr_rds_instance_class = "db.r6g.xlarge"
dr_rds_multi_az       = true

# Tags
tags = {
  Project          = "pipeops"
  Environment      = "drprod"
  ManagedBy        = "terraform"
  GitOps           = "argocd"
  CostCenter       = "engineering"
  Owner            = "platform-team"
  Criticality      = "high"
  DisasterRecovery = "true"
  Workspace        = "dr"
  PrimaryRegion    = "us-west-2"
  DRRegion         = "us-east-1"
}
