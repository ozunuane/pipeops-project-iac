# K8s Manifests Migration Guide

## 🔄 Migration from Flat Structure to Kustomize

This guide explains the migration from the old flat structure to the new Kustomize-based multi-environment setup.

## 📋 What Changed?

### Old Structure (Deprecated)
```
k8s-manifests/
├── argocd/
│   ├── app-of-apps.yaml        # Single file with hardcoded prod values
│   └── sample-app.yaml
├── ingress-controller/
│   └── ingress-class.yaml      # Hardcoded production config
└── monitoring/
    └── service-monitor.yaml
```

**Problems:**
- ❌ No environment separation
- ❌ Hardcoded values (regions, environments, secrets paths)
- ❌ Cannot deploy to dev/staging/prod without manual edits
- ❌ No DRY principle (lots of duplication)

### New Structure (Current)
```
k8s-manifests/
├── README.md                    # Comprehensive documentation
├── MIGRATION_GUIDE.md          # This file
├── base/                        # Shared configurations
│   ├── argocd/
│   ├── ingress-controller/
│   └── monitoring/
├── overlays/                    # Environment-specific patches
│   ├── dev/
│   ├── staging/
│   └── prod/
├── argocd/
│   └── applicationset.yaml      # Auto-generates all environments
└── _archive/                    # Old files (for reference)
```

**Benefits:**
- ✅ **Environment Parity**: Same base, different configs
- ✅ **DRY Principle**: No duplication
- ✅ **Easy Deployment**: `kubectl apply -k overlays/{env}`
- ✅ **GitOps Ready**: Works seamlessly with ArgoCD
- ✅ **Scalable**: Easy to add new environments

## 🚀 Quick Migration Steps

### Step 1: Verify New Structure

```bash
cd k8s-manifests

# Check that base and overlays exist
ls -la base/ overlays/

# Test building each environment
kustomize build overlays/dev > /dev/null && echo "✅ Dev builds"
kustomize build overlays/staging > /dev/null && echo "✅ Staging builds"
kustomize build overlays/prod > /dev/null && echo "✅ Prod builds"
```

### Step 2: Update Repository URLs

Edit the following files and replace `https://github.com/your-org/` with your actual Git repository:

```bash
# Files to update:
base/argocd/appproject.yaml
base/argocd/app-of-apps.yaml
argocd/applicationset.yaml
```

### Step 3: Update AWS Account IDs

Replace `ACCOUNT_ID` placeholders with your actual AWS account ID:

```bash
# Find all occurrences
grep -r "ACCOUNT_ID" overlays/

# Files to update:
overlays/dev/secrets-patch.yaml
overlays/staging/secrets-patch.yaml
overlays/prod/secrets-patch.yaml
```

### Step 4: Update Domain Names

Replace domain placeholders with your actual domains:

```bash
# Dev environment (internal)
# Edit: overlays/dev/ingress-patch.yaml
# Change: app-dev.pipeops.internal → your-dev-domain

# Staging environment
# Edit: overlays/staging/ingress-patch.yaml
# Change: app-staging.pipeops.com → your-staging-domain

# Production environment
# Edit: overlays/prod/ingress-patch.yaml
# Change: app.pipeops.com → your-production-domain
```

### Step 5: Deploy to Development First

```bash
# Test in development
kubectl apply -k overlays/dev

# Verify deployment
kubectl get all -n argocd
kubectl get ingress -A

# Check ArgoCD applications
kubectl get applications -n argocd
```

### Step 6: Deploy to Staging

```bash
# Apply staging configuration
kubectl apply -k overlays/staging

# Verify
kubectl get applications -n argocd | grep staging
```

### Step 7: Deploy to Production

```bash
# Review changes first
kubectl diff -k overlays/prod

# Apply to production
kubectl apply -k overlays/prod

# Monitor rollout
kubectl get applications -n argocd -w
```

## 🔧 Configuration Changes Required

### 1. AWS Secrets Manager

Ensure your secrets follow this structure in AWS Secrets Manager:

```json
{
  "username": "postgres",
  "password": "your-secure-password",
  "endpoint": "pipeops-prod-postgres.xxxxx.us-west-2.rds.amazonaws.com",
  "port": "5432",
  "dbname": "pipeops"
}
```

**Secret Paths:**
- Dev: `pipeops/dev/rds/credentials`
- Staging: `pipeops/staging/rds/credentials`
- Production: `pipeops/prod/rds/credentials`

### 2. IAM Roles

Create IAM roles for External Secrets Operator in each environment:

```bash
# Role names:
pipeops-dev-eks-external-secrets
pipeops-staging-eks-external-secrets
pipeops-prod-eks-external-secrets

# Required permissions:
- secretsmanager:GetSecretValue
- secretsmanager:DescribeSecret
- kms:Decrypt (if using KMS)
```

### 3. ArgoCD Projects

The new structure automatically creates ArgoCD projects:
- `dev` - For development applications
- `staging` - For staging applications
- `production` - For production applications

## 📊 Comparison: Old vs New

| Aspect | Old Approach | New Approach |
|--------|-------------|--------------|
| **Environment Support** | Single (prod only) | Multi (dev/staging/prod) |
| **Configuration Method** | Hardcoded values | Kustomize patches |
| **Deployment Command** | `kubectl apply -f ...` | `kubectl apply -k overlays/{env}` |
| **Secret Management** | Hardcoded paths | Environment-specific patches |
| **Regional Support** | Single region | Multi-region (prod has DR) |
| **Maintenance** | Manual edits per env | Patch-based customization |
| **ArgoCD Integration** | Manual setup | ApplicationSet auto-generation |
| **Rollback** | Manual | Git-based with ArgoCD |

## 🎯 Environment-Specific Features

### Development
- **Internal ingress** (not publicly accessible)
- **Debug logging** enabled
- **Relaxed alerts** (15m grace period)
- **Single-AZ RDS** (cost optimization)
- **No resource quotas**

### Staging
- **Public ingress** (with SSL)
- **Info-level logging**
- **Moderate alerts** (10m grace period)
- **Multi-AZ RDS** (production-like)
- **Automated sync** with ArgoCD

### Production
- **Public ingress** with **WAF protection**
- **Warning-level logging** (minimal)
- **Strict alerts** (5m grace period)
- **Multi-AZ + Multi-Region DR**
- **Manual sync** (requires approval)
- **Resource quotas** enforced
- **PagerDuty integration**

## 🔍 Validation Commands

### Verify Kustomize Build

```bash
# Build all environments
for env in dev staging prod; do
  echo "Building $env..."
  kustomize build overlays/$env > /tmp/$env-manifests.yaml
  echo "✅ $env built successfully"
done
```

### Compare Environments

```bash
# See differences between environments
diff <(kustomize build overlays/dev) <(kustomize build overlays/prod)

# Count resources per environment
for env in dev staging prod; do
  count=$(kustomize build overlays/$env | grep -c "^kind:")
  echo "$env: $count resources"
done
```

### Test Deployment (Dry Run)

```bash
# Test without actually applying
kubectl apply -k overlays/prod --dry-run=server

# Validate YAML syntax
kubectl apply -k overlays/prod --dry-run=client --validate=strict
```

## 🐛 Troubleshooting

### Issue: "No matches for kind in version"

**Cause**: CRDs not installed (e.g., External Secrets, ServiceMonitor)

**Solution**:
```bash
# Install External Secrets Operator
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets -n external-secrets --create-namespace

# Install Prometheus Operator (for ServiceMonitor)
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack -n monitoring
```

### Issue: "Error: accumulating resources: accumulation err"

**Cause**: Invalid Kustomize configuration

**Solution**:
```bash
# Validate Kustomize files
kustomize build overlays/prod 2>&1 | head -20

# Check for common issues:
# - Incorrect indentation in YAML
# - Missing base resources
# - Invalid patch syntax
```

### Issue: External Secrets not syncing

**Cause**: IAM role not properly configured

**Solution**:
```bash
# Verify ServiceAccount annotation
kubectl describe sa external-secrets-sa -n argocd

# Check External Secret status
kubectl get externalsecrets -n argocd
kubectl describe externalsecret database-credentials -n argocd

# View External Secrets Operator logs
kubectl logs -n external-secrets deployment/external-secrets
```

## 📚 Next Steps

1. ✅ **Complete migration** for all environments
2. ✅ **Test deployments** in dev environment first
3. ✅ **Set up ArgoCD** ApplicationSet for automated management
4. ✅ **Configure monitoring** and alerts
5. ✅ **Document any custom changes** specific to your organization
6. ✅ **Archive old manifests** (already done in `_archive/`)

## 🤝 Getting Help

If you encounter issues:

1. Check the [main README](./README.md) for detailed documentation
2. Review the [RDS Complete Guide](../RDS_COMPLETE_GUIDE.md) for database setup
3. Validate your Kustomize files: `kustomize build overlays/{env}`
4. Check ArgoCD logs: `kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server`

## 📝 Rollback Plan

If you need to rollback to the old structure:

```bash
# Restore old files from archive
cp _archive/*.yaml ./argocd/
cp _archive/ingress-class.yaml ./ingress-controller/
cp _archive/service-monitor.yaml ./monitoring/

# Apply old manifests
kubectl apply -f argocd/app-of-apps.yaml
kubectl apply -f ingress-controller/ingress-class.yaml
kubectl apply -f monitoring/service-monitor.yaml
```

**Note**: Rollback should only be temporary. The new structure is recommended for all production use.

---

**Migration Date**: 2026-01-21  
**Breaking Changes**: None (new structure is additive)  
**Rollback Possible**: Yes (old files archived)
