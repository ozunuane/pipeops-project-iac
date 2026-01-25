# ====================================================================
# Global Infrastructure Outputs
# ====================================================================

# ====================================================================
# Route53 Outputs
# ====================================================================

output "hosted_zone_id" {
  description = "Route53 hosted zone ID"
  value       = local.hosted_zone_id
}

output "hosted_zone_name_servers" {
  description = "Name servers for the hosted zone (if created)"
  value       = var.create_hosted_zone ? aws_route53_zone.main[0].name_servers : []
}

output "domain_name" {
  description = "Domain name"
  value       = var.domain_name
}

# ====================================================================
# Certificate Outputs - Primary
# ====================================================================

output "primary_certificate_arn" {
  description = "ARN of the ACM certificate in primary region"
  value       = var.create_certificates ? aws_acm_certificate.primary[0].arn : null
}

output "primary_certificate_status" {
  description = "Status of the primary certificate"
  value       = var.create_certificates ? aws_acm_certificate.primary[0].status : null
}

output "primary_certificate_domain_validation_options" {
  description = "Domain validation options for primary certificate"
  value       = var.create_certificates ? aws_acm_certificate.primary[0].domain_validation_options : []
}

# ====================================================================
# Certificate Outputs - DR
# ====================================================================

output "dr_certificate_arn" {
  description = "ARN of the ACM certificate in DR region"
  value       = var.create_certificates && var.enable_dr_cluster ? aws_acm_certificate.dr[0].arn : null
}

output "dr_certificate_status" {
  description = "Status of the DR certificate"
  value       = var.create_certificates && var.enable_dr_cluster ? aws_acm_certificate.dr[0].status : null
}

# ====================================================================
# Health Check Outputs
# ====================================================================

output "primary_health_check_id" {
  description = "ID of the primary health check"
  value       = var.enable_failover && var.primary_health_check_path != "" ? aws_route53_health_check.primary[0].id : null
}

output "dr_health_check_id" {
  description = "ID of the DR health check"
  value       = var.enable_failover && var.dr_health_check_path != "" && var.enable_dr_cluster ? aws_route53_health_check.dr[0].id : null
}

# ====================================================================
# DNS Record Outputs
# ====================================================================

output "app_fqdn" {
  description = "FQDN for the main application"
  value       = var.app_subdomain != "" ? "${var.app_subdomain}.${var.domain_name}" : var.domain_name
}

output "argocd_fqdn" {
  description = "FQDN for ArgoCD"
  value       = var.argocd_alb_dns != "" ? "argocd.${var.domain_name}" : null
}

output "grafana_fqdn" {
  description = "FQDN for Grafana"
  value       = var.grafana_alb_dns != "" ? "grafana.${var.domain_name}" : null
}

output "api_fqdn" {
  description = "FQDN for API"
  value       = var.api_alb_dns != "" ? "api.${var.domain_name}" : null
}

# ====================================================================
# Failover Configuration
# ====================================================================

output "failover_enabled" {
  description = "Whether failover routing is enabled"
  value       = var.enable_failover
}

output "failover_status" {
  description = "Current failover configuration status"
  value = {
    enabled              = var.enable_failover
    primary_healthy      = var.enable_failover && var.primary_health_check_path != "" ? "Check health_check_id" : "N/A"
    dr_healthy           = var.enable_failover && var.dr_health_check_path != "" && var.enable_dr_cluster ? "Check health_check_id" : "N/A"
    primary_alb_configured = local.primary_alb_dns != ""
    dr_alb_configured      = local.dr_alb_dns != ""
  }
}

# ====================================================================
# Integration Outputs (for other workspaces)
# ====================================================================

output "certificate_arns" {
  description = "Map of certificate ARNs by region"
  value = {
    primary = var.create_certificates ? aws_acm_certificate.primary[0].arn : null
    dr      = var.create_certificates && var.enable_dr_cluster ? aws_acm_certificate.dr[0].arn : null
  }
}

output "dns_configuration" {
  description = "DNS configuration for use in other workspaces"
  value = {
    hosted_zone_id = local.hosted_zone_id
    domain_name    = var.domain_name
    app_subdomain  = var.app_subdomain
  }
}
