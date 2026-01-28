variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "prometheus_stack_version" {
  description = "Version of kube-prometheus-stack Helm chart"
  type        = string
  default     = "55.5.0"
}

variable "ha_mode" {
  description = "Enable high availability mode"
  type        = bool
  default     = true
}

variable "enable_alertmanager" {
  description = "Enable Alertmanager"
  type        = bool
  default     = true
}

variable "enable_grafana" {
  description = "Enable Grafana"
  type        = bool
  default     = true
}

variable "enable_ingress" {
  description = "Enable ingress for monitoring services"
  type        = bool
  default     = true
}

variable "ssl_certificate_arn" {
  description = "ARN of SSL certificate for ALB"
  type        = string
  default     = ""
}

variable "grafana_domain" {
  description = "Domain name for Grafana"
  type        = string
}

variable "prometheus_domain" {
  description = "Domain name for Prometheus"
  type        = string
}

variable "alertmanager_domain" {
  description = "Domain name for Alertmanager"
  type        = string
}

variable "grafana_admin_password" {
  description = "Grafana admin password"
  type        = string
  sensitive   = true
}

variable "prometheus_retention" {
  description = "Prometheus data retention period"
  type        = string
  default     = "30d"
}

variable "prometheus_retention_size" {
  description = "Prometheus data retention size"
  type        = string
  default     = "100GB"
}

variable "prometheus_storage_size" {
  description = "Prometheus storage size"
  type        = string
  default     = "100Gi"
}

variable "enable_oauth" {
  description = "Enable OAuth for Grafana"
  type        = bool
  default     = false
}

variable "oauth_client_id" {
  description = "OAuth client ID"
  type        = string
  default     = ""
}

variable "oauth_client_secret" {
  description = "OAuth client secret"
  type        = string
  default     = ""
  sensitive   = true
}

variable "oauth_auth_url" {
  description = "OAuth authorization URL"
  type        = string
  default     = ""
}

variable "smtp_smarthost" {
  description = "SMTP server for Alertmanager"
  type        = string
  default     = ""
}

variable "smtp_from" {
  description = "From email address for Alertmanager"
  type        = string
  default     = ""
}

variable "slack_api_url" {
  description = "Slack API URL for Alertmanager"
  type        = string
  default     = ""
  sensitive   = true
}

variable "alert_routes" {
  description = "Alert routing rules"
  type        = list(any)
  default     = []
}

variable "alert_receivers" {
  description = "Alert receivers configuration"
  type        = list(any)
  default = [
    {
      name = "web.hook"
      webhook_configs = [
        {
          url = "http://127.0.0.1:5001/"
        }
      ]
    }
  ]
}

variable "enable_container_insights" {
  description = "Enable AWS Container Insights"
  type        = bool
  default     = true
}

variable "oidc_provider_arn" {
  description = "ARN of the OIDC provider"
  type        = string
}

variable "oidc_issuer_url" {
  description = "OIDC issuer URL"
  type        = string
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}

variable "monitoring_node_selector" {
  description = "Node selector for monitoring (e.g. workload-type=system). Schedule Prometheus, Grafana, etc. on dedicated nodes."
  type        = map(string)
  default     = {}
}

variable "monitoring_tolerations" {
  description = "Tolerations for monitoring nodes (e.g. workload-type=system:NoSchedule). Pass from local.karpenter_system_tolerations."
  type        = list(any)
  default     = []
}

variable "storage_class_name" {
  description = "StorageClass name for monitoring PVCs (Grafana, Prometheus, Alertmanager). Must match the gp3 StorageClass metadata name (e.g. project-environment-gp3-storageclass)."
  type        = string
}

variable "grafana_storage_class_name" {
  description = "Optional override StorageClass name for Grafana PVC only. If empty, Grafana uses storage_class_name."
  type        = string
  default     = ""
}