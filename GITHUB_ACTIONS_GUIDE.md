# GitHub Actions CI/CD Guide

Complete guide for the automated deployment pipelines for PipeOps infrastructure using GitHub Actions.

## 📋 Table of Contents

- [Overview](#overview)
- [Workflows](#workflows)
- [Setup Requirements](#setup-requirements)
- [Environment Secrets](#environment-secrets)
- [Deployment Flow](#deployment-flow)
- [Manual Deployment](#manual-deployment)
- [Troubleshooting](#troubleshooting)

---

## 🎯 Overview

The CI/CD pipeline consists of **3 main workflows**:

1. **`terraform-main.yml`** - Deploys dev, staging, and prod infrastructure
2. **`terraform-dr.yml`** - Deploys DR infrastructure (prod only)
3. **`terraform-pr-checks.yml`** - Validates PRs before merge

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     GitHub Actions                          │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │   Dev Env    │  │ Staging Env  │  │   Prod Env   │     │
│  │  (develop)   │  │    (main)    │  │    (main)    │     │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘     │
│         │                  │                  │             │
│         ▼                  ▼                  ▼             │
│    us-west-2          us-west-2          us-west-2         │
│    ┌────────┐        ┌────────┐        ┌────────┐         │
│    │  VPC   │        │  VPC   │        │  VPC   │         │
│    │  EKS   │        │  EKS   │        │  EKS   │         │
│    │  RDS   │        │  RDS   │        │  RDS   │         │
│    └────────┘        └────────┘        └───┬────┘         │
│                                             │              │
│                                             │              │
│                                             ▼              │
│                                     ┌──────────────┐       │
│                                     │   DR Env     │       │
│                                     │ (prod only)  │       │
│                                     └──────┬───────┘       │
│                                            │               │
│                                            ▼               │
│                                       us-east-1            │
│                                       ┌────────┐           │
│                                       │ DR VPC │           │
│                                       │ DR EKS │           │
│                                       │ DR RDS │           │
│                                       └────────┘           │
└─────────────────────────────────────────────────────────────┘
```

---

## 🔄 Workflows

### 1. Terraform Main Infrastructure (`terraform-main.yml`)

**Purpose:** Deploy core infrastructure for dev, staging, and prod environments.

**Trigger Conditions:**
- **Push to `develop`:** Deploys `dev` environment
- **Push to `main`:** Deploys `staging` and `prod` environments
- **Pull Request:** Runs `terraform plan` for all environments (no apply)
- **Manual Dispatch:** Deploy any environment with custom action (plan/apply/destroy)

**Components Deployed:**
- VPC with public/private/database subnets
- EKS cluster with Auto Mode
- RDS PostgreSQL with Multi-AZ
- ArgoCD for GitOps
- Monitoring stack (Prometheus, Grafana)
- AWS Load Balancer Controller
- External Secrets Operator

**Backend Configuration:**
| Environment | S3 Bucket | DynamoDB Table | State Key |
|-------------|-----------|----------------|-----------|
| dev | `pipeops-dev-terraform-state` | `pipeops-dev-terraform-locks` | `dev/terraform.tfstate` |
| staging | `pipeops-staging-terraform-state` | `pipeops-staging-terraform-locks` | `staging/terraform.tfstate` |
| prod | `pipeops-prod-terraform-state` | `pipeops-prod-terraform-locks` | `prod/terraform.tfstate` |

### 2. Terraform DR Infrastructure (`terraform-dr.yml`)

**Purpose:** Deploy disaster recovery infrastructure for production.

**Trigger Conditions:**
- **Push to `main`:** Deploys DR infrastructure
- **Pull Request:** Runs `terraform plan` for DR (no apply)
- **Manual Dispatch:** Deploy DR with custom action (plan/apply/destroy)

**Components Deployed:**
- DR VPC in `us-east-1`
- DR EKS cluster (standby mode, minimal nodes)
- DR RDS read replica (cross-region from primary)
- DR-specific security groups and IAM roles
- DR KMS keys for encryption

**Backend Configuration:**
| Component | Value |
|-----------|-------|
| S3 Bucket | `pipeops-prod-dr-terraform-state` |
| DynamoDB Table | `pipeops-prod-dr-terraform-locks` |
| Region | `us-east-1` |
| State Key | `dr/terraform.tfstate` |

**Dependencies:**
- Requires primary prod infrastructure to be deployed first
- Automatically fetches primary RDS ARN from prod state

### 3. Terraform PR Checks (`terraform-pr-checks.yml`)

**Purpose:** Validate code quality, security, and cost before merging.

**Checks Performed:**
- ✅ Terraform formatting (`terraform fmt`)
- ✅ Terraform validation (`terraform validate`)
- ✅ Security scanning (tfsec)
- ✅ Secrets detection (Gitleaks)
- ✅ Cost estimation (Infracost) - *optional*
- ✅ Documentation check (terraform-docs)

**Trigger Conditions:**
- Any Pull Request to `main` or `develop` branches

---

## ⚙️ Setup Requirements

### 1. GitHub Repository Settings

Enable the following in your GitHub repository:

1. **Actions Permissions:**
   - Settings → Actions → General → Workflow permissions
   - Select: "Read and write permissions"
   - Check: "Allow GitHub Actions to create and approve pull requests"

2. **Environments:**
   Create the following environments in Settings → Environments:
   - `dev`
   - `staging`
   - `prod`
   - `prod-dr`

3. **Branch Protection Rules:**
   - `main` branch:
     - Require PR reviews before merging
     - Require status checks to pass (all PR check workflows)
     - Require branches to be up to date before merging
   - `develop` branch:
     - Require status checks to pass

### 2. AWS Prerequisites

For each environment, run the setup script locally first:

```bash
# Development
./scripts/setup-prerequisites.sh dev

# Staging
./scripts/setup-prerequisites.sh staging

# Production
./scripts/setup-prerequisites.sh prod

# DR (from dr-infrastructure folder)
cd dr-infrastructure
./scripts/setup-dr-prerequisites.sh
```

This creates:
- S3 buckets for Terraform state
- DynamoDB tables for state locking
- KMS keys for encryption

---

## 🔐 Environment Secrets

Configure the following secrets in GitHub:

### Repository Secrets (Settings → Secrets and variables → Actions)

#### AWS Credentials (OIDC - Recommended) ✅

**Using OpenID Connect (No long-lived access keys required):**

```yaml
# Development
AWS_ROLE_ARN_DEV: arn:aws:iam::ACCOUNT_ID:role/pipeops-dev-github-actions

# Staging
AWS_ROLE_ARN_STAGING: arn:aws:iam::ACCOUNT_ID:role/pipeops-staging-github-actions

# Production (used for both prod and DR)
AWS_ROLE_ARN_PROD: arn:aws:iam::ACCOUNT_ID:role/pipeops-prod-github-actions
```

**⚠️ See [AWS OIDC Setup Guide](./.github/workflows/AWS_OIDC_SETUP_GUIDE.md) for complete configuration!**

#### Alternative: Access Keys (Not Recommended) ⚠️

If you must use access keys (legacy approach):

```yaml
# Development
AWS_ACCESS_KEY_ID_DEV: <dev-iam-access-key>
AWS_SECRET_ACCESS_KEY_DEV: <dev-iam-secret-key>

# Staging
AWS_ACCESS_KEY_ID_STAGING: <staging-iam-access-key>
AWS_SECRET_ACCESS_KEY_STAGING: <staging-iam-secret-key>

# Production (used for both prod and DR)
AWS_ACCESS_KEY_ID_PROD: <prod-iam-access-key>
AWS_SECRET_ACCESS_KEY_PROD: <prod-iam-secret-key>
```

**Note:** Access keys are less secure. Use OIDC instead.

#### Optional Secrets

```yaml
# Cost estimation (optional)
INFRACOST_API_KEY: <infracost-api-key>

# Custom notifications (optional)
SLACK_WEBHOOK_URL: <slack-webhook-url>
```

### IAM Permissions Required

The IAM users need the following AWS permissions:

<details>
<summary>IAM Policy (Click to expand)</summary>

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:*",
        "eks:*",
        "rds:*",
        "s3:*",
        "dynamodb:*",
        "kms:*",
        "iam:*",
        "route53:*",
        "elasticloadbalancing:*",
        "autoscaling:*",
        "cloudwatch:*",
        "logs:*",
        "secretsmanager:*",
        "ssm:*"
      ],
      "Resource": "*"
    }
  ]
}
```

**Note:** In production, use more restrictive policies with resource-level permissions.

</details>

---

## 🚀 Deployment Flow

### Automatic Deployments

#### Development Flow

```bash
# 1. Create feature branch
git checkout -b feature/my-feature

# 2. Make changes
# ... edit terraform files ...

# 3. Create PR to develop
git push origin feature/my-feature
# Open PR to 'develop' branch

# 4. PR Checks run automatically
# - Terraform validate
# - Security scan
# - Cost estimate

# 5. Merge PR to develop
# Automatically deploys to dev environment
```

#### Staging/Production Flow

```bash
# 1. Create PR from develop to main
# Or create hotfix branch from main

# 2. PR Checks run automatically

# 3. Merge to main
# Automatically deploys to:
# - staging environment
# - prod environment (sequential)
# - prod-dr environment (after prod)
```

### Deployment Order

When pushing to `main`, deployments happen in this order:

```
1. Staging Environment (us-west-2)
   └─ VPC → RDS → EKS → ArgoCD → Monitoring
           ↓
2. Production Environment (us-west-2)
   └─ VPC → RDS → EKS → ArgoCD → Monitoring
           ↓
3. DR Environment (us-east-1)
   └─ DR VPC → DR EKS → DR RDS Replica
```

---

## 🎮 Manual Deployment

### Deploy Specific Environment

1. Go to **Actions** tab in GitHub
2. Select **"Terraform Main Infrastructure"** workflow
3. Click **"Run workflow"**
4. Select:
   - **Branch:** `main` or `develop`
   - **Environment:** `dev`, `staging`, or `prod`
   - **Action:** `plan`, `apply`, or `destroy`
5. Click **"Run workflow"**

### Deploy DR Infrastructure

1. Go to **Actions** tab in GitHub
2. Select **"Terraform DR Infrastructure"** workflow
3. Click **"Run workflow"**
4. Select:
   - **Branch:** `main`
   - **Action:** `plan`, `apply`, or `destroy`
5. Click **"Run workflow"**

### Emergency Rollback

If a deployment fails or causes issues:

```bash
# Option 1: Revert the Git commit
git revert <commit-hash>
git push origin main

# Option 2: Manual destroy and redeploy (use with caution)
# Go to Actions → Run workflow → Select 'destroy'
# Then redeploy from a known good commit
```

---

## 📊 Monitoring Deployments

### View Deployment Status

1. **GitHub Actions Tab:**
   - Real-time logs for all workflows
   - Deployment summaries
   - Plan outputs

2. **Environment Status:**
   - Settings → Environments
   - Shows last deployment time and status

3. **Artifacts:**
   - Each workflow saves:
     - `tfplan-<environment>` - Terraform plans
     - `outputs-<environment>.json` - Terraform outputs
   - Retained for 5-30 days

### Deployment Notifications

The workflows provide:
- ✅ GitHub status checks on PRs
- 📝 Plan outputs as PR comments
- 📊 Deployment summaries in workflow logs
- 📦 Cost estimates on PRs (if Infracost configured)

---

## 🔍 Troubleshooting

### Common Issues

#### 1. Backend Already Exists Error

**Error:**
```
Error: backend already initialized
```

**Solution:**
```bash
# The workflow will auto-create backends if they don't exist
# If you see this error, the backend exists but might be misconfigured

# Manually check backend:
aws s3 ls s3://pipeops-<env>-terraform-state
aws dynamodb describe-table --table-name pipeops-<env>-terraform-locks
```

#### 2. State Lock Error

**Error:**
```
Error: Error locking state: ConditionalCheckFailedException
```

**Solution:**
```bash
# Someone else is running Terraform or a previous run failed
# Check if another workflow is running
# If stuck, manually remove lock:

aws dynamodb delete-item \
  --table-name pipeops-<env>-terraform-locks \
  --key '{"LockID":{"S":"pipeops-<env>-terraform-state/<env>/terraform.tfstate"}}'
```

#### 3. DR Deployment Fails - Primary RDS Not Found

**Error:**
```
Warning: Primary RDS ARN not found
```

**Solution:**
```bash
# Ensure primary prod infrastructure is deployed first
# Check that prod deployment completed successfully
# Verify RDS instance exists in us-west-2

# Then manually update dr-infrastructure/environments/prod/terraform.tfvars:
primary_rds_arn = "arn:aws:rds:us-west-2:ACCOUNT_ID:db:pipeops-prod-postgres"
```

#### 4. Insufficient IAM Permissions

**Error:**
```
Error: UnauthorizedOperation: You are not authorized to perform this operation
```

**Solution:**
```bash
# Review IAM policy for the GitHub Actions user
# Ensure all required permissions are granted
# Check CloudTrail logs for specific denied actions

aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=<denied-action>
```

#### 5. Terraform Version Mismatch

**Error:**
```
Error: Unsupported Terraform Core version
```

**Solution:**
```yaml
# Update TF_VERSION in workflow files:
# .github/workflows/terraform-main.yml
# .github/workflows/terraform-dr.yml

env:
  TF_VERSION: '1.5.0'  # Update to your required version
```

#### 6. Cost Estimation Fails

**Error:**
```
Infracost error: API key not found
```

**Solution:**
```bash
# Cost estimation is optional
# Either add INFRACOST_API_KEY secret or ignore
# The workflow will continue even if Infracost fails
```

---

## 🔒 Security Best Practices

### 1. Secrets Management
- ✅ Store all credentials in GitHub Secrets (never commit)
- ✅ Use separate IAM users per environment
- ✅ Rotate credentials regularly (every 90 days)
- ✅ Use least-privilege IAM policies

### 2. Branch Protection
- ✅ Require PR reviews for `main` and `develop`
- ✅ Require all checks to pass before merge
- ✅ Prevent force pushes to protected branches

### 3. State File Security
- ✅ S3 buckets encrypted with KMS
- ✅ Versioning enabled on state buckets
- ✅ State locking with DynamoDB
- ✅ Bucket policies restrict access to specific IAM roles

### 4. Network Security
- ✅ Deploy to private subnets when possible
- ✅ Use security groups to restrict traffic
- ✅ Enable VPC Flow Logs
- ✅ Use AWS Systems Manager Session Manager (no SSH)

### 5. Audit and Compliance
- ✅ CloudTrail enabled in all regions
- ✅ Config rules for compliance checks
- ✅ Regular security scans (tfsec, Gitleaks)
- ✅ Cost monitoring and alerts

---

## 📚 Additional Resources

### Documentation
- [Main README](README.md)
- [RDS Complete Guide](RDS_COMPLETE_GUIDE.md)
- [DR Workspace Setup](DR_WORKSPACE_SETUP.md)
- [Environment Deployment Guide](ENVIRONMENT_DEPLOYMENT_GUIDE.md)
- [Kubernetes Manifests](k8s-manifests/README.md)

### External Resources
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [AWS EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)

---

## 🤝 Contributing

When contributing infrastructure changes:

1. Create a feature branch from `develop`
2. Make your changes
3. Ensure `terraform fmt` is run
4. Create PR to `develop`
5. Wait for all checks to pass
6. Get approval from platform team
7. Merge to `develop` (auto-deploys to dev)
8. Test in dev environment
9. Create PR from `develop` to `main` for staging/prod

---

## 📞 Support

For issues or questions:
- **Infrastructure:** platform-team@example.com
- **Security:** security-team@example.com
- **On-call:** See PagerDuty rotation

---

**Last Updated:** 2026-01-22  
**Version:** 1.0.0  
**Maintained by:** Platform Engineering Team
