# ====================================================================
# Global Infrastructure Outputs
# ====================================================================

# ====================================================================
# Route53 Outputs - Multiple Domains
# ====================================================================

output "hosted_zone_ids" {
  description = "Map of hosted zone IDs by domain key"
  value       = local.hosted_zone_ids
}

output "hosted_zone_name_servers" {
  description = "Map of name servers by domain (only for created zones)"
  value = {
    for key, zone in aws_route53_zone.domains : key => zone.name_servers
  }
}

output "domain_names" {
  description = "List of all managed domain names"
  value       = [for k, d in local.all_domains : d.domain_name]
}

output "primary_domain" {
  description = "Primary domain name"
  value       = length(local.all_domains) > 0 ? local.primary_domain.domain_name : null
}

# ====================================================================
# Certificate Outputs - Primary Region (Multiple Domains)
# ====================================================================

output "primary_certificate_arns" {
  description = "Map of ACM certificate ARNs in primary region by domain"
  value = {
    for key, cert in aws_acm_certificate.primary : key => cert.arn
  }
}

output "primary_certificate_statuses" {
  description = "Map of certificate statuses in primary region by domain"
  value = {
    for key, cert in aws_acm_certificate.primary : key => cert.status
  }
}

# Legacy single-domain output for backward compatibility
output "primary_certificate_arn" {
  description = "ARN of the ACM certificate in primary region (primary domain)"
  value       = length(aws_acm_certificate.primary) > 0 && contains(keys(aws_acm_certificate.primary), local.primary_domain_key) ? aws_acm_certificate.primary[local.primary_domain_key].arn : null
}

# ====================================================================
# Certificate Outputs - DR Region (Multiple Domains)
# ====================================================================

output "dr_certificate_arns" {
  description = "Map of ACM certificate ARNs in DR region by domain"
  value = {
    for key, cert in aws_acm_certificate.dr : key => cert.arn
  }
}

output "dr_certificate_statuses" {
  description = "Map of certificate statuses in DR region by domain"
  value = {
    for key, cert in aws_acm_certificate.dr : key => cert.status
  }
}

# Legacy single-domain output for backward compatibility
output "dr_certificate_arn" {
  description = "ARN of the ACM certificate in DR region (primary domain)"
  value       = length(aws_acm_certificate.dr) > 0 && contains(keys(aws_acm_certificate.dr), local.primary_domain_key) ? aws_acm_certificate.dr[local.primary_domain_key].arn : null
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

output "app_fqdns" {
  description = "Map of FQDNs for the main application by domain"
  value = {
    for key, domain in local.all_domains : key => (
      domain.app_subdomain != "" ? "${domain.app_subdomain}.${domain.domain_name}" : domain.domain_name
    )
  }
}

# Legacy single-domain output for backward compatibility
output "app_fqdn" {
  description = "FQDN for the main application (primary domain)"
  value = length(local.all_domains) > 0 ? (
    local.primary_domain.app_subdomain != "" ? "${local.primary_domain.app_subdomain}.${local.primary_domain.domain_name}" : local.primary_domain.domain_name
  ) : null
}

output "argocd_fqdn" {
  description = "FQDN for ArgoCD"
  value       = var.argocd_alb_dns != "" && length(local.all_domains) > 0 ? "argocd.${local.primary_domain.domain_name}" : null
}

output "grafana_fqdn" {
  description = "FQDN for Grafana"
  value       = var.grafana_alb_dns != "" && length(local.all_domains) > 0 ? "grafana.${local.primary_domain.domain_name}" : null
}

output "api_fqdn" {
  description = "FQDN for API"
  value       = var.api_alb_dns != "" && length(local.all_domains) > 0 ? "api.${local.primary_domain.domain_name}" : null
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
    enabled                = var.enable_failover
    primary_healthy        = var.enable_failover && var.primary_health_check_path != "" ? "Check health_check_id" : "N/A"
    dr_healthy             = var.enable_failover && var.dr_health_check_path != "" && var.enable_dr_cluster ? "Check health_check_id" : "N/A"
    primary_alb_configured = local.primary_alb_dns != ""
    dr_alb_configured      = local.dr_alb_dns != ""
  }
}

# ====================================================================
# Integration Outputs (for other workspaces)
# ====================================================================

output "certificate_arns_by_domain" {
  description = "Map of certificate ARNs by domain and region"
  value = {
    for key, domain in local.all_domains : key => {
      primary = contains(keys(aws_acm_certificate.primary), key) ? aws_acm_certificate.primary[key].arn : null
      dr      = contains(keys(aws_acm_certificate.dr), key) ? aws_acm_certificate.dr[key].arn : null
    }
  }
}

# Legacy output for backward compatibility
output "certificate_arns" {
  description = "Map of certificate ARNs by region (primary domain only)"
  value = {
    primary = length(aws_acm_certificate.primary) > 0 && contains(keys(aws_acm_certificate.primary), local.primary_domain_key) ? aws_acm_certificate.primary[local.primary_domain_key].arn : null
    dr      = length(aws_acm_certificate.dr) > 0 && contains(keys(aws_acm_certificate.dr), local.primary_domain_key) ? aws_acm_certificate.dr[local.primary_domain_key].arn : null
  }
}

output "dns_configuration" {
  description = "DNS configuration for use in other workspaces"
  value = {
    hosted_zone_ids = local.hosted_zone_ids
    domain_names    = [for k, d in local.all_domains : d.domain_name]
    primary_domain  = length(local.all_domains) > 0 ? local.primary_domain.domain_name : null
  }
}

# ====================================================================
# Summary Output
# ====================================================================

output "summary" {
  description = "Summary of all managed domains and resources"
  value = {
    domains = {
      for key, domain in local.all_domains : key => {
        domain_name    = domain.domain_name
        hosted_zone_id = contains(keys(local.hosted_zone_ids), key) ? local.hosted_zone_ids[key] : null
        primary_cert   = contains(keys(aws_acm_certificate.primary), key) ? aws_acm_certificate.primary[key].arn : null
        dr_cert        = contains(keys(aws_acm_certificate.dr), key) ? aws_acm_certificate.dr[key].arn : null
      }
    }
    failover = {
      enabled              = var.enable_failover
      primary_health_check = var.enable_failover && var.primary_health_check_path != "" ? aws_route53_health_check.primary[0].id : null
      dr_health_check      = var.enable_failover && var.dr_health_check_path != "" && var.enable_dr_cluster ? aws_route53_health_check.dr[0].id : null
    }
  }
}
