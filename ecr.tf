# ==========================================
# ECR - Elastic Container Registry
# ==========================================
# Container image repositories for microservices
# Features:
# - Image scanning on push
# - Lifecycle policies (auto-cleanup)
# - Cross-region replication (prod only, for DR)
# - IAM policies for CI/CD push and EKS pull
# ==========================================

module "ecr" {
  source = "./modules/ecr"

  project_name = var.project_name
  environment  = var.environment
  region       = var.region

  # Repository names (simple list)
  repository_names = var.ecr_repository_names

  # Repository settings
  image_tag_mutability = var.ecr_image_tag_mutability
  scan_on_push         = var.ecr_scan_on_push

  # Lifecycle policy settings
  lifecycle_keep_count           = var.ecr_lifecycle_keep_count
  lifecycle_expire_untagged_days = var.ecr_lifecycle_expire_untagged_days

  # Cross-region replication for DR (prod only)
  enable_replication  = var.environment == "prod" && var.ecr_enable_replication
  replication_regions = var.ecr_replication_regions

  # Cross-account replication (if using separate AWS accounts)
  replication_account_ids = var.ecr_replication_account_ids

  # IAM access - CI/CD push
  create_github_actions_policy = var.ecr_create_github_actions_policy
  github_actions_role_arn      = var.ecr_github_actions_role_arn

  # IAM access - EKS pull (create_* is plan-time; role ARN can be computed)
  create_eks_ecr_pull_policy = var.create_eks && var.cluster_exists
  eks_node_role_arn          = var.create_eks && var.cluster_exists ? module.eks[0].node_role_arn : ""

  # Additional principals for push/pull access
  push_principals = var.ecr_push_principals
  pull_principals = var.ecr_pull_principals

  tags = var.tags
}
