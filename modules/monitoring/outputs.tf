output "monitoring_namespace" {
  description = "Monitoring namespace"
  value       = kubernetes_namespace.monitoring.metadata[0].name
}

output "prometheus_url" {
  description = "Prometheus URL"
  value       = var.enable_ingress ? "https://${var.prometheus_domain}" : "http://monitoring-prometheus.monitoring.svc.cluster.local:9090"
}

output "grafana_url" {
  description = "Grafana URL"
  value       = var.enable_grafana && var.enable_ingress ? "https://${var.grafana_domain}" : var.enable_grafana ? "http://grafana.monitoring.svc.cluster.local" : ""
}

output "alertmanager_url" {
  description = "Alertmanager URL"
  value       = var.enable_alertmanager && var.enable_ingress ? "https://${var.alertmanager_domain}" : var.enable_alertmanager ? "http://monitoring-alertmanager.monitoring.svc.cluster.local:9093" : ""
}

output "grafana_admin_password" {
  description = "Grafana admin password"
  value       = var.grafana_admin_password
  sensitive   = true
}