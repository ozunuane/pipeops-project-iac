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
# DNS Configuration
# ====================================================================

variable "domain_name" {
  description = "Root domain name (e.g., example.com)"
  type        = string
}

variable "create_hosted_zone" {
  description = "Create a new Route53 hosted zone (false to use existing)"
  type        = bool
  default     = false
}

variable "app_subdomain" {
  description = "Subdomain for the main application (empty for apex domain)"
  type        = string
  default     = "app"
}

# ====================================================================
# Certificate Configuration
# ====================================================================

variable "create_certificates" {
  description = "Create ACM certificates"
  type        = bool
  default     = true
}

variable "certificate_san" {
  description = "Subject Alternative Names for certificates"
  type        = list(string)
  default     = []
  # Example: ["*.example.com", "api.example.com"]
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
