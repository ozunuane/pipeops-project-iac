# ==========================================
# ArgoCD - Helm Installation
# ==========================================
# Install ArgoCD via Helm for GitOps deployments
# Configuration can be customized via values file or set blocks
#
# After deployment, get the admin password:
# kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
#
# Port forward to access UI:
# kubectl port-forward svc/argocd-server -n argocd 8080:443
# ==========================================

resource "helm_release" "argocd" {
  count = var.cluster_exists && var.enable_argocd ? 1 : 0

  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version
  namespace        = "argocd"
  create_namespace = true

  # Timeout for installation (ArgoCD can take a while)
  timeout = 600

  # Wait for all resources to be ready
  wait = true

  # Basic values - customize in values file or via set blocks
  values = [
    yamlencode({
      # Global settings
      global = {
        image = {
          tag = var.argocd_image_tag
        }
      }

      # Server configuration
      server = {
        replicas = var.environment == "prod" ? 2 : 1

        # Insecure mode (disable TLS on server, use if behind LB)
        extraArgs = var.argocd_server_insecure ? ["--insecure"] : []

        # Service type
        service = {
          type = "ClusterIP"
        }

        # Ingress (disabled by default - enable when ready)
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

        # Metrics for Prometheus
        metrics = {
          enabled = var.enable_monitoring
          serviceMonitor = {
            enabled = var.enable_monitoring
          }
        }
      }

      # Controller configuration
      controller = {
        replicas = var.environment == "prod" ? 2 : 1

        metrics = {
          enabled = var.enable_monitoring
          serviceMonitor = {
            enabled = var.enable_monitoring
          }
        }
      }

      # Repo server configuration
      repoServer = {
        replicas = var.environment == "prod" ? 2 : 1

        metrics = {
          enabled = var.enable_monitoring
          serviceMonitor = {
            enabled = var.enable_monitoring
          }
        }
      }

      # ApplicationSet controller
      applicationSet = {
        enabled  = true
        replicas = 1
      }

      # Notifications controller
      notifications = {
        enabled = true
      }

      # Redis (for caching)
      redis = {
        enabled = true
      }

      # Dex (SSO) - disabled by default
      dex = {
        enabled = var.argocd_enable_dex
      }

      # High Availability settings for prod
      redis-ha = {
        enabled = var.environment == "prod" ? true : false
      }
    })
  ]

  depends_on = [module.eks]
}
