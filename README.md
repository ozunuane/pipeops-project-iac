# Production EKS Setup with GitOps

A production-ready Kubernetes infrastructure on AWS using EKS Auto Mode with ArgoCD for GitOps continuous deployment.

## Architecture Overview

This setup includes:

- **EKS Auto Mode Cluster** - Kubernetes cluster with managed node groups
- **VPC with Multi-AZ deployment** - Production-grade networking
- **RDS PostgreSQL with Multi-AZ** - HA database with automatic failover & read replicas
- **ArgoCD** - GitOps continuous deployment
- **AWS Load Balancer Controller** - Application Load Balancer integration
- **Prometheus & Grafana** - Monitoring and observability
- **External Secrets Operator** - AWS Secrets Manager integration
- **Container Insights** - CloudWatch monitoring for containers
- **CloudWatch Alarms** - Proactive database monitoring

## 🏗️ Infrastructure Components

### Network Architecture
- **VPC**: Multi-AZ deployment across 3 availability zones
- **Subnets**: Public, private, and database subnet tiers
- **NAT Gateways**: High availability with one per AZ
- **VPC Endpoints**: Cost optimization for AWS services

### Security
- **IAM Roles**: Fine-grained permissions with IRSA (IAM Roles for Service Accounts)
- **Security Groups**: Least privilege network access
- **KMS Encryption**: Data encryption at rest and in transit
- **Secrets Management**: AWS Secrets Manager integration

### Cost Optimization
- **Spot Instances**: Support for mixed instance types
- **Auto Scaling**: Cluster and application level scaling
- **GP3 Storage**: Cost-optimized storage class
- **Reserved Capacity**: Production workload optimization

## 🎯 Recent Updates

### RDS High Availability & Multi-Region Disaster Recovery (Latest)
The RDS module now supports **enterprise-grade HA/DR** with three protection tiers:

**Tier 1: Multi-AZ (Single Region)**
- ✅ Multi-AZ deployment with automatic failover (1-2 min RTO)
- ✅ Read replicas for horizontal scaling
- ✅ CloudWatch alarms for proactive monitoring
- 💰 Cost: $1,196/month

**Tier 2: + Cross-Region Backups**
- ✅ Everything in Tier 1 +
- ✅ Automated backup replication to DR region
- 💰 Cost: $1,270/month (+6%)

**Tier 3: + Multi-Region DR Replica**
- ✅ Everything in Tier 2 +
- ✅ Live DR replica in us-east-1 (Multi-AZ)
- ✅ 5-10 second replication lag, 15-30 min RTO
- 💰 Cost: $1,798/month (+50%)

**📚 Complete Documentation:**
- **[RDS Complete Guide](./RDS_COMPLETE_GUIDE.md)** ← **START HERE** - Everything you need in one place

## 🚀 Quick Start

### Prerequisites

1. **AWS CLI** configured with appropriate permissions
2. **Terraform** >= 1.5
3. **kubectl** >= 1.28
4. **Helm** >= 3.12

### Step 1: Set up AWS Prerequisites

```bash
# Set up S3 backend and DynamoDB for state locking
./scripts/setup-prerequisites.sh prod us-west-2

# For development environment
./scripts/setup-prerequisites.sh dev us-west-2
```

### Step 2: Configure Variables

```bash
# Copy and customize the example variables
cp terraform.tfvars.example terraform.tfvars

# Or use environment-specific variables
cp environments/prod/terraform.tfvars terraform.tfvars
```

### Step 3: Deploy Infrastructure

```bash
# Plan the deployment
./scripts/deploy.sh prod plan

# Apply the deployment
./scripts/deploy.sh prod apply
```

### Step 4: Access Services

```bash
# Configure kubectl
aws eks update-kubeconfig --region us-west-2 --name pipeops-prod-eks

# Access ArgoCD
kubectl port-forward svc/argocd-server -n argocd 8080:80
# Visit: http://localhost:8080
# Username: admin, Password: (from terraform output)

# Access Grafana (if monitoring enabled)
kubectl port-forward svc/grafana -n monitoring 3000:80
# Visit: http://localhost:3000
# Username: admin, Password: (from terraform output)
```

## 📁 Project Structure

```
.
├── modules/                    # Terraform modules
│   ├── vpc/                   # VPC and networking
│   ├── eks/                   # EKS cluster with Auto Mode
│   ├── rds/                   # PostgreSQL database
│   ├── argocd/                # ArgoCD GitOps setup
│   └── monitoring/            # Prometheus & Grafana
├── environments/              # Environment-specific configurations
│   ├── dev/
│   ├── staging/
│   └── prod/
├── k8s-manifests/            # Kubernetes manifests
│   ├── argocd/               # ArgoCD applications
│   ├── ingress-controller/   # ALB controller configs
│   └── monitoring/           # ServiceMonitor & alerts
├── scripts/                  # Deployment and utility scripts
│   ├── deploy.sh            # Main deployment script
│   └── setup-prerequisites.sh # AWS prerequisites setup
└── policies/                 # IAM policies
```

## 🔧 Configuration

### Environment Variables

Each environment has its own configuration:

- **Production** (`environments/prod/`): High availability, enhanced monitoring
- **Staging** (`environments/staging/`): Reduced capacity, standard monitoring
- **Development** (`environments/dev/`): Minimal resources, cost-optimized

### Key Configuration Options

```hcl
# Network Configuration
vpc_cidr              = "10.0.0.0/16"
availability_zones    = ["us-west-2a", "us-west-2b", "us-west-2c"]

# EKS Configuration
kubernetes_version    = "1.28"
node_instance_types   = ["m5.large", "m5.xlarge"]

# Database Configuration
db_instance_class     = "db.r6g.large"
db_allocated_storage  = 100

# Feature Flags
enable_argocd        = true
enable_monitoring    = true
enable_logging       = true
```

## 🔄 GitOps with ArgoCD

### Application Deployment

1. **App of Apps Pattern**: Central application management
2. **Git Repository**: Store your application manifests in Git
3. **Automatic Sync**: ArgoCD monitors Git and deploys changes
4. **Rollback**: Easy rollback to previous versions

### Example Application Structure

```yaml
# ArgoCD Application
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: sample-web-app
spec:
  source:
    repoURL: https://github.com/your-org/sample-web-app
    path: k8s/overlays/production
  destination:
    server: https://kubernetes.default.svc
    namespace: sample-app
```

## 📊 Monitoring & Observability

### Metrics & Alerts

- **Prometheus**: Metrics collection and alerting
- **Grafana**: Dashboards and visualization
- **AlertManager**: Alert routing and notifications
- **ServiceMonitors**: Automatic service discovery

### Key Dashboards

- Kubernetes Cluster Overview
- ArgoCD Operations
- Application Performance
- Infrastructure Metrics

### Alert Rules

- Application health status
- ArgoCD sync failures
- High resource utilization
- Database connection issues

## 🔐 Security Best Practices

### IAM & Access Control

- **IRSA**: IAM Roles for Service Accounts
- **RBAC**: Kubernetes role-based access control
- **Least Privilege**: Minimal required permissions
- **Service Accounts**: Dedicated accounts per service

### Network Security

- **Private Subnets**: Worker nodes in private subnets
- **Security Groups**: Restricted network access
- **Network Policies**: Kubernetes network segmentation
- **VPC Endpoints**: Private AWS service access

### Secrets Management

- **AWS Secrets Manager**: Centralized secret storage
- **External Secrets Operator**: Kubernetes secret synchronization
- **Encryption**: KMS encryption for secrets

## 💰 Cost Optimization

### Instance Management

- **Mixed Instance Types**: Optimize for cost and performance
- **Spot Instances**: Use for non-critical workloads
- **Auto Scaling**: Scale based on demand
- **Cluster Autoscaler**: Add/remove nodes automatically

### Storage Optimization

- **GP3 Volumes**: Better price-performance ratio
- **Lifecycle Policies**: Automatic data archiving
- **Snapshot Management**: Automated backup retention

### Network Costs

- **VPC Endpoints**: Reduce NAT Gateway costs
- **Data Transfer**: Optimize inter-AZ communication
- **Load Balancer Efficiency**: Share ALBs across services

## 🛠️ Operations

### Deployment Commands

```bash
# Deploy to production
./scripts/deploy.sh prod apply

# Deploy to staging
./scripts/deploy.sh staging apply

# Plan changes
./scripts/deploy.sh prod plan

# Destroy environment (careful!)
./scripts/deploy.sh dev destroy
```

### Maintenance Tasks

```bash
# Update kubectl config
aws eks update-kubeconfig --region us-west-2 --name pipeops-prod-eks

# Check cluster status
kubectl get nodes
kubectl get pods --all-namespaces

# ArgoCD operations
argocd app list
argocd app sync sample-web-app
```

## 🚨 Disaster Recovery

### Backup Strategy

- **RDS Automated Backups**: 30-day retention
- **EBS Snapshots**: Daily snapshots
- **Configuration Backup**: Terraform state in S3
- **Application Config**: Git repository backup

### Recovery Procedures

1. **Database Recovery**: Point-in-time restore from RDS backups
2. **Infrastructure Recovery**: Terraform re-deployment
3. **Application Recovery**: ArgoCD Git sync
4. **Data Recovery**: EBS snapshot restoration

## 🔍 Troubleshooting

### Common Issues

#### EKS Node Issues
```bash
# Check node status
kubectl describe nodes

# Check node logs
kubectl logs -n kube-system -l k8s-app=aws-node
```

#### ArgoCD Issues
```bash
# Check ArgoCD status
kubectl get applications -n argocd

# ArgoCD logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server
```

#### Database Connectivity
```bash
# Test database connection
kubectl run -it --rm debug --image=postgres:15 --restart=Never -- psql -h <rds-endpoint> -U postgres
```

### Getting Help

- Check the troubleshooting guide
- Review CloudWatch logs
- Check AWS EKS documentation
- ArgoCD documentation and community

## 📚 Additional Resources

- [AWS EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Kubernetes Documentation](https://kubernetes.io/docs/)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Test your changes in development environment
4. Submit a pull request with detailed description

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
