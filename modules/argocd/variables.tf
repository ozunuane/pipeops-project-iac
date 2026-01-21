variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "argocd_chart_version" {
  description = "ArgoCD Helm chart version"
  type        = string
  default     = "5.51.6"
}

variable "argocd_domain" {
  description = "Domain name for ArgoCD server"
  type        = string
}

variable "admin_password" {
  description = "Admin password for ArgoCD"
  type        = string
  sensitive   = true
}

variable "admin_password_bcrypt" {
  description = "Bcrypt hash of admin password"
  type        = string
  sensitive   = true
}

variable "server_insecure" {
  description = "Run ArgoCD server in insecure mode"
  type        = bool
  default     = false
}

variable "ha_mode" {
  description = "Enable high availability mode"
  type        = bool
  default     = true
}

variable "enable_metrics" {
  description = "Enable metrics collection"
  type        = bool
  default     = true
}

variable "enable_ingress" {
  description = "Enable ingress for ArgoCD server"
  type        = bool
  default     = true
}

variable "ssl_certificate_arn" {
  description = "ARN of SSL certificate for ALB"
  type        = string
  default     = ""
}

variable "oidc_provider_arn" {
  description = "ARN of the OIDC provider"
  type        = string
}

variable "oidc_issuer_url" {
  description = "OIDC issuer URL"
  type        = string
}

variable "enable_oidc" {
  description = "Enable OIDC authentication"
  type        = bool
  default     = false
}

variable "oidc_client_id" {
  description = "OIDC client ID"
  type        = string
  default     = ""
}

variable "oidc_client_secret" {
  description = "OIDC client secret"
  type        = string
  default     = ""
  sensitive   = true
}

variable "rbac_policy" {
  description = "RBAC policy for ArgoCD"
  type        = string
  default     = <<-EOT
    g, argocd-admins, role:admin
    g, argocd-developers, role:readonly
  EOT
}

variable "enable_notifications" {
  description = "Enable ArgoCD notifications"
  type        = bool
  default     = false
}

variable "notification_secrets" {
  description = "Notification secrets for ArgoCD"
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "slack_webhook_url" {
  description = "Slack webhook URL for notifications"
  type        = string
  default     = ""
  sensitive   = true
}

variable "github_webhook_url" {
  description = "GitHub webhook URL for notifications"
  type        = string
  default     = ""
}

variable "github_webhook_secret" {
  description = "GitHub webhook secret"
  type        = string
  default     = ""
  sensitive   = true
}

variable "create_cli_secret" {
  description = "Create secret for ArgoCD CLI access"
  type        = bool
  default     = false
}

variable "enable_network_policy" {
  description = "Enable network policy for enhanced security"
  type        = bool
  default     = false
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}