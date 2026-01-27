# Scripts Reusability Guide

How to reuse the setup and deployment scripts for other projects.

## 🎯 Overview

All scripts now support the `PROJECT_NAME` environment variable for easy reusability across different projects.

**NEW**: Scripts now automatically configure GitHub Actions OIDC authentication! No more manual OIDC setup required.

---

## 📝 Quick Setup for New Project

### Method 1: Environment Variable (Recommended)

Set `PROJECT_NAME` before running scripts:

```bash
export PROJECT_NAME=your-project-name

# Setup prerequisites for dev
./scripts/setup-prerequisites.sh dev us-west-2

# Setup prerequisites for prod
./scripts/setup-prerequisites.sh prod us-west-2

# Setup DR prerequisites
cd dr-infrastructure
./scripts/setup-dr-prerequisites.sh prod us-east-1
```

### Method 2: Inline Variable

Set `PROJECT_NAME` inline for each command:

```bash
PROJECT_NAME=your-project-name ./scripts/setup-prerequisites.sh dev us-west-2
PROJECT_NAME=your-project-name ./scripts/setup-prerequisites.sh prod us-west-2

cd dr-infrastructure
PROJECT_NAME=your-project-name ./scripts/setup-dr-prerequisites.sh prod us-east-1
```

### Method 3: Update Script Default

Edit the scripts to change the default value:

```bash
# In scripts/setup-prerequisites.sh
PROJECT_NAME=${PROJECT_NAME:-your-project-name}  # Change default here

# In dr-infrastructure/scripts/setup-dr-prerequisites.sh
PROJECT_NAME=${PROJECT_NAME:-your-project-name}  # Change default here
```

---

## 🔧 Scripts Updated

### 1. `setup-prerequisites.sh`

**Location:** `scripts/setup-prerequisites.sh`

**Usage:**
```bash
PROJECT_NAME=myapp ./scripts/setup-prerequisites.sh <environment> <region>
```

**What it creates:**
- S3 Bucket: `${PROJECT_NAME}-${ENVIRONMENT}-terraform-state`
- DynamoDB Table: `${PROJECT_NAME}-${ENVIRONMENT}-terraform-locks`
- KMS Key: `alias/${PROJECT_NAME}-${ENVIRONMENT}-terraform`
- **GitHub OIDC Provider:** `token.actions.githubusercontent.com` (once per AWS account)
- **IAM Role for GitHub Actions:** `${PROJECT_NAME}-${ENVIRONMENT}-github-actions`
- **EKS Terraform exec role:** `${PROJECT_NAME}-${ENVIRONMENT}-eks-terraform-exec` (CI assumes OIDC → this role for `aws eks get-token`)
- **eks-exec-role-arn.txt:** `environments/${ENVIRONMENT}/eks-exec-role-arn.txt` (Terraform uses this for EKS provider auth)
- Backend Config: `environments/${ENVIRONMENT}/backend.conf`

**Environment Variables:**
- `PROJECT_NAME` - Project name (default: pipeops)
- `SKIP_OIDC` - Set to `true` to skip OIDC setup (default: false)

**Example:**
```bash
# For project "acme-platform" dev environment
PROJECT_NAME=acme-platform ./scripts/setup-prerequisites.sh dev us-west-2

# Creates:
# - acme-platform-dev-terraform-state
# - acme-platform-dev-terraform-locks
# - alias/acme-platform-dev-terraform
# - acme-platform-dev-github-actions (IAM role)
# - GitHub OIDC provider (if not exists)

# Skip OIDC if already configured
SKIP_OIDC=true PROJECT_NAME=acme-platform ./scripts/setup-prerequisites.sh dev us-west-2
```

**EKS exec role & bootstrap:** The script creates an EKS Terraform exec role and writes `environments/<ENV>/eks-exec-role-arn.txt`. Terraform uses this for `aws eks get-token --role-arn` when managing Helm/Kubernetes resources. For **existing** EKS clusters, run `make bootstrap-eks-access ENV=<env>` once (with an identity that already has EKS admin, e.g. root) to register the eks-exec role before running full plan/apply. See [GETTING_STARTED.md](../docs/GETTING_STARTED.md) and the [Makefile](../Makefile) (`plan-no-refresh`, `apply-plan`, `bootstrap-eks-access`).

### 2. `setup-dr-prerequisites.sh`

**Location:** `dr-infrastructure/scripts/setup-dr-prerequisites.sh`

**Usage:**
```bash
cd dr-infrastructure
PROJECT_NAME=myapp ./scripts/setup-dr-prerequisites.sh <environment> <dr-region>
```

**What it creates:**
- S3 Bucket: `${PROJECT_NAME}-${ENVIRONMENT}-dr-terraform-state`
- DynamoDB Table: `${PROJECT_NAME}-${ENVIRONMENT}-dr-terraform-locks`
- KMS Key: `alias/${PROJECT_NAME}-${ENVIRONMENT}-dr-terraform`
- Backend Config: `backend.conf`

**Example:**
```bash
# For project "acme-platform" prod DR environment
cd dr-infrastructure
PROJECT_NAME=acme-platform ./scripts/setup-dr-prerequisites.sh prod us-east-1

# Creates:
# - acme-platform-prod-dr-terraform-state
# - acme-platform-prod-dr-terraform-locks
# - alias/acme-platform-prod-dr-terraform
```

### 3. `deploy.sh`

**Location:** `scripts/deploy.sh`

**Usage:**
```bash
PROJECT_NAME=myapp ./scripts/deploy.sh <environment> <action>
```

**Note:** This script reads backend configuration from the generated `backend.conf` files, so it automatically uses the correct project-specific resources.

### 4. `deploy-dr.sh`

**Location:** `dr-infrastructure/scripts/deploy-dr.sh`

**Usage:**
```bash
cd dr-infrastructure
PROJECT_NAME=myapp ./scripts/deploy-dr.sh <action>
```

---

## 🚀 Complete Migration Example

### Migrating to Project "acme-platform"

#### Step 1: Set Project Name

```bash
export PROJECT_NAME=acme-platform
```

#### Step 2: Setup All Environments

```bash
# Development
./scripts/setup-prerequisites.sh dev us-west-2

# Staging
./scripts/setup-prerequisites.sh staging us-west-2

# Production
./scripts/setup-prerequisites.sh prod us-west-2

# DR
cd dr-infrastructure
./scripts/setup-dr-prerequisites.sh prod us-east-1
cd ..
```

#### Step 3: Verify Resources Created

```bash
# Check S3 buckets
aws s3 ls | grep acme-platform

# Expected output:
# acme-platform-dev-terraform-state
# acme-platform-staging-terraform-state
# acme-platform-prod-terraform-state
# acme-platform-prod-dr-terraform-state

# Check DynamoDB tables
aws dynamodb list-tables | grep acme-platform

# Expected output:
# acme-platform-dev-terraform-locks
# acme-platform-staging-terraform-locks
# acme-platform-prod-terraform-locks
# acme-platform-prod-dr-terraform-locks
```

#### Step 4: Deploy Infrastructure

Variables are supplied only via `environments/<ENV>/terraform.tfvars` (declarative; no `-var` overrides). Use `make plan ENV=<env>` / `make apply ENV=<env>` or the deploy scripts.

```bash
# Deploy to dev
make init ENV=dev && make plan ENV=dev && make apply ENV=dev
# Or: PROJECT_NAME=acme-platform ./scripts/deploy.sh dev apply

# Deploy to staging
make init ENV=staging && make plan ENV=staging && make apply ENV=staging

# Deploy to prod
make init ENV=prod && make plan ENV=prod && make apply ENV=prod

# Deploy DR
cd dr-infrastructure
PROJECT_NAME=acme-platform ./scripts/deploy-dr.sh apply
```

---

## 🎨 Integration with GitHub Actions

The workflows automatically use `PROJECT_NAME` from the workflow environment variables:

```yaml
env:
  PROJECT_NAME: your-project-name  # ← Change this
```

The workflows then export `PROJECT_NAME` to the shell environment:

```yaml
- name: Set environment variables
  run: |
    echo "PROJECT_NAME=${{ env.PROJECT_NAME }}" >> $GITHUB_ENV
```

This ensures scripts called by GitHub Actions use the correct project name.

---

## 📊 Resource Naming Convention

| Resource Type | Naming Pattern | Example (PROJECT_NAME=myapp, ENV=prod) |
|---------------|----------------|----------------------------------------|
| **Main Infrastructure** |
| S3 State Bucket | `{PROJECT_NAME}-{ENV}-terraform-state` | `myapp-prod-terraform-state` |
| DynamoDB Lock Table | `{PROJECT_NAME}-{ENV}-terraform-locks` | `myapp-prod-terraform-locks` |
| KMS Key Alias | `alias/{PROJECT_NAME}-{ENV}-terraform` | `alias/myapp-prod-terraform` |
| IAM Deploy Role | `{PROJECT_NAME}-{ENV}-deploy-role` | `myapp-prod-deploy-role` |
| **DR Infrastructure** |
| DR S3 Bucket | `{PROJECT_NAME}-prod-dr-terraform-state` | `myapp-prod-dr-terraform-state` |
| DR DynamoDB Table | `{PROJECT_NAME}-prod-dr-terraform-locks` | `myapp-prod-dr-terraform-locks` |
| DR KMS Key Alias | `alias/{PROJECT_NAME}-prod-dr-terraform` | `alias/myapp-prod-dr-terraform` |

---

## 🔍 Verification

### Check Current Project Name

```bash
# View what PROJECT_NAME is set to
echo $PROJECT_NAME

# If not set, scripts will use default "pipeops"
```

### Verify Backend Configuration

```bash
# Check generated backend config
cat environments/dev/backend.conf

# Should show:
# bucket = "your-project-name-dev-terraform-state"
# key = "dev/terraform.tfstate"
# ...
```

### List All Resources for a Project

```bash
PROJECT=myapp

# List S3 buckets
aws s3 ls | grep $PROJECT

# List DynamoDB tables
aws dynamodb list-tables --output table | grep $PROJECT

# List KMS keys
aws kms list-aliases --output table | grep $PROJECT
```

---

## 🔄 Switching Between Projects

If you work on multiple projects:

```bash
# Set up aliases in ~/.bashrc or ~/.zshrc

alias setup-project-a='export PROJECT_NAME=project-a'
alias setup-project-b='export PROJECT_NAME=project-b'

# Usage:
setup-project-a
./scripts/setup-prerequisites.sh dev us-west-2

setup-project-b
./scripts/setup-prerequisites.sh dev us-west-2
```

---

## 📋 Pre-Migration Checklist

Before migrating to a new project:

- [ ] Decide on project name (lowercase, alphanumeric, hyphens only)
- [ ] Set `PROJECT_NAME` environment variable
- [ ] Update GitHub Actions workflows (if using)
- [ ] Run setup scripts for all environments
- [ ] Verify resources created in AWS
- [ ] Update terraform.tfvars files with project name
- [ ] Test deployment to dev environment first

---

## 🛠️ Troubleshooting

### Issue: "Bucket already exists"

**Problem:** S3 bucket name conflict.

**Solution:**
```bash
# Use a more specific project name
export PROJECT_NAME=company-myapp

# Or include a unique identifier
export PROJECT_NAME=myapp-${USER}
```

### Issue: Scripts still use "pipeops"

**Problem:** `PROJECT_NAME` not exported or not set.

**Solution:**
```bash
# Export the variable (not just set it)
export PROJECT_NAME=your-project-name

# Verify it's set
echo $PROJECT_NAME

# Or use inline
PROJECT_NAME=your-project-name ./scripts/setup-prerequisites.sh dev us-west-2
```

### Issue: GitHub Actions not using custom PROJECT_NAME

**Problem:** Workflow file not updated.

**Solution:**
Update `.github/workflows/terraform-main.yml` and `terraform-dr.yml`:
```yaml
env:
  PROJECT_NAME: your-project-name  # ← Update this
```

---

## 📚 Additional Resources

- [GitHub Actions Reusability Guide](../.github/workflows/REUSABILITY_GUIDE.md)
- [Environment Deployment Guide](../ENVIRONMENT_DEPLOYMENT_GUIDE.md)
- [Quick Start Guide](../QUICK_START.md)

---

## 🤝 Best Practices

### Naming Conventions

1. **Use lowercase:** `myapp` not `MyApp`
2. **Use hyphens for separators:** `my-app` not `my_app`
3. **Keep it short:** `acme-web` not `acme-corporation-web-platform`
4. **Make it unique:** Include company name if needed `acme-myapp`
5. **AWS S3 bucket rules apply:** 3-63 characters, start/end with letter or number

### Organization

1. **Same PROJECT_NAME across all environments**
   ```bash
   export PROJECT_NAME=myapp
   ./scripts/setup-prerequisites.sh dev us-west-2
   ./scripts/setup-prerequisites.sh staging us-west-2
   ./scripts/setup-prerequisites.sh prod us-west-2
   ```

2. **Document your project name**
   ```bash
   # Add to README.md
   ## Project Configuration
   PROJECT_NAME: myapp
   ```

3. **Use consistent names**
   - Terraform variables: `project_name = "myapp"`
   - Scripts: `PROJECT_NAME=myapp`
   - Workflows: `PROJECT_NAME: myapp`

---

## 🔐 GitHub Actions OIDC Setup

### What's New

The `setup-prerequisites.sh` script now automatically configures GitHub Actions OIDC authentication!

### What It Does

When you run `setup-prerequisites.sh`, it will:

1. **Create GitHub OIDC Provider** (once per AWS account)
   - URL: `token.actions.githubusercontent.com`
   - Enables passwordless authentication from GitHub Actions

2. **Create IAM Role per Environment**
   - Dev: `${PROJECT_NAME}-dev-github-actions`
   - Staging: `${PROJECT_NAME}-staging-github-actions`
   - Prod: `${PROJECT_NAME}-prod-github-actions`

3. **Configure Branch-Based Access**
   - Dev role → Can only be assumed from `develop` branch
   - Staging/Prod roles → Can only be assumed from `main` branch

4. **Prompt for GitHub Repository**
   - Asks for your GitHub org/username
   - Asks for your repository name
   - Configures trust policy accordingly

### Usage

**Interactive Mode (Recommended):**
```bash
PROJECT_NAME=myapp ./scripts/setup-prerequisites.sh dev us-west-2

# Script will prompt:
# Enter GitHub organization/username (default: your-org): myorg
# Enter GitHub repository name (default: myapp-project-iac): myapp-infrastructure
```

**Non-Interactive Mode:**
```bash
# Uses defaults: your-org/pipeops-project-iac
PROJECT_NAME=myapp ./scripts/setup-prerequisites.sh dev < /dev/null
```

**Skip OIDC (Use Access Keys):**
```bash
# If you want to use access keys instead
SKIP_OIDC=true PROJECT_NAME=myapp ./scripts/setup-prerequisites.sh dev
```

### After Running Script

The script will display the IAM role ARN that you need to add to GitHub:

```
=== GITHUB ACTIONS SETUP REQUIRED ===
Add this secret to your GitHub repository:

  Secret Name:  AWS_ROLE_ARN_DEV
  Secret Value: arn:aws:iam::123456789012:role/myapp-dev-github-actions

To add via GitHub CLI:
  gh secret set AWS_ROLE_ARN_DEV \
    --body "arn:aws:iam::123456789012:role/myapp-dev-github-actions" \
    --repo myorg/myapp-infrastructure
```

### Adding Secrets to GitHub

**Method 1: GitHub CLI (Recommended)**
```bash
# Dev
gh secret set AWS_ROLE_ARN_DEV \
  --body "arn:aws:iam::ACCOUNT_ID:role/myapp-dev-github-actions" \
  --repo myorg/myapp-infrastructure

# Staging
gh secret set AWS_ROLE_ARN_STAGING \
  --body "arn:aws:iam::ACCOUNT_ID:role/myapp-staging-github-actions" \
  --repo myorg/myapp-infrastructure

# Prod
gh secret set AWS_ROLE_ARN_PROD \
  --body "arn:aws:iam::ACCOUNT_ID:role/myapp-prod-github-actions" \
  --repo myorg/myapp-infrastructure
```

**Method 2: GitHub Web UI**
1. Go to your repository on GitHub
2. Settings → Secrets and variables → Actions
3. Click "New repository secret"
4. Add each secret with the name/value from script output

### Complete Reusable Workflow

For a new project called "acme-platform":

```bash
export PROJECT_NAME=acme-platform

# Setup dev
./scripts/setup-prerequisites.sh dev us-west-2
# (Enter GitHub org/repo when prompted)
# Copy the role ARN from output

# Setup staging
./scripts/setup-prerequisites.sh staging us-west-2
# (Same prompts)
# Copy the role ARN from output

# Setup prod
./scripts/setup-prerequisites.sh prod us-west-2
# (Same prompts)
# Copy the role ARN from output

# Add all three role ARNs as GitHub secrets
gh secret set AWS_ROLE_ARN_DEV --body "arn:aws:iam::ACCOUNT:role/acme-platform-dev-github-actions"
gh secret set AWS_ROLE_ARN_STAGING --body "arn:aws:iam::ACCOUNT:role/acme-platform-staging-github-actions"
gh secret set AWS_ROLE_ARN_PROD --body "arn:aws:iam::ACCOUNT:role/acme-platform-prod-github-actions"

# Done! GitHub Actions will now use OIDC authentication
```

### Benefits

✅ **No Long-Lived Credentials** - No AWS access keys to manage or rotate  
✅ **Automatic Expiration** - Temporary credentials expire in 1 hour  
✅ **Branch Protection** - Roles can only be assumed from specific branches  
✅ **Repository Restriction** - Roles only work for your repository  
✅ **Audit Trail** - All authentication logged in CloudTrail  
✅ **One Command Setup** - No manual OIDC configuration needed  

### Related Documentation

- `.github/workflows/AWS_OIDC_SETUP_GUIDE.md` - Detailed OIDC setup guide
- `GITHUB_ACTIONS_GUIDE.md` - Complete CI/CD documentation

---

## ✅ Summary

All scripts now support `PROJECT_NAME` environment variable and automatic OIDC setup:

✅ **setup-prerequisites.sh** - Uses `PROJECT_NAME` for all resources + OIDC setup  
✅ **setup-dr-prerequisites.sh** - Uses `PROJECT_NAME` for DR resources  
✅ **deploy.sh** - Reads from generated backend configs  
✅ **deploy-dr.sh** - Reads from generated backend configs  

**To use for another project:**
```bash
export PROJECT_NAME=your-project-name
./scripts/setup-prerequisites.sh dev us-west-2
# (Prompts for GitHub org/repo)
# (Displays role ARN to add as GitHub secret)
```

**Environment Variables:**
- `PROJECT_NAME` - Project name (default: `pipeops`)
- `SKIP_OIDC` - Skip OIDC setup (default: `false`)

---

**Last Updated:** 2026-01-22  
**Version:** 1.0.0  
**Script Compatibility:** v1.x
