# GitHub Actions Workflow Diagrams

Visual representation of the CI/CD pipeline flows.

## 📊 Overall Pipeline Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         GitHub Repository                           │
└────────────┬────────────────────────────────────┬───────────────────┘
             │                                    │
             │                                    │
    ┌────────▼────────┐                  ┌───────▼────────┐
    │  Pull Request   │                  │  Push to Branch │
    └────────┬────────┘                  └───────┬─────────┘
             │                                    │
             │                                    │
    ┌────────▼────────────────────┐              │
    │  terraform-pr-checks.yml    │              │
    │  - Validate                 │              │
    │  - Format Check             │              │
    │  - Security Scan            │              │
    │  - Secrets Detection        │              │
    │  - Cost Estimate            │              │
    │  - Documentation Check      │              │
    └─────────────────────────────┘              │
                                                  │
                        ┌─────────────────────────┼──────────────────┐
                        │                         │                  │
               ┌────────▼────────┐    ┌──────────▼─────────┐  ┌────▼─────┐
               │  develop branch │    │   main branch      │  │  Manual  │
               └────────┬────────┘    └──────────┬─────────┘  │ Dispatch │
                        │                        │             └────┬─────┘
                        │                        │                  │
               ┌────────▼────────┐    ┌──────────▼─────────┐  ┌────▼─────┐
               │  Deploy DEV     │    │  Deploy STAGING    │  │  Custom  │
               │  (us-west-2)    │    │  (us-west-2)       │  │  Action  │
               └─────────────────┘    └──────────┬─────────┘  └──────────┘
                                                 │
                                      ┌──────────▼─────────┐
                                      │  Deploy PROD       │
                                      │  (us-west-2)       │
                                      └──────────┬─────────┘
                                                 │
                                      ┌──────────▼─────────┐
                                      │  Deploy PROD-DR    │
                                      │  (us-east-1)       │
                                      └────────────────────┘
```

---

## 🔄 Main Infrastructure Workflow (terraform-main.yml)

### Flow Diagram

```
START
  │
  ├─ Determine Environments
  │   ├─ develop branch → [dev]
  │   ├─ main branch → [staging, prod]
  │   ├─ Pull Request → [dev, staging, prod] (plan only)
  │   └─ Manual → [selected env]
  │
  ├─ For Each Environment (Sequential)
  │   │
  │   ├─ 1. Setup
  │   │   ├─ Checkout Code
  │   │   ├─ Configure AWS Credentials
  │   │   ├─ Setup Terraform
  │   │   └─ Set Environment Variables
  │   │
  │   ├─ 2. Backend Check
  │   │   ├─ Check if S3 bucket exists
  │   │   └─ Run setup-prerequisites.sh if needed
  │   │
  │   ├─ 3. Terraform Init
  │   │   └─ Load backend config from environment
  │   │
  │   ├─ 4. Validation
  │   │   ├─ terraform validate
  │   │   └─ terraform fmt -check
  │   │
  │   ├─ 5. Plan
  │   │   ├─ terraform plan
  │   │   ├─ Save plan artifact
  │   │   └─ Comment on PR (if PR)
  │   │
  │   ├─ 6. Apply (Conditional)
  │   │   ├─ IF: Push to main/develop
  │   │   │   └─ terraform apply
  │   │   └─ ELSE: Skip
  │   │
  │   └─ 7. Outputs
  │       ├─ Capture terraform outputs
  │       └─ Upload outputs artifact
  │
  └─ Deployment Summary
      └─ Generate overall status report

END
```

### Environment-Specific Backend Configuration

```
┌──────────────┬─────────────────────────────────┬────────────────────────────────┐
│ Environment  │ S3 Bucket                       │ State Key                      │
├──────────────┼─────────────────────────────────┼────────────────────────────────┤
│ dev          │ pipeops-dev-terraform-state     │ dev/terraform.tfstate          │
│ staging      │ pipeops-staging-terraform-state │ staging/terraform.tfstate      │
│ prod         │ pipeops-prod-terraform-state    │ prod/terraform.tfstate         │
└──────────────┴─────────────────────────────────┴────────────────────────────────┘
```

---

## 🌐 DR Infrastructure Workflow (terraform-dr.yml)

### Flow Diagram

```
START (Prod Only)
  │
  ├─ 1. Setup
  │   ├─ Checkout Code
  │   ├─ Configure AWS Credentials (Prod)
  │   ├─ Setup Terraform
  │   └─ Set DR Environment Variables
  │
  ├─ 2. Backend Check
  │   ├─ Check if DR S3 bucket exists (us-east-1)
  │   └─ Run setup-dr-prerequisites.sh if needed
  │
  ├─ 3. Get Primary RDS ARN
  │   ├─ Query primary prod state
  │   ├─ Extract RDS ARN
  │   └─ Save to environment variable
  │
  ├─ 4. Terraform Init
  │   └─ Load DR backend config
  │       ├─ Bucket: pipeops-prod-dr-terraform-state
  │       ├─ Key: dr/terraform.tfstate
  │       └─ Region: us-east-1
  │
  ├─ 5. Validation
  │   ├─ terraform validate
  │   └─ terraform fmt -check
  │
  ├─ 6. Update RDS ARN in tfvars
  │   └─ Inject primary_rds_arn into terraform.tfvars
  │
  ├─ 7. Plan
  │   ├─ terraform plan
  │   ├─ Save plan artifact
  │   └─ Comment on PR (if PR)
  │
  ├─ 8. Apply (Conditional)
  │   ├─ IF: Push to main OR Manual dispatch
  │   │   └─ terraform apply
  │   │       ├─ Create DR VPC
  │   │       ├─ Create DR EKS Cluster
  │   │       └─ Create DR RDS Replica
  │   └─ ELSE: Skip
  │
  ├─ 9. Outputs
  │   ├─ Capture DR outputs
  │   │   ├─ DR EKS Endpoint
  │   │   └─ DR RDS Endpoint
  │   └─ Upload outputs artifact
  │
  └─ 10. DR Deployment Summary
      └─ Generate detailed DR status report

END
```

### DR Dependencies

```
Primary Infrastructure (us-west-2)
  │
  ├─ Primary RDS Instance
  │   └─ ARN: arn:aws:rds:us-west-2:ACCOUNT:db:pipeops-prod-postgres
  │
  │                    Cross-Region
  │                    Replication
  │                         │
  ▼                         ▼
DR Infrastructure (us-east-1)
  │
  ├─ DR VPC (10.1.0.0/16)
  │   ├─ Public Subnets
  │   ├─ Private Subnets
  │   └─ Database Subnets
  │
  ├─ DR EKS Cluster
  │   ├─ Standby Mode (minimal nodes)
  │   └─ Auto-scaling enabled
  │
  └─ DR RDS Read Replica
      ├─ Source: Primary RDS ARN
      ├─ Multi-AZ: true
      └─ Encrypted with DR KMS key
```

---

## ✅ PR Checks Workflow (terraform-pr-checks.yml)

### Flow Diagram

```
START (On Pull Request)
  │
  ├─ Parallel Jobs
  │   │
  │   ├─ 1. Terraform Validate
  │   │   ├─ For Main Workspace
  │   │   │   ├─ terraform fmt -check
  │   │   │   ├─ terraform init -backend=false
  │   │   │   └─ terraform validate
  │   │   │
  │   │   └─ For DR Workspace
  │   │       ├─ terraform fmt -check
  │   │       ├─ terraform init -backend=false
  │   │       └─ terraform validate
  │   │
  │   ├─ 2. Security Scan
  │   │   ├─ Run tfsec
  │   │   └─ Upload SARIF results
  │   │
  │   ├─ 3. Secrets Scan
  │   │   ├─ Run Gitleaks
  │   │   └─ Detect sensitive data
  │   │
  │   ├─ 4. Cost Estimate (Optional)
  │   │   ├─ Run Infracost on main workspace
  │   │   ├─ Run Infracost on DR workspace
  │   │   └─ Post cost comment on PR
  │   │
  │   └─ 5. Documentation Check
  │       ├─ Run terraform-docs
  │       └─ Verify docs are up to date
  │
  └─ PR Summary
      ├─ Aggregate all check results
      ├─ Generate status table
      └─ Fail if any critical check failed

END
```

### Check Results Matrix

```
┌──────────────────────┬─────────────┬──────────────────────────────────┐
│ Check                │ Criticality │ Failure Action                   │
├──────────────────────┼─────────────┼──────────────────────────────────┤
│ Terraform Validate   │ Critical    │ Block PR merge                   │
│ Terraform Format     │ Warning     │ Continue (with warning)          │
│ Security Scan        │ Critical    │ Block PR merge                   │
│ Secrets Detection    │ Critical    │ Block PR merge                   │
│ Cost Estimate        │ Info        │ Continue (informational)         │
│ Documentation Check  │ Warning     │ Continue (with warning)          │
└──────────────────────┴─────────────┴──────────────────────────────────┘
```

---

## 🔐 Secrets and Configuration Flow

```
GitHub Secrets
  │
  ├─ AWS_ACCESS_KEY_ID_DEV
  ├─ AWS_SECRET_ACCESS_KEY_DEV
  ├─ AWS_ACCESS_KEY_ID_STAGING
  ├─ AWS_SECRET_ACCESS_KEY_STAGING
  ├─ AWS_ACCESS_KEY_ID_PROD
  ├─ AWS_SECRET_ACCESS_KEY_PROD
  └─ INFRACOST_API_KEY (optional)
  │
  ▼
Workflow Runtime
  │
  ├─ Select Environment-Specific Credentials
  │   └─ Format: AWS_*_<UPPER(environment)>
  │
  ├─ Configure AWS CLI
  │
  ├─ Load Backend Configuration
  │   └─ From: environments/<env>/backend.conf
  │
  ├─ Load Terraform Variables
  │   └─ From: environments/<env>/terraform.tfvars
  │
  └─ Execute Terraform Operations
      └─ State stored in S3 with encryption
```

---

## 📈 Deployment Timeline

### Typical Deployment Duration

```
Development Environment
├─ Setup: ~30s
├─ Terraform Init: ~15s
├─ Terraform Plan: ~45s
├─ Terraform Apply: ~15-20min
│   ├─ VPC: ~2min
│   ├─ RDS: ~8-10min
│   ├─ EKS: ~10-12min
│   └─ Add-ons: ~3-5min
└─ Total: ~20-25min

Staging/Production Environment
├─ Setup: ~30s
├─ Terraform Init: ~15s
├─ Terraform Plan: ~60s
├─ Terraform Apply: ~25-30min
│   ├─ VPC: ~2min
│   ├─ RDS Multi-AZ: ~15-18min
│   ├─ EKS: ~10-12min
│   └─ Add-ons: ~5-8min
└─ Total: ~30-35min

DR Environment
├─ Setup: ~30s
├─ Get Primary RDS ARN: ~20s
├─ Terraform Init: ~15s
├─ Terraform Plan: ~45s
├─ Terraform Apply: ~30-35min
│   ├─ DR VPC: ~2min
│   ├─ DR RDS Replica: ~20-25min
│   ├─ DR EKS: ~10-12min
│   └─ Add-ons: ~3-5min
└─ Total: ~35-40min
```

### Full Production Deployment (main → prod + DR)

```
Sequential Deployment
├─ Staging: ~30min
├─ Prod: ~35min
└─ DR: ~40min
───────────────────
Total: ~105min (1.75 hours)
```

---

## 🔄 Rollback Strategy

```
Failure Detected
  │
  ├─ Automatic Actions
  │   ├─ Workflow marked as failed
  │   ├─ Notifications sent
  │   └─ State preserved in S3
  │
  ├─ Option 1: Git Revert
  │   ├─ git revert <commit-hash>
  │   ├─ Push to trigger new deployment
  │   └─ Workflow redeploys previous state
  │
  ├─ Option 2: Manual Rollback
  │   ├─ Workflow Dispatch
  │   ├─ Select previous commit/tag
  │   └─ Apply known good configuration
  │
  └─ Option 3: Destroy and Recreate (Last Resort)
      ├─ Manual Dispatch → destroy
      ├─ Fix issues in code
      └─ Manual Dispatch → apply
```

---

## 📊 Monitoring and Observability

```
Workflow Execution
  │
  ├─ GitHub Actions Logs
  │   ├─ Real-time stdout/stderr
  │   ├─ Step-by-step execution
  │   └─ Retained for 90 days
  │
  ├─ Artifacts
  │   ├─ Terraform Plans (5 days)
  │   ├─ Terraform Outputs (30 days)
  │   └─ Cost Estimates (30 days)
  │
  ├─ PR Comments
  │   ├─ Plan summaries
  │   ├─ Cost changes
  │   └─ Security findings
  │
  ├─ Job Summaries
  │   ├─ Deployment status
  │   ├─ Resource changes
  │   └─ Endpoint URLs
  │
  └─ AWS CloudWatch (Post-Deployment)
      ├─ EKS cluster metrics
      ├─ RDS performance
      └─ Infrastructure alerts
```

---

**Last Updated:** 2026-01-22  
**Version:** 1.0.0
