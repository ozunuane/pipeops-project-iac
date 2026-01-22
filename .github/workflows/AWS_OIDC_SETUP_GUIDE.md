# AWS OIDC Setup Guide for GitHub Actions

Complete guide to configure AWS OIDC authentication for GitHub Actions (no long-lived access keys required).

## 🎯 Overview

This guide shows how to configure **OpenID Connect (OIDC)** authentication between GitHub Actions and AWS, replacing long-lived access keys with temporary credentials.

### Benefits of OIDC

✅ **No long-lived credentials** - No access keys to manage or rotate  
✅ **Automatic credential rotation** - Temporary credentials expire automatically  
✅ **Better security** - Credentials can't be leaked or stolen  
✅ **Fine-grained permissions** - Use IAM conditions based on repo, branch, etc.  
✅ **Audit trail** - CloudTrail shows which workflow assumed the role  

---

## 📋 Prerequisites

- AWS Account with admin access
- GitHub repository with Actions enabled
- AWS CLI installed (for setup)

---

## 🚀 Setup Steps

### Step 1: Create OIDC Identity Provider in AWS

This needs to be done **once per AWS account** (not per environment).

#### Option A: Using AWS Console

1. Go to **IAM → Identity Providers → Add provider**
2. Select **OpenID Connect**
3. Fill in:
   - **Provider URL:** `https://token.actions.githubusercontent.com`
   - **Audience:** `sts.amazonaws.com`
4. Click **Get thumbprint** (automatic)
5. Click **Add provider**

#### Option B: Using AWS CLI

```bash
# Create OIDC provider
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1

# Verify it was created
aws iam list-open-id-connect-providers
```

#### Option C: Using Terraform

```hcl
resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com",
  ]

  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1"
  ]

  tags = {
    Name = "GitHub Actions OIDC Provider"
  }
}
```

---

### Step 2: Create IAM Roles for Each Environment

Create a separate IAM role for each environment (dev, staging, prod).

#### Dev Environment Role

```bash
# Set variables
PROJECT_NAME="pipeops"
GITHUB_ORG="your-github-org"
GITHUB_REPO="pipeops-project-iac"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Create trust policy
cat > trust-policy-dev.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:${GITHUB_ORG}/${GITHUB_REPO}:ref:refs/heads/develop"
        }
      }
    }
  ]
}
EOF

# Create the role
aws iam create-role \
  --role-name ${PROJECT_NAME}-dev-github-actions \
  --assume-role-policy-document file://trust-policy-dev.json \
  --description "Role for GitHub Actions to deploy dev environment"

# Attach permissions (adjust as needed)
aws iam attach-role-policy \
  --role-name ${PROJECT_NAME}-dev-github-actions \
  --policy-arn arn:aws:iam::aws:policy/PowerUserAccess

# For more granular control, attach only necessary policies
```

#### Staging Environment Role

```bash
# Create trust policy for staging
cat > trust-policy-staging.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:${GITHUB_ORG}/${GITHUB_REPO}:ref:refs/heads/main"
        }
      }
    }
  ]
}
EOF

# Create the role
aws iam create-role \
  --role-name ${PROJECT_NAME}-staging-github-actions \
  --assume-role-policy-document file://trust-policy-staging.json \
  --description "Role for GitHub Actions to deploy staging environment"

# Attach permissions
aws iam attach-role-policy \
  --role-name ${PROJECT_NAME}-staging-github-actions \
  --policy-arn arn:aws:iam::aws:policy/PowerUserAccess
```

#### Production Environment Role

```bash
# Create trust policy for prod
cat > trust-policy-prod.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:${GITHUB_ORG}/${GITHUB_REPO}:ref:refs/heads/main"
        }
      }
    }
  ]
}
EOF

# Create the role
aws iam create-role \
  --role-name ${PROJECT_NAME}-prod-github-actions \
  --assume-role-policy-document file://trust-policy-prod.json \
  --description "Role for GitHub Actions to deploy prod and DR environments"

# Attach permissions
aws iam attach-role-policy \
  --role-name ${PROJECT_NAME}-prod-github-actions \
  --policy-arn arn:aws:iam::aws:policy/PowerUserAccess
```

---

### Step 3: Configure GitHub Secrets

Add the IAM role ARNs to your GitHub repository secrets.

#### Via GitHub Web Interface

1. Go to your repository → **Settings → Secrets and variables → Actions**
2. Click **New repository secret**
3. Add the following secrets:

```
AWS_ROLE_ARN_DEV
Value: arn:aws:iam::ACCOUNT_ID:role/pipeops-dev-github-actions

AWS_ROLE_ARN_STAGING
Value: arn:aws:iam::ACCOUNT_ID:role/pipeops-staging-github-actions

AWS_ROLE_ARN_PROD
Value: arn:aws:iam::ACCOUNT_ID:role/pipeops-prod-github-actions
```

#### Via GitHub CLI

```bash
# Set your GitHub org and repo
GITHUB_ORG="your-github-org"
GITHUB_REPO="pipeops-project-iac"

# Get role ARNs
DEV_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${PROJECT_NAME}-dev-github-actions"
STAGING_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${PROJECT_NAME}-staging-github-actions"
PROD_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${PROJECT_NAME}-prod-github-actions"

# Set secrets
gh secret set AWS_ROLE_ARN_DEV --body "$DEV_ROLE_ARN" --repo ${GITHUB_ORG}/${GITHUB_REPO}
gh secret set AWS_ROLE_ARN_STAGING --body "$STAGING_ROLE_ARN" --repo ${GITHUB_ORG}/${GITHUB_REPO}
gh secret set AWS_ROLE_ARN_PROD --body "$PROD_ROLE_ARN" --repo ${GITHUB_ORG}/${GITHUB_REPO}
```

---

### Step 4: Remove Old Access Keys (Optional)

Once OIDC is working, remove the old access key secrets:

```bash
# Delete old secrets (via GitHub web interface or CLI)
gh secret remove AWS_ACCESS_KEY_ID_DEV --repo ${GITHUB_ORG}/${GITHUB_REPO}
gh secret remove AWS_SECRET_ACCESS_KEY_DEV --repo ${GITHUB_ORG}/${GITHUB_REPO}
gh secret remove AWS_ACCESS_KEY_ID_STAGING --repo ${GITHUB_ORG}/${GITHUB_REPO}
gh secret remove AWS_SECRET_ACCESS_KEY_STAGING --repo ${GITHUB_ORG}/${GITHUB_REPO}
gh secret remove AWS_ACCESS_KEY_ID_PROD --repo ${GITHUB_ORG}/${GITHUB_REPO}
gh secret remove AWS_SECRET_ACCESS_KEY_PROD --repo ${GITHUB_ORG}/${GITHUB_REPO}
```

---

## 🔧 Advanced Configuration

### Fine-Grained Trust Policy

Restrict role assumption to specific branches, tags, or environments:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
          "token.actions.githubusercontent.com:sub": [
            "repo:your-org/your-repo:ref:refs/heads/main",
            "repo:your-org/your-repo:environment:production"
          ]
        }
      }
    }
  ]
}
```

### Multiple Repositories

Allow multiple repos to use the same role:

```json
{
  "Condition": {
    "StringEquals": {
      "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
    },
    "StringLike": {
      "token.actions.githubusercontent.com:sub": [
        "repo:your-org/repo1:*",
        "repo:your-org/repo2:*"
      ]
    }
  }
}
```

### Tag-Based Deployment

Only allow deployments from tags:

```json
{
  "Condition": {
    "StringLike": {
      "token.actions.githubusercontent.com:sub": "repo:your-org/your-repo:ref:refs/tags/*"
    }
  }
}
```

---

## 🧪 Testing

### Test the OIDC Configuration

Create a simple workflow to test authentication:

```yaml
name: Test AWS OIDC

on:
  workflow_dispatch:

permissions:
  id-token: write
  contents: read

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN_DEV }}
          role-session-name: test-session
          aws-region: us-west-2

      - name: Test AWS access
        run: |
          aws sts get-caller-identity
          aws s3 ls
```

### Verify CloudTrail Logs

Check CloudTrail to see the AssumeRoleWithWebIdentity events:

```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity \
  --max-results 10
```

---

## 🔒 Security Best Practices

### 1. Use Least Privilege

Don't use `PowerUserAccess` in production. Create custom policies:

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
        "kms:*"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": "us-west-2"
        }
      }
    }
  ]
}
```

### 2. Restrict to Specific Branches

Production roles should only work from `main` branch:

```json
{
  "Condition": {
    "StringEquals": {
      "token.actions.githubusercontent.com:sub": "repo:org/repo:ref:refs/heads/main"
    }
  }
}
```

### 3. Enable CloudTrail Logging

Monitor all AssumeRole calls:

```bash
aws cloudtrail create-trail \
  --name github-actions-audit \
  --s3-bucket-name my-cloudtrail-bucket
```

### 4. Set Session Duration

Limit how long credentials are valid:

```bash
aws iam update-role \
  --role-name pipeops-prod-github-actions \
  --max-session-duration 3600  # 1 hour
```

### 5. Use GitHub Environments

Configure required reviewers for production:

```yaml
environment:
  name: production
  # Requires approval in GitHub Settings → Environments
```

---

## 📊 Comparison: Access Keys vs OIDC

| Feature | Access Keys | OIDC |
|---------|-------------|------|
| **Security** | ❌ Long-lived, can be leaked | ✅ Temporary, auto-expire |
| **Rotation** | ❌ Manual rotation needed | ✅ Automatic |
| **Management** | ❌ Store in GitHub Secrets | ✅ No secrets to store |
| **Audit** | ⚠️ Hard to track usage | ✅ Clear CloudTrail logs |
| **Permissions** | ⚠️ Static IAM user | ✅ Dynamic IAM role |
| **Best Practice** | ❌ Not recommended | ✅ AWS recommended |

---

## 🛠️ Troubleshooting

### Error: "Not authorized to perform sts:AssumeRoleWithWebIdentity"

**Problem:** Trust policy doesn't allow your repository.

**Solution:**
```bash
# Check trust policy
aws iam get-role --role-name pipeops-dev-github-actions --query 'Role.AssumeRolePolicyDocument'

# Verify it includes your repo name
# Fix: Update trust policy with correct repo name
```

### Error: "An error occurred (AccessDenied) when calling the AssumeRoleWithWebIdentity operation"

**Problem:** OIDC provider not set up correctly.

**Solution:**
```bash
# Verify OIDC provider exists
aws iam list-open-id-connect-providers

# Should see: arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com
```

### Error: "Could not assume role"

**Problem:** Wrong role ARN in GitHub secret.

**Solution:**
```bash
# Get correct role ARN
aws iam get-role --role-name pipeops-dev-github-actions --query 'Role.Arn'

# Update GitHub secret with correct ARN
```

### Workflow doesn't have id-token permission

**Problem:** Missing permissions in workflow file.

**Solution:**
```yaml
permissions:
  id-token: write   # ← Must be present
  contents: read
```

---

## 📚 Additional Resources

### AWS Documentation
- [AWS OIDC for GitHub Actions](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
- [IAM Roles for Service Accounts](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html)

### GitHub Documentation
- [GitHub OIDC Configuration](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect)
- [aws-actions/configure-aws-credentials](https://github.com/aws-actions/configure-aws-credentials)

### Blog Posts
- [AWS Blog: Use IAM roles to connect GitHub Actions](https://aws.amazon.com/blogs/security/use-iam-roles-to-connect-github-actions-to-actions-in-aws/)

---

## ✅ Checklist

Setup checklist for each AWS account:

- [ ] Create OIDC Identity Provider
- [ ] Create IAM role for dev environment
- [ ] Create IAM role for staging environment
- [ ] Create IAM role for prod environment
- [ ] Add role ARNs to GitHub Secrets
- [ ] Update workflow permissions
- [ ] Test OIDC authentication
- [ ] Verify deployments work
- [ ] Remove old access keys
- [ ] Delete old IAM users (if any)
- [ ] Enable CloudTrail monitoring
- [ ] Document role ARNs

---

**Last Updated:** 2026-01-22  
**Version:** 1.0.0  
**Security Level:** ✅ Production Ready
