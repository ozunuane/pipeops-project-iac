# ====================================================================
# DR Infrastructure Variables
# ====================================================================

variable "project_name" {
  description = "Project name (should match primary infrastructure)"
  type        = string
  default     = "pipeops"
}

variable "primary_environment" {
  description = "Primary environment name (e.g., prod, staging)"
  type        = string
  default     = "prod"
}

variable "primary_region" {
  description = "Primary AWS region (for reference)"
  type        = string
  default     = "us-west-2"
}

variable "dr_region" {
  description = "DR AWS region"
  type        = string
  default     = "us-east-1"
}

# ====================================================================
# DR VPC Configuration
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

# ====================================================================
# DR EKS Configuration
# ====================================================================

variable "kubernetes_version" {
  description = "Kubernetes version (should match primary cluster)"
  type        = string
  default     = "1.33"
}

variable "dr_cluster_endpoint_public_access_cidrs" {
  description = "CIDR blocks allowed to access DR EKS cluster endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "dr_desired_capacity" {
  description = "Desired number of nodes in DR cluster"
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
  description = "Instance types for DR cluster nodes"
  type        = list(string)
  default     = ["t3.medium", "t3.large"]
}

variable "dr_cluster_mode" {
  description = "DR cluster operational mode"
  type        = string
  default     = "standby"

  validation {
    condition     = contains(["standby", "active", "warm"], var.dr_cluster_mode)
    error_message = "DR cluster mode must be one of: standby, active, warm"
  }
}

# ====================================================================
# DR RDS Configuration
# ====================================================================

variable "enable_rds_dr_replica" {
  description = "Enable RDS DR replica in this workspace"
  type        = bool
  default     = true
}

variable "primary_rds_arn" {
  description = "ARN of the primary RDS instance to replicate from"
  type        = string
  default     = ""
}

variable "dr_rds_instance_class" {
  description = "Instance class for DR RDS replica"
  type        = string
  default     = "db.r6g.xlarge"
}

variable "dr_rds_multi_az" {
  description = "Enable Multi-AZ for DR RDS replica"
  type        = bool
  default     = true
}

# ====================================================================
# Tags
# ====================================================================

variable "tags" {
  description = "Common tags for all DR resources"
  type        = map(string)
  default = {
    Project          = "pipeops"
    Environment      = "prod-dr"
    ManagedBy        = "terraform"
    DisasterRecovery = "true"
    Workspace        = "dr"
  }
}
