# Backup and Restore

Procedures for EKS and RDS backup management and restoration.

## Backup Overview

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              BACKUP ARCHITECTURE                                 │
│                                                                                 │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                         EKS BACKUPS (AWS Backup)                         │   │
│  │                                                                           │   │
│  │  Daily 6 AM UTC ────▶ Backup Vault (Primary) ────▶ DR Vault (us-east-1) │   │
│  │  Weekly Sunday  ────▶ Backup Vault (Primary) ────▶ DR Vault (us-east-1) │   │
│  │                                                                           │   │
│  │  Includes: K8s resources, EBS volumes, cluster configuration             │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                 │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                         RDS BACKUPS (Automated)                          │   │
│  │                                                                           │   │
│  │  Daily snapshots ────▶ Primary Region ────▶ DR Region (cross-region)    │   │
│  │  Transaction logs ────▶ Every 5 minutes (for PITR)                       │   │
│  │                                                                           │   │
│  │  Retention: 30 days (prod), 14 days (staging), 7 days (dev)              │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                 │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                        TERRAFORM STATE (S3)                              │   │
│  │                                                                           │   │
│  │  Versioned S3 bucket with lifecycle policies                             │   │
│  │  Encrypted with KMS                                                      │   │
│  │  State locking via DynamoDB                                              │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## EKS Backups

### Configuration

```hcl
# Enable EKS backups in terraform.tfvars
enable_eks_backup               = true
backup_schedule                 = "cron(0 6 * * ? *)"  # 6 AM UTC daily
backup_retention_days           = 35
backup_cold_storage_after       = 7   # Move to cold after 7 days
enable_backup_cross_region_copy = true  # Copy to DR region
backup_copy_retention_days      = 90
```

### What Gets Backed Up

| Resource | Included | Notes |
|----------|----------|-------|
| Kubernetes Resources | ✅ | Deployments, Services, ConfigMaps |
| Persistent Volumes | ✅ | EBS volumes via snapshots |
| Cluster Configuration | ✅ | EKS cluster settings |
| Secrets | ✅ | Encrypted in backup |
| Custom Resources | ✅ | ArgoCD apps, etc. |

### View Backups

```bash
# List backup vaults
aws backup list-backup-vaults --region us-west-2

# List recovery points
aws backup list-recovery-points-by-backup-vault \
  --backup-vault-name pipeops-prod-eks-backup-vault \
  --region us-west-2

# Get backup details
aws backup describe-recovery-point \
  --backup-vault-name pipeops-prod-eks-backup-vault \
  --recovery-point-arn <arn> \
  --region us-west-2
```

### Restore EKS

#### Via AWS Console

1. Go to **AWS Backup → Backup vaults**
2. Select vault: `pipeops-prod-eks-backup-vault`
3. Choose recovery point
4. Click **Restore**
5. Configure:
   - Restore to existing cluster or new cluster
   - Select namespaces to restore
   - Review and restore

#### Via CLI

```bash
# Start restore job
aws backup start-restore-job \
  --recovery-point-arn <backup-arn> \
  --iam-role-arn arn:aws:iam::ACCOUNT:role/pipeops-prod-eks-backup-role \
  --resource-type EKS \
  --metadata '{
    "clusterName": "pipeops-prod-eks",
    "restoreScope": "ALL"
  }' \
  --region us-west-2

# Monitor restore job
aws backup describe-restore-job --restore-job-id <job-id> --region us-west-2
```

---

## RDS Backups

### Configuration

```hcl
# RDS backup settings in terraform.tfvars
db_backup_retention            = 30
db_backup_window              = "03:00-04:00"  # UTC
db_enable_cross_region_backups = true
dr_region                      = "us-east-1"
```

### Automated Backups

- **Daily snapshots**: During backup window
- **Transaction logs**: Every 5 minutes
- **Retention**: 30 days (configurable)
- **Cross-region**: Replicated to us-east-1

### View Backups

```bash
# List automated backups
aws rds describe-db-snapshots \
  --db-instance-identifier pipeops-prod-postgres \
  --snapshot-type automated \
  --region us-west-2

# List cross-region backups
aws rds describe-db-instance-automated-backups \
  --region us-east-1 \
  --db-instance-automated-backups-arn <arn>
```

### Restore RDS

#### From Snapshot

```bash
# 1. List available snapshots
aws rds describe-db-snapshots \
  --db-instance-identifier pipeops-prod-postgres \
  --region us-west-2

# 2. Restore from snapshot
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier pipeops-prod-postgres-restored \
  --db-snapshot-identifier rds:pipeops-prod-postgres-2024-01-15-03-00 \
  --db-subnet-group-name pipeops-prod-db-subnet \
  --vpc-security-group-ids sg-xxxxxxxx \
  --region us-west-2

# 3. Wait for restore
aws rds wait db-instance-available \
  --db-instance-identifier pipeops-prod-postgres-restored \
  --region us-west-2
```

#### Point-in-Time Recovery

```bash
# Restore to specific time
aws rds restore-db-instance-to-point-in-time \
  --source-db-instance-identifier pipeops-prod-postgres \
  --target-db-instance-identifier pipeops-prod-postgres-pitr \
  --restore-time 2024-01-15T10:30:00Z \
  --db-subnet-group-name pipeops-prod-db-subnet \
  --vpc-security-group-ids sg-xxxxxxxx \
  --region us-west-2

# Or restore to latest restorable time
aws rds restore-db-instance-to-point-in-time \
  --source-db-instance-identifier pipeops-prod-postgres \
  --target-db-instance-identifier pipeops-prod-postgres-latest \
  --use-latest-restorable-time \
  --region us-west-2
```

#### Restore in DR Region

```bash
# Restore from replicated backup in DR region
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier pipeops-dr-postgres \
  --db-snapshot-identifier <dr-snapshot-id> \
  --db-subnet-group-name pipeops-drprod-db-subnet \
  --vpc-security-group-ids <dr-sg-id> \
  --region us-east-1
```

---

## Terraform State Backup

### S3 Versioning

State files are versioned in S3:

```bash
# List state versions
aws s3api list-object-versions \
  --bucket pipeops-prod-terraform-state \
  --prefix prod/terraform.tfstate

# Restore previous version
aws s3api copy-object \
  --bucket pipeops-prod-terraform-state \
  --copy-source pipeops-prod-terraform-state/prod/terraform.tfstate?versionId=<version-id> \
  --key prod/terraform.tfstate
```

### Manual State Backup

```bash
# Download current state
terraform state pull > terraform.tfstate.backup

# Push restored state
terraform state push terraform.tfstate.backup
```

---

## Backup Verification

### Weekly Verification Checklist

- [ ] EKS backup completed successfully
- [ ] RDS snapshot available
- [ ] Cross-region replication working
- [ ] Backup retention policy applied
- [ ] No failed backup jobs

### Verification Commands

```bash
# Check EKS backup job status
aws backup list-backup-jobs \
  --by-state COMPLETED \
  --by-backup-vault-name pipeops-prod-eks-backup-vault \
  --region us-west-2

# Check RDS backup status
aws rds describe-db-instances \
  --db-instance-identifier pipeops-prod-postgres \
  --query 'DBInstances[0].LatestRestorableTime' \
  --region us-west-2

# Check cross-region backup
aws rds describe-db-instance-automated-backups \
  --region us-east-1 \
  --query 'DBInstanceAutomatedBackups[*].[DBInstanceIdentifier,RestoreWindow]'
```

---

## Backup Retention

| Environment | EKS | RDS | Cold Storage |
|-------------|-----|-----|--------------|
| Dev | 7 days | 7 days | N/A |
| Staging | 14 days | 14 days | N/A |
| Prod | 35 days | 30 days | After 7 days |
| Prod (DR) | 90 days | 30 days | After 7 days |

---

## Cost Considerations

| Backup Type | Cost |
|-------------|------|
| EKS Backup (warm) | $0.05/GB/month |
| EKS Backup (cold) | $0.01/GB/month |
| RDS Snapshot | $0.095/GB/month |
| Cross-region transfer | $0.02/GB |

**Estimated Monthly Cost** (100GB data):
- Primary backups: ~$10
- Cross-region copies: ~$5
- **Total**: ~$15/month

---

## Troubleshooting

### Backup Failed

```bash
# Check backup job details
aws backup describe-backup-job --backup-job-id <job-id> --region us-west-2

# Common issues:
# - IAM role permissions
# - KMS key access
# - Resource tags missing
```

### Restore Failed

```bash
# Check restore job details
aws backup describe-restore-job --restore-job-id <job-id> --region us-west-2

# Common issues:
# - Insufficient capacity
# - Security group not accessible
# - Subnet group doesn't exist
```

### Cross-Region Backup Not Working

```bash
# Check KMS key policy allows cross-region
aws kms describe-key --key-id <dr-key-id> --region us-east-1

# Ensure DR KMS key is properly configured
terraform output dr_kms_key_arn
```

---

## Related Documentation

- [AWS Backup Guide](./AWS_BACKUP_GUIDE.md)
- [Disaster Recovery](./DISASTER_RECOVERY.md)
- [RDS Module](../modules/rds/README.md)
