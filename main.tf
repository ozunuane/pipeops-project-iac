# Configure AWS Provider (Primary Region)
provider "aws" {
  region = var.region

  default_tags {
    tags = var.tags
  }
}

# Configure AWS Provider for Disaster Recovery Region
provider "aws" {
  alias  = "disaster_recovery"
  region = var.dr_region

  default_tags {
    tags = merge(var.tags, {
      DisasterRecovery = "true"
      DRRegion         = var.dr_region
    })
  }
}

# Local values for consistent naming
locals {
  cluster_name = "${var.project_name}-${var.environment}-eks"

  # Generate a random password for the database
  db_password = random_password.db_password.result

  # Generate Grafana admin password
  grafana_admin_password = random_password.grafana_admin.result
}

# Random passwords for security
resource "random_password" "db_password" {
  length = 16
  # RDS does not allow: '/', '@', '"', or space in passwords
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "random_password" "grafana_admin" {
  length  = 16
  special = false
}

# Note: ArgoCD generates its own initial admin password in a Kubernetes secret
# Retrieve it with: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# VPC Module
module "vpc" {
  source = "./modules/vpc"

  project_name          = var.project_name
  environment           = var.environment
  region                = var.region
  vpc_cidr              = var.vpc_cidr
  availability_zones    = var.availability_zones
  public_subnet_cidrs   = var.public_subnet_cidrs
  private_subnet_cidrs  = var.private_subnet_cidrs
  database_subnet_cidrs = var.database_subnet_cidrs
  cluster_name          = local.cluster_name
  tags                  = var.tags
}

# EKS Module
module "eks" {
  source = "./modules/eks"

  cluster_name                              = local.cluster_name
  kubernetes_version                        = var.kubernetes_version
  vpc_id                                    = module.vpc.vpc_id
  vpc_cidr_block                            = module.vpc.vpc_cidr_block
  private_subnet_ids                        = module.vpc.private_subnet_ids
  public_subnet_ids                         = module.vpc.public_subnet_ids
  cluster_endpoint_public_access_cidrs      = ["0.0.0.0/0"]
  desired_capacity                          = 3
  min_capacity                              = 1
  max_capacity                              = 10
  node_instance_types                       = ["m5.large", "m5.xlarge", "m5.2xlarge"]
  enable_aws_load_balancer_controller_addon = var.enable_aws_load_balancer_controller_addon
  tags                                      = var.tags
}

# RDS Module with Multi-AZ and Read Replica support
# Note: Cross-region DR replica is now managed by the DR workspace
module "rds" {
  source = "./modules/rds"

  providers = {
    aws                   = aws
    aws.disaster_recovery = aws.disaster_recovery
  }

  project_name            = var.project_name
  environment             = var.environment
  region                  = var.region
  vpc_id                  = module.vpc.vpc_id
  db_subnet_group_name    = module.vpc.database_subnet_group_name
  allowed_security_groups = [module.eks.node_security_group_id]
  allowed_cidr_blocks     = [module.vpc.vpc_cidr_block]
  database_password       = local.db_password
  db_instance_class       = var.db_instance_class
  allocated_storage       = var.db_allocated_storage
  postgres_version        = var.db_postgres_version
  backup_retention_period = var.db_backup_retention
  deletion_protection     = var.environment == "prod" ? true : false
  skip_final_snapshot     = var.environment == "prod" ? false : true


  # High Availability Configuration
  multi_az                    = var.db_multi_az
  create_read_replica         = var.db_create_read_replica
  read_replica_count          = var.db_read_replica_count
  read_replica_instance_class = var.db_read_replica_instance_class
  replica_availability_zones  = var.db_replica_availability_zones

  # Performance Configuration
  # iops                           = var.db_iops
  performance_insights_retention = var.environment == "prod" ? 31 : 7

  # Monitoring Configuration
  sns_topic_arn     = var.db_monitoring_sns_topic_arn
  apply_immediately = var.db_apply_immediately

  # Cross-region DR replica is now managed by DR workspace
  # But cross-region backups are still managed here (no VPC dependency)
  enable_cross_region_dr      = false                              # DR replica managed by DR workspace
  enable_cross_region_backups = var.db_enable_cross_region_backups # Backups can stay here
  dr_region                   = var.dr_region
  dr_kms_key_id               = var.db_dr_kms_key_id # Optional: KMS key for backup encryption

  tags = var.tags
}

# Configure Kubernetes and Helm providers for EKS
# Use exec-based auth (aws eks get-token) so tokens stay fresh during long applies.
# Static tokens from aws_eks_cluster_auth expire ~15min and cause "credentials" errors.
provider "kubernetes" {
  host                   = var.cluster_exists ? module.eks.cluster_endpoint : "https://localhost"
  cluster_ca_certificate = var.cluster_exists ? base64decode(module.eks.cluster_certificate_authority_data) : ""
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    env = {
      AWS_REGION = var.region
    }
  }
}

provider "helm" {
  kubernetes {
    host                   = var.cluster_exists ? module.eks.cluster_endpoint : "https://localhost"
    cluster_ca_certificate = var.cluster_exists ? base64decode(module.eks.cluster_certificate_authority_data) : ""
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
      env = {
        AWS_REGION = var.region
      }
    }
  }
}

provider "kubectl" {
  host                   = var.cluster_exists ? module.eks.cluster_endpoint : "https://localhost"
  cluster_ca_certificate = var.cluster_exists ? base64decode(module.eks.cluster_certificate_authority_data) : ""
  load_config_file       = false
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    env = {
      AWS_REGION = var.region
    }
  }
}

# AWS Load Balancer Controller is installed via EKS addon (modules/eks).
# ==========================================

# Monitoring Module - Only deploy when cluster exists
module "monitoring" {
  count = var.cluster_exists && var.enable_monitoring ? 1 : 0

  source = "./modules/monitoring"

  cluster_name           = local.cluster_name
  aws_region             = var.region
  ha_mode                = var.environment == "prod" ? true : false
  enable_grafana         = true
  enable_alertmanager    = true
  enable_ingress         = false # Enable when you have proper domains and SSL certs
  grafana_domain         = "grafana.${var.project_name}.com"
  prometheus_domain      = "prometheus.${var.project_name}.com"
  alertmanager_domain    = "alertmanager.${var.project_name}.com"
  grafana_admin_password = local.grafana_admin_password
  oidc_provider_arn      = module.eks.oidc_provider_arn
  oidc_issuer_url        = module.eks.cluster_oidc_issuer_url
  tags                   = var.tags

  depends_on = [module.eks]
}

# External Secrets Operator for AWS Secrets Manager integration
# Only deploy when cluster exists
resource "helm_release" "external_secrets" {
  count = var.cluster_exists ? 1 : 0

  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = "0.9.11"
  namespace        = "external-secrets-system"
  create_namespace = true

  # Timeout for installation (EKS Auto Mode needs time to provision nodes)
  timeout = 600

  # Don't wait for pods - Auto Mode will provision nodes asynchronously
  wait          = false
  wait_for_jobs = false

  set {
    name  = "installCRDs"
    value = "true"
  }

  depends_on = [module.eks]
}

# IAM role for External Secrets Operator - Only when cluster exists
resource "aws_iam_role" "external_secrets" {
  count = var.cluster_exists ? 1 : 0
  name  = "${local.cluster_name}-external-secrets"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Federated = module.eks.oidc_provider_arn
        }
        Condition = {
          StringEquals = {
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub" : "system:serviceaccount:external-secrets-system:external-secrets"
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud" : "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = var.tags
}

# IAM policy for External Secrets Operator
resource "aws_iam_role_policy" "external_secrets" {
  count = var.cluster_exists ? 1 : 0
  name  = "${local.cluster_name}-external-secrets"
  role  = aws_iam_role.external_secrets[0].id

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
      }
    ]
  })
}

# ==========================================
# EKS ADD-ONS - REMOVED FOR AUTO MODE
# ==========================================
# When EKS Auto Mode is enabled with:
#   - compute_config.enabled = true
#   - storage_config.block_storage.enabled = true  
#   - kubernetes_network_config.elastic_load_balancing.enabled = true
#
# AWS automatically manages these add-ons:
#   - coredns
#   - kube-proxy  
#   - vpc-cni
#   - aws-ebs-csi-driver
#   - AWS Load Balancer Controller
#
# Manual creation of these add-ons will conflict with Auto Mode.
# Reference: https://docs.aws.amazon.com/eks/latest/userguide/automode.html
# ==========================================

# ==========================================
# EBS CSI DRIVER IAM - REMOVED FOR AUTO MODE
# ==========================================
# EKS Auto Mode with storage_config.block_storage.enabled = true
# automatically manages the EBS CSI driver and its IAM permissions.
# ==========================================