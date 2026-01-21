# ArgoCD Namespace
resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
    labels = {
      name                                 = "argocd"
      "pod-security.kubernetes.io/audit"   = "privileged"
      "pod-security.kubernetes.io/enforce" = "privileged"
      "pod-security.kubernetes.io/warn"    = "privileged"
    }
  }
}

# ArgoCD Helm Release
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version
  namespace  = kubernetes_namespace.argocd.metadata[0].name

  values = [
    yamlencode({
      global = {
        domain = var.argocd_domain
      }

      configs = {
        params = {
          "server.insecure" = var.server_insecure
        }

        secret = {
          argocdServerAdminPassword = var.admin_password_bcrypt
        }

        cm = {
          "exec.enabled"                  = true
          "server.enable.proxy.extension" = true
          "resource.compareoptions" = yamlencode({
            ignoreAggregatedRoles = true
          })
          "oidc.config" = var.enable_oidc ? yamlencode({
            name            = "AWS SSO"
            issuer          = var.oidc_issuer_url
            clientId        = var.oidc_client_id
            clientSecret    = var.oidc_client_secret
            requestedScopes = ["openid", "profile", "email"]
            requestedIDTokenClaims = {
              groups = {
                essential = true
              }
            }
          }) : ""
        }

        rbac = {
          "policy.default" = "role:readonly"
          "policy.csv"     = var.rbac_policy
        }
      }

      controller = {
        replicas = var.ha_mode ? 2 : 1
        resources = {
          limits = {
            cpu    = "2"
            memory = "2Gi"
          }
          requests = {
            cpu    = "500m"
            memory = "1Gi"
          }
        }
        metrics = {
          enabled = var.enable_metrics
          serviceMonitor = {
            enabled = var.enable_metrics
          }
        }
      }

      server = {
        replicas = var.ha_mode ? 2 : 1
        autoscaling = {
          enabled     = var.ha_mode
          minReplicas = 2
          maxReplicas = 5
        }
        resources = {
          limits = {
            cpu    = "500m"
            memory = "512Mi"
          }
          requests = {
            cpu    = "100m"
            memory = "256Mi"
          }
        }
        metrics = {
          enabled = var.enable_metrics
          serviceMonitor = {
            enabled = var.enable_metrics
          }
        }
        ingress = {
          enabled          = var.enable_ingress
          ingressClassName = "alb"
          annotations = {
            "alb.ingress.kubernetes.io/scheme"           = "internet-facing"
            "alb.ingress.kubernetes.io/target-type"      = "ip"
            "alb.ingress.kubernetes.io/listen-ports"     = "[{\"HTTPS\":443}]"
            "alb.ingress.kubernetes.io/certificate-arn"  = var.ssl_certificate_arn
            "alb.ingress.kubernetes.io/ssl-redirect"     = "443"
            "alb.ingress.kubernetes.io/backend-protocol" = var.server_insecure ? "HTTP" : "HTTPS"
          }
          hosts = [
            {
              host = var.argocd_domain
              paths = [
                {
                  path     = "/"
                  pathType = "Prefix"
                }
              ]
            }
          ]
          tls = [
            {
              secretName = "argocd-server-tls"
              hosts      = [var.argocd_domain]
            }
          ]
        }
      }

      repoServer = {
        replicas = var.ha_mode ? 2 : 1
        autoscaling = {
          enabled     = var.ha_mode
          minReplicas = 2
          maxReplicas = 5
        }
        resources = {
          limits = {
            cpu    = "1"
            memory = "1Gi"
          }
          requests = {
            cpu    = "250m"
            memory = "512Mi"
          }
        }
        metrics = {
          enabled = var.enable_metrics
          serviceMonitor = {
            enabled = var.enable_metrics
          }
        }
      }

      applicationSet = {
        enabled  = true
        replicas = var.ha_mode ? 2 : 1
        resources = {
          limits = {
            cpu    = "500m"
            memory = "512Mi"
          }
          requests = {
            cpu    = "100m"
            memory = "256Mi"
          }
        }
        metrics = {
          enabled = var.enable_metrics
          serviceMonitor = {
            enabled = var.enable_metrics
          }
        }
      }

      notifications = {
        enabled   = var.enable_notifications
        argocdUrl = "https://${var.argocd_domain}"
        secret = {
          items = var.notification_secrets
        }
        cm = {
          "service.slack" = var.slack_webhook_url != "" ? yamlencode({
            token = "$slack-token"
          }) : ""
          "service.webhook.github" = var.github_webhook_secret != "" ? yamlencode({
            url = var.github_webhook_url
            headers = [
              {
                name  = "Authorization"
                value = "token $github-token"
              }
            ]
          }) : ""
          "template.app-deployed" = yamlencode({
            message = "Application {{.app.metadata.name}} is now running new version."
            slack = {
              attachments = yamlencode([
                {
                  title      = "{{.app.metadata.name}}"
                  title_link = "{{.context.argocdUrl}}/applications/{{.app.metadata.name}}"
                  color      = "#18be52"
                  fields = [
                    {
                      title = "Sync Status"
                      value = "{{.app.status.sync.status}}"
                      short = true
                    },
                    {
                      title = "Repository"
                      value = "{{.app.spec.source.repoURL}}"
                      short = true
                    }
                  ]
                }
              ])
            }
          })
          "trigger.on-deployed" = yamlencode([
            {
              oncePer = "app.status.sync.revision"
              send    = ["app-deployed"]
              when    = "app.status.operationState.phase in ['Succeeded'] and app.status.health.status == 'Healthy'"
            }
          ])
        }
      }

      redis-ha = {
        enabled = var.ha_mode
        haproxy = {
          enabled = var.ha_mode
        }
      }

      redis = {
        enabled = !var.ha_mode
      }
    })
  ]

  depends_on = [kubernetes_namespace.argocd]
}

# Service Account for ArgoCD with IRSA
resource "aws_iam_role" "argocd" {
  name = "${var.cluster_name}-argocd-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Federated = var.oidc_provider_arn
        }
        Condition = {
          StringEquals = {
            "${replace(var.oidc_issuer_url, "https://", "")}:sub" : "system:serviceaccount:argocd:argocd-server"
            "${replace(var.oidc_issuer_url, "https://", "")}:aud" : "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = var.tags
}

# IAM policy for ArgoCD to manage AWS resources
resource "aws_iam_role_policy" "argocd" {
  name = "${var.cluster_name}-argocd-policy"
  role = aws_iam_role.argocd.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "eks:DescribeCluster",
          "eks:DescribeNodegroup",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = ["*"]
      }
    ]
  })
}

# Service Account annotation for IRSA
resource "kubernetes_annotations" "argocd_server_sa" {
  api_version = "v1"
  kind        = "ServiceAccount"
  metadata {
    name      = "argocd-server"
    namespace = kubernetes_namespace.argocd.metadata[0].name
  }
  annotations = {
    "eks.amazonaws.com/role-arn" = aws_iam_role.argocd.arn
  }

  depends_on = [helm_release.argocd]
}

# ArgoCD CLI Secret for automation
resource "kubernetes_secret" "argocd_cli" {
  count = var.create_cli_secret ? 1 : 0

  metadata {
    name      = "argocd-cli-secret"
    namespace = kubernetes_namespace.argocd.metadata[0].name
  }

  data = {
    username = "admin"
    password = var.admin_password
    server   = var.server_insecure ? "http://argocd-server.argocd.svc.cluster.local" : "https://argocd-server.argocd.svc.cluster.local"
  }
}

# NetworkPolicy for ArgoCD (optional, for enhanced security)
resource "kubernetes_network_policy" "argocd" {
  count = var.enable_network_policy ? 1 : 0

  metadata {
    name      = "argocd-network-policy"
    namespace = kubernetes_namespace.argocd.metadata[0].name
  }

  spec {
    pod_selector {
      match_labels = {
        "app.kubernetes.io/part-of" = "argocd"
      }
    }

    policy_types = ["Ingress", "Egress"]

    ingress {
      from {
        namespace_selector {
          match_labels = {
            name = "argocd"
          }
        }
      }
      from {
        namespace_selector {
          match_labels = {
            name = "kube-system"
          }
        }
      }
      from {
        namespace_selector {
          match_labels = {
            name = "aws-load-balancer-controller"
          }
        }
      }
    }

    egress {}
  }
}