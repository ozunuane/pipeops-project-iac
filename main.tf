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

  # Generate ArgoCD admin password
  argocd_admin_password = random_password.argocd_admin.result

  # Generate Grafana admin password
  grafana_admin_password = random_password.grafana_admin.result
}

# Random passwords for security
resource "random_password" "db_password" {
  length  = 16
  special = true
}

resource "random_password" "argocd_admin" {
  length  = 16
  special = false
}

resource "random_password" "grafana_admin" {
  length  = 16
  special = false
}

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

  cluster_name                         = local.cluster_name
  kubernetes_version                   = var.kubernetes_version
  vpc_id                               = module.vpc.vpc_id
  vpc_cidr_block                       = module.vpc.vpc_cidr_block
  private_subnet_ids                   = module.vpc.private_subnet_ids
  public_subnet_ids                    = module.vpc.public_subnet_ids
  cluster_endpoint_public_access_cidrs = ["0.0.0.0/0"]
  desired_capacity                     = 3
  min_capacity                         = 1
  max_capacity                         = 10
  node_instance_types                  = ["m5.large", "m5.xlarge", "m5.2xlarge"]
  tags                                 = var.tags
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
  iops                           = var.db_iops
  performance_insights_retention = var.environment == "prod" ? 31 : 7

  # Monitoring Configuration
  sns_topic_arn     = var.db_monitoring_sns_topic_arn
  apply_immediately = var.db_apply_immediately

  # Cross-region DR replica is now managed by DR workspace
  # But cross-region backups are still managed here (no VPC dependency)
  enable_cross_region_dr      = false                          # DR replica managed by DR workspace
  enable_cross_region_backups = var.db_enable_cross_region_backups  # Backups can stay here
  dr_region                   = var.dr_region
  dr_kms_key_id               = var.db_dr_kms_key_id          # Optional: KMS key for backup encryption

  tags = var.tags
}

# Configure Kubernetes and Helm providers after EKS cluster is created
data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_name
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}

# AWS Load Balancer Controller
resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "1.6.2"
  namespace  = "kube-system"

  set {
    name  = "clusterName"
    value = module.eks.cluster_name
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
    value = aws_iam_role.aws_load_balancer_controller.arn
  }

  set {
    name  = "region"
    value = var.region
  }

  set {
    name  = "vpcId"
    value = module.vpc.vpc_id
  }

  depends_on = [
    module.eks,
    aws_iam_role.aws_load_balancer_controller
  ]
}

# IAM role for AWS Load Balancer Controller
resource "aws_iam_role" "aws_load_balancer_controller" {
  name = "${local.cluster_name}-aws-load-balancer-controller"

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
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub" : "system:serviceaccount:kube-system:aws-load-balancer-controller"
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud" : "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = var.tags
}

# IAM policy for AWS Load Balancer Controller
resource "aws_iam_role_policy" "aws_load_balancer_controller" {
  name = "${local.cluster_name}-aws-load-balancer-controller"
  role = aws_iam_role.aws_load_balancer_controller.id

  policy = file("${path.module}/policies/aws-load-balancer-controller-iam-policy.json")
}

# ArgoCD Module
module "argocd" {
  source = "./modules/argocd"

  cluster_name          = local.cluster_name
  argocd_domain         = "argocd.${var.project_name}.com" # Update with your domain
  admin_password        = local.argocd_admin_password
  admin_password_bcrypt = bcrypt(local.argocd_admin_password)
  server_insecure       = true # Set to false in production with proper TLS
  ha_mode               = var.environment == "prod" ? true : false
  enable_metrics        = var.enable_monitoring
  enable_ingress        = false # Enable when you have a proper domain and SSL cert
  oidc_provider_arn     = module.eks.oidc_provider_arn
  oidc_issuer_url       = module.eks.cluster_oidc_issuer_url
  tags                  = var.tags

  depends_on = [
    module.eks,
    helm_release.aws_load_balancer_controller
  ]
}

# Monitoring Module
module "monitoring" {
  count = var.enable_monitoring ? 1 : 0

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

  depends_on = [
    module.eks,
    helm_release.aws_load_balancer_controller
  ]
}

# External Secrets Operator for AWS Secrets Manager integration
resource "helm_release" "external_secrets" {
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

  depends_on = [
    module.eks
  ]
}

# IAM role for External Secrets Operator
resource "aws_iam_role" "external_secrets" {
  name = "${local.cluster_name}-external-secrets"

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
  name = "${local.cluster_name}-external-secrets"
  role = aws_iam_role.external_secrets.id

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

# Create EKS add-ons
resource "aws_eks_addon" "coredns" {
  cluster_name                = module.eks.cluster_name
  addon_name                  = "coredns"
  addon_version               = "v1.10.1-eksbuild.5"
  resolve_conflicts_on_create = "OVERWRITE"

  depends_on = [module.eks]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = module.eks.cluster_name
  addon_name                  = "kube-proxy"
  addon_version               = "v1.28.2-eksbuild.2"
  resolve_conflicts_on_create = "OVERWRITE"

  depends_on = [module.eks]
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = module.eks.cluster_name
  addon_name                  = "vpc-cni"
  addon_version               = "v1.15.4-eksbuild.1"
  resolve_conflicts_on_create = "OVERWRITE"

  depends_on = [module.eks]
}

resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name                = module.eks.cluster_name
  addon_name                  = "aws-ebs-csi-driver"
  addon_version               = "v1.25.0-eksbuild.1"
  resolve_conflicts_on_create = "OVERWRITE"
  service_account_role_arn    = aws_iam_role.ebs_csi_driver.arn

  depends_on = [module.eks]
}

# IAM role for EBS CSI driver
resource "aws_iam_role" "ebs_csi_driver" {
  name = "${local.cluster_name}-ebs-csi-driver"

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
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub" : "system:serviceaccount:kube-system:ebs-csi-controller-sa"
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud" : "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ebs_csi_driver" {
  role       = aws_iam_role.ebs_csi_driver.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/Amazon_EBS_CSI_DriverPolicy"
}