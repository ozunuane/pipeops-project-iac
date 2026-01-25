# CI/CD Pipelines

GitHub Actions workflows for automated infrastructure deployment.

## Workflow Overview

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                            CI/CD PIPELINE                                        │
│                                                                                 │
│  ┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐           │
│  │  Push to        │────▶│  PR Checks      │────▶│  Merge to       │           │
│  │  develop        │     │  (validation)   │     │  main           │           │
│  └─────────────────┘     └─────────────────┘     └─────────────────┘           │
│           │                                               │                     │
│           ▼                                               ▼                     │
│  ┌─────────────────┐                           ┌─────────────────┐             │
│  │  Deploy to DEV  │                           │  Deploy to      │             │
│  │  (auto)         │                           │  STAGING → PROD │             │
│  └─────────────────┘                           │  (auto)         │             │
│                                                └─────────────────┘             │
│                                                          │                     │
│                                                          ▼                     │
│                                                ┌─────────────────┐             │
│                                                │  Deploy to DR   │             │
│                                                │  (manual)       │             │
│                                                └─────────────────┘             │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Workflow Files

| File | Purpose | Trigger |
|------|---------|---------|
| `terraform-main.yml` | Main infrastructure | push, PR, manual |
| `terraform-dr.yml` | DR infrastructure | push, PR, manual |
| `terraform-global.yml` | DNS & certificates | push, PR, manual |
| `terraform-pr-checks.yml` | PR validation | pull_request |

---

## Automatic Triggers

### Push to `develop`

```
develop push → Plan all environments → Apply to DEV only
```

### Push to `main`

```
main push → Plan all environments (no auto-deploy)
```

### Pull Request

```
PR to develop/main → Validate → Security scan → Cost estimate → Plan
```

---

## Manual Deployment

### workflow_dispatch

Trigger manual deployments via GitHub Actions UI:

1. Go to **Actions** tab
2. Select workflow (e.g., "Terraform Main Infrastructure")
3. Click **"Run workflow"**
4. Select:
   - **Branch**: `develop` or `main`
   - **Environment**: `dev`, `staging`, or `prod`
   - **Action**: `plan`, `apply`, or `destroy`
5. Click **"Run workflow"**

### Important Rules

| Action | Branch Requirement |
|--------|-------------------|
| Apply to dev | Any branch |
| Apply to staging | `main` only |
| Apply to prod | `main` only |
| Destroy | Manual confirmation required |

---

## AWS Authentication

### OIDC (Recommended)

Workflows use OIDC to assume AWS roles:

```yaml
- name: Configure AWS credentials
  uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: ${{ secrets.AWS_ROLE_ARN_PROD }}
    aws-region: us-west-2
```

### Required Secrets

Configure in: **Settings → Secrets and variables → Actions**

```yaml
# OIDC Role ARNs (per environment)
AWS_ROLE_ARN_DEV      # arn:aws:iam::ACCOUNT:role/pipeops-dev-github-actions
AWS_ROLE_ARN_STAGING  # arn:aws:iam::ACCOUNT:role/pipeops-staging-github-actions
AWS_ROLE_ARN_PROD     # arn:aws:iam::ACCOUNT:role/pipeops-prod-github-actions

# Optional
INFRACOST_API_KEY     # For cost estimation
SLACK_WEBHOOK_URL     # For notifications
TF_TOKEN              # For private registry
```

### Setup OIDC

Run the setup script to create OIDC provider and roles:

```bash
# Set environment variables
export PROJECT_NAME=pipeops
export GITHUB_ORG=your-org
export GITHUB_REPO=pipeops-project-iac

# Run setup
./scripts/setup-prerequisites.sh prod us-west-2
```

---

## Workflow Details

### terraform-main.yml

```yaml
name: Terraform Main Infrastructure

on:
  push:
    branches: [develop]
  pull_request:
    branches: [develop, main]
  workflow_dispatch:
    inputs:
      environment:
        type: choice
        options: [dev, staging, prod]
      action:
        type: choice
        options: [plan, apply, destroy]

jobs:
  terraform:
    strategy:
      matrix:
        environment: [dev, staging, prod]
    steps:
      - Checkout code
      - Configure AWS credentials
      - Setup Terraform
      - Terraform Init
      - Terraform Plan
      - Terraform Apply (conditional)
```

### terraform-pr-checks.yml

```yaml
name: Terraform PR Checks

on:
  pull_request:
    branches: [develop, main]

jobs:
  validate:
    steps:
      - Terraform fmt check
      - Terraform validate
      
  security:
    steps:
      - tfsec scan
      - checkov scan
      - gitleaks
      
  cost:
    steps:
      - Infracost estimate
```

---

## Pipeline Stages

### 1. Validation

```yaml
- name: Terraform Format
  run: terraform fmt -check -recursive

- name: Terraform Validate
  run: terraform validate
```

### 2. Security Scanning

```yaml
- name: tfsec
  uses: aquasecurity/tfsec-action@v1.0.3
  with:
    soft_fail: true
    github_token: ${{ secrets.TF_TOKEN }}
```

### 3. Cost Estimation

```yaml
- name: Infracost
  uses: infracost/actions/setup@v3
- run: |
    infracost breakdown --path . \
      --format json --out-file infracost.json
```

### 4. Plan

```yaml
- name: Terraform Plan
  run: |
    terraform plan \
      -var-file=environments/${{ matrix.environment }}/terraform.tfvars \
      -out=tfplan-${{ matrix.environment }}
```

### 5. Apply (Conditional)

```yaml
- name: Terraform Apply
  if: |
    github.event_name == 'workflow_dispatch' && 
    github.event.inputs.action == 'apply'
  run: terraform apply -auto-approve tfplan-${{ matrix.environment }}
```

---

## Artifacts

### Generated Artifacts

| Artifact | Retention | Description |
|----------|-----------|-------------|
| `tfplan-{env}` | 5 days | Terraform plan file |
| `outputs-{env}.json` | 30 days | Terraform outputs |
| `infracost-{env}.json` | 30 days | Cost estimate |

### Download Artifacts

```bash
# Via GitHub CLI
gh run download <run-id> -n tfplan-prod

# Or from Actions UI
```

---

## PR Comments

Workflows post comments to PRs with:

- Terraform plan output
- Cost estimate changes
- Security scan results
- Validation status

---

## Execution Times

| Workflow | Duration |
|----------|----------|
| PR Checks | 3-5 min |
| Plan (per env) | 2-3 min |
| Apply (dev) | 15-20 min |
| Apply (staging) | 20-25 min |
| Apply (prod) | 25-30 min |
| Apply (DR) | 30-35 min |

---

## Troubleshooting

### Workflow Failed

```bash
# Check workflow logs
gh run view <run-id> --log

# Re-run failed job
gh run rerun <run-id> --failed
```

### OIDC Authentication Failed

```bash
# Verify trust policy
aws iam get-role --role-name pipeops-prod-github-actions \
  --query 'Role.AssumeRolePolicyDocument'

# Update trust policy
aws iam update-assume-role-policy \
  --role-name pipeops-prod-github-actions \
  --policy-document file://trust-policy.json
```

### State Lock Error

```bash
# Force unlock
terraform force-unlock <lock-id>

# Or via DynamoDB
aws dynamodb delete-item \
  --table-name pipeops-prod-terraform-locks \
  --key '{"LockID":{"S":"<lock-id>"}}'
```

### Backend Not Found

```bash
# Create backend resources
./scripts/setup-prerequisites.sh prod us-west-2
```

---

## Best Practices

1. **Always use PRs**: Never push directly to main
2. **Review plans**: Check plan output before approving
3. **Use environments**: Separate configs per environment
4. **Protect main**: Require approvals for prod
5. **Monitor costs**: Review Infracost estimates
6. **Security first**: Address tfsec findings

---

## Related Documentation

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [OIDC Setup Guide](../.github/workflows/AWS_OIDC_SETUP_GUIDE.md)
- [Reusability Guide](../.github/workflows/REUSABILITY_GUIDE.md)
