#------------------------------------------------------------------------------
# ECR Module - Elastic Container Registry
#------------------------------------------------------------------------------
# Creates ECR repositories with:
# - Image scanning on push
# - Lifecycle policies
# - Cross-region replication (for DR)
# - IAM policies for push/pull access
#------------------------------------------------------------------------------

locals {
  # Convert list to map for for_each
  repositories = { for name in var.repository_names : name => name }

  # Generate full repository names with project/environment prefix
  repository_full_names = {
    for name in var.repository_names :
    name => "${var.project_name}-${var.environment}-${name}"
  }
}

#------------------------------------------------------------------------------
# ECR Repositories
#------------------------------------------------------------------------------

resource "aws_ecr_repository" "main" {
  for_each = local.repositories

  name                 = local.repository_full_names[each.key]
  image_tag_mutability = var.image_tag_mutability

  # Image scanning configuration
  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  # Encryption configuration
  encryption_configuration {
    encryption_type = var.encryption_type
    kms_key         = var.encryption_type == "KMS" ? var.kms_key_arn : null
  }

  tags = merge(var.tags, {
    Name        = local.repository_full_names[each.key]
    Repository  = each.key
    Environment = var.environment
  })
}

#------------------------------------------------------------------------------
# Lifecycle Policies
#------------------------------------------------------------------------------

resource "aws_ecr_lifecycle_policy" "main" {
  for_each = local.repositories

  repository = aws_ecr_repository.main[each.key].name

  policy = jsonencode({
    rules = concat(
      # Rule 1: Keep last N tagged images
      [
        {
          rulePriority = 1
          description  = "Keep last ${var.lifecycle_keep_count} images"
          selection = {
            tagStatus     = "tagged"
            tagPrefixList = var.lifecycle_tagged_prefixes
            countType     = "imageCountMoreThan"
            countNumber   = var.lifecycle_keep_count
          }
          action = {
            type = "expire"
          }
        }
      ],
      # Rule 2: Expire untagged images after N days
      [
        {
          rulePriority = 2
          description  = "Expire untagged images after ${var.lifecycle_expire_untagged_days} days"
          selection = {
            tagStatus   = "untagged"
            countType   = "sinceImagePushed"
            countUnit   = "days"
            countNumber = var.lifecycle_expire_untagged_days
          }
          action = {
            type = "expire"
          }
        }
      ],
      # Rule 3: Clean up old dev/feature tags (non-prod only)
      var.environment != "prod" ? [
        {
          rulePriority = 3
          description  = "Expire old dev/feature images after 7 days"
          selection = {
            tagStatus     = "tagged"
            tagPrefixList = ["dev-", "feature-", "pr-", "branch-"]
            countType     = "sinceImagePushed"
            countUnit     = "days"
            countNumber   = 7
          }
          action = {
            type = "expire"
          }
        }
      ] : []
    )
  })
}

#------------------------------------------------------------------------------
# Cross-Region Replication (DR)
#------------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

# Replication configuration (applied at registry level)
resource "aws_ecr_replication_configuration" "main" {
  count = var.enable_replication && length(var.replication_regions) > 0 ? 1 : 0

  replication_configuration {
    rule {
      # Cross-region replication
      dynamic "destination" {
        for_each = var.replication_regions
        content {
          region      = destination.value
          registry_id = data.aws_caller_identity.current.account_id
        }
      }

      # Cross-account replication (if configured)
      dynamic "destination" {
        for_each = var.replication_account_ids
        content {
          region      = var.region
          registry_id = destination.value
        }
      }

      # Repository filter - replicate all repositories with our prefix
      repository_filter {
        filter      = "${var.project_name}-${var.environment}"
        filter_type = "PREFIX_MATCH"
      }
    }
  }
}

#------------------------------------------------------------------------------
# Repository Policies (Per-Repository Access Control)
#------------------------------------------------------------------------------

resource "aws_ecr_repository_policy" "main" {
  for_each = length(var.push_principals) > 0 || length(var.pull_principals) > 0 || (var.enable_replication && length(var.replication_account_ids) > 0) ? local.repositories : {}

  repository = aws_ecr_repository.main[each.key].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      # Push access for CI/CD and developers
      length(var.push_principals) > 0 ? [
        {
          Sid    = "AllowPush"
          Effect = "Allow"
          Principal = {
            AWS = var.push_principals
          }
          Action = [
            "ecr:GetDownloadUrlForLayer",
            "ecr:BatchGetImage",
            "ecr:BatchCheckLayerAvailability",
            "ecr:PutImage",
            "ecr:InitiateLayerUpload",
            "ecr:UploadLayerPart",
            "ecr:CompleteLayerUpload"
          ]
        }
      ] : [],

      # Pull access for EKS and services
      length(var.pull_principals) > 0 ? [
        {
          Sid    = "AllowPull"
          Effect = "Allow"
          Principal = {
            AWS = var.pull_principals
          }
          Action = [
            "ecr:GetDownloadUrlForLayer",
            "ecr:BatchGetImage",
            "ecr:BatchCheckLayerAvailability"
          ]
        }
      ] : [],

      # Cross-account pull access for DR
      var.enable_replication && length(var.replication_account_ids) > 0 ? [
        {
          Sid    = "AllowCrossAccountPull"
          Effect = "Allow"
          Principal = {
            AWS = [for account_id in var.replication_account_ids : "arn:aws:iam::${account_id}:root"]
          }
          Action = [
            "ecr:GetDownloadUrlForLayer",
            "ecr:BatchGetImage",
            "ecr:BatchCheckLayerAvailability"
          ]
        }
      ] : []
    )
  })
}

#------------------------------------------------------------------------------
# IAM Policy for GitHub Actions (Push Access)
#------------------------------------------------------------------------------

resource "aws_iam_policy" "github_actions_ecr" {
  count = var.create_github_actions_policy && length(var.repository_names) > 0 ? 1 : 0

  name        = "${var.project_name}-${var.environment}-ecr-push"
  description = "Policy for GitHub Actions to push images to ECR"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECRAuth"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Sid    = "ECRPush"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:DescribeRepositories",
          "ecr:DescribeImages",
          "ecr:ListImages"
        ]
        Resource = [for key, repo in aws_ecr_repository.main : repo.arn]
      }
    ]
  })

  tags = var.tags
}

# Attach policy to GitHub Actions role if provided
resource "aws_iam_role_policy_attachment" "github_actions_ecr" {
  count = var.create_github_actions_policy && var.github_actions_role_arn != "" && length(var.repository_names) > 0 ? 1 : 0

  role       = split("/", var.github_actions_role_arn)[1]
  policy_arn = aws_iam_policy.github_actions_ecr[0].arn
}

#------------------------------------------------------------------------------
# IAM Policy for EKS Nodes (Pull Access)
#------------------------------------------------------------------------------

resource "aws_iam_policy" "eks_ecr_pull" {
  count = var.eks_node_role_arn != "" && length(var.repository_names) > 0 ? 1 : 0

  name        = "${var.project_name}-${var.environment}-ecr-pull"
  description = "Policy for EKS nodes to pull images from ECR"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECRAuth"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Sid    = "ECRPull"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:DescribeRepositories",
          "ecr:DescribeImages",
          "ecr:ListImages"
        ]
        Resource = [for key, repo in aws_ecr_repository.main : repo.arn]
      }
    ]
  })

  tags = var.tags
}

# Attach policy to EKS node role if provided
resource "aws_iam_role_policy_attachment" "eks_ecr_pull" {
  count = var.eks_node_role_arn != "" && length(var.repository_names) > 0 ? 1 : 0

  role       = split("/", var.eks_node_role_arn)[1]
  policy_arn = aws_iam_policy.eks_ecr_pull[0].arn
}
