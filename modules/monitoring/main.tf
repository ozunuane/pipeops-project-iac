# Monitoring namespace
resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
    labels = {
      name = "monitoring"
    }
  }
}

# Prometheus Stack (kube-prometheus-stack)
resource "helm_release" "prometheus_stack" {
  name       = "prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = var.prometheus_stack_version
  namespace  = kubernetes_namespace.monitoring.metadata[0].name

  # Timeout for installation (EKS Auto Mode needs time to provision nodes)
  timeout = 900

  # Don't wait for all pods - Auto Mode will provision nodes asynchronously
  wait          = false
  wait_for_jobs = false

  values = [
    yamlencode({
      # Use "monitoring" to avoid duplicate names (e.g. prometheus-prometheus -> monitoring-prometheus)
      fullnameOverride = "monitoring"

      defaultRules = {
        create = true
        rules = {
          alertmanager                = true
          etcd                        = true
          general                     = true
          k8s                         = true
          kubeApiserver               = true
          kubePrometheusNodeAlerting  = true
          kubePrometheusNodeRecording = true
          kubernetesAbsent            = true
          kubernetesApps              = true
          kubernetesResources         = true
          kubernetesStorage           = true
          kubernetesSystem            = true
          node                        = true
          prometheus                  = true
          prometheusOperator          = true
        }
      }

      alertmanager = {
        enabled          = var.enable_alertmanager
        fullnameOverride = "alertmanager"

        alertmanagerSpec = {
          replicas     = var.ha_mode ? 2 : 1
          nodeSelector = var.monitoring_node_selector
          tolerations  = var.monitoring_tolerations
          storage = {
            volumeClaimTemplate = {
              spec = {
                storageClassName = var.storage_class_name
                accessModes      = ["ReadWriteOnce"]
                resources = {
                  requests = {
                    storage = "10Gi"
                  }
                }
              }
            }
          }
          resources = {
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
          }
        }

        config = {
          global = {
            smtp_smarthost = var.smtp_smarthost
            smtp_from      = var.smtp_from
            slack_api_url  = var.slack_api_url
          }
          route = {
            group_by        = ["alertname"]
            group_wait      = "10s"
            group_interval  = "10s"
            repeat_interval = "1h"
            receiver        = "web.hook"
            routes          = var.alert_routes
          }
          receivers = var.alert_receivers
        }

        ingress = {
          enabled          = var.enable_ingress
          ingressClassName = "alb"
          annotations = {
            "alb.ingress.kubernetes.io/scheme"          = "internet-facing"
            "alb.ingress.kubernetes.io/target-type"     = "ip"
            "alb.ingress.kubernetes.io/listen-ports"    = "[{\"HTTPS\":443}]"
            "alb.ingress.kubernetes.io/certificate-arn" = var.ssl_certificate_arn
            "alb.ingress.kubernetes.io/ssl-redirect"    = "443"
          }
          hosts = [
            {
              host = var.alertmanager_domain
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
              secretName = "alertmanager-tls"
              hosts      = [var.alertmanager_domain]
            }
          ]
        }
        podDisruptionBudget = {
          enabled      = true
          minAvailable = 1
        }
      }

      grafana = {
        enabled          = var.enable_grafana
        fullnameOverride = "grafana"
        nodeSelector     = var.monitoring_node_selector
        tolerations      = var.monitoring_tolerations

        adminPassword = var.grafana_admin_password

        grafana_ini = {
          server = {
            domain   = var.grafana_domain
            root_url = "https://${var.grafana_domain}"
          }
          security = {
            cookie_secure   = true
            cookie_samesite = "lax"
          }
          auth = {
            disable_login_form = var.enable_oauth
          }
          "auth.generic_oauth" = var.enable_oauth ? {
            enabled             = true
            name                = "AWS SSO"
            allow_sign_up       = true
            client_id           = var.oauth_client_id
            client_secret       = var.oauth_client_secret
            scopes              = "openid profile email"
            auth_url            = "${var.oauth_auth_url}/oauth2/authorize"
            token_url           = "${var.oauth_auth_url}/oauth2/token"
            api_url             = "${var.oauth_auth_url}/oauth2/userinfo"
            role_attribute_path = "contains(groups[*], 'grafana-admins') && 'Admin' || 'Viewer'"
          } : {}
        }

        # Additional data sources for Grafana (e.g. CloudWatch)
        additionalDataSources = [
          {
            name      = "CloudWatch"
            type      = "cloudwatch"
            access    = "proxy"
            isDefault = false
            jsonData = {
              authType      = "default"
              defaultRegion = var.aws_region
            }
          }
        ]

        persistence = {
          enabled          = true
          storageClassName = trimspace(var.grafana_storage_class_name) != "" ? trimspace(var.grafana_storage_class_name) : var.storage_class_name
          size             = "10Gi"
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

        podDisruptionBudget = {
          enabled      = true
          minAvailable = 1
        }

        dashboardProviders = {
          "dashboardproviders.yaml" = {
            apiVersion = 1
            providers = [
              {
                name            = "default"
                orgId           = 1
                folder          = ""
                type            = "file"
                disableDeletion = false
                editable        = true
                options = {
                  path = "/var/lib/grafana/dashboards/default"
                }
              }
            ]
          }
        }

        dashboards = {
          default = {
            "kubernetes-cluster-monitoring" = {
              gnetId     = 7249
              datasource = "Prometheus"
            }
            "kubernetes-pod-monitoring" = {
              gnetId     = 6417
              datasource = "Prometheus"
            }
            "node-exporter" = {
              gnetId     = 1860
              datasource = "Prometheus"
            }
            "argocd" = {
              gnetId     = 14584
              datasource = "Prometheus"
            }
          }
        }

        ingress = {
          enabled          = var.enable_ingress
          ingressClassName = "alb"
          annotations = {
            "alb.ingress.kubernetes.io/scheme"          = "internet-facing"
            "alb.ingress.kubernetes.io/target-type"     = "ip"
            "alb.ingress.kubernetes.io/listen-ports"    = "[{\"HTTPS\":443}]"
            "alb.ingress.kubernetes.io/certificate-arn" = var.ssl_certificate_arn
            "alb.ingress.kubernetes.io/ssl-redirect"    = "443"
          }
          hosts = [var.grafana_domain]
          tls = [
            {
              secretName = "grafana-tls"
              hosts      = [var.grafana_domain]
            }
          ]
        }

        serviceAccount = {
          annotations = {
            "eks.amazonaws.com/role-arn" = aws_iam_role.grafana[0].arn
          }
        }
      }

      prometheus = {
        enabled = true
        # Subchart name; service becomes monitoring-prometheus (no duplicate)
        fullnameOverride = "prometheus"

        prometheusSpec = {
          replicas      = var.ha_mode ? 2 : 1
          nodeSelector  = var.monitoring_node_selector
          tolerations   = var.monitoring_tolerations
          retention     = var.prometheus_retention
          retentionSize = var.prometheus_retention_size

          storageSpec = {
            volumeClaimTemplate = {
              spec = {
                storageClassName = var.storage_class_name
                accessModes      = ["ReadWriteOnce"]
                resources = {
                  requests = {
                    storage = var.prometheus_storage_size
                  }
                }
              }
            }
          }

          resources = {
            limits = {
              cpu    = "2"
              memory = "4Gi"
            }
            requests = {
              cpu    = "500m"
              memory = "2Gi"
            }
          }

          additionalScrapeConfigs = [
            {
              job_name = "argocd-metrics"
              static_configs = [
                {
                  targets = ["argocd-metrics.argocd.svc.cluster.local:8082"]
                }
              ]
            }
          ]

          podDisruptionBudget = {
            enabled      = true
            minAvailable = 1
          }
        }

        ingress = {
          enabled          = var.enable_ingress
          ingressClassName = "alb"
          annotations = {
            "alb.ingress.kubernetes.io/scheme"          = "internet-facing"
            "alb.ingress.kubernetes.io/target-type"     = "ip"
            "alb.ingress.kubernetes.io/listen-ports"    = "[{\"HTTPS\":443}]"
            "alb.ingress.kubernetes.io/certificate-arn" = var.ssl_certificate_arn
            "alb.ingress.kubernetes.io/ssl-redirect"    = "443"
          }
          hosts = [var.prometheus_domain]
          tls = [
            {
              secretName = "prometheus-tls"
              hosts      = [var.prometheus_domain]
            }
          ]
        }
      }

      prometheusOperator = {
        nodeSelector = var.monitoring_node_selector
        tolerations  = var.monitoring_tolerations
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
        podDisruptionBudget = {
          enabled      = true
          minAvailable = 1
        }
      }

      kubeStateMetrics = {
        enabled      = true
        nodeSelector = var.monitoring_node_selector
        tolerations  = var.monitoring_tolerations
      }

      nodeExporter = {
        enabled = true
      }
    })
  ]

  depends_on = [kubernetes_namespace.monitoring]
}

# IAM role for Grafana (for CloudWatch integration)
resource "aws_iam_role" "grafana" {
  count = var.enable_grafana ? 1 : 0

  name = "${var.cluster_name}-grafana-role"

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
            "${replace(var.oidc_issuer_url, "https://", "")}:sub" : "system:serviceaccount:monitoring:grafana"
            "${replace(var.oidc_issuer_url, "https://", "")}:aud" : "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = var.tags
}

# IAM policy for Grafana CloudWatch access
resource "aws_iam_role_policy" "grafana_cloudwatch" {
  count = var.enable_grafana ? 1 : 0

  name = "${var.cluster_name}-grafana-cloudwatch-policy"
  role = aws_iam_role.grafana[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:DescribeAlarmsForMetric",
          "cloudwatch:DescribeAlarmHistory",
          "cloudwatch:DescribeAlarms",
          "cloudwatch:ListMetrics",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:GetMetricData",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:GetLogEvents",
          "logs:StartQuery",
          "logs:StopQuery",
          "logs:GetQueryResults",
          "logs:GetLogRecord",
          "ec2:DescribeTags",
          "ec2:DescribeInstances",
          "ec2:DescribeRegions",
          "tag:GetResources"
        ]
        Resource = "*"
      }
    ]
  })
}

# AWS CloudWatch Container Insights (for EKS monitoring)
resource "kubernetes_config_map" "cwagentconfig" {
  count = var.enable_container_insights ? 1 : 0

  metadata {
    name      = "cwagentconfig"
    namespace = "amazon-cloudwatch"
  }

  data = {
    "cwagentconfig.json" = jsonencode({
      agent = {
        region = var.aws_region
      }
      logs = {
        metrics_collected = {
          kubernetes = {
            cluster_name                = var.cluster_name
            metrics_collection_interval = 60
          }
        }
        force_flush_interval = 5
      }
    })
  }
}

# Namespace for CloudWatch agent
resource "kubernetes_namespace" "amazon_cloudwatch" {
  count = var.enable_container_insights ? 1 : 0

  metadata {
    name = "amazon-cloudwatch"
    labels = {
      name = "amazon-cloudwatch"
    }
  }
}