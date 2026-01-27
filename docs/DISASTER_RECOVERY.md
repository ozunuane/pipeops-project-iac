# Disaster Recovery

Comprehensive guide to DR architecture, procedures, and failover operations.

## DR Architecture

```
┌───────────────────────────────────────────────────────────────────────────────────┐
│                         DISASTER RECOVERY ARCHITECTURE                             │
│                                                                                   │
│  ┌─────────────────────────────────┐      ┌─────────────────────────────────┐   │
│  │      PRIMARY (us-west-2)        │      │         DR (us-east-1)          │   │
│  │                                 │      │                                  │   │
│  │  ┌─────────────────────────┐   │      │   ┌─────────────────────────┐   │   │
│  │  │         VPC             │   │      │   │       DR VPC            │   │   │
│  │  │     10.0.0.0/16         │   │      │   │    10.1.0.0/16          │   │   │
│  │  └─────────────────────────┘   │      │   └─────────────────────────┘   │   │
│  │                                 │      │                                  │   │
│  │  ┌─────────────────────────┐   │      │   ┌─────────────────────────┐   │   │
│  │  │         EKS             │   │      │   │       DR EKS            │   │   │
│  │  │    (Active)             │───│──────│──▶│    (Standby)            │   │   │
│  │  └─────────────────────────┘   │      │   └─────────────────────────┘   │   │
│  │                                 │      │                                  │   │
│  │  ┌─────────────────────────┐   │      │   ┌─────────────────────────┐   │   │
│  │  │    RDS PostgreSQL       │   │      │   │    RDS Backups          │   │   │
│  │  │    (Primary + Standby)  │───│──────│──▶│    (Replicated)         │   │   │
│  │  └─────────────────────────┘   │      │   └─────────────────────────┘   │   │
│  │                                 │      │                                  │   │
│  │  ┌─────────────────────────┐   │      │   ┌─────────────────────────┐   │   │
│  │  │         ECR             │   │      │   │      ECR Replica        │   │   │
│  │  │    (Primary)            │───│──────│──▶│    (Replicated)         │   │   │
│  │  └─────────────────────────┘   │      │   └─────────────────────────┘   │   │
│  │                                 │      │                                  │   │
│  │  ┌─────────────────────────┐   │      │   ┌─────────────────────────┐   │   │
│  │  │     EKS Backups         │   │      │   │   EKS Backup Copies     │   │   │
│  │  │    (AWS Backup)         │───│──────│──▶│    (Cross-region)       │   │   │
│  │  └─────────────────────────┘   │      │   └─────────────────────────┘   │   │
│  │                                 │      │                                  │   │
│  └─────────────────────────────────┘      └─────────────────────────────────┘   │
│                                                                                   │
└───────────────────────────────────────────────────────────────────────────────────┘
```

---

## Recovery Objectives

| Scenario | RTO | RPO |
|----------|-----|-----|
| **AZ Failure** | 1-2 min | 0 |
| **Region Failure** | 30-60 min | < 5 min |
| **Data Corruption** | 15-30 min | Point-in-time |
| **Application Bug** | 5 min | Git history |

---

## DR Components

### 1. EKS Cluster (DR Standby)

**Location**: `dr-infrastructure/`

```hcl
# DR EKS Configuration
dr_desired_capacity    = 2      # Minimal nodes
dr_node_instance_types = ["t3.medium", "t3.large"]
dr_cluster_mode        = "standby"
```

**Modes**:
| Mode | Nodes | Cost | Activation Time |
|------|-------|------|-----------------|
| Standby | 2 | ~$243/mo | 10-15 min |
| Warm | 4 | ~$400/mo | 5-10 min |
| Active | 6+ | ~$600/mo | Immediate |

### 2. RDS Backups

**Cross-Region Backup Replication**:

```hcl
# Enable in production
enable_cross_region_backups = true
dr_region                   = "us-east-1"
backup_retention_period     = 30
```

**Backup Schedule**:
- Automated daily backups
- Transaction logs every 5 minutes
- Replicated to DR region

### 3. ECR Replication

**Automatic Image Replication**:

```hcl
# Enable for production
ecr_enable_replication  = true
ecr_replication_regions = ["us-east-1"]
```

### 4. AWS Backup for EKS

**Daily Backups**:

```hcl
enable_eks_backup               = true
backup_schedule                 = "cron(0 6 * * ? *)"  # 6 AM UTC
backup_retention_days           = 35
enable_backup_cross_region_copy = true
```

---

## Failover Procedures

### Scenario 1: Primary Region Failure

**Timeline**: 30-60 minutes

#### Step 1: Assess Situation (5 min)

```bash
# Check primary region status
aws health describe-events --region us-west-2

# Check EKS status
aws eks describe-cluster --name pipeops-prod-eks --region us-west-2
```

#### Step 2: Scale DR Cluster (10 min)

```bash
cd dr-infrastructure

# Update configuration (variables declarative in tfvars only; no -var overrides)
vim environments/drprod/terraform.tfvars
# Set: dr_desired_capacity = 6, dr_cluster_mode = "active"

# Apply changes
terraform apply -var-file=environments/drprod/terraform.tfvars -input=false
```

#### Step 3: Restore Database (15 min)

```bash
# List available backups in DR region
aws rds describe-db-cluster-automated-backups \
  --region us-east-1

# Restore from latest backup
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier pipeops-dr-postgres \
  --db-snapshot-identifier <snapshot-id> \
  --region us-east-1 \
  --db-subnet-group-name pipeops-drprod-db-subnet \
  --vpc-security-group-ids <sg-id>
```

#### Step 4: Configure Applications (10 min)

```bash
# Update kubeconfig
aws eks update-kubeconfig --region us-east-1 --name pipeops-drprod-eks

# Deploy applications
kubectl apply -k k8s-manifests/overlays/dr

# Or sync via ArgoCD
argocd app sync --all
```

#### Step 5: Update DNS (5 min)

```bash
# Option 1: Manual DNS update
# Update Route53 to point to DR ALB

# Option 2: Automatic failover (if configured)
# Health check triggers automatic failover
```

#### Step 6: Verify (5 min)

```bash
# Check all pods
kubectl get pods --all-namespaces

# Check services
kubectl get svc,ingress --all-namespaces

# Test application
curl https://app.example.com/health
```

---

### Scenario 2: Database Corruption

**Timeline**: 15-30 minutes

#### Point-in-Time Recovery

```bash
# 1. Identify corruption time
# Review CloudWatch logs/application logs

# 2. Stop application writes
kubectl scale deployment myapp --replicas=0 -n production

# 3. Restore to point before corruption
aws rds restore-db-instance-to-point-in-time \
  --source-db-instance-identifier pipeops-prod-postgres \
  --target-db-instance-identifier pipeops-prod-postgres-restored \
  --restore-time 2024-01-15T10:00:00Z \
  --region us-west-2

# 4. Wait for restore (check status)
aws rds describe-db-instances \
  --db-instance-identifier pipeops-prod-postgres-restored

# 5. Update application endpoint
# Update secrets/config to point to restored DB

# 6. Resume application
kubectl scale deployment myapp --replicas=3 -n production
```

---

### Scenario 3: Application Rollback

**Timeline**: 5 minutes

#### Via ArgoCD

```bash
# List application history
argocd app history myapp

# Rollback to previous version
argocd app rollback myapp <revision>

# Or sync to specific Git commit
argocd app sync myapp --revision <commit-sha>
```

#### Via kubectl

```bash
# Rollback deployment
kubectl rollout undo deployment/myapp -n production

# Check rollout status
kubectl rollout status deployment/myapp -n production
```

---

## DR Testing

### Quarterly DR Drill

**Checklist**:

- [ ] Scale up DR cluster
- [ ] Restore database from backup
- [ ] Deploy test application
- [ ] Verify connectivity
- [ ] Test failover routing
- [ ] Document results
- [ ] Scale down DR cluster

### Test Script

Variables are supplied only via `terraform.tfvars` (declarative). Set `dr_desired_capacity` in `environments/drprod/terraform.tfvars` before apply; do not use `-var` overrides.

```bash
#!/bin/bash
# dr-drill.sh

echo "Starting DR Drill..."

# 1. Scale up DR: set dr_desired_capacity = 4 in environments/drprod/terraform.tfvars
cd dr-infrastructure
terraform apply -var-file=environments/drprod/terraform.tfvars -input=false -auto-approve

# 2. Connect to DR cluster
aws eks update-kubeconfig --region us-east-1 --name pipeops-drprod-eks

# 3. Deploy test app
kubectl apply -f tests/dr-test-app.yaml

# 4. Verify
kubectl wait --for=condition=available deployment/dr-test -n default --timeout=300s
curl http://$(kubectl get svc dr-test -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')/health

# 5. Cleanup
kubectl delete -f tests/dr-test-app.yaml

# 6. Scale down: set dr_desired_capacity = 2 in environments/drprod/terraform.tfvars, then:
terraform apply -var-file=environments/drprod/terraform.tfvars -input=false -auto-approve

echo "DR Drill Complete"
```

---

## Monitoring DR Readiness

### Key Metrics

| Metric | Alert Threshold |
|--------|-----------------|
| RDS Backup Age | > 24 hours |
| ECR Replication Lag | > 1 hour |
| DR Cluster Health | Unhealthy |
| Cross-Region Backup Status | Failed |

### CloudWatch Alarms

```bash
# Check RDS backup status
aws rds describe-db-instance-automated-backups \
  --region us-east-1 \
  --filters Name=db-instance-id,Values=pipeops-prod-postgres

# Check ECR replication
aws ecr describe-registry --region us-east-1
```

---

## Cost Summary

| Component | Monthly Cost |
|-----------|--------------|
| DR EKS Cluster (Standby) | ~$243 |
| DR NAT Gateway (single) | ~$32 |
| Cross-Region Backup Storage | ~$20 |
| ECR Replication Transfer | ~$10 |
| **Total DR Cost** | **~$305/month** |

---

## Related Documentation

- [DR Infrastructure README](../dr-infrastructure/README.md)
- [RDS Module README](../modules/rds/README.md)
- [AWS Backup Guide](./AWS_BACKUP_GUIDE.md)
- [Global Infrastructure](../global-infrastructure/README.md)
