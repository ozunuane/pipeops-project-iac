# ArgoCD Multi-Cluster Management Guide

## Overview

This guide explains how to use the centralized ArgoCD setup to manage multiple EKS clusters (dev, staging, prod, DR) from a single ArgoCD instance.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│              PROD CLUSTER (ArgoCD Management Plane)                         │
│                                                                             │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                    ArgoCD Server                                     │   │
│   │                                                                      │   │
│   │  • ApplicationSets for multi-cluster deployments                    │   │
│   │  • AppProject with access to all clusters                           │   │
│   │  • Cluster secrets for remote cluster authentication                │   │
│   └────────────────────┬────────────────────────────────────────────────┘   │
└────────────────────────┼────────────────────────────────────────────────────┘
                         │
         ┌───────────────┼───────────────────────┐
         │               │                       │
         ▼               ▼                       ▼
   ┌───────────┐   ┌───────────┐           ┌───────────┐
   │    DEV    │   │  STAGING  │           │    DR     │
   │  Cluster  │   │  Cluster  │           │  Cluster  │
   │ us-west-2 │   │ us-west-2 │           │ us-east-1 │
   └───────────┘   └───────────┘           └───────────┘
```

## Configuration

### Step 1: Get Cluster Information

For each cluster you want to manage, get the endpoint and CA certificate:

```bash
# Dev cluster
aws eks describe-cluster --name pipeops-dev-eks --region us-west-2 \
  --query 'cluster.{endpoint:endpoint,ca:certificateAuthority.data}' --output json

# Staging cluster
aws eks describe-cluster --name pipeops-staging-eks --region us-west-2 \
  --query 'cluster.{endpoint:endpoint,ca:certificateAuthority.data}' --output json

# DR cluster
aws eks describe-cluster --name pipeops-prod-dr-eks --region us-east-1 \
  --query 'cluster.{endpoint:endpoint,ca:certificateAuthority.data}' --output json
```

### Step 2: Update Terraform Configuration

In your `environments/prod/terraform.tfvars`, enable multi-cluster ArgoCD:

```hcl
# Enable ArgoCD multi-cluster management
enable_argocd = true

# ArgoCD multi-cluster configuration
argocd_multi_cluster = {
  enabled = true
  
  # Git repository for ApplicationSets
  git_repo_url      = "https://github.com/your-org/pipeops-project-iac.git"
  git_repo_path     = "k8s-manifests"
  git_target_revision = "main"
  
  # Enable sample ApplicationSets
  enable_applicationsets = true
  
  # Managed clusters
  managed_clusters = [
    {
      name        = "dev"
      environment = "dev"
      server      = "https://DEV_CLUSTER_ENDPOINT"
      ca_data     = "DEV_CLUSTER_CA_BASE64"
      aws_auth = {
        cluster_name = "pipeops-dev-eks"
        region       = "us-west-2"
        role_arn     = ""  # Same account, no role needed
      }
    },
    {
      name        = "staging"
      environment = "staging"
      server      = "https://STAGING_CLUSTER_ENDPOINT"
      ca_data     = "STAGING_CLUSTER_CA_BASE64"
      aws_auth = {
        cluster_name = "pipeops-staging-eks"
        region       = "us-west-2"
        role_arn     = ""
      }
    },
    {
      name        = "dr"
      environment = "dr"
      server      = "https://DR_CLUSTER_ENDPOINT"
      ca_data     = "DR_CLUSTER_CA_BASE64"
      aws_auth = {
        cluster_name = "pipeops-prod-dr-eks"
        region       = "us-east-1"
        role_arn     = ""
      }
    }
  ]
}
```

### Step 3: Update main.tf Module Call

Update the ArgoCD module call in `main.tf`:

```hcl
module "argocd" {
  count  = var.cluster_exists && var.enable_argocd ? 1 : 0
  source = "./modules/argocd"

  cluster_name          = local.cluster_name
  argocd_domain         = "argocd.${var.project_name}.com"
  admin_password        = local.argocd_admin_password
  admin_password_bcrypt = bcrypt(local.argocd_admin_password)
  server_insecure       = true
  ha_mode               = var.environment == "prod" ? true : false
  enable_metrics        = var.enable_monitoring
  enable_ingress        = false
  oidc_provider_arn     = module.eks.oidc_provider_arn
  oidc_issuer_url       = module.eks.cluster_oidc_issuer_url
  tags                  = var.tags

  # Multi-cluster configuration
  enable_multi_cluster   = var.argocd_multi_cluster.enabled
  managed_clusters       = var.argocd_multi_cluster.managed_clusters
  project_name           = var.project_name
  git_repo_url           = var.argocd_multi_cluster.git_repo_url
  git_repo_path          = var.argocd_multi_cluster.git_repo_path
  git_target_revision    = var.argocd_multi_cluster.git_target_revision
  enable_applicationsets = var.argocd_multi_cluster.enable_applicationsets

  depends_on = [module.eks]
}
```

### Step 4: Add Variables

Add these variables to `variables.tf`:

```hcl
variable "argocd_multi_cluster" {
  description = "ArgoCD multi-cluster configuration"
  type = object({
    enabled                = bool
    git_repo_url           = optional(string, "")
    git_repo_path          = optional(string, "k8s-manifests")
    git_target_revision    = optional(string, "main")
    enable_applicationsets = optional(bool, false)
    managed_clusters = optional(list(object({
      name        = string
      environment = string
      server      = string
      ca_data     = string
      aws_auth = optional(object({
        cluster_name = string
        region       = optional(string, "us-west-2")
        role_arn     = optional(string, "")
      }), null)
      labels = optional(map(string), {})
    })), [])
  })
  default = {
    enabled            = false
    managed_clusters   = []
  }
  sensitive = true
}
```

## Git Repository Structure

For ApplicationSets to work, structure your k8s-manifests like this:

```
k8s-manifests/
├── base/                       # Common base configurations
│   ├── deployment.yaml
│   ├── service.yaml
│   └── kustomization.yaml
│
└── overlays/
    ├── dev/                    # Dev-specific overrides
    │   ├── kustomization.yaml
    │   └── patches/
    │
    ├── staging/                # Staging-specific overrides
    │   ├── kustomization.yaml
    │   └── patches/
    │
    ├── prod/                   # Prod-specific overrides
    │   ├── kustomization.yaml
    │   └── patches/
    │
    └── dr/                     # DR-specific overrides
        ├── kustomization.yaml
        └── patches/
```

## How ApplicationSets Work

### Environment-Based ApplicationSet

The `pipeops-environments` ApplicationSet automatically:
1. Reads the list of managed clusters
2. For each cluster, creates an Application pointing to its overlay
3. Syncs changes automatically when Git repo is updated

```yaml
# Auto-generated Applications:
- pipeops-dev       → deploys k8s-manifests/overlays/dev to dev cluster
- pipeops-staging   → deploys k8s-manifests/overlays/staging to staging cluster
- pipeops-prod      → deploys k8s-manifests/overlays/prod to prod cluster (in-cluster)
- pipeops-dr        → deploys k8s-manifests/overlays/dr to DR cluster
```

### Multi-Cluster ApplicationSet

The `pipeops-multi-cluster` ApplicationSet uses a matrix generator to:
1. Combine clusters with application directories
2. Create Applications for each cluster/app combination

## IAM Permissions

### Same AWS Account

If all clusters are in the same AWS account, ArgoCD uses the pod's service account to get EKS tokens. No additional IAM roles needed.

### Cross-Account Access

For clusters in different AWS accounts:

1. **In the target account**, create an IAM role with trust policy:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::ARGOCD_ACCOUNT:role/pipeops-prod-eks-argocd-role"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

2. **Add the role ARN** to the managed_clusters configuration:
```hcl
{
  name        = "cross-account-cluster"
  environment = "prod"
  server      = "https://CLUSTER_ENDPOINT"
  ca_data     = "CA_BASE64"
  aws_auth = {
    cluster_name = "eks-cluster-name"
    region       = "us-west-2"
    role_arn     = "arn:aws:iam::TARGET_ACCOUNT:role/argocd-access-role"
  }
}
```

## Verifying Setup

### Check Cluster Registration

```bash
# Port-forward to ArgoCD
kubectl port-forward svc/argocd-server -n argocd 8080:443

# List registered clusters
argocd cluster list

# Expected output:
# SERVER                                                 NAME        STATUS
# https://kubernetes.default.svc                         in-cluster  Successful
# https://XXX.yl4.us-west-2.eks.amazonaws.com           dev         Successful
# https://XXX.yl4.us-west-2.eks.amazonaws.com           staging     Successful
# https://XXX.yl4.us-east-1.eks.amazonaws.com           dr          Successful
```

### Check ApplicationSets

```bash
# List ApplicationSets
kubectl get applicationsets -n argocd

# List generated Applications
argocd app list
```

### Check Sync Status

```bash
# Get sync status for all apps
argocd app list -o wide

# Sync a specific app
argocd app sync pipeops-dev
```

## Troubleshooting

### Cluster Connection Failed

1. **Check cluster secret:**
```bash
kubectl get secret -n argocd -l argocd.argoproj.io/secret-type=cluster
kubectl describe secret cluster-dev -n argocd
```

2. **Verify CA certificate:**
```bash
# Compare with actual cluster CA
aws eks describe-cluster --name pipeops-dev-eks --query 'cluster.certificateAuthority.data'
```

3. **Check ArgoCD logs:**
```bash
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller
```

### ApplicationSet Not Generating Apps

1. **Check ApplicationSet status:**
```bash
kubectl describe applicationset pipeops-environments -n argocd
```

2. **Verify Git repository access:**
```bash
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-repo-server
```

## Cost Considerations

- **No additional cost** for multi-cluster ArgoCD - it's just software running on your existing cluster
- **Network costs** may apply for cross-region communication (ArgoCD → DR cluster)
- Consider **VPC peering** or **Transit Gateway** for private cluster access

## Security Best Practices

1. **Use IRSA** for AWS authentication instead of bearer tokens
2. **Enable RBAC** in ArgoCD for team-based access
3. **Use private Git repos** with SSH keys or GitHub App authentication
4. **Enable audit logging** for compliance
5. **Consider GitOps-only access** - disable UI modifications in production
