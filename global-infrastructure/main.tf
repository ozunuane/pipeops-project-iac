# ====================================================================
# Global Infrastructure - DNS & Certificates
# ====================================================================
# This workspace manages global resources that span multiple regions
# and are critical for DR failover:
# - Route53 hosted zones and DNS records
# - ACM certificates (primary + DR regions)
# - Health checks for failover routing
# - Failover routing policies
# ====================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    # Configured via backend.conf
  }
}

# Primary region provider
provider "aws" {
  region = var.primary_region

  default_tags {
    tags = var.tags
  }
}

# DR region provider
provider "aws" {
  alias  = "dr"
  region = var.dr_region

  default_tags {
    tags = merge(var.tags, {
      DisasterRecovery = "true"
    })
  }
}

# ====================================================================
# Data Sources - EKS Cluster Information
# ====================================================================

# Get primary EKS cluster info from main workspace state
data "terraform_remote_state" "primary" {
  count   = var.enable_primary_cluster ? 1 : 0
  backend = "s3"

  config = {
    bucket         = "${var.project_name}-prod-terraform-state"
    key            = "prod/terraform.tfstate"
    region         = var.primary_region
    dynamodb_table = "${var.project_name}-prod-terraform-locks"
    encrypt        = true
  }
}

# Get DR EKS cluster info from DR workspace state
data "terraform_remote_state" "dr" {
  count   = var.enable_dr_cluster ? 1 : 0
  backend = "s3"

  config = {
    bucket         = "${var.project_name}-drprod-terraform-state"
    key            = "dr-infrastructure/terraform.tfstate"
    region         = var.dr_region
    dynamodb_table = "${var.project_name}-drprod-terraform-locks"
    encrypt        = true
  }
}

# ====================================================================
# Route53 Hosted Zone
# ====================================================================

# Create or use existing hosted zone
resource "aws_route53_zone" "main" {
  count = var.create_hosted_zone ? 1 : 0

  name    = var.domain_name
  comment = "Managed by Terraform - ${var.project_name}"

  tags = {
    Name        = var.domain_name
    Environment = "global"
  }
}

# Use existing hosted zone
data "aws_route53_zone" "existing" {
  count = var.create_hosted_zone ? 0 : 1

  name         = var.domain_name
  private_zone = false
}

locals {
  hosted_zone_id = var.create_hosted_zone ? aws_route53_zone.main[0].zone_id : data.aws_route53_zone.existing[0].zone_id
  
  # EKS endpoints from remote states
  primary_eks_endpoint = var.enable_primary_cluster && length(data.terraform_remote_state.primary) > 0 ? try(data.terraform_remote_state.primary[0].outputs.cluster_endpoint, "") : ""
  dr_eks_endpoint      = var.enable_dr_cluster && length(data.terraform_remote_state.dr) > 0 ? try(data.terraform_remote_state.dr[0].outputs.dr_eks_cluster_endpoint, "") : ""
  
  # ALB endpoints (if available)
  primary_alb_dns = var.primary_alb_dns_name != "" ? var.primary_alb_dns_name : ""
  dr_alb_dns      = var.dr_alb_dns_name != "" ? var.dr_alb_dns_name : ""
}

# ====================================================================
# ACM Certificates - Primary Region
# ====================================================================

resource "aws_acm_certificate" "primary" {
  count = var.create_certificates ? 1 : 0

  domain_name               = var.domain_name
  subject_alternative_names = var.certificate_san
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name        = "${var.project_name}-primary-cert"
    Environment = "prod"
    Region      = var.primary_region
  }
}

# DNS validation records for primary cert
resource "aws_route53_record" "primary_cert_validation" {
  for_each = var.create_certificates ? {
    for dvo in aws_acm_certificate.primary[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = local.hosted_zone_id
}

# Certificate validation
resource "aws_acm_certificate_validation" "primary" {
  count = var.create_certificates ? 1 : 0

  certificate_arn         = aws_acm_certificate.primary[0].arn
  validation_record_fqdns = [for record in aws_route53_record.primary_cert_validation : record.fqdn]
}

# ====================================================================
# ACM Certificates - DR Region
# ====================================================================

resource "aws_acm_certificate" "dr" {
  count    = var.create_certificates && var.enable_dr_cluster ? 1 : 0
  provider = aws.dr

  domain_name               = var.domain_name
  subject_alternative_names = var.certificate_san
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name             = "${var.project_name}-dr-cert"
    Environment      = "drprod"
    Region           = var.dr_region
    DisasterRecovery = "true"
  }
}

# Certificate validation for DR (uses same DNS records)
resource "aws_acm_certificate_validation" "dr" {
  count    = var.create_certificates && var.enable_dr_cluster ? 1 : 0
  provider = aws.dr

  certificate_arn         = aws_acm_certificate.dr[0].arn
  validation_record_fqdns = [for record in aws_route53_record.primary_cert_validation : record.fqdn]
}

# ====================================================================
# Health Checks
# ====================================================================

# Primary cluster health check
resource "aws_route53_health_check" "primary" {
  count = var.enable_failover && var.primary_health_check_path != "" ? 1 : 0

  fqdn              = var.primary_health_check_fqdn
  port              = var.health_check_port
  type              = "HTTPS"
  resource_path     = var.primary_health_check_path
  failure_threshold = var.health_check_failure_threshold
  request_interval  = var.health_check_interval

  tags = {
    Name        = "${var.project_name}-primary-health-check"
    Environment = "prod"
    Region      = var.primary_region
  }
}

# DR cluster health check
resource "aws_route53_health_check" "dr" {
  count = var.enable_failover && var.dr_health_check_path != "" && var.enable_dr_cluster ? 1 : 0

  fqdn              = var.dr_health_check_fqdn
  port              = var.health_check_port
  type              = "HTTPS"
  resource_path     = var.dr_health_check_path
  failure_threshold = var.health_check_failure_threshold
  request_interval  = var.health_check_interval

  tags = {
    Name             = "${var.project_name}-dr-health-check"
    Environment      = "drprod"
    Region           = var.dr_region
    DisasterRecovery = "true"
  }
}

# ====================================================================
# DNS Records - Failover Configuration
# ====================================================================

# Primary DNS record (failover routing)
resource "aws_route53_record" "app_primary" {
  count = var.enable_failover && local.primary_alb_dns != "" ? 1 : 0

  zone_id = local.hosted_zone_id
  name    = var.app_subdomain != "" ? "${var.app_subdomain}.${var.domain_name}" : var.domain_name
  type    = "A"

  failover_routing_policy {
    type = "PRIMARY"
  }

  set_identifier  = "primary"
  health_check_id = var.enable_failover ? aws_route53_health_check.primary[0].id : null

  alias {
    name                   = local.primary_alb_dns
    zone_id                = var.primary_alb_zone_id
    evaluate_target_health = true
  }
}

# DR DNS record (failover routing)
resource "aws_route53_record" "app_dr" {
  count = var.enable_failover && local.dr_alb_dns != "" && var.enable_dr_cluster ? 1 : 0

  zone_id = local.hosted_zone_id
  name    = var.app_subdomain != "" ? "${var.app_subdomain}.${var.domain_name}" : var.domain_name
  type    = "A"

  failover_routing_policy {
    type = "SECONDARY"
  }

  set_identifier  = "dr"
  health_check_id = var.enable_failover && var.enable_dr_cluster ? aws_route53_health_check.dr[0].id : null

  alias {
    name                   = local.dr_alb_dns
    zone_id                = var.dr_alb_zone_id
    evaluate_target_health = true
  }
}

# ====================================================================
# Simple DNS Records (No Failover)
# ====================================================================

# Simple A record pointing to primary (when failover is disabled)
resource "aws_route53_record" "app_simple" {
  count = !var.enable_failover && local.primary_alb_dns != "" ? 1 : 0

  zone_id = local.hosted_zone_id
  name    = var.app_subdomain != "" ? "${var.app_subdomain}.${var.domain_name}" : var.domain_name
  type    = "A"

  alias {
    name                   = local.primary_alb_dns
    zone_id                = var.primary_alb_zone_id
    evaluate_target_health = true
  }
}

# ====================================================================
# Additional DNS Records
# ====================================================================

# ArgoCD subdomain
resource "aws_route53_record" "argocd" {
  count = var.argocd_alb_dns != "" ? 1 : 0

  zone_id = local.hosted_zone_id
  name    = "argocd.${var.domain_name}"
  type    = "A"

  alias {
    name                   = var.argocd_alb_dns
    zone_id                = var.argocd_alb_zone_id
    evaluate_target_health = true
  }
}

# Grafana subdomain
resource "aws_route53_record" "grafana" {
  count = var.grafana_alb_dns != "" ? 1 : 0

  zone_id = local.hosted_zone_id
  name    = "grafana.${var.domain_name}"
  type    = "A"

  alias {
    name                   = var.grafana_alb_dns
    zone_id                = var.grafana_alb_zone_id
    evaluate_target_health = true
  }
}

# API subdomain
resource "aws_route53_record" "api" {
  count = var.api_alb_dns != "" ? 1 : 0

  zone_id = local.hosted_zone_id
  name    = "api.${var.domain_name}"
  type    = "A"

  alias {
    name                   = var.api_alb_dns
    zone_id                = var.api_alb_zone_id
    evaluate_target_health = true
  }
}
