# ECR Module

Elastic Container Registry for Docker images with scanning, lifecycle policies, and cross-region replication.

## Architecture

```
┌───────────────────────────────────────────────────────────────────────────────────┐
│                           PRIMARY REGION (us-west-2)                               │
│                                                                                   │
│  ┌─────────────────────────────────────────────────────────────────────────────┐ │
│  │                         ECR Repositories                                     │ │
│  │                                                                             │ │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐             │ │
│  │  │   frontend      │  │   backend       │  │   api           │             │ │
│  │  │   :latest       │  │   :latest       │  │   :latest       │             │ │
│  │  │   :v1.2.3       │  │   :v1.2.3       │  │   :v1.2.3       │             │ │
│  │  └─────────────────┘  └─────────────────┘  └─────────────────┘             │ │
│  │           │                   │                   │                         │ │
│  │           │       Cross-Region Replication        │                         │ │
│  │           └───────────────────┼───────────────────┘                         │ │
│  │                               │                                             │ │
│  └───────────────────────────────│─────────────────────────────────────────────┘ │
│                                  │                                               │
└──────────────────────────────────│───────────────────────────────────────────────┘
                                   │
                                   ▼
┌───────────────────────────────────────────────────────────────────────────────────┐
│                              DR REGION (us-east-1)                                 │
│                                                                                   │
│  ┌─────────────────────────────────────────────────────────────────────────────┐ │
│  │                       Replicated Repositories                                │ │
│  │                                                                             │ │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐             │ │
│  │  │   frontend      │  │   backend       │  │   api           │             │ │
│  │  │   (replica)     │  │   (replica)     │  │   (replica)     │             │ │
│  │  └─────────────────┘  └─────────────────┘  └─────────────────┘             │ │
│  │                                                                             │ │
│  └─────────────────────────────────────────────────────────────────────────────┘ │
│                                                                                   │
└───────────────────────────────────────────────────────────────────────────────────┘
```

## Features

| Feature | Description |
|---------|-------------|
| **Image Scanning** | Automatic vulnerability scanning on push |
| **KMS Encryption** | Customer-managed KMS key encryption |
| **Lifecycle Policies** | Automatic cleanup of old images |
| **Cross-Region Replication** | Replicate to DR region (prod only) |
| **Immutable Tags** | Prevent tag overwrites for security |
| **IAM Policies** | Push/pull access for GitHub Actions and EKS |

## Usage

```hcl
module "ecr" {
  source = "./modules/ecr"

  project_name = "pipeops"
  environment  = "prod"
  aws_region   = "us-west-2"
  dr_region    = "us-east-1"
  
  # Repository names
  ecr_repository_names = ["frontend", "backend", "api", "worker"]
  
  # Security settings
  image_tag_mutability = "IMMUTABLE"
  scan_on_push         = true
  
  # Lifecycle policies
  lifecycle_keep_count           = 30
  lifecycle_expire_untagged_days = 7
  
  # Cross-region replication (prod only)
  enable_replication  = true
  replication_regions = ["us-east-1"]
  
  # IAM policies
  create_github_actions_policy = true
  eks_node_role_arn            = module.eks.node_role_arn
  
  tags = {
    Environment = "prod"
    ManagedBy   = "terraform"
  }
}
```

## Variables

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `project_name` | Project name | `string` | - | yes |
| `environment` | Environment | `string` | - | yes |
| `ecr_repository_names` | List of repository names | `list(string)` | - | yes |
| `image_tag_mutability` | Tag mutability (MUTABLE/IMMUTABLE) | `string` | `"IMMUTABLE"` | no |
| `scan_on_push` | Enable scan on push | `bool` | `true` | no |
| `lifecycle_keep_count` | Images to keep | `number` | `30` | no |
| `lifecycle_expire_untagged_days` | Days before untagged expire | `number` | `7` | no |
| `enable_replication` | Enable cross-region replication | `bool` | `false` | no |
| `replication_regions` | Regions to replicate to | `list(string)` | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| `repository_urls` | Map of repository URLs |
| `repository_arns` | Map of repository ARNs |
| `kms_key_arn` | KMS key ARN for encryption |
| `github_actions_push_policy_arn` | IAM policy for GitHub Actions |
| `eks_node_pull_policy_arn` | IAM policy for EKS nodes |
| `docker_login_command` | Docker login command |

## Docker Commands

### Login to ECR

```bash
# AWS CLI v2
aws ecr get-login-password --region us-west-2 | \
  docker login --username AWS --password-stdin \
  ACCOUNT_ID.dkr.ecr.us-west-2.amazonaws.com
```

### Push Image

```bash
# Tag image
docker tag myapp:latest \
  ACCOUNT_ID.dkr.ecr.us-west-2.amazonaws.com/pipeops-prod-frontend:v1.0.0

# Push image
docker push \
  ACCOUNT_ID.dkr.ecr.us-west-2.amazonaws.com/pipeops-prod-frontend:v1.0.0
```

### Pull Image

```bash
docker pull \
  ACCOUNT_ID.dkr.ecr.us-west-2.amazonaws.com/pipeops-prod-frontend:v1.0.0
```

## GitHub Actions Integration

```yaml
- name: Configure AWS credentials
  uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: ${{ secrets.AWS_ROLE_ARN_PROD }}
    aws-region: us-west-2

- name: Login to Amazon ECR
  id: login-ecr
  uses: aws-actions/amazon-ecr-login@v2

- name: Build and push image
  env:
    ECR_REGISTRY: ${{ steps.login-ecr.outputs.registry }}
    IMAGE_TAG: ${{ github.sha }}
  run: |
    docker build -t $ECR_REGISTRY/pipeops-prod-frontend:$IMAGE_TAG .
    docker push $ECR_REGISTRY/pipeops-prod-frontend:$IMAGE_TAG
```

## Lifecycle Policy

The module creates lifecycle rules:

```json
{
  "rules": [
    {
      "rulePriority": 1,
      "description": "Keep last 30 tagged images",
      "selection": {
        "tagStatus": "tagged",
        "tagPrefixList": ["v"],
        "countType": "imageCountMoreThan",
        "countNumber": 30
      },
      "action": { "type": "expire" }
    },
    {
      "rulePriority": 2,
      "description": "Expire untagged images after 7 days",
      "selection": {
        "tagStatus": "untagged",
        "countType": "sinceImagePushed",
        "countUnit": "days",
        "countNumber": 7
      },
      "action": { "type": "expire" }
    }
  ]
}
```

## Vulnerability Scanning

### View Scan Results

```bash
# Get scan findings
aws ecr describe-image-scan-findings \
  --repository-name pipeops-prod-frontend \
  --image-id imageTag=v1.0.0 \
  --region us-west-2
```

### Severity Levels

| Severity | Action |
|----------|--------|
| CRITICAL | Block deployment |
| HIGH | Review before deployment |
| MEDIUM | Monitor |
| LOW | Informational |

## Cross-Region Replication

When `enable_replication = true`:

1. Images pushed to primary region automatically replicate
2. ~1-5 minute replication delay
3. Same tags and digests in DR region
4. DR region ready for immediate failover

## Cost Considerations

| Component | Cost |
|-----------|------|
| **Storage** | $0.10/GB/month |
| **Data Transfer (same region)** | Free |
| **Data Transfer (cross-region)** | $0.02/GB |
| **Scanning** | Free (basic), $0.09/image (enhanced) |

## Security Best Practices

1. **Immutable Tags**: Prevent tag overwrites
2. **KMS Encryption**: Customer-managed keys
3. **Scan on Push**: Catch vulnerabilities early
4. **Least Privilege**: Separate push/pull policies
5. **Lifecycle Policies**: Remove unused images
