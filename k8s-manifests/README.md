# Kubernetes Manifests - Multi-Environment Setup

This directory contains Kubernetes manifests organized using **Kustomize** for multi-environment deployments (dev, staging, production).

## 📁 Directory Structure

```
k8s-manifests/
├── README.md                       # This file
├── base/                           # Base configurations (common to all environments)
│   ├── kustomization.yaml
│   ├── argocd/                     # ArgoCD configurations
│   │   ├── kustomization.yaml
│   │   ├── namespace.yaml
│   │   ├── appproject.yaml
│   │   ├── app-of-apps.yaml
│   │   └── external-secrets.yaml
│   ├── ingress-controller/         # ALB Ingress Controller
│   │   ├── kustomization.yaml
│   │   └── ingress-class.yaml
│   └── monitoring/                 # Prometheus monitoring
│       ├── kustomization.yaml
│       ├── namespace.yaml
│       ├── service-monitors.yaml
│       └── prometheus-rules.yaml
│
├── overlays/                       # Environment-specific overrides
│   ├── dev/                        # Development environment
│   │   ├── kustomization.yaml
│   │   ├── argocd-patch.yaml
│   │   ├── ingress-patch.yaml
│   │   ├── secrets-patch.yaml
│   │   └── monitoring-patch.yaml
│   ├── staging/                    # Staging environment
│   │   ├── kustomization.yaml
│   │   ├── argocd-patch.yaml
│   │   ├── ingress-patch.yaml
│   │   ├── secrets-patch.yaml
│   │   └── monitoring-patch.yaml
│   └── prod/                       # Production environment
│       ├── kustomization.yaml
│       ├── argocd-patch.yaml
│       ├── ingress-patch.yaml
│       ├── secrets-patch.yaml
│       ├── monitoring-patch.yaml
│       └── resource-quotas.yaml
│
└── argocd/                         # ArgoCD ApplicationSet
    └── applicationset.yaml         # Auto-generates apps for all environments
```

## 🎯 Design Principles

1. **DRY (Don't Repeat Yourself)**: Common configurations are in `base/`, environment-specific changes are in `overlays/`
2. **GitOps Ready**: Designed to work seamlessly with ArgoCD
3. **Environment Parity**: All environments use the same base with targeted patches
4. **Security**: Production has stricter policies, resource quotas, and monitoring
5. **Scalability**: Easy to add new environments by creating new overlays

## 🚀 Quick Start

### Prerequisites

- `kubectl` installed and configured
- `kustomize` v4.0+ (or use `kubectl apply -k`)
- Access to the EKS cluster

### Deploy to an Environment

```bash
# Development
kubectl apply -k overlays/dev

# Staging
kubectl apply -k overlays/staging

# Production
kubectl apply -k overlays/prod
```

### Preview Changes (Dry Run)

```bash
# See what will be applied
kubectl kustomize overlays/prod

# Validate before applying
kubectl apply -k overlays/prod --dry-run=server
```

### Build and Inspect

```bash
# Build the manifests locally
kustomize build overlays/prod > prod-manifests.yaml

# View differences between environments
diff <(kustomize build overlays/dev) <(kustomize build overlays/prod)
```

## 🔧 Environment Configurations

### Development Environment

**Purpose**: Rapid development and testing

**Characteristics**:
- Internal-only ingress (no public access)
- Debug-level logging
- Relaxed monitoring alerts (15m grace period)
- Lower resource limits
- Cost-optimized

**Secrets Path**: `pipeops/dev/rds/credentials`

### Staging Environment

**Purpose**: Pre-production testing and validation

**Characteristics**:
- Public internet-facing ingress
- Info-level logging
- Moderate monitoring alerts (10m grace period)
- Production-like configuration
- Automated sync with ArgoCD

**Secrets Path**: `pipeops/staging/rds/credentials`

### Production Environment

**Purpose**: Live production workloads

**Characteristics**:
- Public internet-facing with WAF
- Warning-level logging (minimal)
- Strict monitoring alerts (5m grace period)
- Resource quotas and limit ranges enforced
- **Manual sync** (requires approval)
- Multi-region DR database support
- PagerDuty integration for critical alerts

**Secrets Path**: 
- Primary: `pipeops/prod/rds/credentials`
- DR: `pipeops/prod/rds/credentials` (with `dr_endpoint`)

## 🔑 Key Differences Between Environments

| Feature | Dev | Staging | Production |
|---------|-----|---------|------------|
| **Ingress** | Internal | Internet-facing | Internet-facing + WAF |
| **Logging** | Debug | Info | Warning |
| **Alert Grace Period** | 15 minutes | 10 minutes | 5 minutes |
| **Alert Severity** | Info | Warning | Critical + PagerDuty |
| **ArgoCD Sync** | Automated | Automated | Manual |
| **Resource Quotas** | None | Optional | Enforced |
| **TLS Policy** | Standard | Standard | Strict (TLS 1.2+) |
| **Multi-Region DR** | No | No | Yes (us-east-1) |
| **Cost** | Low | Medium | High |

## 🔐 Secrets Management

All environments use **AWS Secrets Manager** via the **External Secrets Operator**:

1. Secrets are stored in AWS Secrets Manager
2. External Secrets Operator pulls secrets into Kubernetes
3. Applications consume secrets as standard Kubernetes Secrets

### Required Secrets

Each environment needs these secrets in AWS Secrets Manager:

```json
{
  "username": "postgres",
  "password": "generated-password",
  "endpoint": "rds-endpoint.region.rds.amazonaws.com",
  "port": "5432",
  "dbname": "pipeops"
}
```

**Secret Paths**:
- Dev: `pipeops/dev/rds/credentials`
- Staging: `pipeops/staging/rds/credentials`
- Production: `pipeops/prod/rds/credentials`

## 🎨 Customizing for Your Environment

### Update Repository URLs

Edit these files to use your Git repository:

```bash
# Base configuration
base/argocd/appproject.yaml
base/argocd/app-of-apps.yaml
argocd/applicationset.yaml
```

### Update AWS Account IDs

Replace `ACCOUNT_ID` placeholders in:

```bash
overlays/dev/secrets-patch.yaml
overlays/staging/secrets-patch.yaml
overlays/prod/secrets-patch.yaml
overlays/prod/ingress-patch.yaml
```

### Update Domains

Replace domain placeholders in:

```bash
overlays/dev/ingress-patch.yaml    # app-dev.pipeops.internal
overlays/staging/ingress-patch.yaml # app-staging.pipeops.com
overlays/prod/ingress-patch.yaml    # app.pipeops.com
```

## 📊 ArgoCD Integration

### Option 1: Manual Application Creation

Create ArgoCD Applications manually for each environment:

```bash
# Apply the environment overlays
kubectl apply -k overlays/dev
kubectl apply -k overlays/staging
kubectl apply -k overlays/prod
```

### Option 2: ApplicationSet (Recommended)

Use the ApplicationSet to automatically manage all environments:

```bash
# Apply the ApplicationSet
kubectl apply -f argocd/applicationset.yaml

# This creates 3 ArgoCD Applications:
# - infrastructure-dev
# - infrastructure-staging
# - infrastructure-prod
```

### View Applications in ArgoCD

```bash
# List all applications
kubectl get applications -n argocd

# Watch sync status
watch kubectl get applications -n argocd

# View in ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Open: https://localhost:8080
```

## 🔄 Common Operations

### Sync an Environment

```bash
# Via kubectl
kubectl apply -k overlays/staging

# Via ArgoCD CLI
argocd app sync infrastructure-staging

# Via ArgoCD UI
# Navigate to the application and click "Sync"
```

### Rollback a Deployment

```bash
# Via ArgoCD CLI
argocd app rollback infrastructure-prod <revision>

# Via kubectl (reapply previous version)
git checkout <previous-commit>
kubectl apply -k overlays/prod
```

### Promote from Staging to Production

```bash
# 1. Test in staging
kubectl apply -k overlays/staging
# ... verify everything works ...

# 2. Update production overlay if needed
# Edit overlays/prod/*.yaml

# 3. Deploy to production (with approval)
kubectl apply -k overlays/prod
```

## 🧪 Testing Your Changes

```bash
# Validate YAML syntax
kustomize build overlays/dev > /dev/null && echo "✅ Valid"

# Check for differences
diff <(kustomize build overlays/dev) <(kustomize build overlays/staging)

# Dry-run before applying
kubectl apply -k overlays/prod --dry-run=server

# Apply with validation
kubectl apply -k overlays/prod --validate=strict
```

## 📈 Monitoring

### View Alerts

```bash
# Check PrometheusRules
kubectl get prometheusrules -n monitoring

# View active alerts
kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090
# Open: http://localhost:9090/alerts
```

### View Service Monitors

```bash
# List ServiceMonitors
kubectl get servicemonitors -n monitoring

# Check ArgoCD metrics
kubectl port-forward -n argocd svc/argocd-metrics 8082:8082
curl http://localhost:8082/metrics
```

## 🛡️ Security Best Practices

1. **Least Privilege**: Each environment has its own IAM role with minimal permissions
2. **Secret Rotation**: Secrets are rotated automatically via AWS Secrets Manager
3. **Network Isolation**: Development is internal-only, production has WAF
4. **Resource Limits**: Production has strict resource quotas
5. **Audit Trail**: All changes are tracked via Git and ArgoCD

## 🐛 Troubleshooting

### Kustomize Build Fails

```bash
# Check for syntax errors
kustomize build overlays/prod 2>&1 | head -20

# Common issues:
# - Missing patches
# - Invalid YAML indentation
# - Non-existent base resources
```

### ArgoCD Application Out of Sync

```bash
# Check differences
argocd app diff infrastructure-prod

# Force sync
argocd app sync infrastructure-prod --force

# Check application logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller
```

### External Secrets Not Working

```bash
# Check External Secrets Operator
kubectl get externalsecrets -n argocd
kubectl describe externalsecret database-credentials -n argocd

# Check IAM role permissions
kubectl describe sa external-secrets-sa -n argocd

# Verify AWS Secrets Manager connectivity
kubectl logs -n external-secrets deployment/external-secrets
```

## 📚 Additional Resources

- [Kustomize Documentation](https://kustomize.io/)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [External Secrets Operator](https://external-secrets.io/)
- [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)

## 🤝 Contributing

When making changes:

1. Create a feature branch
2. Test in dev environment first
3. Validate with `kustomize build`
4. Submit PR with description of changes
5. After approval, promote to staging, then production

---

**Maintained by**: Platform Team  
**Last Updated**: 2026-01-21
