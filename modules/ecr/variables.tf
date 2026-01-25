#------------------------------------------------------------------------------
# ECR Module Variables
#------------------------------------------------------------------------------

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment (dev, staging, prod)"
  type        = string
}

variable "region" {
  description = "AWS region for ECR repositories"
  type        = string
}

#------------------------------------------------------------------------------
# Repository Configuration
#------------------------------------------------------------------------------

variable "repository_names" {
  description = "List of repository names to create"
  type        = list(string)
  default     = []
}

variable "image_tag_mutability" {
  description = "Image tag mutability (MUTABLE or IMMUTABLE). IMMUTABLE recommended for security."
  type        = string
  default     = "IMMUTABLE"
}

variable "scan_on_push" {
  description = "Enable image scanning on push"
  type        = bool
  default     = true
}

variable "kms_key_arn" {
  description = "KMS key ARN for ECR encryption. If not provided, a new KMS key will be created."
  type        = string
  default     = null
}

#------------------------------------------------------------------------------
# Lifecycle Policy Configuration
#------------------------------------------------------------------------------

variable "lifecycle_keep_count" {
  description = "Number of tagged images to keep"
  type        = number
  default     = 30
}

variable "lifecycle_expire_untagged_days" {
  description = "Days before untagged images expire"
  type        = number
  default     = 14
}

variable "lifecycle_tagged_prefixes" {
  description = "Tag prefixes to preserve (e.g., v, release, prod)"
  type        = list(string)
  default     = ["v", "release", "prod", "main"]
}

#------------------------------------------------------------------------------
# Cross-Region Replication (DR)
#------------------------------------------------------------------------------

variable "enable_replication" {
  description = "Enable cross-region replication for DR (recommended for prod only)"
  type        = bool
  default     = false
}

variable "replication_regions" {
  description = "List of regions to replicate to"
  type        = list(string)
  default     = []
}

variable "replication_account_ids" {
  description = "List of AWS account IDs to replicate to (for cross-account replication)"
  type        = list(string)
  default     = []
}

#------------------------------------------------------------------------------
# IAM Access Configuration
#------------------------------------------------------------------------------

variable "push_principals" {
  description = "List of IAM ARNs allowed to push images (CI/CD roles, developers)"
  type        = list(string)
  default     = []
}

variable "pull_principals" {
  description = "List of IAM ARNs allowed to pull images (EKS nodes, services)"
  type        = list(string)
  default     = []
}

variable "create_github_actions_policy" {
  description = "Create IAM policy for GitHub Actions to push images"
  type        = bool
  default     = true
}

variable "github_actions_role_arn" {
  description = "ARN of the GitHub Actions OIDC role (for policy attachment)"
  type        = string
  default     = ""
}

variable "eks_node_role_arn" {
  description = "ARN of the EKS node IAM role (for pull access)"
  type        = string
  default     = ""
}

#------------------------------------------------------------------------------
# Tags
#------------------------------------------------------------------------------

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
