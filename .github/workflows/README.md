# GitHub Actions Workflows

Automated CI/CD pipelines for PipeOps infrastructure deployment.

## 🚀 Quick Reference

### Workflow Files

| File | Purpose | Environments |
|------|---------|--------------|
| `terraform-main.yml` | Main infrastructure deployment | dev, staging, prod |
| `terraform-dr.yml` | DR infrastructure deployment | prod-dr (us-east-1) |
| `terraform-pr-checks.yml` | PR validation and checks | N/A (checks only) |

---

## 🔄 Automatic Triggers

### Push to `develop` Branch
```
develop branch push → Deploy to DEV (us-west-2)
```

### Push to `main` Branch
```
main branch push → Deploy to STAGING (us-west-2)
                 → Deploy to PROD (us-west-2)
                 → Deploy to DR (us-east-1)
```

### Pull Request
```
Any PR → Run terraform-pr-checks.yml
      → Plan for all environments
      → Security scan
      → Cost estimate
```

---

## 🎮 Manual Deployment

### Deploy Main Infrastructure

1. Go to **Actions** tab
2. Select **"Terraform Main Infrastructure"**
3. Click **"Run workflow"**
4. Fill in:
   ```yaml
   Branch: main or develop
   Environment: dev | staging | prod
   Action: plan | apply | destroy
   ```
5. Click **"Run workflow"**

### Deploy DR Infrastructure

1. Go to **Actions** tab
2. Select **"Terraform DR Infrastructure"**
3. Click **"Run workflow"**
4. Fill in:
   ```yaml
   Branch: main
   Action: plan | apply | destroy
   ```
5. Click **"Run workflow"**

---

## 📊 Workflow Status

### View Running Workflows

```
Repository → Actions → Click on workflow run
```

### Check Deployment Status

```
Repository → Environments → Select environment
```

### Download Artifacts

```
Workflow run → Scroll to "Artifacts" section → Download
```

---

## 🔐 Required Secrets

Configure in: **Settings → Secrets and variables → Actions → New repository secret**

### AWS Credentials (Required)

```yaml
AWS_ACCESS_KEY_ID_DEV
AWS_SECRET_ACCESS_KEY_DEV
AWS_ACCESS_KEY_ID_STAGING
AWS_SECRET_ACCESS_KEY_STAGING
AWS_ACCESS_KEY_ID_PROD
AWS_SECRET_ACCESS_KEY_PROD
```

### Optional Secrets

```yaml
INFRACOST_API_KEY      # For cost estimation
SLACK_WEBHOOK_URL      # For Slack notifications
```

---

## 📋 Workflow Outputs

### Artifacts Generated

**Terraform Plans** (5 days):
- `tfplan-dev`
- `tfplan-staging`
- `tfplan-prod`
- `tfplan-dr`

**Terraform Outputs** (30 days):
- `outputs-dev.json`
- `outputs-staging.json`
- `outputs-prod.json`
- `outputs-dr.json`

### PR Comments

- Terraform plan outputs
- Cost estimates (if configured)
- Security scan results

---

## ⚙️ Backend Configuration

### Main Infrastructure

| Environment | S3 Bucket | DynamoDB Table | State Key |
|-------------|-----------|----------------|-----------|
| dev | `pipeops-dev-terraform-state` | `pipeops-dev-terraform-locks` | `dev/terraform.tfstate` |
| staging | `pipeops-staging-terraform-state` | `pipeops-staging-terraform-locks` | `staging/terraform.tfstate` |
| prod | `pipeops-prod-terraform-state` | `pipeops-prod-terraform-locks` | `prod/terraform.tfstate` |

### DR Infrastructure

| Component | Value |
|-----------|-------|
| S3 Bucket | `pipeops-prod-dr-terraform-state` |
| DynamoDB Table | `pipeops-prod-dr-terraform-locks` |
| State Key | `dr/terraform.tfstate` |
| Region | `us-east-1` |

---

## 🔍 Troubleshooting

### Workflow Failed - Check Logs

1. Go to **Actions** tab
2. Click on failed workflow
3. Click on failed job
4. Expand failed step
5. Review error message

### State Lock Error

```bash
# Remove lock manually
aws dynamodb delete-item \
  --table-name pipeops-<env>-terraform-locks \
  --key '{"LockID":{"S":"<lock-id>"}}'
```

### Permission Denied

- Check IAM permissions for the environment's AWS credentials
- Ensure secrets are correctly configured in GitHub

### Backend Not Found

- Run setup script locally first:
  ```bash
  ./scripts/setup-prerequisites.sh <env>
  ```

---

## 🔄 Reusability

These workflows are designed to be reusable across multiple projects!

**To use for another project:**
1. Copy `.github/workflows/` directory
2. Update `PROJECT_NAME` variable in workflows
3. See: [Reusability Guide](./REUSABILITY_GUIDE.md) for details

## 📚 Documentation

- 🔄 [Reusability Guide](./REUSABILITY_GUIDE.md) - **Use for other projects**
- 📖 [Complete GitHub Actions Guide](../../GITHUB_ACTIONS_GUIDE.md)
- 📊 [Workflow Diagrams](./WORKFLOW_DIAGRAM.md)
- 🚀 [Environment Deployment Guide](../../ENVIRONMENT_DEPLOYMENT_GUIDE.md)
- 🌐 [DR Workspace Setup](../../DR_WORKSPACE_SETUP.md)

---

## 🎯 Common Tasks

### Deploy to Development

```bash
git checkout develop
git pull origin develop
# Make changes
git commit -am "feat: update infrastructure"
git push origin develop
# Automatically deploys to dev
```

### Deploy to Production

```bash
# Create PR: develop → main
# Wait for checks to pass
# Merge PR
# Automatically deploys to staging → prod → DR
```

### Run Plan Only

```bash
# Create PR to main or develop
# Plan runs automatically
# View plan in PR comments
```

### Emergency Rollback

```bash
# Option 1: Revert commit
git revert <commit-hash>
git push origin main

# Option 2: Manual destroy
# Actions → Terraform Main Infrastructure → Run workflow
# Environment: prod, Action: destroy
```

---

## ⏱️ Typical Execution Times

| Workflow | Duration |
|----------|----------|
| PR Checks | 3-5 minutes |
| Dev Deployment | 20-25 minutes |
| Staging Deployment | 30-35 minutes |
| Prod Deployment | 30-35 minutes |
| DR Deployment | 35-40 minutes |
| **Full Prod + DR** | **~105 minutes** |

---

## 📞 Support

**Questions?** Check the [GitHub Actions Guide](../../GITHUB_ACTIONS_GUIDE.md)

**Issues?** Create a GitHub issue with the `ci-cd` label

**Emergency?** Contact the on-call engineer

---

**Last Updated:** 2026-01-22  
**Workflow Version:** 1.0.0
