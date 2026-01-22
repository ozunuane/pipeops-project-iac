# ====================================================================
# DISASTER RECOVERY INFRASTRUCTURE - STANDALONE WORKSPACE
# ====================================================================
# This is a completely separate Terraform workspace for DR infrastructure
# 
# Purpose: Provides isolated DR infrastructure management
# Region: Configured via var.dr_region (default: us-east-1)
# Deployment: Independent from primary infrastructure
# State: Separate Terraform state in S3
# ====================================================================

# Configure AWS Provider for DR Region
provider "aws" {
  region = var.dr_region

  default_tags {
    tags = merge(var.tags, {
      DisasterRecovery = "true"
      DRRegion         = var.dr_region
      Workspace        = "dr"
    })
  }
}

# Local values for consistent naming
locals {
  dr_cluster_name = "${var.project_name}-${var.primary_environment}-dr-eks"
  
  # Reference to primary region for cross-region resources
  primary_region = var.primary_region
}

# ====================================================================
# DR VPC Module
# ====================================================================
# Creates a complete VPC infrastructure in the DR region

module "dr_vpc" {
  source = "../modules/vpc"

  project_name          = var.project_name
  environment           = "${var.primary_environment}-dr"
  region                = var.dr_region
  vpc_cidr              = var.dr_vpc_cidr
  availability_zones    = var.dr_availability_zones
  public_subnet_cidrs   = var.dr_public_subnet_cidrs
  private_subnet_cidrs  = var.dr_private_subnet_cidrs
  database_subnet_cidrs = var.dr_database_subnet_cidrs
  cluster_name          = local.dr_cluster_name
  
  tags = merge(var.tags, {
    DisasterRecovery = "true"
    DRRegion         = var.dr_region
    DRPurpose        = "standby-cluster"
    PrimaryRegion    = var.primary_region
  })
}

# ====================================================================
# DR EKS Cluster Module
# ====================================================================
# Creates a standby EKS cluster in the DR region

module "dr_eks" {
  source = "../modules/eks"

  cluster_name                         = local.dr_cluster_name
  kubernetes_version                   = var.kubernetes_version
  vpc_id                               = module.dr_vpc.vpc_id
  vpc_cidr_block                       = module.dr_vpc.vpc_cidr_block
  private_subnet_ids                   = module.dr_vpc.private_subnet_ids
  public_subnet_ids                    = module.dr_vpc.public_subnet_ids
  cluster_endpoint_public_access_cidrs = var.dr_cluster_endpoint_public_access_cidrs

  # DR Cluster Sizing (Cost-optimized for standby)
  desired_capacity    = var.dr_desired_capacity
  min_capacity        = var.dr_min_capacity
  max_capacity        = var.dr_max_capacity
  node_instance_types = var.dr_node_instance_types

  tags = merge(var.tags, {
    DisasterRecovery = "true"
    DRRegion         = var.dr_region
    DRPurpose        = "standby-cluster"
    ClusterMode      = var.dr_cluster_mode
    PrimaryRegion    = var.primary_region
  })

  depends_on = [module.dr_vpc]
}

# ====================================================================
# DR Kubernetes Provider
# ====================================================================
# Configure Kubernetes provider for DR cluster management

data "aws_eks_cluster_auth" "dr_cluster" {
  name = module.dr_eks.cluster_name
}

provider "kubernetes" {
  host                   = module.dr_eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.dr_eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.dr_cluster.token
}

provider "helm" {
  kubernetes {
    host                   = module.dr_eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.dr_eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.dr_cluster.token
  }
}

# ====================================================================
# DR AWS Load Balancer Controller
# ====================================================================

resource "helm_release" "dr_aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "1.6.2"
  namespace  = "kube-system"

  set {
    name  = "clusterName"
    value = module.dr_eks.cluster_name
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.dr_aws_load_balancer_controller.arn
  }

  set {
    name  = "region"
    value = var.dr_region
  }

  set {
    name  = "vpcId"
    value = module.dr_vpc.vpc_id
  }

  depends_on = [
    module.dr_eks,
    aws_iam_role.dr_aws_load_balancer_controller
  ]
}

# ====================================================================
# DR IAM Role for AWS Load Balancer Controller
# ====================================================================

resource "aws_iam_role" "dr_aws_load_balancer_controller" {
  name = "${local.dr_cluster_name}-aws-load-balancer-controller"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Federated = module.dr_eks.oidc_provider_arn
        }
        Condition = {
          StringEquals = {
            "${replace(module.dr_eks.cluster_oidc_issuer_url, "https://", "")}:sub" : "system:serviceaccount:kube-system:aws-load-balancer-controller"
            "${replace(module.dr_eks.cluster_oidc_issuer_url, "https://", "")}:aud" : "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = merge(var.tags, {
    DisasterRecovery = "true"
    DRRegion         = var.dr_region
  })
}

resource "aws_iam_role_policy" "dr_aws_load_balancer_controller" {
  name = "${local.dr_cluster_name}-aws-load-balancer-controller"
  role = aws_iam_role.dr_aws_load_balancer_controller.id

  policy = file("${path.module}/../policies/aws-load-balancer-controller-iam-policy.json")
}

# ====================================================================
# DR External Secrets Operator
# ====================================================================

resource "helm_release" "dr_external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = "0.9.11"
  namespace        = "external-secrets-system"
  create_namespace = true

  set {
    name  = "installCRDs"
    value = "true"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.dr_external_secrets.arn
  }

  depends_on = [
    module.dr_eks
  ]
}

# ====================================================================
# DR IAM Role for External Secrets Operator
# ====================================================================

resource "aws_iam_role" "dr_external_secrets" {
  name = "${local.dr_cluster_name}-external-secrets"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Federated = module.dr_eks.oidc_provider_arn
        }
        Condition = {
          StringEquals = {
            "${replace(module.dr_eks.cluster_oidc_issuer_url, "https://", "")}:sub" : "system:serviceaccount:external-secrets-system:external-secrets"
            "${replace(module.dr_eks.cluster_oidc_issuer_url, "https://", "")}:aud" : "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = merge(var.tags, {
    DisasterRecovery = "true"
    DRRegion         = var.dr_region
  })
}

resource "aws_iam_role_policy" "dr_external_secrets" {
  name = "${local.dr_cluster_name}-external-secrets"
  role = aws_iam_role.dr_external_secrets.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ]
        Resource = ["*"]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = ["*"]
      }
    ]
  })
}

# ====================================================================
# DR EKS Add-ons
# ====================================================================

resource "aws_eks_addon" "dr_coredns" {
  cluster_name                = module.dr_eks.cluster_name
  addon_name                  = "coredns"
  addon_version               = "v1.10.1-eksbuild.5"
  resolve_conflicts_on_create = "OVERWRITE"

  depends_on = [module.dr_eks]
}

resource "aws_eks_addon" "dr_kube_proxy" {
  cluster_name                = module.dr_eks.cluster_name
  addon_name                  = "kube-proxy"
  addon_version               = "v1.28.2-eksbuild.2"
  resolve_conflicts_on_create = "OVERWRITE"

  depends_on = [module.dr_eks]
}

resource "aws_eks_addon" "dr_vpc_cni" {
  cluster_name                = module.dr_eks.cluster_name
  addon_name                  = "vpc-cni"
  addon_version               = "v1.15.4-eksbuild.1"
  resolve_conflicts_on_create = "OVERWRITE"

  depends_on = [module.dr_eks]
}

resource "aws_eks_addon" "dr_ebs_csi_driver" {
  cluster_name                = module.dr_eks.cluster_name
  addon_name                  = "aws-ebs-csi-driver"
  addon_version               = "v1.25.0-eksbuild.1"
  resolve_conflicts_on_create = "OVERWRITE"
  service_account_role_arn    = aws_iam_role.dr_ebs_csi_driver.arn

  depends_on = [module.dr_eks]
}

# ====================================================================
# DR IAM Role for EBS CSI Driver
# ====================================================================

resource "aws_iam_role" "dr_ebs_csi_driver" {
  name = "${local.dr_cluster_name}-ebs-csi-driver"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Federated = module.dr_eks.oidc_provider_arn
        }
        Condition = {
          StringEquals = {
            "${replace(module.dr_eks.cluster_oidc_issuer_url, "https://", "")}:sub" : "system:serviceaccount:kube-system:ebs-csi-controller-sa"
            "${replace(module.dr_eks.cluster_oidc_issuer_url, "https://", "")}:aud" : "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = merge(var.tags, {
    DisasterRecovery = "true"
    DRRegion         = var.dr_region
  })
}

resource "aws_iam_role_policy_attachment" "dr_ebs_csi_driver" {
  role       = aws_iam_role.dr_ebs_csi_driver.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/Amazon_EBS_CSI_DriverPolicy"
}

# ====================================================================
# DR RDS Read Replica
# ====================================================================
# Cross-region read replica of the primary RDS instance
# This replica uses the DR VPC network for connectivity with DR EKS

# Security group for DR RDS replica
resource "aws_security_group" "dr_rds" {
  count = var.enable_rds_dr_replica && var.primary_rds_arn != "" ? 1 : 0

  name        = "${var.project_name}-${var.primary_environment}-rds-dr-sg"
  description = "Security group for DR RDS replica"
  vpc_id      = module.dr_vpc.vpc_id

  # Ingress from DR EKS nodes
  ingress {
    description     = "PostgreSQL from DR EKS nodes"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [module.dr_eks.node_security_group_id]
  }

  # Ingress from DR VPC CIDR
  ingress {
    description = "PostgreSQL from DR VPC"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.dr_vpc_cidr]
  }

  # Egress (allow all outbound)
  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name             = "${var.project_name}-${var.primary_environment}-rds-dr-sg"
    DisasterRecovery = "true"
    DRRegion         = var.dr_region
  })
}

# KMS key for DR RDS encryption
resource "aws_kms_key" "dr_rds" {
  count = var.enable_rds_dr_replica && var.primary_rds_arn != "" ? 1 : 0

  description             = "KMS key for DR RDS encryption in ${var.dr_region}"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = merge(var.tags, {
    Name             = "${var.project_name}-${var.primary_environment}-rds-dr-key"
    DisasterRecovery = "true"
    DRRegion         = var.dr_region
  })
}

resource "aws_kms_alias" "dr_rds" {
  count = var.enable_rds_dr_replica && var.primary_rds_arn != "" ? 1 : 0

  name          = "alias/${var.project_name}-${var.primary_environment}-rds-dr"
  target_key_id = aws_kms_key.dr_rds[0].key_id
}

# IAM role for DR RDS monitoring
resource "aws_iam_role" "dr_rds_monitoring" {
  count = var.enable_rds_dr_replica && var.primary_rds_arn != "" ? 1 : 0

  name = "${var.project_name}-${var.primary_environment}-rds-dr-monitoring"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(var.tags, {
    DisasterRecovery = "true"
    DRRegion         = var.dr_region
  })
}

resource "aws_iam_role_policy_attachment" "dr_rds_monitoring" {
  count = var.enable_rds_dr_replica && var.primary_rds_arn != "" ? 1 : 0

  role       = aws_iam_role.dr_rds_monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# DR RDS Read Replica
resource "aws_db_instance" "dr_replica" {
  count = var.enable_rds_dr_replica && var.primary_rds_arn != "" ? 1 : 0

  identifier          = "${var.project_name}-${var.primary_environment}-postgres-dr"
  replicate_source_db = var.primary_rds_arn
  instance_class      = var.dr_rds_instance_class

  # Multi-AZ in DR region for additional redundancy
  multi_az = var.dr_rds_multi_az

  # Storage encryption
  storage_encrypted = true
  kms_key_id        = aws_kms_key.dr_rds[0].arn

  # Network - Use DR VPC
  db_subnet_group_name   = module.dr_vpc.database_subnet_group_name
  vpc_security_group_ids = [aws_security_group.dr_rds[0].id]
  publicly_accessible    = false

  # Backup configuration (can be promoted to standalone)
  backup_retention_period = 30

  # Parameter and Option Groups (will be created from source)
  auto_minor_version_upgrade = true

  # Monitoring
  monitoring_interval             = 60
  monitoring_role_arn             = aws_iam_role.dr_rds_monitoring[0].arn
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  # Performance Insights
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.dr_rds[0].arn
  performance_insights_retention_period = 31

  # Snapshots
  copy_tags_to_snapshot     = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.project_name}-${var.primary_environment}-dr-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"

  # Apply changes
  apply_immediately = false

  tags = merge(var.tags, {
    Name             = "${var.project_name}-${var.primary_environment}-postgres-dr"
    DisasterRecovery = "true"
    DRRegion         = var.dr_region
    Role             = "read-replica"
    CanPromote       = "true"
  })

  depends_on = [
    module.dr_vpc,
    module.dr_eks
  ]

  lifecycle {
    ignore_changes = [
      replicate_source_db, # Ignore after promotion
      final_snapshot_identifier
    ]
  }
}
