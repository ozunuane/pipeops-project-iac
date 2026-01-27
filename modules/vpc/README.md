# VPC Module

Production-grade VPC with multi-AZ deployment for EKS and RDS workloads.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              VPC (10.0.0.0/16)                              │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                        PUBLIC SUBNETS (ALB, NAT)                     │   │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐      │   │
│  │  │   10.0.101.0/24 │  │   10.0.102.0/24 │  │   10.0.103.0/24 │      │   │
│  │  │     us-west-2a  │  │     us-west-2b  │  │     us-west-2c  │      │   │
│  │  │ NAT Gateway (1) │  │                 │  │                 │      │   │
│  │  └─────────────────┘  └─────────────────┘  └─────────────────┘      │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                       PRIVATE SUBNETS (EKS Nodes)                    │   │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐      │   │
│  │  │   10.0.1.0/24   │  │   10.0.2.0/24   │  │   10.0.3.0/24   │      │   │
│  │  │     us-west-2a  │  │     us-west-2b  │  │     us-west-2c  │      │   │
│  │  │   EKS Workers   │  │   EKS Workers   │  │   EKS Workers   │      │   │
│  │  └─────────────────┘  └─────────────────┘  └─────────────────┘      │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                      DATABASE SUBNETS (RDS)                          │   │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐      │   │
│  │  │   10.0.201.0/24 │  │   10.0.202.0/24 │  │   10.0.203.0/24 │      │   │
│  │  │     us-west-2a  │  │     us-west-2b  │  │     us-west-2c  │      │   │
│  │  │   RDS Primary   │  │   RDS Standby   │  │   Read Replica  │      │   │
│  │  └─────────────────┘  └─────────────────┘  └─────────────────┘      │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Features

| Feature | Description |
|---------|-------------|
| **Multi-AZ** | Subnets across 3 availability zones |
| **3-Tier Network** | Public, private, and database subnets |
| **NAT Gateway** | Single regional NAT gateway; all private subnets share egress (cost-optimized) |
| **EKS Tags** | Automatic subnet tagging for EKS |
| **Flow Logs** | VPC Flow Logs to CloudWatch |

## Usage

```hcl
module "vpc" {
  source = "./modules/vpc"

  project_name = "pipeops"
  environment  = "prod"
  
  vpc_cidr             = "10.0.0.0/16"
  availability_zones   = ["us-west-2a", "us-west-2b", "us-west-2c"]
  public_subnet_cidrs  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
  private_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  database_subnet_cidrs = ["10.0.201.0/24", "10.0.202.0/24", "10.0.203.0/24"]
  
  enable_nat_gateway = true
  # single_nat_gateway: current implementation uses a single regional NAT (cost-optimized)
  
  tags = {
    Environment = "prod"
    ManagedBy   = "terraform"
  }
}
```

## Variables

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `project_name` | Project name for resource naming | `string` | - | yes |
| `environment` | Environment (dev/staging/prod) | `string` | - | yes |
| `vpc_cidr` | CIDR block for VPC | `string` | `"10.0.0.0/16"` | no |
| `availability_zones` | List of AZs | `list(string)` | - | yes |
| `public_subnet_cidrs` | Public subnet CIDRs | `list(string)` | - | yes |
| `private_subnet_cidrs` | Private subnet CIDRs | `list(string)` | - | yes |
| `database_subnet_cidrs` | Database subnet CIDRs | `list(string)` | - | yes |
| `enable_nat_gateway` | Enable NAT Gateway | `bool` | `true` | no |
| `single_nat_gateway` | Use single NAT Gateway | `bool` | — | no (implementation uses single regional NAT) |
| `enable_dns_hostnames` | Enable DNS hostnames | `bool` | `true` | no |
| `enable_dns_support` | Enable DNS support | `bool` | `true` | no |

## Outputs

| Name | Description |
|------|-------------|
| `vpc_id` | VPC ID |
| `vpc_cidr_block` | VPC CIDR block |
| `public_subnet_ids` | List of public subnet IDs |
| `private_subnet_ids` | List of private subnet IDs |
| `database_subnet_ids` | List of database subnet IDs |
| `database_subnet_group_name` | Database subnet group name |
| `nat_gateway_ids` | NAT Gateway ID(s) (single regional NAT in current implementation) |

## Subnet Tagging

The module automatically tags subnets for EKS:

```hcl
# Public subnets (for ALBs)
kubernetes.io/role/elb = 1
kubernetes.io/cluster/{cluster-name} = shared

# Private subnets (for internal LBs and nodes)
kubernetes.io/role/internal-elb = 1
kubernetes.io/cluster/{cluster-name} = shared
```

## Cost Considerations

| Component | Cost Impact |
|-----------|-------------|
| **NAT Gateway** | ~$32/month (single regional) + data processing |
| **VPC Endpoints** | ~$7.30/month each |
| **Data Transfer** | Inter-AZ: $0.01/GB |

**Cost Optimization Tips:**
- The module uses a single regional NAT gateway by default.
- Add VPC Endpoints for frequently used AWS services to reduce NAT data transfer.
- Monitor data transfer between AZs.

## Security

- Private subnets have no direct internet access
- Database subnets only accessible from private subnets
- VPC Flow Logs enabled for audit trail
- Default security group denies all traffic
