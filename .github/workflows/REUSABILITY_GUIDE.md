# Workflow Reusability Guide

How to reuse these GitHub Actions workflows for other projects.

## 🎯 Overview

The workflows are designed to be reusable across multiple projects with minimal configuration changes. Simply update the `PROJECT_NAME` variable and your project-specific settings.

---

## 📝 Quick Setup for New Project

### Step 1: Copy Workflow Files

Copy the entire `.github/workflows/` directory to your new project:

```bash
cp -r .github/workflows /path/to/new-project/.github/
```

### Step 2: Update Project Name

Update the `PROJECT_NAME` in **all three workflow files**:

#### 1. `terraform-main.yml`

```yaml
env:
  TF_VERSION: '1.5.0'
  AWS_REGION: us-west-2
  PROJECT_NAME: your-project-name  # ← Change this
```

#### 2. `terraform-dr.yml`

```yaml
env:
  TF_VERSION: '1.5.0'
  DR_REGION: us-east-1
  PRIMARY_REGION: us-west-2
  PROJECT_NAME: your-project-name  # ← Change this
```

#### 3. `terraform-pr-checks.yml`

No project name needed - this workflow is already fully generic!

---

## 🔧 Configuration Variables

### Project-Specific Variables

| Variable | Location | Description | Example |
|----------|----------|-------------|---------|
| `PROJECT_NAME` | workflow env | Base name for all resources | `myapp`, `acme-platform` |
| `AWS_REGION` | workflow env | Primary AWS region | `us-west-2`, `eu-west-1` |
| `DR_REGION` | workflow env (DR only) | DR AWS region | `us-east-1`, `eu-central-1` |
| `TF_VERSION` | workflow env | Terraform version | `1.5.0`, `1.6.0` |

### Automatic Resource Naming

With `PROJECT_NAME` set, resources are automatically named:

| Resource Type | Naming Pattern | Example (PROJECT_NAME=myapp) |
|---------------|----------------|------------------------------|
| S3 State Bucket | `{PROJECT_NAME}-{env}-terraform-state` | `myapp-dev-terraform-state` |
| DynamoDB Lock Table | `{PROJECT_NAME}-{env}-terraform-locks` | `myapp-prod-terraform-locks` |
| DR State Bucket | `{PROJECT_NAME}-prod-dr-terraform-state` | `myapp-prod-dr-terraform-state` |
| DR Lock Table | `{PROJECT_NAME}-prod-dr-terraform-locks` | `myapp-prod-dr-terraform-locks` |
| RDS Instance | `{PROJECT_NAME}-{env}-postgres` | `myapp-prod-postgres` |

---

## 🚀 Complete Migration Example

### Migrating to Project "acme-platform"

#### 1. Update Workflow Files

**`terraform-main.yml`:**
```yaml
env:
  TF_VERSION: '1.5.0'
  AWS_REGION: us-east-1  # Changed region
  PROJECT_NAME: acme-platform  # New project name
```

**`terraform-dr.yml`:**
```yaml
env:
  TF_VERSION: '1.5.0'
  DR_REGION: us-west-2  # Swapped regions
  PRIMARY_REGION: us-east-1
  PROJECT_NAME: acme-platform  # New project name
```

#### 2. Expected Resource Names

The workflows will automatically use:

**Development Environment:**
- S3 Bucket: `acme-platform-dev-terraform-state`
- DynamoDB: `acme-platform-dev-terraform-locks`
- State Key: `dev/terraform.tfstate`

**Staging Environment:**
- S3 Bucket: `acme-platform-staging-terraform-state`
- DynamoDB: `acme-platform-staging-terraform-locks`
- State Key: `staging/terraform.tfstate`

**Production Environment:**
- S3 Bucket: `acme-platform-prod-terraform-state`
- DynamoDB: `acme-platform-prod-terraform-locks`
- State Key: `prod/terraform.tfstate`

**DR Environment:**
- S3 Bucket: `acme-platform-prod-dr-terraform-state`
- DynamoDB: `acme-platform-prod-dr-terraform-locks`
- State Key: `dr/terraform.tfstate`

#### 3. Update GitHub Secrets

Use the same secret names (no changes needed):
- `AWS_ACCESS_KEY_ID_DEV`
- `AWS_SECRET_ACCESS_KEY_DEV`
- `AWS_ACCESS_KEY_ID_STAGING`
- `AWS_SECRET_ACCESS_KEY_STAGING`
- `AWS_ACCESS_KEY_ID_PROD`
- `AWS_SECRET_ACCESS_KEY_PROD`

#### 4. Run Setup Scripts

```bash
# Update project name in your terraform.tfvars files
# Then run setup for each environment:

./scripts/setup-prerequisites.sh dev
./scripts/setup-prerequisites.sh staging
./scripts/setup-prerequisites.sh prod

cd dr-infrastructure
./scripts/setup-dr-prerequisites.sh
```

---

## 📋 Checklist for New Project

### Initial Setup
- [ ] Copy `.github/workflows/` directory
- [ ] Update `PROJECT_NAME` in `terraform-main.yml`
- [ ] Update `PROJECT_NAME` in `terraform-dr.yml`
- [ ] Update `AWS_REGION` if needed
- [ ] Update `DR_REGION` if needed
- [ ] Update `TF_VERSION` if needed

### GitHub Configuration
- [ ] Configure GitHub Secrets (AWS credentials)
- [ ] Create GitHub Environments (dev, staging, prod, prod-dr)
- [ ] Set up branch protection rules
- [ ] Enable GitHub Actions for the repository

### Terraform Configuration
- [ ] Update `project_name` in all `terraform.tfvars` files
- [ ] Update region settings in `terraform.tfvars`
- [ ] Run setup scripts for all environments
- [ ] Verify backend buckets created

### Testing
- [ ] Create test PR to verify checks
- [ ] Test deployment to dev
- [ ] Verify state stored in correct buckets
- [ ] Test promotion to staging/prod
- [ ] Verify DR deployment

---

## 🔄 Environment-Specific Overrides

### Custom Backend Configuration

If you need different backend naming patterns, override in the workflow:

```yaml
- name: Set environment variables
  run: |
    echo "ENVIRONMENT=${{ matrix.environment }}" >> $GITHUB_ENV
    
    # Custom naming pattern
    if [[ "${{ matrix.environment }}" == "prod" ]]; then
      echo "BACKEND_BUCKET=custom-prod-state-bucket" >> $GITHUB_ENV
      echo "BACKEND_KEY=terraform/prod.tfstate" >> $GITHUB_ENV
      echo "BACKEND_DYNAMODB=custom-prod-locks" >> $GITHUB_ENV
    else
      # Use default pattern
      echo "BACKEND_BUCKET=${{ env.PROJECT_NAME }}-${{ matrix.environment }}-terraform-state" >> $GITHUB_ENV
      echo "BACKEND_KEY=${{ matrix.environment }}/terraform.tfstate" >> $GITHUB_ENV
      echo "BACKEND_DYNAMODB=${{ env.PROJECT_NAME }}-${{ matrix.environment }}-terraform-locks" >> $GITHUB_ENV
    fi
```

### Custom Regions per Environment

```yaml
- name: Configure AWS credentials
  uses: aws-actions/configure-aws-credentials@v4
  with:
    aws-access-key-id: ${{ secrets[format('AWS_ACCESS_KEY_ID_{0}', upper(matrix.environment))] }}
    aws-secret-access-key: ${{ secrets[format('AWS_SECRET_ACCESS_KEY_{0}', upper(matrix.environment))] }}
    # Custom region per environment
    aws-region: ${{ matrix.environment == 'prod' && 'us-west-2' || matrix.environment == 'staging' && 'us-east-1' || 'eu-west-1' }}
```

---

## 🎨 Advanced Customization

### Multi-Region Support (Non-DR)

To deploy the same environment to multiple regions:

```yaml
strategy:
  matrix:
    environment: [dev, staging, prod]
    region: [us-west-2, eu-west-1]  # Add regions
```

### Custom Environment Names

```yaml
- name: Determine environments to deploy
  id: set-environments
  run: |
    if [[ "${{ github.ref }}" == "refs/heads/main" ]]; then
      echo "environments=[\"qa\",\"uat\",\"production\"]" >> $GITHUB_OUTPUT
    fi
```

### Different Project Name per Environment

```yaml
- name: Set environment variables
  run: |
    # Different project names per environment
    if [[ "${{ matrix.environment }}" == "dev" ]]; then
      PROJECT="myapp-dev"
    elif [[ "${{ matrix.environment }}" == "prod" ]]; then
      PROJECT="myapp"
    fi
    
    echo "BACKEND_BUCKET=${PROJECT}-${{ matrix.environment }}-terraform-state" >> $GITHUB_ENV
```

---

## 🔐 Security Considerations

### Separate AWS Accounts

For better isolation, use separate AWS accounts per environment:

1. Create IAM users in each AWS account
2. Use same secret names in GitHub
3. Credentials automatically routed to correct account
4. Prevents cross-environment access

### Project-Specific IAM Policies

Update IAM policies to use project name:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:*"],
      "Resource": [
        "arn:aws:s3:::${PROJECT_NAME}-*-terraform-state",
        "arn:aws:s3:::${PROJECT_NAME}-*-terraform-state/*"
      ]
    }
  ]
}
```

---

## 📊 Multi-Project Example

### Organization with Multiple Projects

```
acme-org/
├── frontend-app/
│   └── .github/workflows/
│       ├── terraform-main.yml (PROJECT_NAME: acme-frontend)
│       └── terraform-dr.yml
│
├── backend-api/
│   └── .github/workflows/
│       ├── terraform-main.yml (PROJECT_NAME: acme-backend)
│       └── terraform-dr.yml
│
└── data-platform/
    └── .github/workflows/
        ├── terraform-main.yml (PROJECT_NAME: acme-data)
        └── terraform-dr.yml
```

Each project gets its own:
- State buckets
- Lock tables
- AWS resources
- Deployment pipelines

All using the **same workflow templates**!

---

## 🧪 Testing New Configuration

### Dry Run

1. Create a test branch
2. Update `PROJECT_NAME` to `{project}-test`
3. Push and create PR
4. Review plan outputs
5. Verify correct resource names
6. **Do not merge** - this is just for testing

### Validation Script

```bash
#!/bin/bash
# validate-workflows.sh

PROJECT_NAME="your-project-name"

echo "Validating workflow configuration..."

# Check if PROJECT_NAME is set in workflows
grep -q "PROJECT_NAME: $PROJECT_NAME" .github/workflows/terraform-main.yml || \
  echo "❌ PROJECT_NAME not set in terraform-main.yml"

grep -q "PROJECT_NAME: $PROJECT_NAME" .github/workflows/terraform-dr.yml || \
  echo "❌ PROJECT_NAME not set in terraform-dr.yml"

# Verify backend bucket naming
echo "Expected backend buckets:"
echo "  - ${PROJECT_NAME}-dev-terraform-state"
echo "  - ${PROJECT_NAME}-staging-terraform-state"
echo "  - ${PROJECT_NAME}-prod-terraform-state"
echo "  - ${PROJECT_NAME}-prod-dr-terraform-state"

echo "✅ Validation complete"
```

---

## 📚 Additional Resources

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Terraform Backend Configuration](https://www.terraform.io/docs/language/settings/backends/s3.html)
- [Main Workflow Guide](./README.md)
- [Workflow Diagrams](./WORKFLOW_DIAGRAM.md)

---

## 🤝 Contributing Improvements

To improve workflow reusability:

1. Test changes with multiple project names
2. Document any new variables
3. Update this guide
4. Submit PR with examples

---

## ❓ FAQ

### Q: Can I use the same workflows for different cloud providers?

**A:** The workflows are AWS-specific. For other providers, you'll need to:
- Replace `aws-actions/configure-aws-credentials`
- Update backend configuration
- Adjust IAM/credentials setup

### Q: Can I use a different backend (not S3)?

**A:** Yes, update the `terraform init` backend config in workflows:

```yaml
terraform init \
  -backend-config="address=https://your-backend.com" \
  -backend-config="token=${{ secrets.BACKEND_TOKEN }}"
```

### Q: How do I handle multiple projects in one repository (monorepo)?

**A:** Use different working directories:

```yaml
defaults:
  run:
    working-directory: ./projects/${{ env.PROJECT_NAME }}
```

### Q: Can PROJECT_NAME contain special characters?

**A:** Stick to lowercase letters, numbers, and hyphens. AWS S3 bucket naming rules apply:
- 3-63 characters
- Lowercase letters, numbers, hyphens
- Start/end with letter or number

---

**Last Updated:** 2026-01-22  
**Version:** 1.0.0  
**Workflow Compatibility:** v1.x
