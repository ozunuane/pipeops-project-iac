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

# ====================================================================
# ArgoCD Helm Configuration
# ====================================================================

variable "argocd_chart_version" {
  description = "ArgoCD Helm chart version"
  type        = string
  default     = "5.51.6"
}

variable "argocd_image_tag" {
  description = "ArgoCD image tag (leave empty for chart default)"
  type        = string
  default     = ""
}

variable "argocd_server_insecure" {
  description = "Run ArgoCD server in insecure mode (no TLS). Use when behind a load balancer that handles TLS."
  type        = bool
  default     = true
}

variable "argocd_enable_ingress" {
  description = "Enable ingress for ArgoCD server"
  type        = bool
  default     = false
}

variable "argocd_domain" {
  description = "Domain for ArgoCD server ingress"
  type        = string
  default     = ""
}

variable "argocd_ssl_certificate_arn" {
  description = "ACM certificate ARN for ArgoCD ingress"
  type        = string
  default     = ""
}

variable "argocd_enable_dex" {
  description = "Enable Dex for SSO integration"
  type        = bool
  default     = false
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

variable "enable_aws_load_balancer_controller_addon" {
  description = "Install AWS Load Balancer Controller as EKS addon. Set to false for Kubernetes 1.33 (addon not supported); use Helm instead if needed."
  type        = bool
  default     = false
}

variable "cluster_access_entries" {
  description = "EKS access entries: key = label, value = { principal_arn, level, namespaces? }. Levels: admin (full), devops (edit cluster), dev (edit), qa (view-only). Optional namespaces = list for dev/qa to scope access."
  type = map(object({
    principal_arn = string
    level         = string # admin | devops | dev | qa
    namespaces    = optional(list(string))
  }))
  default = {}
}

variable "eks_exec_role_arn" {
  description = "IAM role ARN for aws eks get-token --role-arn. CI (OIDC) assumes this role for EKS; only this role needs Access Entry. Overrides eks-exec-role-arn.txt when set. Setup-prerequisites creates the role and writes the file."
  type        = string
  default     = ""
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

# ====================================================================
# ECR - Elastic Container Registry Variables
# ====================================================================

variable "ecr_repository_names" {
  description = "List of ECR repository names to create"
  type        = list(string)
  default     = ["api", "web", "worker"]
}

variable "ecr_image_tag_mutability" {
  description = "Image tag mutability for all repositories (IMMUTABLE recommended for security)"
  type        = string
  default     = "IMMUTABLE"
}

variable "ecr_scan_on_push" {
  description = "Enable image scanning on push for all repositories"
  type        = bool
  default     = true
}

variable "ecr_lifecycle_keep_count" {
  description = "Number of images to keep per repository"
  type        = number
  default     = 30
}

variable "ecr_lifecycle_expire_untagged_days" {
  description = "Days before untagged images expire"
  type        = number
  default     = 14
}

variable "ecr_enable_replication" {
  description = "Enable cross-region ECR replication for DR (only applies in prod)"
  type        = bool
  default     = true
}

variable "ecr_replication_regions" {
  description = "AWS regions to replicate ECR images to (for DR)"
  type        = list(string)
  default     = ["us-east-1"] # DR region
}

variable "ecr_replication_account_ids" {
  description = "AWS account IDs for cross-account ECR replication"
  type        = list(string)
  default     = []
}

variable "ecr_create_github_actions_policy" {
  description = "Create IAM policy for GitHub Actions to push to ECR"
  type        = bool
  default     = true
}

variable "ecr_github_actions_role_arn" {
  description = "ARN of the GitHub Actions OIDC role (for attaching ECR push policy)"
  type        = string
  default     = ""
}

variable "ecr_push_principals" {
  description = "Additional IAM ARNs allowed to push images to ECR"
  type        = list(string)
  default     = []
}

variable "ecr_pull_principals" {
  description = "Additional IAM ARNs allowed to pull images from ECR"
  type        = list(string)
  default     = []
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

# ====================================================================
# AWS Backup Configuration
# ====================================================================

variable "enable_eks_backup" {
  description = "Enable AWS Backup for EKS cluster"
  type        = bool
  default     = true
}

variable "backup_schedule" {
  description = "Cron expression for backup schedule (default: daily at 6 AM UTC)"
  type        = string
  default     = "cron(0 6 * * ? *)"
}

variable "backup_retention_days" {
  description = "Number of days to retain backups before deletion"
  type        = number
  default     = 35
}

variable "backup_cold_storage_after" {
  description = "Number of days after which to move backups to cold storage (set to 0 to disable)"
  type        = number
  default     = 0
}

variable "backup_weekly_retention_days" {
  description = "Number of days to retain weekly backups (should be longer than daily retention)"
  type        = number
  default     = 90
}

variable "enable_backup_cross_region_copy" {
  description = "Enable cross-region backup copy to DR region"
  type        = bool
  default     = false
}