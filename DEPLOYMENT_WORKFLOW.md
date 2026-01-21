# Deployment Workflow Guide

Complete guide for setting up and deploying the PipeOps infrastructure.

## 🔄 Complete Workflow

```
┌─────────────────────────────────────────────────────────────────┐
│                    1. PREREQUISITES SETUP                        │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
        ./scripts/setup-prerequisites.sh <environment> <region>
                              │
                              ▼
                    ┌─────────────────┐
                    │  Creates AWS    │
                    │  Resources:     │
                    │  • S3 Bucket    │
                    │  • DynamoDB     │
                    │  • KMS Key      │
                    │  • IAM Roles    │
                    └─────────┬───────┘
                              │
                              ▼
        ┌─────────────────────────────────────────────┐
        │ Generates: environments/$ENV/backend.conf    │
        │                                             │
        │  key      = "pipeops-project-iac-$ENV..."  │
        │  region   = "us-west-2"                    │
        │  encrypt  = true                           │
        │  dynamodb_table = "terraform-state-lock"   │
        │  bucket   = "pipeops-terraform-state..."   │
        └─────────────────┬───────────────────────────┘
                          │
┌─────────────────────────────────────────────────────────────────┐
│                    2. DEPLOYMENT                                 │
└─────────────────────────────────────────────────────────────────┘
                          │
                          ▼
             ./scripts/deploy.sh <environment> <action>
                          │
                          ▼
            ┌─────────────────────────┐
            │  deploy.sh Reads:       │
            │  environments/$ENV/     │
            │    • backend.conf       │
            │    • terraform.tfvars   │
            └───────────┬─────────────┘
                        │
                        ▼
        ┌───────────────────────────────┐
        │  terraform init               │
        │    -backend-config=           │
        │    environments/$ENV/         │
        │    backend.conf               │
        └───────────┬───────────────────┘
                    │
                    ▼
        ┌───────────────────────────────┐
        │  terraform plan/apply         │
        │    -var-file=environments/    │
        │    $ENV/terraform.tfvars      │
        └───────────┬───────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────────────────┐
│                 3. INFRASTRUCTURE CREATED                        │
└─────────────────────────────────────────────────────────────────┘
                    │
                    ▼
        ┌───────────────────────────────┐
        │  • VPC & Networking           │
        │  • EKS Cluster (Auto Mode)    │
        │  • RDS (Multi-AZ + DR)        │
        │  • ArgoCD                     │
        │  • Monitoring Stack           │
        │  • Load Balancer Controller   │
        └───────────────────────────────┘
```

## 📋 Step-by-Step Guide

### **Step 1: Prerequisites Setup**

This step creates all necessary AWS resources for Terraform state management.

```bash
# For Development
./scripts/setup-prerequisites.sh dev us-east-1

# For Staging
./scripts/setup-prerequisites.sh staging us-west-2

# For Production
./scripts/setup-prerequisites.sh prod us-west-2
```

#### What It Creates:

| Resource | Naming Pattern | Purpose |
|----------|----------------|---------|
| **S3 Bucket** | `pipeops-terraform-state-{env}-{account-id}` | Stores Terraform state files |
| **DynamoDB Table** | `terraform-state-lock-{env}` | Prevents concurrent state modifications |
| **KMS Key** | `alias/pipeops-{env}-terraform` | Encrypts sensitive data |
| **IAM Role** | `pipeops-{env}-deploy-role` | CI/CD deployment permissions |
| **Backend Config** | `environments/{env}/backend.conf` | Backend configuration for Terraform |

#### Output Files:

```
environments/{env}/
├── backend.conf                    # Used by deploy.sh
└── terraform.tfvars               # Environment variables

backend-{env}.hcl                  # Reference file (optional)
.env.{env}                         # Environment variables
```

### **Step 2: Deployment**

Once prerequisites are set up, deploy the infrastructure.

```bash
# Plan (preview changes)
./scripts/deploy.sh dev plan

# Apply (create resources)
./scripts/deploy.sh dev apply

# Destroy (remove all resources - be careful!)
./scripts/deploy.sh dev destroy
```

#### What deploy.sh Does:

1. **Validates Environment**
   - Checks if environment exists (dev/staging/prod)
   - Verifies terraform.tfvars file exists

2. **Sets Up Backend**
   - Reads `environments/{env}/backend.conf`
   - Initializes Terraform with proper backend config
   - Ensures state is stored in S3

3. **Runs Terraform**
   - Executes terraform plan/apply/destroy
   - Uses environment-specific variables
   - Manages infrastructure as code

4. **Configures kubectl** (on apply)
   - Updates kubeconfig for EKS access
   - Enables direct cluster management

## 🔧 Configuration Files

### Backend Configuration (`environments/{env}/backend.conf`)

**Generated by**: `setup-prerequisites.sh`  
**Used by**: `deploy.sh` → `terraform init`

```hcl
key      = "pipeops-project-iac-dev-terraform.tfstate"
region   = "us-east-1"
encrypt  = true
dynamodb_table = "terraform-state-lock-dev"
bucket   = "pipeops-terraform-state-dev-742890864997"
```

### Terraform Variables (`environments/{env}/terraform.tfvars`)

**Created manually** (or from template)  
**Used by**: `deploy.sh` → `terraform apply`

```hcl
# Core Configuration
project_name = "pipeops"
environment  = "dev"
region       = "us-west-2"

# EKS Configuration
kubernetes_version = "1.31"

# RDS Configuration
db_instance_class = "db.t3.micro"
db_multi_az = false
db_enable_cross_region_dr = false
```

## 🌍 Environment-Specific Setup

### Development

```bash
# 1. Setup prerequisites
./scripts/setup-prerequisites.sh dev us-east-1

# 2. Review generated config
cat environments/dev/backend.conf

# 3. Deploy infrastructure
./scripts/deploy.sh dev plan
./scripts/deploy.sh dev apply

# 4. Access the cluster
kubectl get nodes
```

**Characteristics:**
- Single-AZ RDS (cost-optimized)
- Smaller instance types
- Internal-only ingress
- Region: `us-east-1`

### Staging

```bash
# 1. Setup prerequisites
./scripts/setup-prerequisites.sh staging us-west-2

# 2. Deploy infrastructure
./scripts/deploy.sh staging plan
./scripts/deploy.sh staging apply
```

**Characteristics:**
- Multi-AZ RDS (production-like)
- Medium instance types
- Public ingress with SSL
- Region: `us-west-2`

### Production

```bash
# 1. Setup prerequisites
./scripts/setup-prerequisites.sh prod us-west-2

# 2. Deploy infrastructure
./scripts/deploy.sh prod plan
./scripts/deploy.sh prod apply
```

**Characteristics:**
- Multi-AZ RDS + Multi-Region DR
- Production-grade instance types
- Public ingress with WAF
- Strict monitoring and alerting
- Region: `us-west-2` (Primary), `us-east-1` (DR)

## 🔐 Security Best Practices

### State Management

1. **S3 Bucket Security:**
   - ✅ Versioning enabled
   - ✅ Encryption at rest (AES256)
   - ✅ Public access blocked
   - ✅ Access logging recommended

2. **DynamoDB Table:**
   - ✅ On-demand billing (no over-provisioning)
   - ✅ Point-in-time recovery (enable in production)
   - ✅ Encryption at rest

3. **IAM Roles:**
   - ⚠️ Review permissions (currently PowerUserAccess)
   - ✅ Use external ID for assume role
   - ⚠️ Restrict in production (use least privilege)

### Secrets Management

- ❌ **Never** commit `terraform.tfvars` to Git
- ❌ **Never** commit `backend.conf` with production values
- ✅ Use AWS Secrets Manager for sensitive data
- ✅ Use KMS for encryption keys
- ✅ Rotate credentials regularly

## 🔄 Complete Example: Dev Environment

```bash
# 1. Navigate to project
cd pipeops-project-iac

# 2. Check AWS credentials
aws sts get-caller-identity

# 3. Run prerequisites setup
./scripts/setup-prerequisites.sh dev us-east-1

# Expected output:
# ✓ S3 bucket created: pipeops-terraform-state-dev-123456789012
# ✓ DynamoDB table created: terraform-state-lock-dev
# ✓ KMS key created
# ✓ Backend config written to: environments/dev/backend.conf

# 4. Verify backend config
cat environments/dev/backend.conf

# 5. Review Terraform variables
cat environments/dev/terraform.tfvars

# 6. Plan deployment (dry run)
./scripts/deploy.sh dev plan

# Review the plan output...

# 7. Apply deployment
./scripts/deploy.sh dev apply

# Type 'yes' when prompted...

# 8. Wait for resources to be created (~15-20 minutes)
# Watch for completion messages

# 9. Verify EKS cluster
kubectl get nodes
kubectl get namespaces

# 10. Check RDS instance
aws rds describe-db-instances --query 'DBInstances[0].Endpoint'

# 11. Access ArgoCD
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Open https://localhost:8080

# 12. Get ArgoCD admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

## 🧹 Cleanup

To destroy all resources:

```bash
# Destroy infrastructure
./scripts/deploy.sh dev destroy

# Type 'destroy' when prompted

# Optional: Remove backend resources
aws s3 rb s3://pipeops-terraform-state-dev-ACCOUNT_ID --force
aws dynamodb delete-table --table-name terraform-state-lock-dev
```

## 🐛 Troubleshooting

### Issue: "Backend configuration not found"

**Cause:** `setup-prerequisites.sh` hasn't been run yet

**Solution:**
```bash
./scripts/setup-prerequisites.sh <environment> <region>
```

### Issue: "S3 bucket does not exist"

**Cause:** Prerequisites not created or wrong region

**Solution:**
```bash
# Check if bucket exists
aws s3 ls | grep pipeops-terraform-state

# Recreate if needed
./scripts/setup-prerequisites.sh <environment> <region>
```

### Issue: "terraform init fails"

**Cause:** Invalid backend.conf or no access to S3

**Solution:**
```bash
# Verify backend.conf
cat environments/$ENV/backend.conf

# Test S3 access
aws s3 ls s3://$(grep bucket environments/$ENV/backend.conf | cut -d'"' -f2)

# Reinitialize
./scripts/deploy.sh <environment> plan
```

### Issue: "State lock timeout"

**Cause:** Previous terraform process didn't release lock

**Solution:**
```bash
# Check DynamoDB for locks
aws dynamodb scan --table-name terraform-state-lock-<env>

# If needed, force unlock (use with caution!)
terraform force-unlock <lock-id>
```

## 📊 File Structure Reference

```
pipeops-project-iac/
├── scripts/
│   ├── setup-prerequisites.sh      # Creates AWS resources
│   └── deploy.sh                   # Deploys infrastructure
│
├── environments/
│   ├── dev/
│   │   ├── backend.conf            # Generated by setup-prerequisites.sh
│   │   └── terraform.tfvars        # Manual configuration
│   ├── staging/
│   │   ├── backend.conf
│   │   └── terraform.tfvars
│   └── prod/
│       ├── backend.conf
│       └── terraform.tfvars
│
├── backend-{env}.hcl               # Reference files (optional)
├── .env.{env}                      # Environment variables
│
└── modules/                        # Terraform modules
    ├── vpc/
    ├── eks/
    ├── rds/
    ├── argocd/
    └── monitoring/
```

## 📚 Additional Resources

- [Terraform Backend Documentation](https://www.terraform.io/docs/language/settings/backends/s3.html)
- [AWS EKS Auto Mode](https://docs.aws.amazon.com/eks/latest/userguide/auto-mode.html)
- [RDS Multi-AZ Deployments](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Concepts.MultiAZ.html)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)

---

**Last Updated**: 2026-01-21  
**Maintained by**: Platform Team
