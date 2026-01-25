# Environment Management

Configuration and deployment guide for dev, staging, and production environments.

## Environment Overview

| Environment | Region | Purpose | Cost Tier |
|-------------|--------|---------|-----------|
| **dev** | us-west-2 | Development and testing | Low |
| **staging** | us-west-2 | Pre-production validation | Medium |
| **prod** | us-west-2 | Production workloads | High |
| **drprod** | us-east-1 | Disaster recovery standby | Medium |

---

## Configuration Files

Each environment has its own configuration:

```
environments/
├── dev/
│   ├── terraform.tfvars    # Development variables
│   └── backend.conf        # Dev state backend
├── staging/
│   ├── terraform.tfvars    # Staging variables
│   └── backend.conf        # Staging state backend
├── prod/
│   ├── terraform.tfvars    # Production variables
│   └── backend.conf        # Prod state backend
└── drprod/
    ├── terraform.tfvars    # DR Production variables
    └── backend.conf        # DR state backend
```

---

## Environment Configurations

### Development

**Purpose**: Rapid iteration, testing new features

```hcl
# environments/dev/terraform.tfvars

project_name = "pipeops"
environment  = "dev"
region       = "us-west-2"

# Minimal EKS
kubernetes_version = "1.33"
cluster_exists     = true

# Small RDS
db_instance_class    = "db.t3.medium"
db_allocated_storage = 100
db_multi_az          = false
db_backup_retention  = 7

# Features
enable_argocd     = true
enable_monitoring = true
enable_logging    = false

# Cost optimization
ecr_lifecycle_keep_count = 10
backup_retention_days    = 7
```

**Estimated Cost**: ~$300/month

### Staging

**Purpose**: Pre-production testing, QA validation

```hcl
# environments/staging/terraform.tfvars

project_name = "pipeops"
environment  = "staging"
region       = "us-west-2"

# Moderate EKS
kubernetes_version = "1.33"
cluster_exists     = true

# Medium RDS
db_instance_class    = "db.t3.large"
db_allocated_storage = 200
db_multi_az          = true
db_backup_retention  = 14

# Features
enable_argocd     = true
enable_monitoring = true
enable_logging    = true

# Moderate retention
ecr_lifecycle_keep_count = 20
backup_retention_days    = 14
```

**Estimated Cost**: ~$600/month

### Production

**Purpose**: Live workloads, customer-facing

```hcl
# environments/prod/terraform.tfvars

project_name = "pipeops"
environment  = "prod"
region       = "us-west-2"

# Full EKS
kubernetes_version = "1.33"
cluster_exists     = true

# Large RDS with DR
db_instance_class              = "db.r6g.large"
db_allocated_storage           = 400
db_multi_az                    = true
db_backup_retention            = 30
db_create_read_replica         = true
db_enable_cross_region_backups = true

# All features enabled
enable_argocd     = true
enable_monitoring = true
enable_logging    = true

# Full DR
enable_eks_backup              = true
enable_backup_cross_region_copy = true

# Cross-region replication
ecr_enable_replication  = true
ecr_replication_regions = ["us-east-1"]

# Long retention
ecr_lifecycle_keep_count = 30
backup_retention_days    = 35
```

**Estimated Cost**: ~$2,000/month (including DR)

---

## State Management

Each environment uses separate Terraform state:

| Environment | S3 Bucket | DynamoDB Table |
|-------------|-----------|----------------|
| dev | `pipeops-dev-terraform-state` | `pipeops-dev-terraform-locks` |
| staging | `pipeops-staging-terraform-state` | `pipeops-staging-terraform-locks` |
| prod | `pipeops-prod-terraform-state` | `pipeops-prod-terraform-locks` |
| drprod | `pipeops-drprod-terraform-state` | `pipeops-drprod-terraform-locks` |

### Backend Configuration

```hcl
# environments/prod/backend.conf
bucket         = "pipeops-prod-terraform-state"
key            = "prod/terraform.tfstate"
region         = "us-west-2"
dynamodb_table = "pipeops-prod-terraform-locks"
encrypt        = true
```

---

## Deployment Commands

### Deploy to Specific Environment

```bash
# Development
terraform init -backend-config=environments/dev/backend.conf
terraform plan -var-file=environments/dev/terraform.tfvars
terraform apply -var-file=environments/dev/terraform.tfvars

# Staging
terraform init -backend-config=environments/staging/backend.conf -reconfigure
terraform plan -var-file=environments/staging/terraform.tfvars
terraform apply -var-file=environments/staging/terraform.tfvars

# Production
terraform init -backend-config=environments/prod/backend.conf -reconfigure
terraform plan -var-file=environments/prod/terraform.tfvars
terraform apply -var-file=environments/prod/terraform.tfvars
```

### Switch Between Environments

```bash
# Re-initialize with different backend
terraform init -backend-config=environments/staging/backend.conf -reconfigure
```

---

## Environment Isolation

### Network Isolation

Each environment uses different VPC CIDRs:

| Environment | VPC CIDR |
|-------------|----------|
| dev | `10.0.0.0/16` |
| staging | `10.0.0.0/16` |
| prod | `10.0.0.0/16` |
| drprod | `10.1.0.0/16` |

### Resource Naming

Resources are prefixed with project and environment:

```
{project}-{environment}-{resource}

Examples:
- pipeops-dev-eks
- pipeops-staging-rds
- pipeops-prod-vpc
```

### IAM Isolation

Separate IAM roles per environment:

```
pipeops-dev-github-actions
pipeops-staging-github-actions
pipeops-prod-github-actions
```

---

## Promotion Workflow

### Dev → Staging

```bash
# 1. Verify dev deployment
kubectl get pods -A --context=dev

# 2. Create PR from develop to main
git checkout develop
git pull origin develop
# Make changes, commit, push

# 3. PR triggers staging plan
# Review plan in PR comments

# 4. Merge PR
# Staging auto-deploys
```

### Staging → Production

```bash
# 1. Verify staging deployment
kubectl get pods -A --context=staging

# 2. Merge to main triggers prod deployment
git checkout main
git merge develop
git push origin main

# 3. Production auto-deploys after staging
```

---

## Environment-Specific Features

### Feature Matrix

| Feature | Dev | Staging | Prod |
|---------|-----|---------|------|
| Multi-AZ RDS | ❌ | ✅ | ✅ |
| Read Replicas | ❌ | ❌ | ✅ |
| Cross-Region Backups | ❌ | ❌ | ✅ |
| EKS Backup | ❌ | ✅ | ✅ |
| ECR Replication | ❌ | ❌ | ✅ |
| Monitoring | ✅ | ✅ | ✅ |
| ArgoCD HA | ❌ | ❌ | ✅ |

### Conditional Configuration

```hcl
# ArgoCD replicas based on environment
server = {
  replicas = var.environment == "prod" ? 2 : 1
}

# RDS instance class based on environment
db_instance_class = var.environment == "prod" ? "db.r6g.large" : "db.t3.medium"
```

---

## Cost Comparison

| Component | Dev | Staging | Prod |
|-----------|-----|---------|------|
| EKS Cluster | $73 | $73 | $73 |
| EKS Nodes | ~$60 | ~$120 | ~$300 |
| RDS | ~$50 | ~$100 | ~$280 |
| NAT Gateways | ~$100 | ~$100 | ~$100 |
| Data Transfer | ~$10 | ~$20 | ~$50 |
| DR (us-east-1) | - | - | ~$300 |
| **Total** | **~$300** | **~$400** | **~$1,100** |

---

## Cleanup

### Destroy Environment

```bash
# Destroy development (be careful!)
terraform destroy -var-file=environments/dev/terraform.tfvars

# Manual confirmation required
```

### Cleanup Backend Resources

```bash
# Delete state bucket (only after terraform destroy)
aws s3 rb s3://pipeops-dev-terraform-state --force

# Delete DynamoDB table
aws dynamodb delete-table --table-name pipeops-dev-terraform-locks
```
