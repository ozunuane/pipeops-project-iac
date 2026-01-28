# ==========================================
# Helm Addons - EKS Cluster Add-ons
# ==========================================
# All addons require create_eks && cluster_exists. Optional addons use enable_*.
# Shared depends_on: module.eks, aws_eks_access_policy_association.cluster_scoped.
# ==========================================

# ------------------------------------------------------------------------------
# Metrics Server
# ------------------------------------------------------------------------------
# metrics.k8s.io for HPA, kubectl top, Karpenter. Optional: enable_metrics_server.
# ------------------------------------------------------------------------------
resource "helm_release" "metrics_server" {
  count = var.create_eks && var.cluster_exists && var.enable_metrics_server ? 1 : 0

  name             = "metrics-server"
  repository       = "https://kubernetes-sigs.github.io/metrics-server/"
  chart            = "metrics-server"
  version          = "3.12.2"
  namespace        = "kube-system"
  create_namespace = false

  timeout       = 300
  wait          = true
  wait_for_jobs = false

  set {
    name  = "args[0]"
    value = "--kubelet-insecure-tls"
  }

  depends_on = [module.eks, aws_eks_access_policy_association.cluster_scoped]
}

# ------------------------------------------------------------------------------
# External Secrets Operator
# ------------------------------------------------------------------------------
# AWS Secrets Manager integration. No enable flag.
# ------------------------------------------------------------------------------
resource "helm_release" "external_secrets" {
  count = var.create_eks && var.cluster_exists ? 1 : 0

  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = "0.9.11"
  namespace        = "external-secrets-system"
  create_namespace = true

  timeout       = 600
  wait          = false
  wait_for_jobs = false

  set {
    name  = "installCRDs"
    value = "true"
  }

  depends_on = [module.eks, aws_eks_access_policy_association.cluster_scoped]
}

# ------------------------------------------------------------------------------
# ArgoCD
# ------------------------------------------------------------------------------
# GitOps. Optional: enable_argocd. Password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
# ------------------------------------------------------------------------------
resource "helm_release" "argocd" {
  count = var.create_eks && var.cluster_exists && var.enable_argocd ? 1 : 0

  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version
  namespace        = "argocd"
  create_namespace = true

  timeout       = 900
  wait          = true
  wait_for_jobs = false

  values = [
    yamlencode({
      global = {
        image = { tag = var.argocd_image_tag }
      }
      server = {
        replicas  = var.environment == "prod" ? 2 : 1
        extraArgs = var.argocd_server_insecure ? ["--insecure"] : []
        service   = { type = "ClusterIP" }
        ingress = {
          enabled          = var.argocd_enable_ingress
          ingressClassName = "alb"
          annotations = var.argocd_enable_ingress ? {
            "alb.ingress.kubernetes.io/scheme"          = "internet-facing"
            "alb.ingress.kubernetes.io/target-type"     = "ip"
            "alb.ingress.kubernetes.io/listen-ports"    = "[{\"HTTPS\":443}]"
            "alb.ingress.kubernetes.io/certificate-arn" = var.argocd_ssl_certificate_arn
            "alb.ingress.kubernetes.io/ssl-redirect"    = "443"
          } : {}
          hosts = var.argocd_enable_ingress ? [var.argocd_domain] : []
        }
        metrics = {
          enabled        = var.enable_monitoring
          serviceMonitor = { enabled = var.enable_monitoring }
        }
      }
      controller = {
        replicas = var.environment == "prod" ? 2 : 1
        metrics = {
          enabled        = var.enable_monitoring
          serviceMonitor = { enabled = var.enable_monitoring }
        }
      }
      repoServer = {
        replicas = var.environment == "prod" ? 2 : 1
        metrics = {
          enabled        = var.enable_monitoring
          serviceMonitor = { enabled = var.enable_monitoring }
        }
      }
      applicationSet = { enabled = true, replicas = 1 }
      notifications  = { enabled = true }
      redis          = { enabled = true }
      dex            = { enabled = var.argocd_enable_dex }
      redis-ha       = { enabled = var.environment == "prod" ? true : false }
    })
  ]

  depends_on = [module.eks, aws_eks_access_policy_association.cluster_scoped]
}

# ------------------------------------------------------------------------------
# Karpenter
# ------------------------------------------------------------------------------
# Just-in-time node provisioning. Depends on karpenter_controller IAM + cluster_scoped.
# ------------------------------------------------------------------------------
resource "helm_release" "karpenter" {
  count = var.create_eks && var.cluster_exists ? 1 : 0

  name             = "karpenter"
  repository       = "oci://public.ecr.aws/karpenter"
  chart            = "karpenter"
  version          = "1.5.0"
  namespace        = "karpenter"
  create_namespace = true

  timeout       = 900
  wait          = false
  wait_for_jobs = false

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