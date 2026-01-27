#------------------------------------------------------------------------------
# ECR Module Outputs
#------------------------------------------------------------------------------

output "repository_urls" {
  description = "Map of repository names to their URLs"
  value = {
    for key, repo in aws_ecr_repository.main : key => repo.repository_url
  }
}

output "repository_arns" {
  description = "Map of repository names to their ARNs"
  value = {
    for key, repo in aws_ecr_repository.main : key => repo.arn
  }
}

output "repository_names" {
  description = "Map of repository keys to their full names"
  value = {
    for key, repo in aws_ecr_repository.main : key => repo.name
  }
}

output "repository_urls_list" {
  description = "List of repository URLs (same order as input, only repos that exist)"
  value       = [for name in var.repository_names : aws_ecr_repository.main[name].repository_url if contains(keys(aws_ecr_repository.main), name)]
}

output "registry_id" {
  description = "The registry ID (AWS account ID)"
  value       = data.aws_caller_identity.current.account_id
}

output "registry_url" {
  description = "The ECR registry URL"
  value       = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com"
}

output "github_actions_policy_arn" {
  description = "ARN of the IAM policy for GitHub Actions ECR access"
  value       = var.create_github_actions_policy && length(var.repository_names) > 0 ? aws_iam_policy.github_actions_ecr[0].arn : null
}

output "eks_pull_policy_arn" {
  description = "ARN of the IAM policy for EKS ECR pull access"
  value       = var.create_eks_ecr_pull_policy && length(var.repository_names) > 0 ? aws_iam_policy.eks_ecr_pull[0].arn : null
}

output "replication_enabled" {
  description = "Whether cross-region replication is enabled"
  value       = var.enable_replication
}

output "replication_regions" {
  description = "List of regions images are replicated to"
  value       = var.enable_replication ? var.replication_regions : []
}

# Docker login command helper
output "docker_login_command" {
  description = "Command to authenticate Docker with ECR"
  value       = "aws ecr get-login-password --region ${var.region} | docker login --username AWS --password-stdin ${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com"
}

# KMS key for ECR encryption
output "kms_key_arn" {
  description = "ARN of the KMS key used for ECR encryption"
  value       = local.ecr_kms_key_arn
}

output "kms_key_id" {
  description = "ID of the KMS key used for ECR encryption"
  value       = var.kms_key_arn == null ? aws_kms_key.ecr[0].key_id : null
}
