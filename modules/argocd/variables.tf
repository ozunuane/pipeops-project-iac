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

# ====================================================================
# Multi-Cluster Management Configuration
# ====================================================================

variable "enable_multi_cluster" {
  description = "Enable multi-cluster management from this ArgoCD instance"
  type        = bool
  default     = false
}

variable "managed_clusters" {
  description = "List of external clusters to be managed by this ArgoCD instance"
  type = list(object({
    name        = string # Cluster name (e.g., 'dev', 'staging', 'dr')
    environment = string # Environment label
    server      = string # Kubernetes API server URL
    ca_data     = string # Base64-encoded CA certificate
    # Auth method: either bearer_token OR aws_auth
    bearer_token = optional(string, "") # Service account bearer token
    # AWS EKS specific auth (recommended for EKS clusters)
    aws_auth = optional(object({
      cluster_name = string               # EKS cluster name
      role_arn     = optional(string, "") # IAM role ARN for cross-account access
      region       = optional(string, "us-west-2")
    }), null)
    labels = optional(map(string), {}) # Additional labels for cluster selection
  }))
  default   = []
  sensitive = true
}

variable "project_name" {
  description = "Project name for ApplicationSet generators"
  type        = string
  default     = "pipeops"
}

variable "git_repo_url" {
  description = "Git repository URL for ApplicationSets"
  type        = string
  default     = ""
}

variable "git_repo_path" {
  description = "Path in git repo for application manifests"
  type        = string
  default     = "k8s-manifests"
}

variable "git_target_revision" {
  description = "Git target revision (branch, tag, or commit)"
  type        = string
  default     = "HEAD"
}

variable "enable_applicationsets" {
  description = "Enable sample ApplicationSets for multi-cluster deployments"
  type        = bool
  default     = false
}