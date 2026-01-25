# EKS Module

Production-ready Amazon EKS cluster with Auto Mode for simplified node management.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              EKS CLUSTER                                     │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                      CONTROL PLANE (AWS Managed)                     │   │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐      │   │
│  │  │   API Server    │  │   etcd          │  │   Scheduler     │      │   │
│  │  └─────────────────┘  └─────────────────┘  └─────────────────┘      │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                        │
│                                    ▼                                        │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    AUTO MODE (Automatic Node Management)             │   │
│  │                                                                       │   │
│  │  ┌────────────────────────────────────────────────────────────────┐  │   │
│  │  │  Node Pools: general-purpose, system                           │  │   │
│  │  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐            │  │   │
│  │  │  │   Node 1    │  │   Node 2    │  │   Node N    │            │  │   │
│  │  │  │  (on-demand)│  │  (on-demand)│  │  (dynamic)  │            │  │   │
│  │  │  └─────────────┘  └─────────────┘  └─────────────┘            │  │   │
│  │  └────────────────────────────────────────────────────────────────┘  │   │
│  │                                                                       │   │
│  │  Built-in Add-ons: CoreDNS, kube-proxy, VPC CNI, EBS CSI             │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Features

| Feature | Description |
|---------|-------------|
| **EKS Auto Mode** | Automatic node provisioning and scaling |
| **OIDC Provider** | IRSA for fine-grained IAM permissions |
| **Private Endpoint** | API server in private subnet |
| **Encryption** | Secrets encrypted with KMS |
| **Logging** | Control plane logs to CloudWatch |

## Usage

```hcl
module "eks" {
  source = "./modules/eks"

  project_name = "pipeops"
  environment  = "prod"
  
  cluster_name       = "pipeops-prod-eks"
  kubernetes_version = "1.33"
  
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  
  # Auto Mode configuration
  enable_auto_mode = true
  node_pools       = ["general-purpose", "system"]
  
  # Access configuration  
  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true
  cluster_endpoint_public_access_cidrs = ["0.0.0.0/0"]  # Restrict in production
  
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
| `cluster_name` | EKS cluster name | `string` | - | yes |
| `kubernetes_version` | Kubernetes version | `string` | `"1.33"` | no |
| `vpc_id` | VPC ID | `string` | - | yes |
| `private_subnet_ids` | Private subnet IDs | `list(string)` | - | yes |
| `enable_auto_mode` | Enable EKS Auto Mode | `bool` | `true` | no |
| `node_pools` | Node pool types | `list(string)` | `["general-purpose", "system"]` | no |
| `cluster_endpoint_public_access` | Public API endpoint | `bool` | `true` | no |
| `cluster_endpoint_private_access` | Private API endpoint | `bool` | `true` | no |

## Outputs

| Name | Description |
|------|-------------|
| `cluster_id` | EKS cluster ID |
| `cluster_name` | EKS cluster name |
| `cluster_endpoint` | EKS API endpoint |
| `cluster_certificate_authority_data` | CA certificate |
| `cluster_security_group_id` | Cluster security group ID |
| `node_security_group_id` | Node security group ID |
| `oidc_provider_arn` | OIDC provider ARN |
| `oidc_provider_url` | OIDC provider URL |
| `node_role_arn` | Node IAM role ARN |

## EKS Auto Mode

EKS Auto Mode automatically manages:

| Component | Description |
|-----------|-------------|
| **Nodes** | Provisions nodes based on workload requirements |
| **Scaling** | Automatic scaling up/down based on demand |
| **Updates** | Node AMI updates with minimal disruption |
| **Add-ons** | CoreDNS, kube-proxy, VPC CNI, EBS CSI Driver |

### Node Pools

| Pool | Purpose | Instance Types |
|------|---------|----------------|
| `general-purpose` | Application workloads | On-demand, mixed types |
| `system` | System components | Smaller instances |

## Access Configuration

### kubectl Access

```bash
# Update kubeconfig
aws eks update-kubeconfig --region us-west-2 --name pipeops-prod-eks

# Verify access
kubectl get nodes
kubectl cluster-info
```

### Add IAM User/Role Access

```bash
# Create access entry
aws eks create-access-entry \
  --cluster-name pipeops-prod-eks \
  --principal-arn arn:aws:iam::ACCOUNT_ID:user/USERNAME \
  --region us-west-2

# Associate admin policy
aws eks associate-access-policy \
  --cluster-name pipeops-prod-eks \
  --principal-arn arn:aws:iam::ACCOUNT_ID:user/USERNAME \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster \
  --region us-west-2
```

## IRSA (IAM Roles for Service Accounts)

Create IAM roles for Kubernetes service accounts:

```hcl
# Trust policy for service account
data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }
    actions = ["sts:AssumeRoleWithWebIdentity"]
    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.oidc_provider_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:NAMESPACE:SERVICE_ACCOUNT"]
    }
  }
}
```

## Logging

Control plane logs sent to CloudWatch:

| Log Type | Description |
|----------|-------------|
| `api` | API server logs |
| `audit` | Audit logs |
| `authenticator` | Authentication logs |
| `controllerManager` | Controller manager logs |
| `scheduler` | Scheduler logs |

## Cost Considerations

| Component | Cost |
|-----------|------|
| **EKS Cluster** | $0.10/hour (~$73/month) |
| **Nodes** | Based on EC2 instance types |
| **Data Transfer** | Cross-AZ and internet egress |

## Security Best Practices

1. **Restrict API Access**: Limit `cluster_endpoint_public_access_cidrs`
2. **Use IRSA**: Fine-grained IAM for pods
3. **Network Policies**: Implement pod-to-pod restrictions
4. **Secrets Encryption**: KMS key for secrets
5. **Audit Logging**: Enable all control plane logs
