# ==========================================
# Karpenter - Just-in-Time Node Provisioning
# ==========================================
# Ref: https://dev.to/aws-builders/navigating-aws-eks-with-terraform-configuring-karpenter-for-just-in-time-node-provisioning-5g45
# Karpenter provisions nodes dynamically based on pod requirements.
# Deploy only when cluster exists. EC2NodeClass uses existing EKS node instance profile.
# ==========================================

# SQS Queue for Karpenter spot interruption handling
resource "aws_sqs_queue" "karpenter" {
  count                     = var.create_eks && var.cluster_exists ? 1 : 0
  name                      = "${local.cluster_name}-karpenter-interruption"
  tags                      = merge(var.tags, { "karpenter.sh/cluster" = local.cluster_name })
  message_retention_seconds = 300
  receive_wait_time_seconds = 20
}

resource "aws_sqs_queue_policy" "karpenter" {
  count     = var.create_eks && var.cluster_exists ? 1 : 0
  queue_url = aws_sqs_queue.karpenter[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "events.amazonaws.com" }
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.karpenter[0].arn
      },
      {
        Effect    = "Allow"
        Principal = { Service = "sqs.amazonaws.com" }
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.karpenter[0].arn
      }
    ]
  })
}

# EventBridge rule for EC2 Spot Instance Interruption Warning
resource "aws_cloudwatch_event_rule" "karpenter_interruption" {
  count = var.create_eks && var.cluster_exists ? 1 : 0
  name  = "${local.cluster_name}-karpenter-interruption"
  tags  = var.tags
  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Spot Instance Interruption Warning"]
  })
}

resource "aws_cloudwatch_event_target" "karpenter_interruption" {
  count = var.create_eks && var.cluster_exists ? 1 : 0
  rule  = aws_cloudwatch_event_rule.karpenter_interruption[0].name
  arn   = aws_sqs_queue.karpenter[0].arn
}

# IAM policy for Karpenter controller (scoped to cluster; uses existing instance profile)
resource "aws_iam_role_policy" "karpenter_controller" {
  count = var.create_eks && var.cluster_exists ? 1 : 0
  name  = "${local.cluster_name}-karpenter-controller"
  role  = module.eks[0].karpenter_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowScopedEC2InstanceActions"
        Effect = "Allow"
        Action = [
          "ec2:RunInstances",
          "ec2:CreateFleet"
        ]
        Resource = [
          "arn:aws:ec2:${var.region}::image/*",
          "arn:aws:ec2:${var.region}::snapshot/*",
          "arn:aws:ec2:${var.region}:*:security-group/*",
          "arn:aws:ec2:${var.region}:*:subnet/*"
        ]
      },
      {
        Sid    = "AllowScopedEC2LaunchTemplateActions"
        Effect = "Allow"
        Action = [
          "ec2:RunInstances",
          "ec2:CreateFleet"
        ]
        Resource = "arn:aws:ec2:${var.region}:*:launch-template/*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/karpenter.sh/cluster" = local.cluster_name
          }
        }
      },
      {
        Sid    = "AllowScopedEC2InstanceActionsWithTags"
        Effect = "Allow"
        Action = [
          "ec2:RunInstances",
          "ec2:CreateFleet",
          "ec2:CreateLaunchTemplate"
        ]
        Resource = [
          "arn:aws:ec2:${var.region}:*:fleet/*",
          "arn:aws:ec2:${var.region}:*:instance/*",
          "arn:aws:ec2:${var.region}:*:volume/*",
          "arn:aws:ec2:${var.region}:*:network-interface/*",
          "arn:aws:ec2:${var.region}:*:launch-template/*",
          "arn:aws:ec2:${var.region}:*:spot-instances-request/*"
        ]
        Condition = {
          StringEquals = {
            "aws:RequestTag/karpenter.sh/cluster" = local.cluster_name
          }
        }
      },
      {
        Sid    = "AllowScopedResourceCreationTagging"
        Effect = "Allow"
        Action = "ec2:CreateTags"
        Resource = [
          "arn:aws:ec2:${var.region}:*:fleet/*",
          "arn:aws:ec2:${var.region}:*:instance/*",
          "arn:aws:ec2:${var.region}:*:volume/*",
          "arn:aws:ec2:${var.region}:*:network-interface/*",
          "arn:aws:ec2:${var.region}:*:launch-template/*",
          "arn:aws:ec2:${var.region}:*:spot-instances-request/*"
        ]
        Condition = {
          StringEquals = {
            "aws:RequestTag/karpenter.sh/cluster" = local.cluster_name
          }
          "ForAnyValue:StringEquals" = {
            "ec2:CreateAction" = [
              "RunInstances",
              "CreateFleet",
              "CreateLaunchTemplate"
            ]
          }
        }
      },
      {
        Sid      = "AllowScopedResourceTagging"
        Effect   = "Allow"
        Action   = "ec2:CreateTags"
        Resource = "arn:aws:ec2:${var.region}:*:instance/*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/karpenter.sh/cluster" = local.cluster_name
          }
          StringLike = {
            "aws:RequestTag/karpenter.sh/nodepool" = "*"
          }
          "ForAllValues:StringEquals" = {
            "aws:TagKeys" = [
              "karpenter.sh/nodeclaim",
              "Name"
            ]
          }
        }
      },
      {
        Sid    = "AllowScopedDeletion"
        Effect = "Allow"
        Action = [
          "ec2:TerminateInstances",
          "ec2:DeleteLaunchTemplate"
        ]
        Resource = [
          "arn:aws:ec2:${var.region}:*:instance/*",
          "arn:aws:ec2:${var.region}:*:launch-template/*"
        ]
        Condition = {
          StringEquals = {
            "aws:ResourceTag/karpenter.sh/cluster" = local.cluster_name
          }
        }
      },
      {
        Sid    = "AllowRegionalReadActions"
        Effect = "Allow"
        Action = [
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeImages",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceTypeOfferings",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSpotPriceHistory",
          "ec2:DescribeSubnets"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.region
          }
        }
      },
      {
        Sid      = "AllowSSMReadActions"
        Effect   = "Allow"
        Action   = "ssm:GetParameter"
        Resource = "arn:aws:ssm:${var.region}::parameter/aws/service/*"
      },
      {
        Sid      = "AllowPricingReadActions"
        Effect   = "Allow"
        Action   = "pricing:GetProducts"
        Resource = "*"
      },
      {
        Sid    = "AllowInterruptionQueueActions"
        Effect = "Allow"
        Action = [
          "sqs:DeleteMessage",
          "sqs:GetQueueUrl",
          "sqs:ReceiveMessage"
        ]
        Resource = aws_sqs_queue.karpenter[0].arn
      },
      {
        Sid      = "AllowPassingInstanceRole"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = module.eks[0].node_role_arn
      },
      {
        Sid      = "AllowInstanceProfileRead"
        Effect   = "Allow"
        Action   = "iam:GetInstanceProfile"
        Resource = "*"
      },
      {
        Sid    = "AllowEKSClusterAccess"
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster"
        ]
        Resource = module.eks[0].cluster_arn
      }
    ]
  })
}

# Helm release - Karpenter
resource "helm_release" "karpenter" {
  count = var.create_eks && var.cluster_exists ? 1 : 0

  name             = "karpenter"
  repository       = "oci://public.ecr.aws/karpenter"
  chart            = "karpenter"
  version          = "1.5.0"
  namespace        = "karpenter"
  create_namespace = true
  timeout          = 900
  wait             = false
  wait_for_jobs    = false

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.eks[0].karpenter_role_arn
  }
  set {
    name  = "settings.clusterName"
    value = local.cluster_name
  }
  set {
    name  = "settings.defaultInstanceProfile"
    value = module.eks[0].node_instance_profile_name
  }
  set {
    name  = "settings.interruptionQueue"
    value = aws_sqs_queue.karpenter[0].name
  }

  depends_on = [
    module.eks,
    aws_iam_role_policy.karpenter_controller[0],
    aws_eks_access_policy_association.cluster_scoped,
  ]
}

# EC2NodeClass - default (subnets/SG via karpenter.sh/discovery)
# Karpenter 1.5 uses v1 API only. Ref: https://docs.aws.amazon.com/eks/latest/best-practices/karpenter.html
resource "kubectl_manifest" "karpenter_nodeclass" {
  count = var.create_eks && var.cluster_exists ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "karpenter.k8s.aws/v1"
    kind       = "EC2NodeClass"
    metadata   = { name = "default" }
    spec = {
      amiFamily = "AL2"
      # v1 requires amiSelectorTerms. Pin alias in prod, e.g. al2@v20240807 (see AWS Karpenter best practices).
      amiSelectorTerms           = [{ alias = "al2@latest" }]
      instanceProfile            = module.eks[0].node_instance_profile_name
      subnetSelectorTerms        = [{ tags = { "karpenter.sh/discovery" = local.cluster_name } }]
      securityGroupSelectorTerms = [{ tags = { "karpenter.sh/discovery" = local.cluster_name } }]
    }
  })

  depends_on = [helm_release.karpenter[0]]
}

# NodePool - default (spot + on-demand, instance types, limits)
# nodeClassRef uses group/kind/name per v1 API and AWS best practices.
resource "kubectl_manifest" "karpenter_nodepool" {
  count = var.create_eks && var.cluster_exists ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata   = { name = "default" }
    spec = {
      template = {
        metadata = { labels = { "intent" = "apps" } }
        spec = {
          nodeClassRef = {
            group = "karpenter.k8s.aws"
            kind  = "EC2NodeClass"
            name  = "default"
          }
          expireAfter = "Never"
          requirements = [
            { key = "karpenter.sh/capacity-type", operator = "In", values = ["spot", "on-demand"] },
            { key = "kubernetes.io/arch", operator = "In", values = ["amd64"] },
            { key = "kubernetes.io/os", operator = "In", values = ["linux"] },
            { key = "node.kubernetes.io/instance-type", operator = "In", values = ["m5.large", "m5.xlarge", "m5.2xlarge", "c5.large", "c5.xlarge", "c5.2xlarge"] }
          ]
        }
      }
      limits = { cpu = "1000", memory = "1000Gi" }
      disruption = {
        consolidationPolicy = "WhenEmptyOrUnderutilized"
        consolidateAfter    = "1m"
      }
    }
  })

  depends_on = [helm_release.karpenter[0], kubectl_manifest.karpenter_nodeclass[0]]
}
