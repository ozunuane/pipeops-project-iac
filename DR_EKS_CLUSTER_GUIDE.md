# 🌍 Disaster Recovery EKS Cluster Guide

## Overview

This guide explains the **DR EKS Cluster** setup, which provides application-level disaster recovery capabilities for **production environments only**. The DR cluster is automatically provisioned in a secondary AWS region when deploying to production.

## 🎯 Key Features

### Automatic Production-Only Deployment
- **Trigger**: Automatically enabled when `environment = "prod"`
- **Primary Region**: `us-west-2` (configurable)
- **DR Region**: `us-east-1` (configurable via `dr_region`)
- **Cost Optimization**: Runs in standby mode with minimal nodes

### Complete Infrastructure
The DR setup includes:
- ✅ Dedicated VPC in DR region
- ✅ EKS cluster with Auto Mode enabled
- ✅ AWS Load Balancer Controller
- ✅ External Secrets Operator
- ✅ EKS add-ons (CoreDNS, kube-proxy, VPC CNI, EBS CSI)
- ✅ IAM roles and policies (IRSA)
- ✅ Multi-AZ subnet distribution

## 📁 Architecture

### File Structure
```
pipeops-project-iac/
├── dr-main.tf              # DR infrastructure (VPC + EKS)
├── main.tf                 # Primary infrastructure
├── variables.tf            # All variables including DR
├── outputs.tf              # Outputs including DR cluster info
└── environments/
    ├── prod/
    │   └── terraform.tfvars  # DR enabled here
    ├── staging/
    │   └── terraform.tfvars  # DR disabled
    └── dev/
        └── terraform.tfvars  # DR disabled
```

### Network Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    PRIMARY REGION (us-west-2)               │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  VPC: 10.0.0.0/16                                    │   │
│  │  ┌────────────┐  ┌────────────┐  ┌────────────┐     │   │
│  │  │ EKS Cluster│  │    RDS     │  │   Apps     │     │   │
│  │  │  (Active)  │  │ (Primary)  │  │  (Active)  │     │   │
│  │  └────────────┘  └────────────┘  └────────────┘     │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                              │
                              │ Cross-Region Replication
                              │ (RDS Read Replica + Backups)
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                     DR REGION (us-east-1)                   │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  VPC: 10.1.0.0/16                                    │   │
│  │  ┌────────────┐  ┌────────────┐  ┌────────────┐     │   │
│  │  │ EKS Cluster│  │    RDS     │  │   Apps     │     │   │
│  │  │ (Standby)  │  │  (Replica) │  │ (Standby)  │     │   │
│  │  └────────────┘  └────────────┘  └────────────┘     │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## 🔧 Configuration

### DR Variables (variables.tf)

```hcl
# DR Region
dr_region = "us-east-1"

# DR VPC Configuration
dr_vpc_cidr              = "10.1.0.0/16"
dr_availability_zones    = ["us-east-1a", "us-east-1b", "us-east-1c"]
dr_public_subnet_cidrs   = ["10.1.101.0/24", "10.1.102.0/24", "10.1.103.0/24"]
dr_private_subnet_cidrs  = ["10.1.1.0/24", "10.1.2.0/24", "10.1.3.0/24"]
dr_database_subnet_cidrs = ["10.1.201.0/24", "10.1.202.0/24", "10.1.203.0/24"]

# DR EKS Cluster Sizing (Standby Mode)
dr_desired_capacity    = 2
dr_min_capacity        = 2
dr_max_capacity        = 6
dr_node_instance_types = ["t3.medium", "t3.large"]
```

### Production Configuration (environments/prod/terraform.tfvars)

```hcl
environment = "prod"  # DR automatically enabled

# DR is configured with cost-optimized settings
dr_desired_capacity = 2              # Minimal nodes for standby
dr_min_capacity     = 2
dr_max_capacity     = 6              # Scale during DR activation
dr_node_instance_types = ["t3.medium", "t3.large"]
```

### Non-Production Environments

DR cluster is **automatically disabled** for `dev` and `staging`:

```hcl
environment = "dev"     # DR not provisioned
environment = "staging" # DR not provisioned
```

## 🚀 Deployment

### Deploy Production (with DR)

```bash
# Setup prerequisites
./scripts/setup-prerequisites.sh prod

# Deploy infrastructure (includes DR)
./scripts/deploy.sh prod apply
```

The DR cluster will be automatically provisioned in the DR region.

### Verify DR Cluster

```bash
# Check DR outputs
terraform output dr_cluster_name
terraform output dr_cluster_endpoint
terraform output dr_kubectl_config_command

# Configure kubectl for DR cluster
aws eks update-kubeconfig --region us-east-1 --name pipeops-prod-dr-eks

# Verify DR cluster
kubectl get nodes
kubectl get namespaces
```

## 📊 What Gets Deployed in DR

### Infrastructure Components

1. **VPC Infrastructure**
   - VPC with CIDR `10.1.0.0/16`
   - 3 Public subnets across 3 AZs
   - 3 Private subnets across 3 AZs
   - 3 Database subnets across 3 AZs
   - NAT Gateways for private subnet internet access
   - Internet Gateway for public subnets

2. **EKS Cluster**
   - Kubernetes version matching primary cluster
   - EKS Auto Mode enabled
   - OIDC provider for IRSA
   - Cluster endpoint (public access configurable)

3. **EKS Add-ons**
   - CoreDNS (v1.10.1)
   - kube-proxy (v1.28.2)
   - VPC CNI (v1.15.4)
   - EBS CSI Driver (v1.25.0)

4. **Kubernetes Controllers**
   - AWS Load Balancer Controller (v1.6.2)
   - External Secrets Operator (v0.9.11)

5. **IAM Roles (IRSA)**
   - Load Balancer Controller role
   - External Secrets Operator role
   - EBS CSI Driver role

## 💰 Cost Optimization

### Standby Mode Costs (Approximate Monthly)

| Component | Configuration | Est. Cost |
|-----------|--------------|-----------|
| EKS Cluster | 1 cluster | $73 |
| EC2 Nodes | 2x t3.medium (standby) | ~$60 |
| NAT Gateway | 3 AZs | ~$100 |
| Data Transfer | Minimal (standby) | ~$10 |
| **Total** | **Standby Mode** | **~$243/month** |

### Active Mode Costs (During DR)

When scaled up to 6 nodes (t3.large):
- EC2 Nodes: ~$300/month
- Increased data transfer: ~$50/month
- **Total Active**: ~$523/month

### Cost Reduction Strategies

1. **Reduce NAT Gateways**: Use 1 NAT Gateway instead of 3
   ```hcl
   # In modules/vpc/main.tf
   enable_nat_gateway     = true
   single_nat_gateway     = true  # Save ~$66/month
   ```

2. **Use Spot Instances**: For non-critical DR workloads
   ```hcl
   dr_node_instance_types = ["t3.medium", "t3.large"]
   # Add spot instance support in module
   ```

3. **Scheduled Scaling**: Scale down to 0 nodes during off-hours
   ```bash
   # Scale down (manual)
   kubectl scale deployment --all --replicas=0 -n default
   ```

4. **On-Demand DR**: Only provision when needed (not recommended for production)

## 🔄 DR Activation Process

### 1. Assess the Situation

```bash
# Check primary cluster health
kubectl get nodes --context=primary
kubectl get pods --all-namespaces --context=primary

# Check RDS status
aws rds describe-db-instances --region us-west-2
```

### 2. Promote DR Database

```bash
# Promote DR RDS replica to standalone
aws rds promote-read-replica \
  --db-instance-identifier pipeops-prod-dr-replica \
  --region us-east-1
```

### 3. Scale Up DR Cluster

```bash
# Configure kubectl for DR
aws eks update-kubeconfig --region us-east-1 --name pipeops-prod-dr-eks

# Scale up node groups (if using managed node groups)
# For EKS Auto Mode, increase desired capacity via Terraform:
# Update dr_desired_capacity = 6 in terraform.tfvars
terraform apply -target=module.dr_eks
```

### 4. Deploy Applications

```bash
# Apply application manifests
kubectl apply -k k8s-manifests/overlays/prod

# Or use ArgoCD to sync applications
argocd app sync --all
```

### 5. Update DNS

```bash
# Update Route53 to point to DR region ALB
aws route53 change-resource-record-sets \
  --hosted-zone-id YOUR_ZONE_ID \
  --change-batch file://dns-failover.json
```

### 6. Verify Services

```bash
# Check all pods are running
kubectl get pods --all-namespaces

# Check services and ingresses
kubectl get svc,ingress --all-namespaces

# Test application endpoints
curl https://your-app.example.com
```

## 📈 Monitoring DR Cluster

### CloudWatch Metrics

```bash
# View DR cluster metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/EKS \
  --metric-name cluster_failed_node_count \
  --dimensions Name=ClusterName,Value=pipeops-prod-dr-eks \
  --region us-east-1 \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average
```

### Kubernetes Monitoring

```bash
# Check node status
kubectl get nodes -o wide

# Check resource usage
kubectl top nodes
kubectl top pods --all-namespaces

# Check cluster events
kubectl get events --all-namespaces --sort-by='.lastTimestamp'
```

## 🧪 Testing DR Cluster

### Regular DR Drills (Recommended: Quarterly)

```bash
# 1. Scale up DR cluster
terraform apply -var="dr_desired_capacity=4"

# 2. Deploy test application
kubectl apply -f test-app.yaml

# 3. Verify connectivity
kubectl port-forward svc/test-app 8080:80
curl localhost:8080

# 4. Scale back down
terraform apply -var="dr_desired_capacity=2"

# 5. Clean up test resources
kubectl delete -f test-app.yaml
```

## 🔐 Security Considerations

### Network Security

1. **VPC Isolation**: DR VPC is completely isolated from primary
2. **Security Groups**: Restrictive rules for EKS nodes
3. **Private Subnets**: Nodes run in private subnets only
4. **NAT Gateways**: Controlled internet access

### IAM Security

1. **IRSA**: Fine-grained IAM permissions per service account
2. **Least Privilege**: Minimal permissions for each role
3. **Cross-Region Access**: Secrets Manager access to both regions

### Secrets Management

```bash
# Replicate secrets to DR region
aws secretsmanager replicate-secret-to-regions \
  --secret-id pipeops-prod-db-credentials \
  --add-replica-regions Region=us-east-1 \
  --region us-west-2
```

## 📝 Outputs

After deployment, access DR cluster information:

```bash
# Get DR cluster details
terraform output dr_cluster_name
terraform output dr_cluster_endpoint
terraform output dr_vpc_id
terraform output dr_kubectl_config_command
terraform output dr_cluster_status

# Configure kubectl
$(terraform output -raw dr_kubectl_config_command)
```

## 🚨 Troubleshooting

### DR Cluster Not Created

**Issue**: DR cluster not provisioned for production

**Solution**:
```bash
# Verify environment variable
grep "environment" environments/prod/terraform.tfvars
# Should show: environment = "prod"

# Check Terraform plan
terraform plan | grep "module.dr_"
```

### Cannot Access DR Cluster

**Issue**: `kubectl` cannot connect to DR cluster

**Solution**:
```bash
# Update kubeconfig
aws eks update-kubeconfig \
  --region us-east-1 \
  --name pipeops-prod-dr-eks

# Verify AWS credentials
aws sts get-caller-identity

# Check cluster status
aws eks describe-cluster \
  --name pipeops-prod-dr-eks \
  --region us-east-1
```

### Nodes Not Joining Cluster

**Issue**: EKS nodes not appearing in `kubectl get nodes`

**Solution**:
```bash
# Check Auto Scaling Group
aws autoscaling describe-auto-scaling-groups \
  --region us-east-1 \
  --query 'AutoScalingGroups[?contains(Tags[?Key==`eks:cluster-name`].Value, `dr-eks`)]'

# Check node IAM role
aws eks describe-cluster \
  --name pipeops-prod-dr-eks \
  --region us-east-1 \
  --query 'cluster.resourcesVpcConfig'
```

## 📚 Related Documentation

- [RDS_COMPLETE_GUIDE.md](./RDS_COMPLETE_GUIDE.md) - RDS DR setup
- [ENVIRONMENT_DEPLOYMENT_GUIDE.md](./ENVIRONMENT_DEPLOYMENT_GUIDE.md) - Deployment procedures
- [DR_FAILOVER_RUNBOOK.md](./DR_FAILOVER_RUNBOOK.md) - Failover procedures
- [QUICK_START.md](./QUICK_START.md) - Quick reference guide

## 🎓 Best Practices

1. **Regular Testing**: Perform DR drills quarterly
2. **Documentation**: Keep runbooks updated
3. **Monitoring**: Set up CloudWatch alarms for DR cluster
4. **Automation**: Use ArgoCD for application deployment
5. **Communication**: Maintain team contact list for DR events
6. **Cost Review**: Monthly review of DR costs
7. **Security Audits**: Regular security reviews of DR infrastructure

## 🔄 Maintenance

### Monthly Tasks
- [ ] Review DR cluster costs
- [ ] Verify DR cluster health
- [ ] Test kubectl access
- [ ] Review CloudWatch logs

### Quarterly Tasks
- [ ] Perform full DR drill
- [ ] Update documentation
- [ ] Review and update IAM policies
- [ ] Test RDS failover
- [ ] Validate backup restoration

### Annual Tasks
- [ ] Full disaster recovery simulation
- [ ] Security audit
- [ ] Cost optimization review
- [ ] Update DR procedures

---

**Note**: This DR setup is designed for production environments only. The infrastructure is automatically provisioned when deploying to production and provides a cost-optimized standby cluster ready for activation during disaster scenarios.
