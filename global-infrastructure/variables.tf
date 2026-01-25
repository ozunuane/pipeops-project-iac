# ====================================================================
# Global Infrastructure Variables
# ====================================================================

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "pipeops"
}

variable "primary_region" {
  description = "Primary AWS region"
  type        = string
  default     = "us-west-2"
}

variable "dr_region" {
  description = "Disaster recovery AWS region"
  type        = string
  default     = "us-east-1"
}

# ====================================================================
# Cluster Configuration
# ====================================================================

variable "enable_primary_cluster" {
  description = "Enable integration with primary EKS cluster"
  type        = bool
  default     = true
}

variable "enable_dr_cluster" {
  description = "Enable integration with DR EKS cluster"
  type        = bool
  default     = true
}

# ====================================================================
# DNS Configuration - Multiple Domains
# ====================================================================

variable "domains" {
  description = "Map of domains to configure with their settings"
  type = map(object({
    domain_name        = string       # Root domain (e.g., example.com)
    create_hosted_zone = bool         # Create new zone or use existing
    create_certificate = bool         # Create ACM certificates
    certificate_san    = list(string) # Subject Alternative Names
    app_subdomain      = string       # Main app subdomain (e.g., "app" for app.example.com)
    primary            = bool         # Is this the primary domain for failover
  }))
  default = {}
  # Example:
  # domains = {
  #   "example" = {
  #     domain_name        = "example.com"
  #     create_hosted_zone = false
  #     create_certificate = true
  #     certificate_san    = ["*.example.com"]
  #     app_subdomain      = "app"
  #     primary            = true
  #   }
  #   "example-io" = {
  #     domain_name        = "example.io"
  #     create_hosted_zone = true
  #     create_certificate = true
  #     certificate_san    = ["*.example.io"]
  #     app_subdomain      = ""
  #     primary            = false
  #   }
  # }
}

# Legacy single domain support (deprecated, use 'domains' instead)
variable "domain_name" {
  description = "DEPRECATED: Use 'domains' variable instead. Root domain name."
  type        = string
  default     = ""
}

variable "create_hosted_zone" {
  description = "DEPRECATED: Use 'domains' variable instead."
  type        = bool
  default     = false
}

variable "app_subdomain" {
  description = "DEPRECATED: Use 'domains' variable instead."
  type        = string
  default     = "app"
}

variable "create_certificates" {
  description = "DEPRECATED: Use 'domains' variable instead."
  type        = bool
  default     = true
}

variable "certificate_san" {
  description = "DEPRECATED: Use 'domains' variable instead."
  type        = list(string)
  default     = []
}

# ====================================================================
# Failover Configuration
# ====================================================================

variable "enable_failover" {
  description = "Enable DNS failover routing between primary and DR"
  type        = bool
  default     = false
}

variable "health_check_port" {
  description = "Port for health checks"
  type        = number
  default     = 443
}

variable "health_check_failure_threshold" {
  description = "Number of consecutive health check failures before failover"
  type        = number
  default     = 3
}

variable "health_check_interval" {
  description = "Health check interval in seconds (10 or 30)"
  type        = number
  default     = 30
}

variable "primary_health_check_fqdn" {
  description = "FQDN for primary health check"
  type        = string
  default     = ""
}

variable "primary_health_check_path" {
  description = "Path for primary health check (e.g., /health)"
  type        = string
  default     = "/health"
}

variable "dr_health_check_fqdn" {
  description = "FQDN for DR health check"
  type        = string
  default     = ""
}

variable "dr_health_check_path" {
  description = "Path for DR health check (e.g., /health)"
  type        = string
  default     = "/health"
}

# ====================================================================
# ALB Configuration (from EKS clusters)
# ====================================================================

variable "primary_alb_dns_name" {
  description = "DNS name of the primary ALB"
  type        = string
  default     = ""
}

variable "primary_alb_zone_id" {
  description = "Route53 zone ID of the primary ALB"
  type        = string
  default     = ""
}

variable "dr_alb_dns_name" {
  description = "DNS name of the DR ALB"
  type        = string
  default     = ""
}

variable "dr_alb_zone_id" {
  description = "Route53 zone ID of the DR ALB"
  type        = string
  default     = ""
}

# ====================================================================
# Additional Service ALBs
# ====================================================================

variable "argocd_alb_dns" {
  description = "DNS name of the ArgoCD ALB"
  type        = string
  default     = ""
}

variable "argocd_alb_zone_id" {
  description = "Route53 zone ID of the ArgoCD ALB"
  type        = string
  default     = ""
}

variable "grafana_alb_dns" {
  description = "DNS name of the Grafana ALB"
  type        = string
  default     = ""
}

variable "grafana_alb_zone_id" {
  description = "Route53 zone ID of the Grafana ALB"
  type        = string
  default     = ""
}

variable "api_alb_dns" {
  description = "DNS name of the API ALB"
  type        = string
  default     = ""
}

variable "api_alb_zone_id" {
  description = "Route53 zone ID of the API ALB"
  type        = string
  default     = ""
}

# ====================================================================
# Tags
# ====================================================================

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    Project     = "pipeops"
    Environment = "global"
    ManagedBy   = "terraform"
    Workspace   = "global-infrastructure"
  }
}
