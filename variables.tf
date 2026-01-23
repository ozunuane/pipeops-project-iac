variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "pipeops"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b", "us-west-2c"]
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
}

variable "database_subnet_cidrs" {
  description = "CIDR blocks for database subnets"
  type        = list(string)
  default     = ["10.0.201.0/24", "10.0.202.0/24", "10.0.203.0/24"]
}

variable "kubernetes_version" {
  description = "Kubernetes version for EKS cluster"
  type        = string
  default     = "1.33"
}

variable "cluster_exists" {
  description = "Set to true after EKS cluster is created. Required for Helm/K8s resources."
  type        = bool
  default     = false
}

variable "enable_argocd" {
  description = "Enable ArgoCD installation"
  type        = bool
  default     = true
}

variable "enable_monitoring" {
  description = "Enable monitoring stack (Prometheus, Grafana)"
  type        = bool
  default     = true
}

variable "enable_logging" {
  description = "Enable logging stack (AWS CloudWatch)"
  type        = bool
  default     = true
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.r6g.large"
}

variable "db_allocated_storage" {
  description = "RDS allocated storage in GB"
  type        = number
  default     = 100
}

variable "db_postgres_version" {
  description = "PostgreSQL engine version for RDS"
  type        = string
  default     = "16.6"
}

variable "db_backup_retention" {
  description = "RDS backup retention period in days"
  type        = number
  default     = 30
}

variable "db_multi_az" {
  description = "Enable Multi-AZ deployment for RDS high availability"
  type        = bool
  default     = true
}

variable "db_create_read_replica" {
  description = "Create read replicas for RDS"
  type        = bool
  default     = false
}

variable "db_read_replica_count" {
  description = "Number of read replicas to create"
  type        = number
  default     = 1
}

variable "db_read_replica_instance_class" {
  description = "Instance class for read replicas"
  type        = string
  default     = "db.r6g.large"
}

variable "db_replica_availability_zones" {
  description = "Availability zones for read replicas"
  type        = list(string)
  default     = []
}

variable "db_iops" {
  description = "The amount of provisioned IOPS for gp3 storage"
  type        = number
  default     = null
}

variable "db_monitoring_sns_topic_arn" {
  description = "SNS topic ARN for RDS CloudWatch alarms"
  type        = string
  default     = ""
}

variable "db_apply_immediately" {
  description = "Apply RDS changes immediately instead of during maintenance window"
  type        = bool
  default     = false
}

# Multi-Region Disaster Recovery Variables
variable "dr_region" {
  description = "AWS region for disaster recovery (if different from primary)"
  type        = string
  default     = "us-east-1"
}

variable "db_enable_cross_region_dr" {
  description = "Enable cross-region disaster recovery with read replica in DR region"
  type        = bool
  default     = false
}

variable "db_dr_instance_class" {
  description = "Instance class for DR replica"
  type        = string
  default     = "db.r6g.large"
}

variable "db_dr_multi_az" {
  description = "Enable Multi-AZ for DR replica (recommended for production)"
  type        = bool
  default     = true
}

variable "db_enable_cross_region_backups" {
  description = "Enable automated backup replication to DR region"
  type        = bool
  default     = false
}

variable "db_dr_kms_key_id" {
  description = "KMS key ID in DR region for backup encryption (optional, will use AWS managed key if not provided)"
  type        = string
  default     = ""
}

# ====================================================================
# DR EKS Cluster Variables (Production Only)
# ====================================================================

variable "dr_vpc_cidr" {
  description = "CIDR block for DR VPC"
  type        = string
  default     = "10.1.0.0/16"
}

variable "dr_availability_zones" {
  description = "Availability zones for DR region"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "dr_public_subnet_cidrs" {
  description = "CIDR blocks for DR public subnets"
  type        = list(string)
  default     = ["10.1.101.0/24", "10.1.102.0/24", "10.1.103.0/24"]
}

variable "dr_private_subnet_cidrs" {
  description = "CIDR blocks for DR private subnets"
  type        = list(string)
  default     = ["10.1.1.0/24", "10.1.2.0/24", "10.1.3.0/24"]
}

variable "dr_database_subnet_cidrs" {
  description = "CIDR blocks for DR database subnets"
  type        = list(string)
  default     = ["10.1.201.0/24", "10.1.202.0/24", "10.1.203.0/24"]
}

variable "dr_cluster_endpoint_public_access_cidrs" {
  description = "CIDR blocks allowed to access DR EKS cluster endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "dr_desired_capacity" {
  description = "Desired number of nodes in DR cluster (cost-optimized for standby)"
  type        = number
  default     = 2
}

variable "dr_min_capacity" {
  description = "Minimum number of nodes in DR cluster"
  type        = number
  default     = 2
}

variable "dr_max_capacity" {
  description = "Maximum number of nodes in DR cluster"
  type        = number
  default     = 6
}

variable "dr_node_instance_types" {
  description = "Instance types for DR cluster nodes (cost-optimized)"
  type        = list(string)
  default     = ["t3.medium", "t3.large"]
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    Project     = "pipeops"
    Environment = "prod"
    ManagedBy   = "terraform"
    GitOps      = "argocd"
  }
}