# EKS Cluster with Auto Mode
resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  version  = var.kubernetes_version
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids              = concat(var.private_subnet_ids, var.public_subnet_ids)
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = var.cluster_endpoint_public_access_cidrs
    security_group_ids      = [aws_security_group.cluster.id]
  }

  # Access configuration - Required for EKS Auto Mode
  # Must be API_AND_CONFIG_MAP or API when Auto Mode is enabled
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  # EKS Auto Mode Configuration
  # When Auto Mode is enabled with node_pools, node_role_arn is required
  # Reference: https://docs.aws.amazon.com/eks/latest/userguide/automode.html
  compute_config {
    enabled       = true
    node_pools    = ["general-purpose", "system"] # Auto Mode managed node pools
    node_role_arn = aws_iam_role.node.arn
  }

  # When Auto Mode is enabled, bootstrapSelfManagedAddons must be false
  bootstrap_self_managed_addons = false

  kubernetes_network_config {
    elastic_load_balancing {
      enabled = true # Enable ALB/NLB integration
    }
  }

  storage_config {
    block_storage {
      enabled = true # Enable EBS CSI driver auto-provisioning
    }
  }

  # Encryption of secrets in etcd
  encryption_config {
    provider {
      key_arn = aws_kms_key.eks.arn
    }
    resources = ["secrets"]
  }

  # Enable logging
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  depends_on = [
    # Cluster IAM policies
    aws_iam_role_policy_attachment.cluster_AmazonEKSClusterPolicy,
    # EKS Auto Mode required policies
    aws_iam_role_policy_attachment.cluster_AmazonEKSComputePolicy,
    aws_iam_role_policy_attachment.cluster_AmazonEKSBlockStoragePolicy,
    aws_iam_role_policy_attachment.cluster_AmazonEKSLoadBalancingPolicy,
    aws_iam_role_policy_attachment.cluster_AmazonEKSNetworkingPolicy,
    aws_cloudwatch_log_group.cluster,
    # Node role and instance profile must exist before cluster creation (required for Auto Mode)
    aws_iam_role.node,
    aws_iam_instance_profile.node,
    aws_iam_role_policy_attachment.node_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.node_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.node_AmazonEC2ContainerRegistryReadOnly,
  ]

  tags = var.tags

  # Lifecycle rules for cluster replacement
  # - Destroy existing cluster before creating new one (not create_before_destroy)
  # - Replace if IAM roles change (ensures proper permissions on new cluster)
  # lifecycle {
  #   create_before_destroy = false

    # # Force replacement if these critical resources change
    # replace_triggered_by = [
    #   aws_iam_role.cluster.arn,
    #   aws_iam_role.node.arn,
    #   aws_iam_instance_profile.node.arn,
    # ]
  # }
}


# KMS key for EKS encryption
resource "aws_kms_key" "eks" {
  description             = "EKS Secret Encryption Key"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-eks-key"
  })
}

resource "aws_kms_alias" "eks" {
  name          = "alias/${var.cluster_name}-eks-key"
  target_key_id = aws_kms_key.eks.key_id
}

# CloudWatch Log Group for EKS cluster logs
resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = 30

  tags = var.tags
}

# IAM role for EKS cluster
resource "aws_iam_role" "cluster" {
  name = "${var.cluster_name}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster.name
}

# ==========================================
# EKS Auto Mode Required Policies
# ==========================================
# These AWS managed policies are required for EKS Auto Mode to:
# - Provision and manage EC2 instances (Compute)
# - Provision and attach EBS volumes (BlockStorage)
# - Create and manage ALB/NLB load balancers (LoadBalancing)
# - Manage VPC networking and ENIs (Networking)

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSComputePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSComputePolicy"
  role       = aws_iam_role.cluster.name
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSBlockStoragePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSBlockStoragePolicy"
  role       = aws_iam_role.cluster.name
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSLoadBalancingPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSLoadBalancingPolicy"
  role       = aws_iam_role.cluster.name
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSNetworkingPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSNetworkingPolicy"
  role       = aws_iam_role.cluster.name
}

# Additional IAM policy for EKS cluster to work with Auto Mode
resource "aws_iam_role_policy" "cluster_auto_mode" {
  name = "${var.cluster_name}-auto-mode-policy"
  role = aws_iam_role.cluster.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EC2NetworkingPermissions"
        Effect = "Allow"
        Action = [
          # Network interface management
          "ec2:CreateNetworkInterface",
          "ec2:DeleteNetworkInterface",
          "ec2:AttachNetworkInterface",
          "ec2:DetachNetworkInterface",
          "ec2:ModifyNetworkInterfaceAttribute",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeSubnets",
          "ec2:DescribeVpcs",
          "ec2:DescribeRouteTables",
          "ec2:DescribeSecurityGroups",
          # Auto Scaling permissions
          "autoscaling:*",
          "application-autoscaling:*",
          # EKS Auto Mode specific permissions
          "eks:CreateNodepool",
          "eks:DeleteNodepool",
          "eks:DescribeNodepool",
          "eks:ListNodepools",
          "eks:UpdateNodepool",
          "eks:TagResource",
          "eks:UntagResource",
          # Additional EC2 permissions for Auto Mode
          "ec2:CreateTags",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeLaunchTemplateVersions",
          "ec2:RunInstances",
          "ec2:TerminateInstances",
          # IAM permissions for service-linked roles
          "iam:CreateServiceLinkedRole",
          "iam:PassRole"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = [
          "arn:aws:iam::*:role/aws-service-role/eks-nodepool.amazonaws.com/AWSServiceRoleForAmazonEKSNodepool",
          "arn:aws:iam::*:role/aws-service-role/compute.eks.amazonaws.com/AWSServiceRoleForAmazonEKSComputeManagement"
        ]
      }
    ]
  })
}

# Security Group for EKS Cluster
resource "aws_security_group" "cluster" {
  name_prefix = "${var.cluster_name}-cluster-sg"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr_block]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-cluster-sg"
  })
}

# Security Group for worker nodes
resource "aws_security_group" "node" {
  name_prefix = "${var.cluster_name}-node-sg"
  vpc_id      = var.vpc_id

  ingress {
    description = "Node to node"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    self        = true
  }

  ingress {
    description     = "Control plane to nodes"
    from_port       = 1025
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.cluster.id]
  }

  ingress {
    description     = "Control plane to nodes (HTTPS)"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.cluster.id]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-node-sg"
  })
}

# Security Group rule to allow control plane to communicate with nodes
resource "aws_security_group_rule" "cluster_to_nodes" {
  description              = "Control plane to nodes"
  from_port                = 1025
  protocol                 = "tcp"
  security_group_id        = aws_security_group.cluster.id
  source_security_group_id = aws_security_group.node.id
  to_port                  = 65535
  type                     = "egress"
}

# ==========================================
# NOTE: Manual node group REMOVED
# ==========================================
# When EKS Auto Mode is enabled (compute_config.enabled = true with node_pools),
# AWS automatically manages node groups. Creating manual aws_eks_node_group
# resources will conflict with Auto Mode.
#
# Auto Mode handles:
# - Node provisioning and scaling
# - Instance type selection
# - Node upgrades and patching
# - Security configuration
#
# Reference: https://docs.aws.amazon.com/eks/latest/userguide/automode.html
# ==========================================

# IAM role for EKS Node Group
resource "aws_iam_role" "node" {
  name = "${var.cluster_name}-eks-node-role"

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })

  tags = var.tags
}

# Instance profile for EKS nodes (required for EKS Auto Mode)
# EKS Auto Mode NodeClass references this to launch EC2 instances
resource "aws_iam_instance_profile" "node" {
  name = "${var.cluster_name}-eks-node-role"
  role = aws_iam_role.node.name

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-eks-node-instance-profile"
  })
}

resource "aws_iam_role_policy_attachment" "node_AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node.name
}

resource "aws_iam_role_policy_attachment" "node_AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node.name
}

resource "aws_iam_role_policy_attachment" "node_AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.node.name
}

# EBS CSI Driver policy (required for Auto Mode with persistent volumes)
resource "aws_iam_role_policy_attachment" "node_AmazonEBSCSIDriverPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  role       = aws_iam_role.node.name
}

# Additional IAM policy for Auto Scaling, CloudWatch, and EBS CSI
resource "aws_iam_role_policy" "node_auto_scaling" {
  name = "${var.cluster_name}-node-auto-scaling"
  role = aws_iam_role.node.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          # Auto Scaling permissions
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:DescribeLaunchConfigurations",
          "autoscaling:DescribeTags",
          "autoscaling:SetDesiredCapacity",
          "autoscaling:TerminateInstanceInAutoScalingGroup",
          "ec2:DescribeLaunchTemplateVersions",
          # CloudWatch permissions
          "cloudwatch:PutMetricData",
          # EBS CSI driver permissions (required for Auto Mode)
          "ec2:AttachVolume",
          "ec2:CreateSnapshot",
          "ec2:CreateTags",
          "ec2:CreateVolume",
          "ec2:DeleteSnapshot",
          "ec2:DeleteTags",
          "ec2:DeleteVolume",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeInstances",
          "ec2:DescribeSnapshots",
          "ec2:DescribeTags",
          "ec2:DescribeVolumes",
          "ec2:DescribeVolumesModifications",
          "ec2:DetachVolume",
          "ec2:ModifyVolume",
          # VPC CNI advanced permissions for Auto Mode
          "ec2:AssignPrivateIpAddresses",
          "ec2:CreateNetworkInterface",
          "ec2:DeleteNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeSubnets",
          "ec2:DescribeVpcs",
          "ec2:ModifyNetworkInterfaceAttribute",
          "ec2:UnassignPrivateIpAddresses"
        ]
        Resource = "*"
      }
    ]
  })
}

# OIDC Identity provider
data "tls_certificate" "cluster" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "cluster" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.cluster.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-eks-irsa"
  })
}

# ==========================================
# Service-Linked Roles
# ==========================================
# NOTE: Service-linked roles for EKS Auto Mode are automatically created by AWS
# when the cluster is created. We do NOT need to create them manually.
# 
# AWS automatically creates:
# - AWSServiceRoleForAmazonEKS (for cluster management)
# - Any additional roles needed for Auto Mode
#
# Attempting to create them manually will fail with "not a valid AWS service name"
# Reference: https://docs.aws.amazon.com/eks/latest/userguide/using-service-linked-roles.html
# ==========================================