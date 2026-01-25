# ====================================================================
# Global Infrastructure - Production Configuration
# ====================================================================
# Manages DNS and certificates for failover between main EKS and DR EKS

# Project Configuration
project_name   = "pipeops"
primary_region = "us-west-2"
dr_region      = "us-east-1"

# Cluster Integration
enable_primary_cluster = true
enable_dr_cluster      = true

# ====================================================================
# DNS Configuration - Multiple Domains
# ====================================================================
# Configure one or more domains with their certificates
# The first domain is considered the "primary" domain for service records

domain_names = [
  {
    domain_name             = "example.com" # TODO: Replace with your primary domain
    create_hosted_zone      = false         # Set to true if you want Terraform to create the zone
    existing_hosted_zone_id = ""            # Required if create_hosted_zone = false
    app_subdomain           = "app"         # Creates app.example.com
    create_certificates     = true
    subject_alternative_names = [
      "*.example.com", # Wildcard for all subdomains
      "api.example.com",
      "argocd.example.com",
      "grafana.example.com"
    ]
  }
  # Example: Add additional domains
  # {
  #   domain_name              = "secondary-domain.com"
  #   create_hosted_zone       = true
  #   existing_hosted_zone_id  = ""
  #   app_subdomain            = ""   # Use root domain
  #   create_certificates      = true
  #   subject_alternative_names = [
  #     "*.secondary-domain.com"
  #   ]
  # }
]

# ====================================================================
# Failover Configuration
# ====================================================================
enable_failover                = false # Set to true when ALBs are ready
health_check_port              = 443
health_check_failure_threshold = 3
health_check_interval          = 30

# Health check endpoints (configure after ALBs are deployed)
primary_health_check_fqdn = "" # e.g., "app-primary.example.com"
primary_health_check_path = "/health"
dr_health_check_fqdn      = "" # e.g., "app-dr.example.com"
dr_health_check_path      = "/health"

# ====================================================================
# ALB Configuration (populate after EKS deployments)
# ====================================================================
# Get these values from:
# - Primary: terraform output -state=../environments/prod/terraform.tfstate
# - DR: terraform output -state=../dr-infrastructure/environments/drprod/terraform.tfstate

# Primary cluster ALB
primary_alb_dns_name = "" # e.g., "k8s-default-ingressp-xxxxx.us-west-2.elb.amazonaws.com"
primary_alb_zone_id  = "" # e.g., "Z1H1FL5HABSF5"

# DR cluster ALB
dr_alb_dns_name = "" # e.g., "k8s-default-ingressp-xxxxx.us-east-1.elb.amazonaws.com"
dr_alb_zone_id  = "" # e.g., "Z35SXDOTRQ7X7K"

# ====================================================================
# Service ALBs (optional - for primary domain)
# ====================================================================
argocd_alb_dns     = ""
argocd_alb_zone_id = ""

grafana_alb_dns     = ""
grafana_alb_zone_id = ""

api_alb_dns     = ""
api_alb_zone_id = ""

# ====================================================================
# Tags
# ====================================================================
tags = {
  Project     = "pipeops"
  Environment = "global"
  ManagedBy   = "terraform"
  Workspace   = "global-infrastructure"
  CostCenter  = "engineering"
  Owner       = "platform-team"
}
