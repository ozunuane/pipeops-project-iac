# ====================================================================
# AWS Backup for EKS
# ====================================================================
# Automated backups of EKS cluster resources and persistent volumes
# Schedule: Daily at 6:00 AM UTC

# Enable AWS Backup for EKS only when cluster exists
resource "aws_backup_vault" "eks" {
  count = var.cluster_exists && var.enable_eks_backup ? 1 : 0

  name        = "${var.project_name}-${var.environment}-eks-backup-vault"
  kms_key_arn = aws_kms_key.backup[0].arn

  tags = {
    Name        = "${var.project_name}-${var.environment}-eks-backup-vault"
    Environment = var.environment
    Purpose     = "EKS cluster backups"
  }
}

# KMS key for backup encryption
resource "aws_kms_key" "backup" {
  count = var.cluster_exists && var.enable_eks_backup ? 1 : 0

  description             = "KMS key for AWS Backup encryption - ${var.project_name}-${var.environment}"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = {
    Name        = "${var.project_name}-${var.environment}-backup-kms"
    Environment = var.environment
  }
}

resource "aws_kms_alias" "backup" {
  count = var.cluster_exists && var.enable_eks_backup ? 1 : 0

  name          = "alias/${var.project_name}-${var.environment}-backup"
  target_key_id = aws_kms_key.backup[0].key_id
}

# Backup plan - Daily at 6:00 AM UTC
resource "aws_backup_plan" "eks_daily" {
  count = var.cluster_exists && var.enable_eks_backup ? 1 : 0

  name = "${var.project_name}-${var.environment}-eks-daily-backup"

  # Daily backup rule
  rule {
    rule_name         = "daily-6am-backup"
    target_vault_name = aws_backup_vault.eks[0].name
    schedule          = var.backup_schedule # Default: "cron(0 6 * * ? *)" = 6:00 AM UTC daily

    # Lifecycle settings
    lifecycle {
      cold_storage_after = var.backup_cold_storage_after # Move to cold storage after N days
      delete_after       = var.backup_retention_days     # Delete after N days
    }

    # Copy to DR region (if enabled)
    dynamic "copy_action" {
      for_each = var.enable_backup_cross_region_copy ? [1] : []
      content {
        destination_vault_arn = aws_backup_vault.eks_dr[0].arn
        lifecycle {
          cold_storage_after = var.backup_cold_storage_after
          delete_after       = var.backup_retention_days
        }
      }
    }

    # Recovery point tags
    recovery_point_tags = {
      Environment = var.environment
      BackupType  = "daily"
      ManagedBy   = "aws-backup"
    }
  }

  # Weekly backup rule (Sundays at 6 AM)
  rule {
    rule_name         = "weekly-sunday-backup"
    target_vault_name = aws_backup_vault.eks[0].name
    schedule          = "cron(0 6 ? * SUN *)" # 6:00 AM UTC every Sunday

    lifecycle {
      cold_storage_after = 30  # Move to cold storage after 30 days
      delete_after       = 90  # Keep weekly backups for 90 days
    }

    recovery_point_tags = {
      Environment = var.environment
      BackupType  = "weekly"
      ManagedBy   = "aws-backup"
    }
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-eks-backup-plan"
    Environment = var.environment
  }
}

# Backup selection - What to backup
resource "aws_backup_selection" "eks" {
  count = var.cluster_exists && var.enable_eks_backup ? 1 : 0

  name         = "${var.project_name}-${var.environment}-eks-backup-selection"
  plan_id      = aws_backup_plan.eks_daily[0].id
  iam_role_arn = aws_iam_role.backup[0].arn

  # Backup the EKS cluster
  resources = [
    module.eks.cluster_arn
  ]

  # Additional selection by tags (backup all resources with these tags)
  selection_tag {
    type  = "STRINGEQUALS"
    key   = "kubernetes.io/cluster/${local.cluster_name}"
    value = "owned"
  }
}

# IAM role for AWS Backup
resource "aws_iam_role" "backup" {
  count = var.cluster_exists && var.enable_eks_backup ? 1 : 0

  name = "${var.project_name}-${var.environment}-aws-backup-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "backup.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-${var.environment}-aws-backup-role"
    Environment = var.environment
  }
}

# Attach AWS managed policies for backup
resource "aws_iam_role_policy_attachment" "backup_policy" {
  count = var.cluster_exists && var.enable_eks_backup ? 1 : 0

  role       = aws_iam_role.backup[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_iam_role_policy_attachment" "restore_policy" {
  count = var.cluster_exists && var.enable_eks_backup ? 1 : 0

  role       = aws_iam_role.backup[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}

# Additional policy for EKS backup
resource "aws_iam_role_policy" "backup_eks" {
  count = var.cluster_exists && var.enable_eks_backup ? 1 : 0

  name = "${var.project_name}-${var.environment}-backup-eks-policy"
  role = aws_iam_role.backup[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters",
          "eks:ListNodegroups",
          "eks:DescribeNodegroup",
          "ec2:DescribeVolumes",
          "ec2:DescribeSnapshots",
          "ec2:CreateSnapshot",
          "ec2:DeleteSnapshot",
          "ec2:CreateTags",
          "ec2:DeleteTags"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey",
          "kms:CreateGrant"
        ]
        Resource = aws_kms_key.backup[0].arn
      }
    ]
  })
}

# ====================================================================
# Cross-Region Backup Vault (DR)
# ====================================================================
# Backup vault in DR region for cross-region copy

resource "aws_backup_vault" "eks_dr" {
  count    = var.cluster_exists && var.enable_eks_backup && var.enable_backup_cross_region_copy ? 1 : 0
  provider = aws.disaster_recovery

  name        = "${var.project_name}-${var.environment}-eks-backup-vault-dr"
  kms_key_arn = aws_kms_key.backup_dr[0].arn

  tags = {
    Name             = "${var.project_name}-${var.environment}-eks-backup-vault-dr"
    Environment      = var.environment
    DisasterRecovery = "true"
    Purpose          = "EKS cluster backup replication"
  }
}

resource "aws_kms_key" "backup_dr" {
  count    = var.cluster_exists && var.enable_eks_backup && var.enable_backup_cross_region_copy ? 1 : 0
  provider = aws.disaster_recovery

  description             = "KMS key for AWS Backup encryption (DR) - ${var.project_name}-${var.environment}"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = {
    Name             = "${var.project_name}-${var.environment}-backup-kms-dr"
    Environment      = var.environment
    DisasterRecovery = "true"
  }
}

resource "aws_kms_alias" "backup_dr" {
  count    = var.cluster_exists && var.enable_eks_backup && var.enable_backup_cross_region_copy ? 1 : 0
  provider = aws.disaster_recovery

  name          = "alias/${var.project_name}-${var.environment}-backup-dr"
  target_key_id = aws_kms_key.backup_dr[0].key_id
}
