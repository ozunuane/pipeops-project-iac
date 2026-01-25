# Documentation Index

## 📚 Quick Start

**New to this project?** Start here:
1. [Main README](../README.md) - Project overview
2. [RDS Complete Guide](../RDS_COMPLETE_GUIDE.md) - Database setup & DR

---

## 🗂️ Documentation Structure

### Essential Guides

#### **[RDS Complete Guide](../RDS_COMPLETE_GUIDE.md)** ⭐ PRIMARY REFERENCE
**Complete reference for all RDS setup, HA, and DR procedures**

Contents:
- Architecture overview (all 3 tiers)
- Configuration options (dev/staging/prod)
- Deployment procedures
- Disaster recovery scenarios & procedures
- Monitoring & alerting setup
- Cost analysis by tier
- Maintenance operations
- Troubleshooting guide
- Quick reference commands

**Use this for:** Everything RDS-related

---

### Infrastructure Documentation

#### **[Main README](../README.md)**
Project overview and quick start guide

Contents:
- Architecture overview
- Infrastructure components
- Quick start guide
- Deployment commands
- Monitoring setup
- Security best practices
- Cost optimization

**Use this for:** Understanding the overall infrastructure

---

#### **[AWS Backup Guide](./AWS_BACKUP_GUIDE.md)** 🆕
EKS cluster backup and restore procedures

Contents:
- Backup architecture (primary + DR region)
- Configuration options (schedule, retention, cross-region)
- Environment-specific settings
- Restore procedures (console & CLI)
- Monitoring and alerting
- Cost considerations
- Troubleshooting

**Use this for:** EKS backup configuration and disaster recovery

---

### Configuration Files

#### Terraform Configuration
- `main.tf` - Root module configuration
- `variables.tf` - Input variables
- `outputs.tf` - Output values
- `versions.tf` - Provider versions
- `backend.tf` - State backend configuration

#### Environment Configurations
- `environments/dev/terraform.tfvars` - Development config
- `environments/staging/terraform.tfvars` - Staging config
- `environments/prod/terraform.tfvars` - Production config
- `terraform.tfvars.example` - Example configuration

#### Modules
- `modules/vpc/` - VPC networking module
- `modules/eks/` - EKS cluster module
- `modules/rds/` - RDS database module (with HA/DR)
- `modules/argocd/` - ArgoCD GitOps module
- `modules/monitoring/` - Prometheus/Grafana module
- `modules/ecr/` - ECR container registry module

#### Standalone Terraform Files
- `backup.tf` - AWS Backup for EKS (daily 6 AM + weekly backups)
- `ecr.tf` - ECR repository configuration
- `argocd.tf` - ArgoCD Helm installation

---

### Scripts

#### Deployment Scripts
- `scripts/deploy.sh` - Main deployment script
- `scripts/setup-prerequisites.sh` - AWS prerequisites setup

#### Kubernetes Manifests
- `k8s-manifests/argocd/` - ArgoCD applications
- `k8s-manifests/ingress-controller/` - ALB controller configs
- `k8s-manifests/monitoring/` - Monitoring configs

---

## 🎯 Quick Navigation by Task

### Setting Up RDS
➡️ Go to: [RDS Complete Guide - Deployment Section](../RDS_COMPLETE_GUIDE.md#deployment-guide)

### Configuring Disaster Recovery
➡️ Go to: [RDS Complete Guide - Configuration Options](../RDS_COMPLETE_GUIDE.md#configuration-options)

### Understanding DR Tiers
➡️ Go to: [RDS Complete Guide - Architecture Section](../RDS_COMPLETE_GUIDE.md#architecture)

### Disaster Recovery Procedures
➡️ Go to: [RDS Complete Guide - Disaster Recovery Section](../RDS_COMPLETE_GUIDE.md#disaster-recovery)

### Monitoring Setup
➡️ Go to: [RDS Complete Guide - Monitoring Section](../RDS_COMPLETE_GUIDE.md#monitoring--alerts)

### Cost Analysis
➡️ Go to: [RDS Complete Guide - Cost Analysis Section](../RDS_COMPLETE_GUIDE.md#cost-analysis)

### Troubleshooting
➡️ Go to: [RDS Complete Guide - Troubleshooting Section](../RDS_COMPLETE_GUIDE.md#troubleshooting)

### Configuring EKS Backups
➡️ Go to: [AWS Backup Guide - Configuration](./AWS_BACKUP_GUIDE.md#configuration)

### Restore EKS from Backup
➡️ Go to: [AWS Backup Guide - Restore Procedures](./AWS_BACKUP_GUIDE.md#restore-procedures)

---

## 📖 Documentation by Role

### DevOps Engineer
**Primary:** [RDS Complete Guide](../RDS_COMPLETE_GUIDE.md)
- Full deployment procedures
- DR setup and testing
- Monitoring configuration
- Maintenance operations

**Secondary:** [Main README](../README.md)
- Overall infrastructure
- EKS cluster management
- ArgoCD GitOps workflow

### Developer
**Primary:** [Main README](../README.md)
- Application deployment via ArgoCD
- Accessing services
- Development environment

**Secondary:** [RDS Complete Guide - Quick Reference](../RDS_COMPLETE_GUIDE.md#quick-reference)
- Database connection strings
- Common commands

### Manager/Stakeholder
**Primary:** [RDS Complete Guide - Cost Analysis](../RDS_COMPLETE_GUIDE.md#cost-analysis)
- Cost breakdown by tier
- ROI analysis
- DR tier comparison

**Secondary:** [RDS Complete Guide - Overview](../RDS_COMPLETE_GUIDE.md#overview)
- What protection levels are available
- Recovery objectives (RPO/RTO)

---

## 🚀 Common Workflows

### Deploy New Environment
1. [Main README - Quick Start](../README.md#quick-start)
2. [RDS Complete Guide - Deployment](../RDS_COMPLETE_GUIDE.md#deployment-guide)

### Enable Multi-Region DR
1. [RDS Complete Guide - Configuration Options](../RDS_COMPLETE_GUIDE.md#configuration-options)
2. [RDS Complete Guide - Deployment](../RDS_COMPLETE_GUIDE.md#deployment-guide)

### Perform DR Failover
1. [RDS Complete Guide - DR Scenarios](../RDS_COMPLETE_GUIDE.md#disaster-recovery)

### Upgrade RDS Configuration
1. [RDS Complete Guide - Maintenance](../RDS_COMPLETE_GUIDE.md#maintenance--operations)

### Troubleshoot Issues
1. [RDS Complete Guide - Troubleshooting](../RDS_COMPLETE_GUIDE.md#troubleshooting)

---

## 📊 Documentation Metrics

| Document | Size | Last Updated | Audience |
|----------|------|--------------|----------|
| **RDS Complete Guide** | ~45 KB | Latest | All roles |
| **Main README** | ~10 KB | Latest | All roles |
| **Terraform Configs** | Various | Latest | DevOps |

**Total Documentation**: 2 main guides (simplified from 8 files)

---

## 🔄 Documentation Updates

### Recent Changes
- ✅ Consolidated 7 RDS documents into 1 comprehensive guide
- ✅ Added multi-region DR support
- ✅ Simplified documentation structure
- ✅ Created this index for easy navigation

### Documentation Principles
1. **Single Source of Truth**: One guide per major component
2. **Role-Based Navigation**: Easy to find what you need
3. **Quick Reference**: Common commands readily available
4. **Comprehensive**: All details in one place

---

## 📞 Getting Help

### Documentation Issues
- Missing information? Check [RDS Complete Guide](../RDS_COMPLETE_GUIDE.md)
- Still unclear? Contact DevOps team

### Technical Issues
- Review [Troubleshooting Section](../RDS_COMPLETE_GUIDE.md#troubleshooting)
- Check CloudWatch logs
- Contact on-call engineer

### Access Issues
- AWS credentials: Contact AWS admin
- Repository access: Contact team lead

---

**Happy deploying! 🚀**
tf init -backend-config /environments/dev/backend.conf