variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "region" {
  description = "Primary AWS region"
  type        = string
  default     = ""
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "db_subnet_group_name" {
  description = "Name of the database subnet group"
  type        = string
}

variable "allowed_security_groups" {
  description = "List of security group IDs allowed to access the database"
  type        = list(string)
  default     = []
}

variable "allowed_cidr_blocks" {
  description = "List of CIDR blocks allowed to access the database"
  type        = list(string)
  default     = []
}

variable "postgres_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "16.3"  # PostgreSQL 16.3 - widely available in all AWS regions
  # To list available versions: aws rds describe-db-engine-versions --engine postgres --query 'DBEngineVersions[].EngineVersion'
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.r6g.large"
}

variable "allocated_storage" {
  description = "The allocated storage in GB"
  type        = number
  default     = 100
}

variable "max_allocated_storage" {
  description = "The upper limit to which RDS can automatically scale the storage"
  type        = number
  default     = 1000
}

variable "database_name" {
  description = "Name of the database"
  type        = string
  default     = "app"
}

variable "database_username" {
  description = "Database master username"
  type        = string
  default     = "postgres"
}

variable "database_password" {
  description = "Database master password"
  type        = string
  sensitive   = true
}

variable "backup_retention_period" {
  description = "Number of days to retain backups"
  type        = number
  default     = 30
}

variable "deletion_protection" {
  description = "Enable deletion protection"
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "Skip final snapshot when deleting"
  type        = bool
  default     = false
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}

variable "multi_az" {
  description = "Enable Multi-AZ deployment for high availability"
  type        = bool
  default     = true
}

variable "create_read_replica" {
  description = "Create read replicas for load distribution"
  type        = bool
  default     = false
}

variable "read_replica_count" {
  description = "Number of read replicas to create"
  type        = number
  default     = 1
}

variable "read_replica_instance_class" {
  description = "Instance class for read replicas"
  type        = string
  default     = "db.r6g.large"
}

variable "replica_availability_zones" {
  description = "Availability zones for read replicas"
  type        = list(string)
  default     = []
}

variable "apply_immediately" {
  description = "Apply changes immediately instead of during maintenance window"
  type        = bool
  default     = false
}

variable "sns_topic_arn" {
  description = "SNS topic ARN for CloudWatch alarms"
  type        = string
  default     = ""
}

variable "performance_insights_retention" {
  description = "Performance Insights retention period in days"
  type        = number
  default     = 7
}

variable "iops" {
  description = "The amount of provisioned IOPS for gp3 storage"
  type        = number
  default     = null
}

# Multi-Region Disaster Recovery Variables
variable "enable_cross_region_dr" {
  description = "Enable cross-region disaster recovery with read replica in another region"
  type        = bool
  default     = false
}

variable "dr_region" {
  description = "AWS region for disaster recovery (must be different from primary)"
  type        = string
  default     = ""
}

variable "dr_instance_class" {
  description = "Instance class for DR replica"
  type        = string
  default     = "db.r6g.large"
}

variable "dr_multi_az" {
  description = "Enable Multi-AZ for DR replica (recommended)"
  type        = bool
  default     = true
}

variable "enable_cross_region_backups" {
  description = "Enable automated backup replication to DR region"
  type        = bool
  default     = false
}

variable "dr_kms_key_id" {
  description = "KMS key ID in DR region for encryption (if not provided, will create one)"
  type        = string
  default     = ""
}

# DR Network Configuration
variable "dr_vpc_id" {
  description = "VPC ID in DR region for RDS replica"
  type        = string
  default     = ""
}

variable "dr_db_subnet_group_name" {
  description = "DB subnet group name in DR region"
  type        = string
  default     = ""
}

variable "dr_allowed_security_groups" {
  description = "List of security group IDs allowed to access DR RDS replica"
  type        = list(string)
  default     = []
}

variable "dr_allowed_cidr_blocks" {
  description = "List of CIDR blocks allowed to access DR RDS replica"
  type        = list(string)
  default     = []
}