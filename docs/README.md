# Documentation Index

Complete technical documentation for the PipeOps Infrastructure as Code project.

## Quick Navigation

| Topic | Description | Link |
|-------|-------------|------|
| **Getting Started** | Prerequisites, setup, first deployment | [GETTING_STARTED.md](./GETTING_STARTED.md) |
| **Environments** | Dev, staging, prod configuration | [ENVIRONMENTS.md](./ENVIRONMENTS.md) |
| **CI/CD Pipelines** | GitHub Actions workflows | [CI_CD.md](./CI_CD.md) |
| **Disaster Recovery** | DR architecture and procedures | [DISASTER_RECOVERY.md](./DISASTER_RECOVERY.md) |
| **Backup & Restore** | EKS and RDS backup procedures | [BACKUP_RESTORE.md](./BACKUP_RESTORE.md) |

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                         PIPEOPS INFRASTRUCTURE                                   │
│                                                                                 │
│  ┌──────────────────────────────────────────────────────────────────────────┐  │
│  │                    PRIMARY REGION (us-west-2)                             │  │
│  │                                                                           │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐     │  │
│  │  │     VPC     │  │     EKS     │  │     RDS     │  │     ECR     │     │  │
│  │  │  (Network)  │  │  (K8s)      │  │  (Database) │  │  (Images)   │     │  │
│  │  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘     │  │
│  │                                                                           │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                       │  │
│  │  │   ArgoCD    │  │  Monitoring │  │  AWS Backup │                       │  │
│  │  │  (GitOps)   │  │ (Prometheus)│  │  (EKS)      │                       │  │
│  │  └─────────────┘  └─────────────┘  └─────────────┘                       │  │
│  │                                                                           │  │
│  └──────────────────────────────────────────────────────────────────────────┘  │
│                                      │                                          │
│                     Cross-Region Replication                                    │
│                                      │                                          │
│  ┌──────────────────────────────────────────────────────────────────────────┐  │
│  │                      DR REGION (us-east-1)                                │  │
│  │                                                                           │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐     │  │
│  │  │   DR VPC    │  │   DR EKS    │  │  RDS Backup │  │  ECR Replica│     │  │
│  │  │ (Standby)   │  │  (Standby)  │  │  (Copies)   │  │  (Copies)   │     │  │
│  │  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘     │  │
│  │                                                                           │  │
│  └──────────────────────────────────────────────────────────────────────────┘  │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Module Documentation

Each Terraform module has its own README with detailed documentation:

| Module | Description | README |
|--------|-------------|--------|
| **VPC** | Multi-AZ networking | [modules/vpc/README.md](../modules/vpc/README.md) |
| **EKS** | Kubernetes cluster (Auto Mode) | [modules/eks/README.md](../modules/eks/README.md) |
| **RDS** | PostgreSQL database with DR | [modules/rds/README.md](../modules/rds/README.md) |
| **ECR** | Container registry | [modules/ecr/README.md](../modules/ecr/README.md) |
| **ArgoCD** | GitOps deployment | [modules/argocd/README.md](../modules/argocd/README.md) |
| **Monitoring** | Prometheus & Grafana | [modules/monitoring/README.md](../modules/monitoring/README.md) |

---

## Workspaces

The project uses multiple Terraform workspaces for separation:

| Workspace | Purpose | Location |
|-----------|---------|----------|
| **Main** | Primary infrastructure (dev/staging/prod) | `/` (root) |
| **DR** | Disaster recovery infrastructure | `/dr-infrastructure/` |
| **Global** | DNS, certificates, failover | `/global-infrastructure/` |

---

## Directory Structure

```
pipeops-project-iac/
├── docs/                           # 📚 Documentation (this folder)
│   ├── README.md                   # Documentation index
│   ├── GETTING_STARTED.md          # Setup guide
│   ├── ENVIRONMENTS.md             # Environment configuration
│   ├── CI_CD.md                    # GitHub Actions guide
│   ├── DISASTER_RECOVERY.md        # DR procedures
│   └── BACKUP_RESTORE.md           # Backup procedures
│
├── modules/                        # 🧩 Terraform modules
│   ├── vpc/                        # VPC networking
│   ├── eks/                        # EKS cluster
│   ├── rds/                        # RDS PostgreSQL
│   ├── ecr/                        # Container registry
│   ├── argocd/                     # ArgoCD GitOps
│   └── monitoring/                 # Prometheus/Grafana
│
├── environments/                   # 🌍 Environment configs
│   ├── dev/                        # Development
│   ├── staging/                    # Staging
│   ├── prod/                       # Production
│   └── drprod/                     # DR Production
│
├── dr-infrastructure/              # 🔄 DR workspace
│   ├── main.tf
│   ├── variables.tf
│   └── environments/drprod/
│
├── global-infrastructure/          # 🌐 Global workspace
│   ├── main.tf
│   ├── variables.tf
│   └── environments/prod/
│
├── .github/workflows/              # 🚀 CI/CD pipelines
│   ├── terraform-main.yml          # Main deployments
│   ├── terraform-dr.yml            # DR deployments
│   ├── terraform-global.yml        # Global deployments
│   └── terraform-pr-checks.yml     # PR validation
│
├── scripts/                        # 🔧 Utility scripts
│   ├── setup-prerequisites.sh      # AWS setup
│   └── deploy.sh                   # Deployment helper
│
├── main.tf                         # Root module
├── variables.tf                    # Input variables
├── outputs.tf                      # Output values
└── README.md                       # Project README
```

---

## Quick Reference

### Common Commands

```bash
# Initialize Terraform
terraform init -backend-config=environments/prod/backend.conf

# Plan changes
terraform plan -var-file=environments/prod/terraform.tfvars

# Apply changes
terraform apply -var-file=environments/prod/terraform.tfvars

# Access EKS cluster
aws eks update-kubeconfig --region us-west-2 --name pipeops-prod-eks

# Get ArgoCD password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

### Environment URLs

| Service | Dev | Staging | Prod |
|---------|-----|---------|------|
| ArgoCD | `argocd.dev.example.com` | `argocd.staging.example.com` | `argocd.example.com` |
| Grafana | `grafana.dev.example.com` | `grafana.staging.example.com` | `grafana.example.com` |

---

## Support

- **Issues**: Create a GitHub issue
- **Questions**: Check the FAQ in each document
- **Emergency**: See [DISASTER_RECOVERY.md](./DISASTER_RECOVERY.md)
