# Environment Deployment Guide

Complete guide for deploying infrastructure to Development, Staging, and Production environments.

## 📋 Table of Contents

- [Prerequisites](#prerequisites)
- [Development Environment](#development-environment)
- [Staging Environment](#staging-environment)
- [Production Environment](#production-environment)
- [Common Operations](#common-operations)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

Before deploying to any environment, ensure you have:

### Required Tools

```bash
# Check AWS CLI
aws --version
# Required: AWS CLI 2.0+

# Check Terraform
terraform --version
# Required: Terraform 1.0+

# Check kubectl
kubectl version --client
# Required: kubectl 1.21+

# Check AWS credentials
aws sts get-caller-identity
# Should return your AWS account details
```

### AWS Permissions

Your AWS user/role needs permissions for:
- S3 (bucket creation and management)
- DynamoDB (table creation)
- KMS (key creation)
- IAM (role creation)
- EKS (cluster management)
- RDS (database management)
- VPC (networking)
- EC2 (instances, security groups)

---

## Development Environment

### 🎯 Purpose
- Rapid development and testing
- Cost-optimized configuration
- Internal-only access
- Single-AZ resources

### 📊 Specifications

| Component | Configuration |
|-----------|--------------|
| **Region** | `us-east-1` |
| **EKS** | Kubernetes 1.31, Auto Mode |
| **RDS** | Single-AZ, db.t3.micro |
| **Ingress** | Internal-only (no public access) |
| **Monitoring** | Relaxed alerts (15min grace) |
| **Cost** | ~$100-150/month |

### 🚀 Deployment Steps

#### Step 1: Setup Prerequisites

```bash
# Navigate to project directory
cd /Users/gptemp/Desktop/Personal/pipieops/pipeops-project-iac

# Run prerequisites setup for dev environment
./scripts/setup-prerequisites.sh dev us-east-1
```

**Expected Output:**
```
[INFO] Setting up prerequisites for dev environment in region us-east-1
[INFO] Account ID: 742890864997
[SUCCESS] S3 bucket created: pipeops-terraform-state-dev-742890864997
[SUCCESS] DynamoDB table created: terraform-state-lock-dev
[SUCCESS] KMS key created with alias: alias/pipeops-dev-terraform
[SUCCESS] Backend configuration written to environments/dev/backend.conf
[SUCCESS] Prerequisites setup completed!
```

**Time:** ~2-3 minutes

#### Step 2: Verify Configuration

```bash
# Check backend configuration
cat environments/dev/backend.conf

# Expected output:
# key      = "pipeops-project-iac-dev-terraform.tfstate"
# region   = "us-east-1"
# encrypt  = true
# dynamodb_table = "terraform-state-lock-dev"
# bucket   = "pipeops-terraform-state-dev-742890864997"

# Review Terraform variables
cat environments/dev/terraform.tfvars

# Verify key settings:
# - environment = "dev"
# - region = "us-east-1"
# - db_multi_az = false (cost optimization)
# - db_enable_cross_region_dr = false
```

#### Step 3: Plan Deployment

```bash
# Preview what will be created
./scripts/deploy.sh dev plan
```

**What Happens:**
1. Validates environment configuration
2. Initializes Terraform backend (reads backend.conf)
3. Downloads required provider plugins
4. Shows execution plan

**Expected Resources:**
- 1 VPC with public/private/database subnets
- 1 EKS cluster (Auto Mode)
- 1 RDS instance (Single-AZ)
- Security groups, IAM roles
- ArgoCD installation
- Monitoring stack (Prometheus, Grafana)

**Time:** ~3-5 minutes

#### Step 4: Apply Deployment

```bash
# Deploy the infrastructure
./scripts/deploy.sh dev apply
```

**Confirmation Prompt:**
```
Do you want to perform these actions in workspace "default"?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value: yes
```

**Time:** ~15-20 minutes

**Progress Indicators:**
```
[INFO] Creating VPC...
[INFO] Creating EKS cluster...
[INFO] Creating RDS instance...
[INFO] Deploying ArgoCD...
[INFO] Configuring monitoring...
```

#### Step 5: Verify Deployment

```bash
# Check EKS cluster
kubectl get nodes
# Should show Auto Mode managed nodes

# Check namespaces
kubectl get namespaces
# Should include: argocd, monitoring, kube-system

# Check RDS instance
aws rds describe-db-instances \
  --region us-east-1 \
  --query 'DBInstances[?DBInstanceIdentifier==`pipeops-dev-postgres`].[Endpoint.Address,DBInstanceStatus]' \
  --output table

# Check ArgoCD
kubectl get pods -n argocd
# All pods should be Running
```

#### Step 6: Access Services

```bash
# Get ArgoCD admin password
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)

echo "ArgoCD Password: $ARGOCD_PASSWORD"

# Port-forward ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Open in browser: https://localhost:8080
# Username: admin
# Password: (from above)

# Port-forward Grafana (optional)
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

# Open in browser: http://localhost:3000
# Username: admin
# Password: prom-operator
```

### 🔧 Development Workflow

```bash
# Make infrastructure changes
vim main.tf

# Preview changes
./scripts/deploy.sh dev plan

# Apply changes
./scripts/deploy.sh dev apply

# Test your applications
kubectl apply -f your-app-manifests.yaml

# Deploy using ArgoCD
kubectl apply -k k8s-manifests/overlays/dev
```

### 🧹 Cleanup

```bash
# Destroy all resources
./scripts/deploy.sh dev destroy

# Type 'destroy' when prompted

# Optional: Remove backend resources
aws s3 rb s3://pipeops-terraform-state-dev-742890864997 --force
aws dynamodb delete-table --table-name terraform-state-lock-dev --region us-east-1
```

---

## Staging Environment

### 🎯 Purpose
- Pre-production validation
- Production-like configuration
- Public access for testing
- Multi-AZ resources

### 📊 Specifications

| Component | Configuration |
|-----------|--------------|
| **Region** | `us-west-2` |
| **EKS** | Kubernetes 1.31, Auto Mode |
| **RDS** | Multi-AZ, db.r6g.large |
| **Ingress** | Public with SSL |
| **Monitoring** | Moderate alerts (10min grace) |
| **Cost** | ~$300-400/month |

### 🚀 Deployment Steps

#### Step 1: Setup Prerequisites

```bash
# Navigate to project directory
cd /Users/gptemp/Desktop/Personal/pipieops/pipeops-project-iac

# Run prerequisites setup for staging environment
./scripts/setup-prerequisites.sh staging us-west-2
```

**Expected Output:**
```
[INFO] Setting up prerequisites for staging environment in region us-west-2
[SUCCESS] S3 bucket created: pipeops-terraform-state-staging-742890864997
[SUCCESS] DynamoDB table created: terraform-state-lock-staging
[SUCCESS] Backend configuration written to environments/staging/backend.conf
```

**Time:** ~2-3 minutes

#### Step 2: Configure SSL Certificate (Important!)

```bash
# Request ACM certificate for your domain
aws acm request-certificate \
  --region us-west-2 \
  --domain-name "app-staging.yourdomain.com" \
  --validation-method DNS

# Get certificate ARN
aws acm list-certificates --region us-west-2

# Update ingress configuration
vim k8s-manifests/overlays/staging/ingress-patch.yaml

# Add certificate ARN:
# alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:us-west-2:ACCOUNT:certificate/CERT_ID
```

#### Step 3: Update Domain Configuration

```bash
# Edit staging ingress patch
vim k8s-manifests/overlays/staging/ingress-patch.yaml

# Update domain:
# spec:
#   rules:
#   - host: app-staging.yourdomain.com  # Change this
```

#### Step 4: Plan Deployment

```bash
# Preview what will be created
./scripts/deploy.sh staging plan

# Review carefully - this creates Multi-AZ resources
```

**Time:** ~3-5 minutes

#### Step 5: Apply Deployment

```bash
# Deploy the infrastructure
./scripts/deploy.sh staging apply
```

**Time:** ~20-25 minutes (Multi-AZ takes longer)

#### Step 6: Configure DNS

```bash
# Get ALB DNS name
kubectl get ingress -A

# Create CNAME record in your DNS provider:
# app-staging.yourdomain.com → <ALB-DNS-NAME>

# Wait for DNS propagation (5-10 minutes)
dig app-staging.yourdomain.com

# Verify SSL
curl -I https://app-staging.yourdomain.com
```

#### Step 7: Deploy Applications

```bash
# Deploy staging K8s manifests
kubectl apply -k k8s-manifests/overlays/staging

# Verify ArgoCD applications
kubectl get applications -n argocd

# Check application status
argocd app list
```

### 🔧 Staging Workflow

```bash
# Promote code from dev to staging
git checkout staging
git merge dev
git push

# Update infrastructure
./scripts/deploy.sh staging plan
./scripts/deploy.sh staging apply

# Run integration tests
./run-integration-tests.sh staging

# Monitor application health
kubectl get pods -A
kubectl top nodes
```

### 📊 Monitoring

```bash
# Access Grafana
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

# Access Prometheus
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090

# View RDS metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name CPUUtilization \
  --dimensions Name=DBInstanceIdentifier,Value=pipeops-staging-postgres \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average
```

---

## Production Environment

### 🎯 Purpose
- Live production workloads
- Maximum reliability and security
- Multi-region disaster recovery
- Strict monitoring and alerting

### 📊 Specifications

| Component | Configuration |
|-----------|--------------|
| **Region** | `us-west-2` (Primary), `us-east-1` (DR) |
| **EKS** | Kubernetes 1.31, Auto Mode |
| **RDS** | Multi-AZ + Multi-Region DR, db.r6g.xlarge |
| **Ingress** | Public with SSL + WAF |
| **Monitoring** | Strict alerts (5min grace) + PagerDuty |
| **Cost** | ~$800-1200/month |

### ⚠️ Production Checklist

Before deploying to production, ensure:

- [ ] Security audit completed
- [ ] Backup strategy documented
- [ ] Disaster recovery plan tested
- [ ] Monitoring alerts configured
- [ ] PagerDuty integration set up
- [ ] SSL certificates provisioned
- [ ] WAF rules defined
- [ ] Cost budget alerts configured
- [ ] Change management process approved
- [ ] Rollback plan documented

### 🚀 Deployment Steps

#### Step 1: Security Review

```bash
# Review all configurations
cat environments/prod/terraform.tfvars

# Verify security settings:
# - db_multi_az = true ✓
# - db_enable_cross_region_dr = true ✓
# - Encryption enabled ✓
# - Backup retention = 30 days ✓
```

#### Step 2: Setup Prerequisites

```bash
# Setup production backend (PRIMARY REGION)
./scripts/setup-prerequisites.sh prod us-west-2
```

**Expected Output:**
```
[INFO] Setting up prerequisites for prod environment in region us-west-2
[SUCCESS] S3 bucket created: pipeops-terraform-state-prod-742890864997
[SUCCESS] DynamoDB table created: terraform-state-lock-prod
[SUCCESS] KMS key created
[SUCCESS] IAM role created: pipeops-prod-deploy-role
[SUCCESS] Backend configuration written to environments/prod/backend.conf
```

#### Step 3: Configure SSL and WAF

```bash
# 1. Request production SSL certificate
aws acm request-certificate \
  --region us-west-2 \
  --domain-name "app.yourdomain.com" \
  --subject-alternative-names "*.yourdomain.com" \
  --validation-method DNS

# 2. Create WAF Web ACL
aws wafv2 create-web-acl \
  --region us-west-2 \
  --name pipeops-prod-waf \
  --scope REGIONAL \
  --default-action Allow={} \
  --rules file://waf-rules.json

# 3. Get WAF ARN
WAF_ARN=$(aws wafv2 list-web-acls --scope REGIONAL --region us-west-2 \
  --query 'WebACLs[?Name==`pipeops-prod-waf`].ARN' --output text)

# 4. Update ingress configuration
vim k8s-manifests/overlays/prod/ingress-patch.yaml

# Add:
# alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:...
# alb.ingress.kubernetes.io/wafv2-acl-arn: $WAF_ARN
```

#### Step 4: Configure PagerDuty

```bash
# Create PagerDuty service
# Get integration key from PagerDuty UI

# Create secret in AWS Secrets Manager
aws secretsmanager create-secret \
  --name pipeops/prod/pagerduty \
  --secret-string '{"integration_key":"YOUR_KEY"}'

# Update monitoring alerts
vim k8s-manifests/overlays/prod/monitoring-patch.yaml

# Ensure pagerduty: "true" label is set
```

#### Step 5: Plan Deployment (CRITICAL)

```bash
# Generate detailed plan
./scripts/deploy.sh prod plan | tee prod-plan-$(date +%Y%m%d-%H%M%S).txt

# Review plan CAREFULLY
# - Check all resource changes
# - Verify no destructive changes
# - Confirm Multi-AZ settings
# - Verify DR region configuration
```

**Expected Resources:**
- 2 VPCs (us-west-2 primary, us-east-1 DR)
- 1 EKS cluster (primary region)
- 2 RDS instances (Multi-AZ primary + DR replica)
- Resource quotas and limit ranges
- Enhanced monitoring and alerting

**Time:** ~5-7 minutes

#### Step 6: Staged Production Deployment

```bash
# STAGE 1: Deploy core infrastructure
./scripts/deploy.sh prod apply

# Type 'yes' when prompted
# Monitor closely for any errors

# WAIT: 25-30 minutes for infrastructure

# STAGE 2: Verify infrastructure
kubectl get nodes
aws rds describe-db-instances --region us-west-2 \
  --db-instance-identifier pipeops-prod-postgres

# STAGE 3: Deploy Kubernetes manifests
kubectl apply -k k8s-manifests/overlays/prod

# WAIT: 5-10 minutes for ArgoCD and monitoring

# STAGE 4: Verify all services
kubectl get pods -A
kubectl get applications -n argocd
```

#### Step 7: Configure DNS and CDN (Production)

```bash
# Get ALB DNS name
ALB_DNS=$(kubectl get ingress -A -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}')

# Configure Route53 (or your DNS provider)
aws route53 change-resource-record-sets \
  --hosted-zone-id YOUR_ZONE_ID \
  --change-batch '{
    "Changes": [{
      "Action": "CREATE",
      "ResourceRecordSet": {
        "Name": "app.yourdomain.com",
        "Type": "CNAME",
        "TTL": 300,
        "ResourceRecords": [{"Value": "'$ALB_DNS'"}]
      }
    }]
  }'

# Optional: Configure CloudFront CDN
# (for global distribution and DDoS protection)
```

#### Step 8: Smoke Tests

```bash
# Test primary endpoint
curl -I https://app.yourdomain.com/health

# Expected: HTTP 200 OK

# Test database connectivity
kubectl run -it --rm debug --image=postgres:15 --restart=Never -- \
  psql -h $(kubectl get secret db-credentials -n argocd -o jsonpath='{.data.host}' | base64 -d) \
  -U postgres -d pipeops -c "SELECT version();"

# Test ArgoCD
argocd login localhost:8080 --username admin --password $ARGOCD_PASSWORD
argocd app list

# Test monitoring
curl -s http://localhost:9090/-/healthy  # Prometheus
curl -s http://localhost:3000/api/health  # Grafana
```

#### Step 9: Enable Monitoring Alerts

```bash
# Verify AlertManager is running
kubectl get pods -n monitoring | grep alertmanager

# Test alert routing
kubectl port-forward -n monitoring svc/kube-prometheus-stack-alertmanager 9093:9093

# Open: http://localhost:9093
# Verify PagerDuty integration is configured

# Create test alert
kubectl run cpu-hog --image=busybox --restart=Never -- sh -c "while true; do :; done"

# Wait 5 minutes, verify alert fires
```

#### Step 10: Document Deployment

```bash
# Record deployment details
cat > deployments/prod-$(date +%Y%m%d).md << EOF
# Production Deployment - $(date +%Y-%m-%d)

## Infrastructure
- EKS Cluster: pipeops-prod-eks
- RDS Primary: pipeops-prod-postgres (us-west-2)
- RDS DR: pipeops-prod-postgres-dr (us-east-1)
- Domain: app.yourdomain.com

## Versions
- Terraform: $(terraform version -json | jq -r .terraform_version)
- Kubernetes: $(kubectl version --short 2>/dev/null | grep Server)
- ArgoCD: $(kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server -o jsonpath='{.items[0].spec.containers[0].image}')

## Deployed By
- User: $(aws sts get-caller-identity --query Arn --output text)
- Date: $(date -u +"%Y-%m-%d %H:%M:%S UTC")

## Notes
- All smoke tests passed
- Monitoring alerts configured
- DR failover tested: [PENDING]
EOF
```

### 🔧 Production Operations

#### Deployment Update

```bash
# 1. Create change request (follow your process)

# 2. Update staging first
./scripts/deploy.sh staging apply

# 3. Test in staging
./run-production-tests.sh staging

# 4. If tests pass, deploy to production
./scripts/deploy.sh prod plan
# REVIEW OUTPUT CAREFULLY

./scripts/deploy.sh prod apply

# 5. Monitor deployment
watch kubectl get pods -A
```

#### Health Checks

```bash
# Daily health check script
cat > scripts/health-check.sh << 'EOF'
#!/bin/bash
echo "=== EKS Cluster Health ==="
kubectl get nodes
kubectl top nodes

echo "=== Pod Health ==="
kubectl get pods -A | grep -v Running | grep -v Completed

echo "=== RDS Health ==="
aws rds describe-db-instances \
  --region us-west-2 \
  --db-instance-identifier pipeops-prod-postgres \
  --query 'DBInstances[0].[DBInstanceStatus,MultiAZ,ReadReplicaDBInstanceIdentifiers]'

echo "=== ArgoCD Sync Status ==="
argocd app list

echo "=== Resource Usage ==="
kubectl top nodes
kubectl top pods -A --containers
EOF

chmod +x scripts/health-check.sh
./scripts/health-check.sh
```

#### Disaster Recovery Test

```bash
# Test DR failover (do this in maintenance window!)

# 1. Promote DR RDS to standalone
aws rds promote-read-replica \
  --region us-east-1 \
  --db-instance-identifier pipeops-prod-postgres-dr

# 2. Update application to use DR endpoint
kubectl edit secret db-credentials-dr -n argocd

# 3. Restart application pods
kubectl rollout restart deployment/your-app

# 4. Verify application works with DR database

# 5. Document failover time (RTO)

# 6. Failback when ready (recreate read replica)
```

### 📊 Production Monitoring

```bash
# View real-time metrics
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

# Key dashboards to monitor:
# - Kubernetes Cluster Monitoring
# - Node Exporter
# - PostgreSQL Overview
# - ArgoCD Overview

# Set up cost monitoring
aws ce get-cost-and-usage \
  --time-period Start=2026-01-01,End=2026-01-31 \
  --granularity MONTHLY \
  --metrics UnblendedCost \
  --group-by Type=TAG,Key=Environment \
  --filter file://cost-filter.json
```

---

## Common Operations

### View Terraform State

```bash
# List all resources
terraform state list

# Show specific resource
terraform state show module.eks.aws_eks_cluster.main

# Pull remote state
terraform state pull > state-backup-$(date +%Y%m%d).json
```

### Update Single Component

```bash
# Target specific module
terraform plan -target=module.rds
terraform apply -target=module.rds

# Target specific resource
terraform plan -target=module.eks.aws_eks_cluster.main
```

### Import Existing Resources

```bash
# Import existing S3 bucket
terraform import aws_s3_bucket.state pipeops-terraform-state-prod-742890864997

# Import existing RDS instance
terraform import module.rds.aws_db_instance.main pipeops-prod-postgres
```

### Rollback Changes

```bash
# View state versions (S3 versioning)
aws s3api list-object-versions \
  --bucket pipeops-terraform-state-prod-742890864997 \
  --prefix pipeops-project-iac-prod-terraform.tfstate

# Restore previous state
aws s3api get-object \
  --bucket pipeops-terraform-state-prod-742890864997 \
  --key pipeops-project-iac-prod-terraform.tfstate \
  --version-id VERSION_ID \
  state-rollback.tfstate

# Apply rollback (with approval)
terraform apply
```

### Cost Analysis

```bash
# Estimate costs before deployment
terraform plan -out=tfplan
terraform show -json tfplan | infracost breakdown --path -

# Check current costs
aws ce get-cost-and-usage \
  --time-period Start=$(date -d '30 days ago' +%Y-%m-%d),End=$(date +%Y-%m-%d) \
  --granularity MONTHLY \
  --metrics UnblendedCost
```

---

## Troubleshooting

### Issue: Terraform Init Fails

**Error:** `Error: Failed to get existing workspaces: S3 bucket does not exist`

**Solution:**
```bash
# Run prerequisites setup first
./scripts/setup-prerequisites.sh <env> <region>

# Verify bucket exists
aws s3 ls | grep pipeops-terraform-state

# If bucket exists but still fails, check region
aws s3api get-bucket-location --bucket pipeops-terraform-state-<env>-ACCOUNT_ID
```

### Issue: State Lock Timeout

**Error:** `Error acquiring the state lock`

**Solution:**
```bash
# Check for existing locks
aws dynamodb scan \
  --table-name terraform-state-lock-<env> \
  --region <region>

# If lock is stale (check ID and timestamp)
terraform force-unlock <LOCK_ID>

# Prevent future locks: ensure only one terraform process runs
```

### Issue: EKS Cluster Not Accessible

**Error:** `error: You must be logged in to the server (Unauthorized)`

**Solution:**
```bash
# Update kubeconfig
aws eks update-kubeconfig \
  --region <region> \
  --name pipeops-<env>-eks

# Verify IAM permissions
aws sts get-caller-identity

# Check cluster status
aws eks describe-cluster --name pipeops-<env>-eks --region <region>
```

### Issue: RDS Connection Refused

**Error:** `could not connect to server: Connection refused`

**Solution:**
```bash
# 1. Check RDS status
aws rds describe-db-instances \
  --db-instance-identifier pipeops-<env>-postgres \
  --region <region> \
  --query 'DBInstances[0].DBInstanceStatus'

# 2. Verify security group allows traffic
aws ec2 describe-security-groups \
  --filters "Name=tag:Name,Values=*rds*" \
  --region <region>

# 3. Test from within cluster
kubectl run -it --rm debug --image=postgres:15 --restart=Never -- \
  psql -h <RDS_ENDPOINT> -U postgres -d pipeops
```

### Issue: High Costs

**Problem:** Monthly bill exceeds budget

**Solution:**
```bash
# Identify expensive resources
aws ce get-cost-and-usage \
  --time-period Start=$(date -d '7 days ago' +%Y-%m-%d),End=$(date +%Y-%m-%d) \
  --granularity DAILY \
  --group-by Type=SERVICE \
  --metrics UnblendedCost

# Common cost optimizations:
# 1. Stop dev environment after hours
# 2. Use smaller RDS instances in non-prod
# 3. Enable RDS Auto Scaling
# 4. Use Spot instances for EKS worker nodes
# 5. Clean up unused EBS volumes and snapshots
```

---

## Best Practices

### Security

1. ✅ Never commit `terraform.tfvars` with production values
2. ✅ Use AWS Secrets Manager for sensitive data
3. ✅ Enable MFA for production AWS access
4. ✅ Rotate credentials regularly
5. ✅ Review IAM policies (principle of least privilege)
6. ✅ Enable CloudTrail for audit logging
7. ✅ Use private subnets for databases

### Operations

1. ✅ Always run `plan` before `apply`
2. ✅ Test in dev/staging before production
3. ✅ Document all production changes
4. ✅ Maintain separate AWS accounts for environments
5. ✅ Use infrastructure versioning (Git tags)
6. ✅ Automate deployments via CI/CD
7. ✅ Keep Terraform and provider versions pinned

### Disaster Recovery

1. ✅ Test DR failover quarterly
2. ✅ Document RTO and RPO requirements
3. ✅ Automate backups and verify restores
4. ✅ Maintain runbooks for common scenarios
5. ✅ Configure multi-region monitoring
6. ✅ Practice disaster scenarios

---

## Quick Reference

### Development
```bash
./scripts/setup-prerequisites.sh dev us-east-1
./scripts/deploy.sh dev plan
./scripts/deploy.sh dev apply
```

### Staging
```bash
./scripts/setup-prerequisites.sh staging us-west-2
./scripts/deploy.sh staging plan
./scripts/deploy.sh staging apply
```

### Production
```bash
./scripts/setup-prerequisites.sh prod us-west-2
./scripts/deploy.sh prod plan
./scripts/deploy.sh prod apply
```

### Access Services
```bash
# ArgoCD
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Grafana
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

# Prometheus
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
```

---

**Last Updated:** 2026-01-21  
**Version:** 1.0  
**Maintained By:** Platform Team

For questions or issues, contact: platform-team@yourcompany.com
