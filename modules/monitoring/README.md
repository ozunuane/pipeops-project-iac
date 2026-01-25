# Monitoring Module

Prometheus and Grafana stack for Kubernetes observability.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              Monitoring Stack                                    │
│                                                                                 │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                          Prometheus                                       │   │
│  │                                                                           │   │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐          │   │
│  │  │  Prometheus     │  │  AlertManager   │  │  Node Exporter  │          │   │
│  │  │  Server         │  │                 │  │  (per node)     │          │   │
│  │  └─────────────────┘  └─────────────────┘  └─────────────────┘          │   │
│  │           │                   │                                           │   │
│  │           │ Metrics           │ Alerts                                    │   │
│  │           ▼                   ▼                                           │   │
│  │  ┌─────────────────┐  ┌─────────────────┐                                │   │
│  │  │  Grafana        │  │  Slack/PagerDuty│                                │   │
│  │  │  (Dashboards)   │  │  (Notifications)│                                │   │
│  │  └─────────────────┘  └─────────────────┘                                │   │
│  │                                                                           │   │
│  └───────────────────────────────────────────────────────────────────────────┘   │
│                                                                                 │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                        Data Sources                                       │   │
│  │                                                                           │   │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐          │   │
│  │  │  kube-state-    │  │  cAdvisor       │  │  ServiceMonitors│          │   │
│  │  │  metrics        │  │  (containers)   │  │  (custom apps)  │          │   │
│  │  └─────────────────┘  └─────────────────┘  └─────────────────┘          │   │
│  │                                                                           │   │
│  └───────────────────────────────────────────────────────────────────────────┘   │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

## Features

| Feature | Description |
|---------|-------------|
| **Prometheus** | Metrics collection and storage |
| **Grafana** | Visualization and dashboards |
| **AlertManager** | Alert routing and notifications |
| **ServiceMonitor** | Automatic service discovery |
| **Pre-built Dashboards** | Kubernetes, ArgoCD, RDS dashboards |

## Usage

```hcl
module "monitoring" {
  source = "./modules/monitoring"

  project_name = "pipeops"
  environment  = "prod"
  
  # Prometheus configuration
  prometheus_retention = "15d"
  prometheus_storage   = "50Gi"
  
  # Grafana configuration
  grafana_admin_password = random_password.grafana_admin.result
  grafana_replicas       = var.environment == "prod" ? 2 : 1
  
  # Alert configuration
  slack_webhook_url     = var.slack_webhook_url
  pagerduty_service_key = var.pagerduty_service_key
  
  tags = {
    Environment = "prod"
    ManagedBy   = "terraform"
  }

  depends_on = [module.eks]
}
```

## Variables

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `enable_monitoring` | Enable monitoring stack | `bool` | `true` |
| `prometheus_retention` | Metrics retention period | `string` | `"15d"` |
| `prometheus_storage` | Storage size | `string` | `"50Gi"` |
| `grafana_admin_password` | Grafana admin password | `string` | - |
| `slack_webhook_url` | Slack webhook for alerts | `string` | `""` |

## Outputs

| Name | Description |
|------|-------------|
| `prometheus_endpoint` | Prometheus internal endpoint |
| `grafana_endpoint` | Grafana internal endpoint |
| `alertmanager_endpoint` | AlertManager internal endpoint |

## Accessing Services

### Grafana

```bash
# Port forward
kubectl port-forward svc/grafana -n monitoring 3000:80

# Access at http://localhost:3000
# Username: admin
# Password: (from terraform output grafana_admin_password)
```

### Prometheus

```bash
# Port forward
kubectl port-forward svc/prometheus-server -n monitoring 9090:9090

# Access at http://localhost:9090
```

## Pre-built Dashboards

| Dashboard | Description |
|-----------|-------------|
| **Kubernetes Cluster** | Cluster overview, node metrics |
| **Kubernetes Pods** | Pod resource usage |
| **ArgoCD** | Application sync status |
| **RDS** | Database performance metrics |
| **ALB** | Load balancer metrics |

## ServiceMonitor

Monitor custom applications:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: myapp
  namespace: monitoring
  labels:
    release: prometheus
spec:
  selector:
    matchLabels:
      app: myapp
  namespaceSelector:
    matchNames:
      - myapp-namespace
  endpoints:
    - port: metrics
      interval: 30s
      path: /metrics
```

## Alert Rules

### Example PrometheusRule

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: myapp-alerts
  namespace: monitoring
spec:
  groups:
    - name: myapp
      rules:
        - alert: HighErrorRate
          expr: |
            sum(rate(http_requests_total{status=~"5.."}[5m])) /
            sum(rate(http_requests_total[5m])) > 0.05
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "High error rate detected"
            description: "Error rate is above 5%"
```

### Default Alerts

| Alert | Severity | Description |
|-------|----------|-------------|
| `KubePodCrashLooping` | warning | Pod restarting frequently |
| `KubePodNotReady` | warning | Pod not ready for 15min |
| `NodeNotReady` | critical | Node unhealthy |
| `HighMemoryUsage` | warning | Memory > 85% |
| `HighCPUUsage` | warning | CPU > 85% |

## AlertManager Configuration

### Slack Integration

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: alertmanager-config
  namespace: monitoring
stringData:
  alertmanager.yaml: |
    global:
      slack_api_url: 'https://hooks.slack.com/services/xxx'
    route:
      receiver: 'slack'
      group_by: ['alertname', 'namespace']
      group_wait: 30s
      group_interval: 5m
      repeat_interval: 4h
    receivers:
      - name: 'slack'
        slack_configs:
          - channel: '#alerts'
            send_resolved: true
```

## Metrics

### Key Prometheus Queries

```promql
# CPU usage by namespace
sum(rate(container_cpu_usage_seconds_total[5m])) by (namespace)

# Memory usage by namespace
sum(container_memory_usage_bytes) by (namespace)

# HTTP request rate
sum(rate(http_requests_total[5m])) by (service)

# Pod restart count
sum(kube_pod_container_status_restarts_total) by (namespace, pod)
```

## Storage

### Prometheus PVC

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: prometheus-server
  namespace: monitoring
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 50Gi
  storageClassName: gp3
```

## Cost Considerations

| Component | Estimated Cost |
|-----------|----------------|
| **Prometheus PVC (50Gi)** | ~$5/month |
| **Grafana PVC (10Gi)** | ~$1/month |
| **Node Exporter** | Minimal (DaemonSet) |

## Security

1. **Network Policies**: Restrict Prometheus access
2. **RBAC**: Limit Grafana permissions
3. **Secrets**: Store credentials in Secrets Manager
4. **TLS**: Enable HTTPS for dashboards

## Troubleshooting

### No Metrics from Service

```bash
# Check ServiceMonitor
kubectl get servicemonitor -n monitoring

# Check Prometheus targets
# Go to Prometheus UI > Status > Targets

# Verify service labels match
kubectl get svc myapp -o yaml | grep -A5 labels
```

### Alerts Not Firing

```bash
# Check PrometheusRule
kubectl get prometheusrule -n monitoring

# Check AlertManager status
kubectl port-forward svc/alertmanager -n monitoring 9093:9093
# Access http://localhost:9093
```
