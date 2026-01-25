# ArgoCD Module

GitOps continuous delivery with ArgoCD for Kubernetes deployments.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              ArgoCD (Hub Cluster)                                │
│                                                                                 │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                        ArgoCD Components                                  │   │
│  │                                                                           │   │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐          │   │
│  │  │  API Server     │  │  Application    │  │  Repo Server    │          │   │
│  │  │  (UI + API)     │  │  Controller     │  │  (Git clone)    │          │   │
│  │  └─────────────────┘  └─────────────────┘  └─────────────────┘          │   │
│  │                                                                           │   │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐          │   │
│  │  │  Redis          │  │  Notifications  │  │  ApplicationSet │          │   │
│  │  │  (Cache)        │  │  Controller     │  │  Controller     │          │   │
│  │  └─────────────────┘  └─────────────────┘  └─────────────────┘          │   │
│  │                                                                           │   │
│  └───────────────────────────────────────────────────────────────────────────┘   │
│                                      │                                          │
│           ┌──────────────────────────┼──────────────────────────┐              │
│           │                          │                          │              │
│           ▼                          ▼                          ▼              │
│  ┌─────────────────┐      ┌─────────────────┐      ┌─────────────────┐        │
│  │  Git Repository │      │  Dev Cluster    │      │  Prod Cluster   │        │
│  │  (Source)       │      │  (Target)       │      │  (Target)       │        │
│  └─────────────────┘      └─────────────────┘      └─────────────────┘        │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

## Features

| Feature | Description |
|---------|-------------|
| **GitOps** | Declarative deployments from Git |
| **Multi-Cluster** | Manage multiple Kubernetes clusters |
| **App of Apps** | Hierarchical application management |
| **Auto Sync** | Automatic deployment on Git changes |
| **Rollback** | Easy rollback to previous versions |
| **SSO** | OIDC/SAML authentication support |

## Usage

ArgoCD is deployed via Helm in the root module:

```hcl
resource "helm_release" "argocd" {
  count = var.cluster_exists && var.enable_argocd ? 1 : 0

  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version
  namespace        = "argocd"
  create_namespace = true
  
  timeout = 600
  wait    = true

  values = [yamlencode({
    server = {
      replicas = var.environment == "prod" ? 2 : 1
      service = {
        type = "ClusterIP"
      }
      ingress = {
        enabled          = var.argocd_enable_ingress
        ingressClassName = "alb"
      }
    }
    controller = {
      replicas = var.environment == "prod" ? 2 : 1
    }
    repoServer = {
      replicas = var.environment == "prod" ? 2 : 1
    }
  })]

  depends_on = [module.eks]
}
```

## Variables

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `enable_argocd` | Enable ArgoCD | `bool` | `true` |
| `argocd_chart_version` | Helm chart version | `string` | `"5.51.6"` |
| `argocd_enable_ingress` | Enable ALB ingress | `bool` | `false` |
| `argocd_domain` | Domain for ArgoCD | `string` | `""` |
| `argocd_ssl_certificate_arn` | ACM certificate ARN | `string` | `""` |

## Accessing ArgoCD

### Port Forward (Development)

```bash
# Port forward to ArgoCD server
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Access at https://localhost:8080
```

### Get Admin Password

```bash
# Get initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

### ArgoCD CLI

```bash
# Install CLI
brew install argocd

# Login
argocd login localhost:8080

# List applications
argocd app list

# Sync application
argocd app sync myapp

# Get app status
argocd app get myapp
```

## Application Management

### Create Application

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: myapp
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/org/repo.git
    targetRevision: main
    path: k8s/overlays/prod
  destination:
    server: https://kubernetes.default.svc
    namespace: myapp
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

### App of Apps Pattern

```yaml
# Parent application that manages child apps
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: apps
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/org/gitops-config.git
    targetRevision: main
    path: applications
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
```

## Multi-Cluster Management

### Register External Cluster

```bash
# Get cluster credentials
aws eks update-kubeconfig --name target-cluster --region us-east-1

# Add cluster to ArgoCD
argocd cluster add arn:aws:eks:us-east-1:ACCOUNT:cluster/target-cluster
```

### Deploy to Multiple Clusters

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: myapp
  namespace: argocd
spec:
  generators:
    - list:
        elements:
          - cluster: dev
            url: https://dev-cluster.example.com
          - cluster: prod
            url: https://prod-cluster.example.com
  template:
    metadata:
      name: 'myapp-{{cluster}}'
    spec:
      project: default
      source:
        repoURL: https://github.com/org/repo.git
        targetRevision: main
        path: 'k8s/overlays/{{cluster}}'
      destination:
        server: '{{url}}'
        namespace: myapp
```

## Sync Policies

| Policy | Description |
|--------|-------------|
| **Manual** | Require manual sync |
| **Automated** | Auto-sync on Git changes |
| **Self-Heal** | Revert manual changes |
| **Prune** | Delete removed resources |

```yaml
syncPolicy:
  automated:
    prune: true      # Delete resources removed from Git
    selfHeal: true   # Revert manual changes
  syncOptions:
    - CreateNamespace=true
    - PrunePropagationPolicy=foreground
```

## Notifications

Configure Slack notifications:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
  namespace: argocd
data:
  service.slack: |
    token: $slack-token
  template.app-deployed: |
    message: |
      Application {{.app.metadata.name}} deployed!
  trigger.on-deployed: |
    - when: app.status.health.status == 'Healthy'
      send: [app-deployed]
```

## Metrics

ArgoCD exports Prometheus metrics:

| Metric | Description |
|--------|-------------|
| `argocd_app_info` | Application metadata |
| `argocd_app_sync_total` | Sync operations |
| `argocd_app_reconcile_count` | Reconciliation count |
| `argocd_cluster_api_resource_objects` | Cluster resource count |

## Security Best Practices

1. **RBAC**: Use ArgoCD projects for access control
2. **SSO**: Enable OIDC for authentication
3. **Secrets**: Use External Secrets Operator
4. **Audit**: Enable audit logging
5. **Network**: Restrict API server access

## Troubleshooting

### Application Out of Sync

```bash
# Check sync status
argocd app get myapp

# Force sync
argocd app sync myapp --force

# View diff
argocd app diff myapp
```

### Application Degraded

```bash
# Check application health
kubectl get application myapp -n argocd -o yaml

# Check events
kubectl get events -n myapp --sort-by='.lastTimestamp'

# Check pod logs
kubectl logs -n myapp -l app=myapp
```
