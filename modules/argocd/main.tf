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
    Statement = concat(
      [
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
      ],
      # Multi-cluster support: Allow ArgoCD to get EKS tokens for managed clusters
      var.enable_multi_cluster ? [
        {
          Effect = "Allow"
          Action = [
            "eks:DescribeCluster",
            "eks:ListClusters"
          ]
          Resource = ["*"]
        },
        {
          Effect = "Allow"
          Action = [
            "sts:AssumeRole"
          ]
          Resource = [
            for cluster in var.managed_clusters : cluster.aws_auth.role_arn
            if cluster.aws_auth != null && cluster.aws_auth.role_arn != ""
          ]
        }
      ] : []
    )
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

# ====================================================================
# Multi-Cluster Management - External Cluster Registration
# ====================================================================
# Register external clusters in ArgoCD for centralized management

resource "kubernetes_secret" "cluster" {
  for_each = var.enable_multi_cluster ? {
    for cluster in var.managed_clusters : cluster.name => cluster
  } : {}

  metadata {
    name      = "cluster-${each.value.name}"
    namespace = kubernetes_namespace.argocd.metadata[0].name
    labels = merge(
      {
        "argocd.argoproj.io/secret-type" = "cluster"
        "environment"                    = each.value.environment
        "cluster-name"                   = each.value.name
      },
      each.value.labels
    )
  }

  data = {
    name   = each.value.name
    server = each.value.server
    config = jsonencode({
      # Use AWS EKS exec auth if aws_auth is provided, otherwise use bearer token
      execProviderConfig = each.value.aws_auth != null ? {
        command = "aws"
        args = concat(
          ["eks", "get-token", "--cluster-name", each.value.aws_auth.cluster_name, "--region", each.value.aws_auth.region],
          each.value.aws_auth.role_arn != "" ? ["--role-arn", each.value.aws_auth.role_arn] : []
        )
        apiVersion  = "client.authentication.k8s.io/v1beta1"
        env         = null
        installHint = "Install AWS CLI and configure credentials"
      } : null
      bearerToken = each.value.aws_auth == null ? each.value.bearer_token : null
      tlsClientConfig = {
        insecure = false
        caData   = each.value.ca_data
      }
    })
  }

  depends_on = [helm_release.argocd]
}

# ====================================================================
# ArgoCD AppProject for Multi-Environment Deployments
# ====================================================================
# Define an AppProject that allows deployments to all managed clusters

resource "kubernetes_manifest" "appproject" {
  count = var.enable_multi_cluster ? 1 : 0

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "AppProject"
    metadata = {
      name      = var.project_name
      namespace = kubernetes_namespace.argocd.metadata[0].name
    }
    spec = {
      description = "Project for ${var.project_name} multi-cluster deployments"

      # Source repositories
      sourceRepos = ["*"]

      # Destination clusters and namespaces
      destinations = concat(
        # In-cluster (current cluster)
        [
          {
            server    = "https://kubernetes.default.svc"
            namespace = "*"
          }
        ],
        # External managed clusters
        [
          for cluster in var.managed_clusters : {
            server    = cluster.server
            namespace = "*"
          }
        ]
      )

      # Cluster resource whitelist
      clusterResourceWhitelist = [
        { group = "*", kind = "*" }
      ]

      # Namespace resource whitelist
      namespaceResourceWhitelist = [
        { group = "*", kind = "*" }
      ]

      # Allow orphaned resources
      orphanedResources = {
        warn = true
      }
    }
  }

  depends_on = [helm_release.argocd]
}

# ====================================================================
# ApplicationSet for Multi-Cluster Deployments
# ====================================================================
# Creates applications across all managed clusters based on Git repo structure

resource "kubernetes_manifest" "applicationset_multi_cluster" {
  count = var.enable_multi_cluster && var.enable_applicationsets && var.git_repo_url != "" ? 1 : 0

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "ApplicationSet"
    metadata = {
      name      = "${var.project_name}-multi-cluster"
      namespace = kubernetes_namespace.argocd.metadata[0].name
    }
    spec = {
      generators = [
        {
          # Matrix generator: combines clusters with applications
          matrix = {
            generators = [
              {
                # Cluster generator - selects all registered clusters
                clusters = {
                  selector = {
                    matchLabels = {} # Match all clusters
                  }
                }
              },
              {
                # Git directory generator - finds apps in the repo
                git = {
                  repoURL  = var.git_repo_url
                  revision = var.git_target_revision
                  directories = [
                    { path = "${var.git_repo_path}/overlays/{{name}}/*" }
                  ]
                }
              }
            ]
          }
        }
      ]

      template = {
        metadata = {
          name = "{{path.basename}}-{{name}}"
          labels = {
            "app.kubernetes.io/managed-by" = "argocd-applicationset"
            "environment"                  = "{{metadata.labels.environment}}"
            "cluster"                      = "{{name}}"
          }
        }
        spec = {
          project = var.project_name
          source = {
            repoURL        = var.git_repo_url
            targetRevision = var.git_target_revision
            path           = "{{path}}"
          }
          destination = {
            server    = "{{server}}"
            namespace = "{{path.basename}}"
          }
          syncPolicy = {
            automated = {
              prune      = true
              selfHeal   = true
              allowEmpty = false
            }
            syncOptions = [
              "CreateNamespace=true",
              "PrunePropagationPolicy=foreground",
              "PruneLast=true"
            ]
            retry = {
              limit = 5
              backoff = {
                duration    = "5s"
                factor      = 2
                maxDuration = "3m"
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    helm_release.argocd,
    kubernetes_manifest.appproject
  ]
}

# ====================================================================
# ApplicationSet for Environment-Based Deployments
# ====================================================================
# Simpler ApplicationSet that deploys based on environment overlays

resource "kubernetes_manifest" "applicationset_environments" {
  count = var.enable_multi_cluster && var.enable_applicationsets && var.git_repo_url != "" ? 1 : 0

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "ApplicationSet"
    metadata = {
      name      = "${var.project_name}-environments"
      namespace = kubernetes_namespace.argocd.metadata[0].name
    }
    spec = {
      generators = [
        {
          # List generator for explicit environment mapping
          list = {
            elements = concat(
              # Add in-cluster as an environment
              [
                {
                  cluster     = "in-cluster"
                  url         = "https://kubernetes.default.svc"
                  environment = "prod"
                }
              ],
              # Add all managed clusters
              [
                for cluster in var.managed_clusters : {
                  cluster     = cluster.name
                  url         = cluster.server
                  environment = cluster.environment
                }
              ]
            )
          }
        }
      ]

      template = {
        metadata = {
          name = "${var.project_name}-{{environment}}"
          labels = {
            "app.kubernetes.io/managed-by" = "argocd-applicationset"
            "environment"                  = "{{environment}}"
            "cluster"                      = "{{cluster}}"
          }
        }
        spec = {
          project = var.project_name
          source = {
            repoURL        = var.git_repo_url
            targetRevision = var.git_target_revision
            path           = "${var.git_repo_path}/overlays/{{environment}}"
          }
          destination = {
            server    = "{{url}}"
            namespace = var.project_name
          }
          syncPolicy = {
            automated = {
              prune    = true
              selfHeal = true
            }
            syncOptions = [
              "CreateNamespace=true"
            ]
          }
        }
      }
    }
  }

  depends_on = [
    helm_release.argocd,
    kubernetes_manifest.appproject
  ]
}