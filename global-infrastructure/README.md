# Global Infrastructure - DNS & Certificates

This workspace manages global resources that span multiple regions and are critical for DR failover. It supports **multiple domain names**, each with its own hosted zone and certificates.

## Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        GLOBAL INFRASTRUCTURE                                 │
│                                                                             │
│  ┌─────────────────────────┐    ┌─────────────────────────┐                │
│  │   Route53 Hosted Zone   │    │   Route53 Hosted Zone   │                │
│  │     example.com         │    │    another.io           │                │
│  └───────────┬─────────────┘    └───────────┬─────────────┘                │
│              │                              │                               │
│              └──────────────┬───────────────┘                               │
│                             │                                               │
│              ┌──────────────┴───────────────┐                               │
│              ▼                              ▼                               │
│    ┌─────────────────────┐      ┌─────────────────────┐                    │
│    │   Health Check      │      │   Health Check      │                    │
│    │   (Primary)         │      │   (DR)              │                    │
│    └─────────────────────┘      └─────────────────────┘                    │
│              │                              │                               │
│              ▼                              ▼                               │
│    ┌─────────────────────┐      ┌─────────────────────┐                    │
│    │   Failover Record   │      │   Failover Record   │                    │
│    │   PRIMARY           │      │   SECONDARY         │                    │
│    └─────────────────────┘      └─────────────────────┘                    │
│              │                              │                               │
└──────────────│──────────────────────────────│───────────────────────────────┘
               │                              │
               ▼                              ▼
┌──────────────────────────────┐  ┌──────────────────────────────┐
│     PRIMARY (us-west-2)      │  │       DR (us-east-1)         │
│                              │  │                              │
│  ┌────────────────────────┐  │  │  ┌────────────────────────┐  │
│  │  ACM Certificates      │  │  │  │  ACM Certificates      │  │
│  │  - *.example.com       │  │  │  │  - *.example.com       │  │
│  │  - *.another.io        │  │  │  │  - *.another.io        │  │
│  └────────────────────────┘  │  │  └────────────────────────┘  │
│                              │  │                              │
│  ┌────────────────────────┐  │  │  ┌────────────────────────┐  │
│  │  EKS Cluster + ALB     │  │  │  │  EKS Cluster + ALB     │  │
│  │  (Main)                │  │  │  │  (Standby)             │  │
│  └────────────────────────┘  │  │  └────────────────────────┘  │
│                              │  │                              │
└──────────────────────────────┘  └──────────────────────────────┘
```

## What This Workspace Manages

| Resource | Description |
|----------|-------------|
| **Route53 Hosted Zones** | DNS zones for all your domains |
| **ACM Certificates** | SSL certificates in both regions for all domains |
| **Health Checks** | Monitor primary and DR cluster health |
| **Failover Records** | DNS failover routing between clusters |
| **Service DNS** | Records for ArgoCD, Grafana, API, etc. |

## Key Features

- **Multiple Domains**: Manage several root domains from a single workspace
- **Per-Domain Certificates**: Each domain gets its own certificates in both regions
- **Automatic Validation**: DNS validation records created automatically
- **Failover Routing**: Primary domain uses failover; secondary domains use simple routing

## Prerequisites

1. **Domains registered** - Either in Route53 or external registrar
2. **Primary EKS deployed** - Main infrastructure must be running
3. **DR EKS deployed** (optional) - For failover configuration
4. **ALBs created** - Via Kubernetes Ingress resources

## Quick Start

### 1. Create Backend Resources

```bash
cd global-infrastructure

# Set project name
export PROJECT_NAME=pipeops

# Create S3 bucket for state
aws s3api create-bucket \
  --bucket ${PROJECT_NAME}-global-terraform-state \
  --region us-west-2 \
  --create-bucket-configuration LocationConstraint=us-west-2

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket ${PROJECT_NAME}-global-terraform-state \
  --versioning-configuration Status=Enabled

# Create DynamoDB table for locking
aws dynamodb create-table \
  --table-name ${PROJECT_NAME}-global-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-west-2
```

### 2. Configure Your Domains

Edit `environments/prod/terraform.tfvars`:

```hcl
# Multiple domains with their configurations
domain_names = [
  {
    domain_name              = "example.com"       # Your primary domain
    create_hosted_zone       = false               # Use existing zone
    existing_hosted_zone_id  = "Z1234567890ABC"    # Your zone ID
    app_subdomain            = "app"               # Creates app.example.com
    create_certificates      = true
    subject_alternative_names = [
      "*.example.com",
      "api.example.com",
      "argocd.example.com"
    ]
  },
  {
    domain_name              = "another-domain.io" # Additional domain
    create_hosted_zone       = true                # Let Terraform create zone
    existing_hosted_zone_id  = ""
    app_subdomain            = ""                  # Use root domain
    create_certificates      = true
    subject_alternative_names = [
      "*.another-domain.io"
    ]
  }
]
```

### 3. Deploy

```bash
# Initialize
terraform init -backend-config="environments/prod/backend.conf"

# Plan
terraform plan -var-file="environments/prod/terraform.tfvars"

# Apply
terraform apply -var-file="environments/prod/terraform.tfvars"
```

### 4. Configure Failover (After ALBs are Ready)

Once your EKS clusters have ALBs deployed:

```hcl
# Enable failover
enable_failover = true

# Primary ALB (get from kubectl or AWS console)
primary_alb_dns_name = "k8s-default-ingressp-xxxxx.us-west-2.elb.amazonaws.com"
primary_alb_zone_id  = "Z1H1FL5HABSF5"  # ALB zone ID for us-west-2

# DR ALB
dr_alb_dns_name = "k8s-default-ingressp-xxxxx.us-east-1.elb.amazonaws.com"
dr_alb_zone_id  = "Z35SXDOTRQ7X7K"  # ALB zone ID for us-east-1

# Health check endpoints
primary_health_check_fqdn = "primary-direct.example.com"
dr_health_check_fqdn      = "dr-direct.example.com"
```

## Multi-Domain Configuration

### Primary vs Secondary Domains

| Feature | Primary Domain (First) | Secondary Domains |
|---------|------------------------|-------------------|
| Failover routing | ✅ Yes | ❌ Simple routing |
| Health checks | ✅ Associated | ❌ N/A |
| Service subdomains | ✅ argocd.*, grafana.* | ❌ N/A |
| Certificate | ✅ Both regions | ✅ Both regions |

### Example: Multiple Brands

```hcl
domain_names = [
  {
    domain_name              = "main-brand.com"
    create_hosted_zone       = false
    existing_hosted_zone_id  = "Z123..."
    app_subdomain            = "app"
    create_certificates      = true
    subject_alternative_names = ["*.main-brand.com"]
  },
  {
    domain_name              = "secondary-brand.com"
    create_hosted_zone       = false
    existing_hosted_zone_id  = "Z456..."
    app_subdomain            = "app"
    create_certificates      = true
    subject_alternative_names = ["*.secondary-brand.com"]
  },
  {
    domain_name              = "api.io"
    create_hosted_zone       = true  # New zone
    existing_hosted_zone_id  = ""
    app_subdomain            = ""    # Use root
    create_certificates      = true
    subject_alternative_names = ["*.api.io"]
  }
]
```

## Failover Behavior

### Normal Operation (Primary Healthy)

```
User Request → Route53 → Primary Health Check ✅ → Primary ALB → Primary EKS
```

### Failover (Primary Unhealthy)

```
User Request → Route53 → Primary Health Check ❌ 
                       → DR Health Check ✅ → DR ALB → DR EKS
```

### Health Check Settings

| Setting | Default | Description |
|---------|---------|-------------|
| `health_check_port` | 443 | HTTPS port |
| `health_check_failure_threshold` | 3 | Failures before failover |
| `health_check_interval` | 30 | Check interval (seconds) |

## Getting ALB Information

### From Kubernetes

```bash
# Primary cluster
kubectl get ingress -A

# Output includes ALB DNS name
# k8s-default-ingressp-xxxxx.us-west-2.elb.amazonaws.com
```

### From AWS CLI

```bash
# List ALBs
aws elbv2 describe-load-balancers --region us-west-2 \
  --query "LoadBalancers[*].[LoadBalancerName,DNSName,CanonicalHostedZoneId]" \
  --output table
```

### ALB Zone IDs by Region

| Region | Zone ID |
|--------|---------|
| us-east-1 | Z35SXDOTRQ7X7K |
| us-west-2 | Z1H1FL5HABSF5 |
| eu-west-1 | Z32O12XQLNTSW2 |
| ap-southeast-1 | Z1LMS91P8CMLE5 |

## Outputs

After deployment, get certificate ARNs for use in other workspaces:

```bash
# All certificate ARNs by domain
terraform output certificate_arns_by_domain

# Primary certificate ARN (first domain)
terraform output primary_certificate_arn

# DR certificate ARN (first domain)
terraform output dr_certificate_arn

# Hosted zone IDs
terraform output hosted_zone_ids

# Summary of all domains
terraform output summary
```

### Example Output

```hcl
certificate_arns_by_domain = {
  "example_com" = {
    primary = "arn:aws:acm:us-west-2:xxx:certificate/abc123"
    dr      = "arn:aws:acm:us-east-1:xxx:certificate/def456"
  }
  "another_io" = {
    primary = "arn:aws:acm:us-west-2:xxx:certificate/ghi789"
    dr      = "arn:aws:acm:us-east-1:xxx:certificate/jkl012"
  }
}
```

## Integration with EKS Workspaces

### Use Certificates in Ingress

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:us-west-2:xxx:certificate/xxx
    alb.ingress.kubernetes.io/ssl-redirect: "443"
spec:
  # ...
```

### Reference from Main Workspace

```hcl
# In main.tf
data "terraform_remote_state" "global" {
  backend = "s3"
  config = {
    bucket = "pipeops-global-terraform-state"
    key    = "global/terraform.tfstate"
    region = "us-west-2"
  }
}

# Use primary certificate ARN
locals {
  primary_cert = data.terraform_remote_state.global.outputs.primary_certificate_arn
  
  # Or get specific domain certificate
  example_cert = data.terraform_remote_state.global.outputs.certificate_arns_by_domain["example_com"].primary
}
```

## Troubleshooting

### Certificate Validation Pending

```bash
# Check validation status
aws acm describe-certificate \
  --certificate-arn $(terraform output -raw primary_certificate_arn) \
  --region us-west-2 \
  --query "Certificate.DomainValidationOptions"
```

Ensure DNS validation records exist in Route53.

### Health Check Failing

```bash
# Check health check status
aws route53 get-health-check-status \
  --health-check-id $(terraform output -raw primary_health_check_id)
```

### DNS Not Resolving

```bash
# Check DNS propagation
dig +short app.example.com

# Check Route53 records
aws route53 list-resource-record-sets \
  --hosted-zone-id $(terraform output -json hosted_zone_ids | jq -r '.example_com')
```

### External Registrar Setup

If using an external registrar (e.g., GoDaddy, Namecheap):

1. Deploy with `create_hosted_zone = true`
2. Get name servers: `terraform output hosted_zone_name_servers`
3. Update registrar's NS records to point to AWS name servers
4. Wait for propagation (up to 48 hours)

## File Structure

```
global-infrastructure/
├── main.tf                         # Main Terraform configuration
├── variables.tf                    # Input variables
├── outputs.tf                      # Output values
├── README.md                       # This file
└── environments/
    └── prod/
        ├── backend.conf            # S3 backend configuration
        └── terraform.tfvars        # Production variables
```

## Related Documentation

- [AWS Route53 Failover](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/routing-policy-failover.html)
- [ACM Certificate Validation](https://docs.aws.amazon.com/acm/latest/userguide/dns-validation.html)
- [ALB Zone IDs](https://docs.aws.amazon.com/general/latest/gr/elb.html)
