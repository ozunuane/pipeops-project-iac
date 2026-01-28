# ==========================================
# AWS Load Balancer Controller + Gateway API
# ==========================================
# LBC via Helm (Ingress + Gateway API). Gateway API CRDs installed via script;
# GatewayClass `alb` created for L7 (ALB) HTTPRoute/GRPCRoute.
# Requires create_eks && cluster_exists && enable_aws_load_balancer_controller_addon.
# ==========================================

locals {
  _lbc_enabled = var.create_eks && var.cluster_exists && var.enable_aws_load_balancer_controller_addon
}

# Install Gateway API CRDs (standard, experimental) and LBC gateway-specific CRDs.
# Runs kubectl apply against release manifests. Pass role-arn only when use_eks_exec_role is true
# (e.g. CI); otherwise use default AWS identity (local dev) to avoid AssumeRole AccessDenied.
resource "null_resource" "gateway_api_crds" {
  count = local._lbc_enabled ? 1 : 0

  triggers = {
    cluster = local.cluster_name
    region  = var.region
  }

  provisioner "local-exec" {
    command = "chmod +x ${path.module}/scripts/install-gateway-api-crds.sh && ${path.module}/scripts/install-gateway-api-crds.sh ${local.cluster_name} ${var.region} ${local._eks_exec_arn}"
  }

  depends_on = [module.eks, aws_eks_access_policy_association.cluster_scoped]
}

# AWS Load Balancer Controller (Helm) with Gateway API feature gates.
# IngressClass `alb` + IngressGroup; ALB/NLB for Gateway API (GatewayClass alb).
# Chart 1.14.1+ required: controller v2.14+ supports ALBGatewayAPI/NLBGatewayAPI (v2.8.x does not).
resource "helm_release" "aws_load_balancer_controller" {
  count = local._lbc_enabled ? 1 : 0

  name             = "aws-load-balancer-controller"
  repository       = "https://aws.github.io/eks-charts"
  chart            = "aws-load-balancer-controller"
  version          = "1.14.1"
  namespace        = "kube-system"
  create_namespace = false

  timeout       = 600
  wait          = true
  wait_for_jobs = false

  values = [
    yamlencode({
      clusterName = local.cluster_name
      region      = var.region
      vpcId       = module.vpc.vpc_id

      image = {
        tag = "v2.14.1"
      }

      serviceAccount = {
        create      = true
        name        = "aws-load-balancer-controller"
        annotations = { "eks.amazonaws.com/role-arn" = module.eks[0].aws_load_balancer_controller_role_arn }
      }

      ingressClass               = "alb"
      createIngressClassResource = true

      enableCertManager = false
      defaultTargetType = "ip"

      controllerConfig = {
        featureGates = {
          ALBGatewayAPI = "true"
          NLBGatewayAPI = "true"
        }
      }
    })
  ]

  depends_on = [
    null_resource.gateway_api_crds[0],
    module.eks,
    aws_eks_access_policy_association.cluster_scoped,
  ]
}

# GatewayClass for L7 (ALB). Gateways referencing this class are provisioned as ALBs.
resource "kubectl_manifest" "gateway_class_alb" {
  count = local._lbc_enabled ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "GatewayClass"
    metadata   = { name = "alb" }
    spec = {
      controllerName = "gateway.k8s.aws/alb"
      description    = "AWS ALB GatewayClass for L7 (HTTP/HTTPS, gRPC)"
    }
  })

  depends_on = [helm_release.aws_load_balancer_controller[0]]
}
