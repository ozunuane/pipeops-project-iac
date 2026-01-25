# AWS Backup for EKS - Configuration Guide

This document describes the AWS Backup configuration for EKS clusters in the pipeops infrastructure.

## Overview

AWS Backup provides automated, centralized backup management for EKS clusters. This includes:
- Kubernetes resources (Deployments, Services, ConfigMaps, Secrets, etc.)
- Persistent Volumes (EBS volumes)
- Cluster configuration

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        PRIMARY REGION (us-west-2)                       │
│                                                                         │
│  ┌─────────────────┐                    ┌─────────────────────────────┐│
│  │   EKS Cluster   │                    │      AWS Backup Vault       ││
│  │                 │   Daily @ 6 AM     │                             ││
│  │  - Deployments  │ ─────────────────► │  - Recovery Points          ││
│  │  - Services     │   Weekly @ Sunday  │  - Encrypted (KMS)          ││
│  │  - ConfigMaps   │                    │  - Lifecycle managed        ││
│  │  - Secrets      │                    │                             ││
│  │  - PVs (EBS)    │                    └─────────────────────────────┘│
│  └─────────────────┘                                 │                  │
│                                                      │ Cross-Region     │
│                                                      │ Copy (prod only) │
└──────────────────────────────────────────────────────│──────────────────┘
                                                       │
                                                       ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                        DR REGION (us-east-1)                            │
│                                                                         │
│                         ┌─────────────────────────────┐                 │
│                         │    DR Backup Vault          │                 │
│                         │                             │                 │
│                         │  - Replicated backups       │                 │
│                         │  - For disaster recovery    │                 │
│                         │  - Encrypted (KMS)          │                 │
│                         └─────────────────────────────┘                 │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

## Configuration

### Enable/Disable Backups

```hcl
# In terraform.tfvars
enable_eks_backup = true   # Set to false to disable
```

### Backup Schedule

```hcl
# Default: Daily at 6:00 AM UTC
backup_schedule = "cron(0 6 * * ? *)"

# Examples:
# Every 12 hours:      "cron(0 */12 * * ? *)"
# Daily at midnight:   "cron(0 0 * * ? *)"
# Daily at 2 AM UTC:   "cron(0 2 * * ? *)"
```

### Retention Policy

```hcl
# Number of days to keep backups
backup_retention_days = 35

# Move to cold storage after N days (0 = disabled, min 7 days if enabled)
backup_cold_storage_after = 0
```

### Cross-Region Copy (DR)

```hcl
# Enable backup replication to DR region
enable_backup_cross_region_copy = true
```

## Environment Settings

| Setting | Dev | Staging | Prod |
|---------|-----|---------|------|
| `enable_eks_backup` | `true` | `true` | `true` |
| `backup_schedule` | 6 AM UTC | 6 AM UTC | 6 AM UTC |
| `backup_retention_days` | 7 | 14 | 35 |
| `backup_cold_storage_after` | 0 | 0 | 0 |
| `enable_backup_cross_region_copy` | `false` | `false` | `true` |
| Weekly Backups | ✅ (90 days) | ✅ (90 days) | ✅ (90 days) |

## Backup Rules

### Daily Backup
- **Schedule**: Every day at 6:00 AM UTC
- **Retention**: Configurable (default 35 days for prod)
- **Cross-Region**: Optional (enabled for prod)

### Weekly Backup
- **Schedule**: Every Sunday at 6:00 AM UTC
- **Cold Storage**: After 30 days
- **Retention**: 90 days

## What Gets Backed Up

1. **EKS Cluster Configuration**
   - Cluster settings
   - Node group configurations
   - Add-ons

2. **Kubernetes Resources**
   - Namespaces
   - Deployments
   - StatefulSets
   - Services
   - ConfigMaps
   - Secrets
   - ServiceAccounts
   - RBAC (Roles, ClusterRoles, Bindings)
   - Custom Resources

3. **Persistent Volumes**
   - EBS volumes attached to pods
   - PersistentVolumeClaims

4. **Tagged Resources**
   - All resources with tag: `kubernetes.io/cluster/${cluster_name}=owned`

## Restore Procedures

### Restore from AWS Console

1. Navigate to **AWS Backup** → **Backup vaults**
2. Select the backup vault (e.g., `pipeops-prod-eks-backup-vault`)
3. Choose the recovery point to restore
4. Click **Restore**
5. Select restore options:
   - Restore to existing cluster
   - Restore to new cluster
6. Click **Restore backup**

### Restore using AWS CLI

```bash
# List recovery points
aws backup list-recovery-points-by-backup-vault \
  --backup-vault-name pipeops-prod-eks-backup-vault \
  --region us-west-2

# Start restore job
aws backup start-restore-job \
  --recovery-point-arn arn:aws:backup:us-west-2:ACCOUNT:recovery-point:RECOVERY_ID \
  --iam-role-arn arn:aws:iam::ACCOUNT:role/pipeops-prod-aws-backup-role \
  --metadata '{"restoreAsNewCluster":"false"}' \
  --region us-west-2
```

### Restore from DR Region

If primary region is unavailable:

```bash
# List recovery points in DR vault
aws backup list-recovery-points-by-backup-vault \
  --backup-vault-name pipeops-prod-eks-backup-vault-dr \
  --region us-east-1

# Restore in DR region
aws backup start-restore-job \
  --recovery-point-arn arn:aws:backup:us-east-1:ACCOUNT:recovery-point:RECOVERY_ID \
  --iam-role-arn arn:aws:iam::ACCOUNT:role/pipeops-prod-aws-backup-role \
  --metadata '{"restoreAsNewCluster":"true"}' \
  --region us-east-1
```

## Monitoring

### CloudWatch Metrics

AWS Backup publishes metrics to CloudWatch:
- `NumberOfBackupJobsCompleted`
- `NumberOfBackupJobsFailed`
- `NumberOfRestoreJobsCompleted`

### Alerts (Recommended)

Create CloudWatch alarms for:
```hcl
# Example: Alert on backup job failures
resource "aws_cloudwatch_metric_alarm" "backup_failed" {
  alarm_name          = "eks-backup-job-failed"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "NumberOfBackupJobsFailed"
  namespace           = "AWS/Backup"
  period              = 86400  # 24 hours
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "EKS backup job failed"
}
```

## Terraform Resources

The backup infrastructure consists of:

| Resource | Purpose |
|----------|---------|
| `aws_backup_vault.eks` | Primary backup vault |
| `aws_backup_vault.eks_dr` | DR backup vault (cross-region) |
| `aws_backup_plan.eks_daily` | Backup schedule and rules |
| `aws_backup_selection.eks` | What to backup |
| `aws_kms_key.backup` | Encryption key for backups |
| `aws_iam_role.backup` | IAM role for backup service |

## Cost Considerations

### Pricing Factors
- **Warm Storage**: $0.05 per GB-month
- **Cold Storage**: $0.01 per GB-month (min 90 days)
- **Restore**: $0.02 per GB
- **Cross-Region Copy**: Data transfer charges apply

### Cost Optimization Tips
1. Set appropriate retention periods per environment
2. Use cold storage for long-term backups (prod weekly)
3. Disable cross-region copy for non-prod environments
4. Consider disabling backups for dev if not required

## Troubleshooting

### Backup Job Failed

```bash
# Check backup job status
aws backup list-backup-jobs \
  --by-backup-vault-name pipeops-prod-eks-backup-vault \
  --by-state FAILED \
  --region us-west-2
```

### Permission Issues

Ensure the backup IAM role has:
- `AWSBackupServiceRolePolicyForBackup`
- `AWSBackupServiceRolePolicyForRestores`
- EKS describe permissions
- KMS encrypt/decrypt permissions

### Cross-Region Copy Failed

Check:
1. DR backup vault exists
2. KMS key in DR region is accessible
3. IAM role has cross-region permissions

## Related Documentation

- [AWS Backup for EKS](https://docs.aws.amazon.com/aws-backup/latest/devguide/eks-backups.html)
- [Backup Scheduling](https://docs.aws.amazon.com/aws-backup/latest/devguide/schedules.html)
- [Cross-Region Backup](https://docs.aws.amazon.com/aws-backup/latest/devguide/cross-region-backup.html)
