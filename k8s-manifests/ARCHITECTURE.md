# K8s Manifests Architecture

## 🏗️ Directory Structure

```
k8s-manifests/
│
├── 📄 README.md                    # Main documentation (500+ lines)
├── 📄 MIGRATION_GUIDE.md          # Migration instructions (350+ lines)
├── 📄 ARCHITECTURE.md             # This file
│
├── 📁 base/                        # Common configurations (DRY principle)
│   ├── kustomization.yaml         # Base orchestration
│   │
│   ├── 📁 argocd/                 # ArgoCD GitOps
│   │   ├── kustomization.yaml
│   │   ├── namespace.yaml         # argocd namespace
│   │   ├── appproject.yaml        # Template project (patched per env)
│   │   ├── app-of-apps.yaml       # Root application (patched per env)
│   │   └── external-secrets.yaml  # AWS Secrets Manager integration
│   │
│   ├── 📁 ingress-controller/     # AWS Load Balancer Controller
│   │   ├── kustomization.yaml
│   │   └── ingress-class.yaml     # ALB ingress + sample ingress
│   │
│   └── 📁 monitoring/             # Prometheus/Grafana
│       ├── kustomization.yaml
│       ├── namespace.yaml         # monitoring namespace
│       ├── service-monitors.yaml  # Scrape ArgoCD metrics
│       └── prometheus-rules.yaml  # Alert definitions
│
├── 📁 overlays/                    # Environment-specific configurations
│   │
│   ├── 📁 dev/                     # Development Environment
│   │   ├── kustomization.yaml     # Orchestrates dev patches
│   │   ├── argocd-patch.yaml      # Project: dev, auto-sync
│   │   ├── ingress-patch.yaml     # Internal-only, app-dev.internal
│   │   ├── secrets-patch.yaml     # pipeops/dev/rds/credentials
│   │   └── monitoring-patch.yaml  # Relaxed alerts (15m)
│   │
│   ├── 📁 staging/                 # Staging Environment
│   │   ├── kustomization.yaml     # Orchestrates staging patches
│   │   ├── argocd-patch.yaml      # Project: staging, auto-sync
│   │   ├── ingress-patch.yaml     # Public, app-staging.com, SSL
│   │   ├── secrets-patch.yaml     # pipeops/staging/rds/credentials
│   │   └── monitoring-patch.yaml  # Moderate alerts (10m)
│   │
│   └── 📁 prod/                    # Production Environment
│       ├── kustomization.yaml     # Orchestrates prod patches
│       ├── argocd-patch.yaml      # Project: production, manual-sync
│       ├── ingress-patch.yaml     # Public, app.com, SSL+WAF
│       ├── secrets-patch.yaml     # pipeops/prod/rds/credentials + DR
│       ├── monitoring-patch.yaml  # Strict alerts (5m), PagerDuty
│       └── resource-quotas.yaml   # CPU/memory limits & quotas
│
├── 📁 argocd/                      # ArgoCD automation
│   └── applicationset.yaml        # Generates apps for all 3 envs
│
└── 📁 _archive/                    # Old structure (for rollback)
    ├── README.md                  # Archive explanation
    ├── app-of-apps.yaml           # Old flat file
    ├── sample-app.yaml            # Old flat file
    ├── ingress-class.yaml         # Old flat file
    └── service-monitor.yaml       # Old flat file
```

## 🔄 Data Flow

### 1. Development Workflow
```
Developer                Git Repository              Kubernetes Cluster
    |                           |                            |
    |--[1. Edit overlays]------>|                            |
    |                           |                            |
    |                           |<----[2. ArgoCD polls]------|
    |                           |                            |
    |                           |-----[3. Sync]------------->|
    |                           |                            |
    |                           |                    [4. Apply patches]
    |                           |                            |
    |                           |                    [5. Create resources]
    |                           |                            |
    |<-----------[6. View in ArgoCD UI]---------------------|
```

### 2. Environment Promotion
```
Dev Environment         Staging Environment      Production Environment
       |                        |                         |
       |--[Test & Validate]---->|                         |
       |                        |                         |
       |                        |--[QA Approval]--------->|
       |                        |                         |
       |                        |                [Manual Review]
       |                        |                         |
       |                        |                   [Deploy with
       |                        |                    approval]
```

### 3. Kustomize Build Process
```
Base Resources           Overlays                  Final Manifest
      |                     |                            |
namespace.yaml            |                            |
appproject.yaml           |                            |
app-of-apps.yaml          |                            |
external-secrets.yaml     |                            |
ingress-class.yaml        |                            |
service-monitors.yaml     |                            |
prometheus-rules.yaml     |                            |
      |                     |                            |
      |-------[Load Base]-->|                            |
      |                     |                            |
      |              [Apply Patches]                     |
      |                 (dev/staging/prod)               |
      |                     |                            |
      |                     |--[Merge & Generate]------->|
      |                     |                            |
      |                     |                    [Deploy to K8s]
```

## 🌍 Multi-Environment Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      Git Repository                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐         │
│  │ k8s-manifests│  │ k8s-manifests│  │ k8s-manifests│         │
│  │ overlays/dev │  │overlays/stag │  │ overlays/prod│         │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘         │
└─────────┼──────────────────┼──────────────────┼─────────────────┘
          │                  │                  │
          │                  │                  │
    ┌─────▼──────┐    ┌──────▼─────┐    ┌──────▼─────┐
    │  ArgoCD    │    │  ArgoCD    │    │  ArgoCD    │
    │Application │    │Application │    │Application │
    │   (dev)    │    │ (staging)  │    │  (prod)    │
    └─────┬──────┘    └──────┬─────┘    └──────┬─────┘
          │                  │                  │
          │ Auto-Sync        │ Auto-Sync        │ Manual-Sync
          │                  │                  │
    ┌─────▼──────┐    ┌──────▼─────┐    ┌──────▼─────┐
    │   Dev EKS  │    │Staging EKS │    │  Prod EKS  │
    │  Cluster   │    │  Cluster   │    │  Cluster   │
    │            │    │            │    │            │
    │ ┌────────┐ │    │ ┌────────┐ │    │ ┌────────┐ │
    │ │ArgoCD  │ │    │ │ArgoCD  │ │    │ │ArgoCD  │ │
    │ │Ingress │ │    │ │Ingress │ │    │ │Ingress │ │
    │ │Monitor │ │    │ │Monitor │ │    │ │Monitor │ │
    │ └────────┘ │    │ └────────┘ │    │ └────────┘ │
    │            │    │            │    │            │
    │ ┌────────┐ │    │ ┌────────┐ │    │ ┌────────┐ │
    │ │RDS     │ │    │ │RDS     │ │    │ │RDS     │ │
    │ │Single  │ │    │ │Multi-AZ│ │    │ │Multi-AZ│ │
    │ │AZ      │ │    │ │        │ │    │ │+ DR    │ │
    │ └────────┘ │    │ └────────┘ │    │ └────────┘ │
    │            │    │            │    │            │
    │us-west-2   │    │us-west-2   │    │us-west-2   │
    │Internal    │    │Public      │    │Public+WAF  │
    └────────────┘    └────────────┘    └────────────┘
                                              │
                                              │
                                         ┌────▼─────┐
                                         │ DR RDS   │
                                         │us-east-1 │
                                         │Multi-AZ  │
                                         └──────────┘
```

## 🔐 Secrets Flow

```
AWS Secrets Manager              External Secrets           Kubernetes
     (Source)                       Operator                 Secrets
        │                              │                         │
  ┌─────▼─────┐                       │                         │
  │pipeops/   │                       │                         │
  │dev/rds/   │───[1. Read]───────────>│                         │
  │credentials│                       │                         │
  └───────────┘                       │                         │
        │                              │                         │
  ┌─────▼─────┐                       │                         │
  │pipeops/   │                       │                         │
  │staging/rds│───[1. Read]───────────>│                         │
  │credentials│                       │                         │
  └───────────┘                       │                         │
        │                              │                         │
  ┌─────▼─────┐                       │                         │
  │pipeops/   │                       │                         │
  │prod/rds/  │───[1. Read]───────────>│                         │
  │credentials│                       │                         │
  └───────────┘                       │                         │
                                      │                         │
                              [2. Transform]                    │
                                      │                         │
                                      │──[3. Create Secret]─────>│
                                      │                         │
                                      │                   ┌─────▼────┐
                                      │                   │db-creds  │
                                      │                   │(Secret)  │
                                      │                   └─────┬────┘
                                      │                         │
                                      │                         │
                                      │                   [4. Mount to
                                      │                    Pods]
                                      │                         │
                              [5. Auto-refresh                  │
                               every 30m]                       │
```

## 📊 Resource Hierarchy

```
Namespace: argocd
    │
    ├── AppProject (dev/staging/production)
    │   └── Defines RBAC, allowed repos, destinations
    │
    ├── Application (app-of-apps-{env})
    │   └── Root application managing child apps
    │
    ├── ServiceAccount (external-secrets-sa)
    │   └── IRSA for AWS Secrets Manager access
    │
    ├── SecretStore (aws-secrets-manager)
    │   └── Configures connection to AWS
    │
    └── ExternalSecret (database-credentials)
        └── Pulls RDS creds from AWS Secrets Manager

Namespace: monitoring
    │
    ├── ServiceMonitor (argocd-metrics)
    │   └── Scrapes ArgoCD application controller
    │
    ├── ServiceMonitor (argocd-server-metrics)
    │   └── Scrapes ArgoCD API server
    │
    ├── ServiceMonitor (argocd-repo-server-metrics)
    │   └── Scrapes ArgoCD repo server
    │
    └── PrometheusRule (argocd-alerts)
        └── Defines alerts for app sync/health

IngressClass: alb
    └── Used by all Ingress resources

Ingress: sample-app-ingress
    ├── Dev: Internal-only (scheme: internal)
    ├── Staging: Public with SSL
    └── Production: Public with SSL + WAF
```

## 🎯 Patch Strategy

### How Kustomize Merges Configurations

```
Base Resource                    Patch                       Final Resource
─────────────────────────────────────────────────────────────────────────────
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: ENVIRONMENT_NAME     +   name: dev              =   name: dev
spec:                            $patch: replace            spec:
  description: "Template"        spec:                        description: "Dev env"
  sourceRepos:                     description: "Dev env"     sourceRepos:
    - '*'                                                       - 'https://...'
```

### Patch Types Used

1. **Strategic Merge** (default)
   - Merges fields intelligently
   - Arrays are replaced unless annotated
   
2. **JSON Patch**
   - Precise field-level operations
   - Used for complex transformations

3. **Replace**
   - Completely replaces resource
   - Used when base is just a template

## 🚀 Deployment Strategies

### 1. Direct Apply (Manual)
```bash
kubectl apply -k overlays/prod
```
- Immediate deployment
- Good for testing
- Manual process

### 2. ArgoCD Sync (GitOps)
```bash
argocd app sync infrastructure-prod
```
- Automated from Git
- Tracks drift
- Rollback capability

### 3. ApplicationSet (Automated)
```yaml
# Auto-generates applications for all environments
# Production uses manual sync for safety
```
- Manages multiple apps
- Consistent configuration
- Environment templating

## 📈 Monitoring & Observability

```
Application Metrics          Infrastructure Metrics        Business Metrics
       │                           │                             │
       │                           │                             │
   ┌───▼───┐                  ┌────▼────┐                  ┌────▼────┐
   │ArgoCD │                  │EKS      │                  │Custom   │
   │Metrics│                  │Metrics  │                  │App      │
   └───┬───┘                  └────┬────┘                  │Metrics  │
       │                           │                       └────┬────┘
       │                           │                            │
       └───────────────┬───────────┴────────────────────────────┘
                       │
                  ┌────▼─────┐
                  │Prometheus│
                  │          │
                  └────┬─────┘
                       │
           ┌───────────┼───────────┐
           │           │           │
      ┌────▼────┐ ┌────▼────┐ ┌───▼────┐
      │Grafana  │ │AlertMgr │ │PagerDty│
      │Dashbrd  │ │         │ │(Prod)  │
      └─────────┘ └─────────┘ └────────┘
```

## 🔧 Customization Points

### Easy to Modify

1. **Environment Variables** (kustomization.yaml)
   ```yaml
   configMapGenerator:
     - name: environment-config
       literals:
         - ENVIRONMENT=dev
         - AWS_REGION=us-west-2
   ```

2. **Resource Limits** (resource-quotas.yaml)
   ```yaml
   spec:
     hard:
       requests.cpu: "100"
       requests.memory: 200Gi
   ```

3. **Alert Thresholds** (monitoring-patch.yaml)
   ```yaml
   - alert: ArgoCDAppOutOfSync
     for: 5m  # Change per environment
   ```

4. **Domains** (ingress-patch.yaml)
   ```yaml
   spec:
     rules:
     - host: app.your-domain.com
   ```

## 🎓 Best Practices Checklist

- ✅ **Base contains common config** (DRY)
- ✅ **Overlays contain only differences** (patches)
- ✅ **Secrets stored in AWS Secrets Manager** (not Git)
- ✅ **Environment-specific values** externalized
- ✅ **Production has manual sync** (safety)
- ✅ **Monitoring configured** for all environments
- ✅ **Resource quotas** in production
- ✅ **Multi-region DR** for production database
- ✅ **Documentation** comprehensive
- ✅ **Rollback capability** maintained

---

**Architecture Version**: 1.0  
**Last Updated**: 2026-01-21  
**Maintained by**: Platform Team
