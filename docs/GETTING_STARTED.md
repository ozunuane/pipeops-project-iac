# Getting Started

Step-by-step guide to deploy the PipeOps infrastructure.

## Prerequisites

### Required Tools

| Tool | Version | Installation |
|------|---------|--------------|
| **AWS CLI** | >= 2.0 | `brew install awscli` |
| **Terraform** | >= 1.5 | `brew install terraform` |
| **kubectl** | >= 1.28 | `brew install kubectl` |
| **Helm** | >= 3.12 | `brew install helm` |
| **Git** | >= 2.0 | `brew install git` |

### AWS Permissions

The IAM user/role needs these permissions:

- `AmazonEKSFullAccess`
- `AmazonVPCFullAccess`
- `AmazonRDSFullAccess`
- `AmazonS3FullAccess`
- `AmazonDynamoDBFullAccess`
- `IAMFullAccess`
- `AmazonEC2FullAccess`
- `SecretsManagerReadWrite`
- `CloudWatchFullAccess`

---

## Initial Setup

### Step 1: Clone Repository

```bash
git clone https://github.com/your-org/pipeops-project-iac.git
cd pipeops-project-iac
```

### Step 2: Configure AWS Credentials

```bash
# Configure AWS CLI
aws configure
# AWS Access Key ID: YOUR_ACCESS_KEY
# AWS Secret Access Key: YOUR_SECRET_KEY
# Default region: us-west-2
# Default output format: json

# Verify credentials
aws sts get-caller-identity
```

### Step 3: Create Backend Resources

The S3 bucket and DynamoDB table for Terraform state:

```bash
# For development environment
./scripts/setup-prerequisites.sh dev us-west-2

# For production environment
./scripts/setup-prerequisites.sh prod us-west-2
```

This creates:
- S3 bucket: `pipeops-{env}-terraform-state`
- DynamoDB table: `pipeops-{env}-terraform-locks`
- OIDC provider for GitHub Actions (optional)

### Step 4: Configure Variables

Variables are supplied **only** via `environments/<ENV>/terraform.tfvars` (declarative). Do not use `-var` overrides. Use `make plan ENV=<env>` and `make apply ENV=<env>` so the Makefile passes the correct `-var-file`.

```bash
# Copy example and edit per environment
cp terraform.tfvars.example environments/prod/terraform.tfvars
# Or edit existing: environments/dev/terraform.tfvars, etc.
vim environments/prod/terraform.tfvars
```

Key variables to configure:

```hcl
# Project
project_name = "pipeops"
environment  = "prod"
region       = "us-west-2"

# EKS / RDS – optional creation per environment
create_eks         = true   # Set false to skip EKS and EKS-dependent resources
create_rds         = true   # Set false to skip RDS and DB-related resources
kubernetes_version = "1.33"
cluster_exists     = false  # Set to true after first EKS deployment (enables Helm, Karpenter, etc.)

# RDS
db_instance_class    = "db.r6g.large"
db_allocated_storage = 400
db_postgres_version  = "16.6"

# Features
enable_argocd     = true
enable_monitoring = true
```

---

## Deployment

### Option 1: GitHub Actions (Recommended)

Push to trigger automatic deployment:

```bash
# Deploy to development
git checkout develop
git push origin develop

# Deploy to production (via PR)
git checkout main
git merge develop
git push origin main
```

### Option 2: Local Deployment

Use the **Makefile** (recommended). Variables come only from `-var-file`; no `-var` overrides.

#### Initialize Terraform

```bash
make init ENV=prod
# Or: terraform init -backend-config=environments/prod/backend.conf -reconfigure
```

#### Plan Changes

```bash
make plan ENV=prod
# Or: terraform plan -var-file=environments/prod/terraform.tfvars -no-color -input=false
```

To save a plan for apply: use `make plan-no-refresh ENV=prod` then `make apply-plan ENV=prod` when the EKS exec role does not yet have EKS access (e.g. first CI run). See [Makefile](../Makefile) help.

#### Apply Changes

```bash
make apply ENV=prod
# Or: terraform apply -var-file=environments/prod/terraform.tfvars -input=false
```

### Two-Phase Deployment

For initial deployment, use two phases:

```bash
# Phase 1: Infrastructure only (EKS not ready yet)
# Set cluster_exists = false in environments/prod/terraform.tfvars
make apply ENV=prod

# Phase 2: Kubernetes resources (Helm, Karpenter, etc.)
# Set cluster_exists = true in environments/prod/terraform.tfvars
make apply ENV=prod
```

### EKS Access (CI / existing clusters)

- **Setup prerequisites** creates an EKS Terraform exec role and writes `environments/<ENV>/eks-exec-role-arn.txt`. Terraform uses this for `aws eks get-token --role-arn` when talking to EKS.
- For **existing clusters**, run `make bootstrap-eks-access ENV=prod` once (with an identity that already has EKS admin, e.g. root) to register the eks-exec role before running full plan/apply.

---

## Post-Deployment

### Access EKS Cluster

```bash
# Update kubeconfig
aws eks update-kubeconfig --region us-west-2 --name pipeops-prod-eks

# Verify access
kubectl get nodes
kubectl get namespaces
```

### Add Your IAM User to EKS

If you get authentication errors:

```bash
# Create access entry
aws eks create-access-entry \
  --cluster-name pipeops-prod-eks \
  --principal-arn arn:aws:iam::ACCOUNT_ID:user/YOUR_USER \
  --region us-west-2

# Grant admin access
aws eks associate-access-policy \
  --cluster-name pipeops-prod-eks \
  --principal-arn arn:aws:iam::ACCOUNT_ID:user/YOUR_USER \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster \
  --region us-west-2
```

### Access ArgoCD

```bash
# Port forward
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# Access at https://localhost:8080
# Username: admin
# Password: (from above command)
```

### Access Grafana

```bash
# Port forward
kubectl port-forward svc/grafana -n monitoring 3000:80

# Access at http://localhost:3000
# Username: admin
# Password: (from terraform output grafana_admin_password)
```

---

## Terraform Outputs

View deployed resource information:

```bash
# All outputs
terraform output

# Specific outputs
terraform output cluster_endpoint
terraform output rds_endpoint
terraform output argocd_url
```

---

## Troubleshooting

### Terraform Init Fails

```bash
# Check AWS credentials
aws sts get-caller-identity

# Check S3 bucket exists
aws s3 ls s3://pipeops-prod-terraform-state
```

### EKS Access Denied

```bash
# Update kubeconfig
aws eks update-kubeconfig --region us-west-2 --name pipeops-prod-eks

# Check current context
kubectl config current-context

# List access entries
aws eks list-access-entries --cluster-name pipeops-prod-eks --region us-west-2
```

### RDS Connection Issues

```bash
# Check security groups
aws ec2 describe-security-groups --group-ids sg-xxx

# Test from within cluster
kubectl run -it --rm debug --image=postgres:16 --restart=Never -- \
  psql -h <rds-endpoint> -U postgres
```

---

## Next Steps

1. **Configure CI/CD**: See [CI_CD.md](./CI_CD.md)
2. **Setup environments**: See [ENVIRONMENTS.md](./ENVIRONMENTS.md)
3. **Enable DR**: See [DISASTER_RECOVERY.md](./DISASTER_RECOVERY.md)
4. **Deploy applications**: Use ArgoCD to deploy your apps
