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
# Locals - Domain Configuration
# ====================================================================

locals {
  # Merge legacy single domain with new multi-domain support
  # If 'domains' is empty but 'domain_name' is set, create a single domain entry
  all_domains = length(var.domains) > 0 ? var.domains : (
    var.domain_name != "" ? {
      "default" = {
        domain_name        = var.domain_name
        create_hosted_zone = var.create_hosted_zone
        create_certificate = var.create_certificates
        certificate_san    = var.certificate_san
        app_subdomain      = var.app_subdomain
        primary            = true
      }
    } : {}
  )

  # Filter domains that need hosted zones created
  domains_create_zone       = { for k, v in local.all_domains : k => v if v.create_hosted_zone }
  domains_use_existing_zone = { for k, v in local.all_domains : k => v if !v.create_hosted_zone }

  # Filter domains that need certificates
  domains_with_certs = { for k, v in local.all_domains : k => v if v.create_certificate }

  # Get primary domain for failover
  primary_domain_key = [for k, v in local.all_domains : k if v.primary][0]
  primary_domain     = local.all_domains[local.primary_domain_key]

  # Build hosted zone ID map
  hosted_zone_ids = merge(
    { for k, v in aws_route53_zone.domains : k => v.zone_id },
    { for k, v in data.aws_route53_zone.existing : k => v.zone_id }
  )

  # EKS endpoints from remote states
  primary_eks_endpoint = var.enable_primary_cluster && length(data.terraform_remote_state.primary) > 0 ? try(data.terraform_remote_state.primary[0].outputs.cluster_endpoint, "") : ""
  dr_eks_endpoint      = var.enable_dr_cluster && length(data.terraform_remote_state.dr) > 0 ? try(data.terraform_remote_state.dr[0].outputs.dr_eks_cluster_endpoint, "") : ""

  # ALB endpoints (if available)
  primary_alb_dns = var.primary_alb_dns_name != "" ? var.primary_alb_dns_name : ""
  dr_alb_dns      = var.dr_alb_dns_name != "" ? var.dr_alb_dns_name : ""
}

# ====================================================================
# Route53 Hosted Zones - Multiple Domains
# ====================================================================

# Create new hosted zones
resource "aws_route53_zone" "domains" {
  for_each = local.domains_create_zone

  name    = each.value.domain_name
  comment = "Managed by Terraform - ${var.project_name} - ${each.key}"

  tags = {
    Name        = each.value.domain_name
    DomainKey   = each.key
    Environment = "global"
  }
}

# Use existing hosted zones
data "aws_route53_zone" "existing" {
  for_each = local.domains_use_existing_zone

  name         = each.value.domain_name
  private_zone = false
}

# ====================================================================
# ACM Certificates - Primary Region (Multiple Domains)
# ====================================================================

resource "aws_acm_certificate" "primary" {
  for_each = local.domains_with_certs

  domain_name               = each.value.domain_name
  subject_alternative_names = each.value.certificate_san
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name        = "${var.project_name}-${each.key}-primary-cert"
    DomainKey   = each.key
    Domain      = each.value.domain_name
    Environment = "prod"
    Region      = var.primary_region
  }
}

# DNS validation records for primary certs
resource "aws_route53_record" "primary_cert_validation" {
  for_each = {
    for item in flatten([
      for domain_key, domain in local.domains_with_certs : [
        for dvo in aws_acm_certificate.primary[domain_key].domain_validation_options : {
          key        = "${domain_key}-${dvo.domain_name}"
          domain_key = domain_key
          name       = dvo.resource_record_name
          record     = dvo.resource_record_value
          type       = dvo.resource_record_type
        }
      ]
    ]) : item.key => item
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = local.hosted_zone_ids[each.value.domain_key]
}

# Certificate validation - Primary
resource "aws_acm_certificate_validation" "primary" {
  for_each = local.domains_with_certs

  certificate_arn = aws_acm_certificate.primary[each.key].arn
  validation_record_fqdns = [
    for record in aws_route53_record.primary_cert_validation : record.fqdn
    if startswith(record.name, each.value.domain_name) || endswith(record.name, ".${each.value.domain_name}.")
  ]
}

# ====================================================================
# ACM Certificates - DR Region (Multiple Domains)
# ====================================================================

resource "aws_acm_certificate" "dr" {
  for_each = var.enable_dr_cluster ? local.domains_with_certs : {}
  provider = aws.dr

  domain_name               = each.value.domain_name
  subject_alternative_names = each.value.certificate_san
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name             = "${var.project_name}-${each.key}-dr-cert"
    DomainKey        = each.key
    Domain           = each.value.domain_name
    Environment      = "drprod"
    Region           = var.dr_region
    DisasterRecovery = "true"
  }
}

# Certificate validation - DR (uses same DNS records as primary)
resource "aws_acm_certificate_validation" "dr" {
  for_each = var.enable_dr_cluster ? local.domains_with_certs : {}
  provider = aws.dr

  certificate_arn = aws_acm_certificate.dr[each.key].arn
  validation_record_fqdns = [
    for record in aws_route53_record.primary_cert_validation : record.fqdn
    if startswith(record.name, each.value.domain_name) || endswith(record.name, ".${each.value.domain_name}.")
  ]
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
# DNS Records - Failover Configuration (Primary Domain Only)
# ====================================================================

# Primary DNS record (failover routing)
resource "aws_route53_record" "app_primary" {
  count = var.enable_failover && local.primary_alb_dns != "" && length(local.all_domains) > 0 ? 1 : 0

  zone_id = local.hosted_zone_ids[local.primary_domain_key]
  name    = local.primary_domain.app_subdomain != "" ? "${local.primary_domain.app_subdomain}.${local.primary_domain.domain_name}" : local.primary_domain.domain_name
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
  count = var.enable_failover && local.dr_alb_dns != "" && var.enable_dr_cluster && length(local.all_domains) > 0 ? 1 : 0

  zone_id = local.hosted_zone_ids[local.primary_domain_key]
  name    = local.primary_domain.app_subdomain != "" ? "${local.primary_domain.app_subdomain}.${local.primary_domain.domain_name}" : local.primary_domain.domain_name
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
# Simple DNS Records (No Failover) - All Domains
# ====================================================================

# Simple A record pointing to primary for each domain (when failover is disabled)
resource "aws_route53_record" "app_simple" {
  for_each = !var.enable_failover && local.primary_alb_dns != "" ? local.all_domains : {}

  zone_id = local.hosted_zone_ids[each.key]
  name    = each.value.app_subdomain != "" ? "${each.value.app_subdomain}.${each.value.domain_name}" : each.value.domain_name
  type    = "A"

  alias {
    name                   = local.primary_alb_dns
    zone_id                = var.primary_alb_zone_id
    evaluate_target_health = true
  }
}

# ====================================================================
# Additional DNS Records (Primary Domain Only)
# ====================================================================

# ArgoCD subdomain
resource "aws_route53_record" "argocd" {
  count = var.argocd_alb_dns != "" && length(local.all_domains) > 0 ? 1 : 0

  zone_id = local.hosted_zone_ids[local.primary_domain_key]
  name    = "argocd.${local.primary_domain.domain_name}"
  type    = "A"

  alias {
    name                   = var.argocd_alb_dns
    zone_id                = var.argocd_alb_zone_id
    evaluate_target_health = true
  }
}

# Grafana subdomain
resource "aws_route53_record" "grafana" {
  count = var.grafana_alb_dns != "" && length(local.all_domains) > 0 ? 1 : 0

  zone_id = local.hosted_zone_ids[local.primary_domain_key]
  name    = "grafana.${local.primary_domain.domain_name}"
  type    = "A"

  alias {
    name                   = var.grafana_alb_dns
    zone_id                = var.grafana_alb_zone_id
    evaluate_target_health = true
  }
}

# API subdomain
resource "aws_route53_record" "api" {
  count = var.api_alb_dns != "" && length(local.all_domains) > 0 ? 1 : 0

  zone_id = local.hosted_zone_ids[local.primary_domain_key]
  name    = "api.${local.primary_domain.domain_name}"
  type    = "A"

  alias {
    name                   = var.api_alb_dns
    zone_id                = var.api_alb_zone_id
    evaluate_target_health = true
  }
}
