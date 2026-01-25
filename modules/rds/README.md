# RDS Module

Production PostgreSQL database with Multi-AZ, read replicas, and cross-region disaster recovery.

## Architecture

```
┌───────────────────────────────────────────────────────────────────────────────────┐
│                           PRIMARY REGION (us-west-2)                               │
│                                                                                   │
│  ┌─────────────────────────────────────────────────────────────────────────────┐ │
│  │                            RDS PostgreSQL                                    │ │
│  │                                                                             │ │
│  │  ┌─────────────────┐      Sync        ┌─────────────────┐                  │ │
│  │  │   PRIMARY       │ ◄──────────────► │   STANDBY       │                  │ │
│  │  │   (us-west-2a)  │    Replication   │   (us-west-2b)  │                  │ │
│  │  │                 │                  │   (Multi-AZ)    │                  │ │
│  │  └─────────────────┘                  └─────────────────┘                  │ │
│  │           │                                                                 │ │
│  │           │ Async Replication                                               │ │
│  │           ▼                                                                 │ │
│  │  ┌─────────────────┐                                                       │ │
│  │  │  READ REPLICA   │  (Optional, for read scaling)                         │ │
│  │  │  (us-west-2c)   │                                                       │ │
│  │  └─────────────────┘                                                       │ │
│  │                                                                             │ │
│  └─────────────────────────────────────────────────────────────────────────────┘ │
│                                      │                                            │
│                     Cross-Region Backup Replication                               │
│                                      ▼                                            │
└───────────────────────────────────────────────────────────────────────────────────┘
                                       │
                                       │
┌───────────────────────────────────────────────────────────────────────────────────┐
│                              DR REGION (us-east-1)                                 │
│                                                                                   │
│  ┌─────────────────────────────────────────────────────────────────────────────┐ │
│  │                         Automated Backups                                    │ │
│  │  ┌─────────────────┐                                                        │ │
│  │  │  Backup Copies  │  (Encrypted with DR KMS key)                           │ │
│  │  │  (us-east-1)    │                                                        │ │
│  │  └─────────────────┘                                                        │ │
│  └─────────────────────────────────────────────────────────────────────────────┘ │
│                                                                                   │
└───────────────────────────────────────────────────────────────────────────────────┘
```

## Features

| Feature | Description |
|---------|-------------|
| **Multi-AZ** | Synchronous replication with automatic failover |
| **Read Replicas** | Async replicas for read scaling |
| **Cross-Region Backups** | Automated backup replication to DR region |
| **Encryption** | KMS encryption at rest and in transit |
| **Monitoring** | CloudWatch metrics and alarms |
| **Secrets Manager** | Automatic credential rotation |

## Usage

```hcl
module "rds" {
  source = "./modules/rds"

  project_name = "pipeops"
  environment  = "prod"
  
  # Instance configuration
  instance_class      = "db.r6g.large"
  allocated_storage   = 400
  postgres_version    = "16.6"
  
  # Network
  vpc_id               = module.vpc.vpc_id
  db_subnet_group_name = module.vpc.database_subnet_group_name
  allowed_security_groups = [module.eks.node_security_group_id]
  
  # High Availability
  multi_az              = true
  create_read_replica   = true
  read_replica_count    = 1
  
  # Backup & DR
  backup_retention_period     = 30
  enable_cross_region_backups = true
  dr_region                   = "us-east-1"
  
  # Monitoring
  enable_performance_insights = true
  monitoring_interval         = 60
  
  tags = {
    Environment = "prod"
    ManagedBy   = "terraform"
  }
}
```

## Variables

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `project_name` | Project name | `string` | - | yes |
| `environment` | Environment | `string` | - | yes |
| `instance_class` | RDS instance class | `string` | `"db.r6g.large"` | no |
| `allocated_storage` | Storage in GB | `number` | `100` | no |
| `postgres_version` | PostgreSQL version | `string` | `"16.6"` | no |
| `multi_az` | Enable Multi-AZ | `bool` | `true` | no |
| `create_read_replica` | Create read replica | `bool` | `false` | no |
| `read_replica_count` | Number of read replicas | `number` | `0` | no |
| `backup_retention_period` | Backup retention days | `number` | `30` | no |
| `enable_cross_region_backups` | Enable cross-region backups | `bool` | `false` | no |
| `dr_region` | DR region for backups | `string` | `"us-east-1"` | no |

## Outputs

| Name | Description |
|------|-------------|
| `db_instance_endpoint` | RDS endpoint |
| `db_instance_id` | RDS instance ID |
| `db_instance_arn` | RDS instance ARN |
| `db_security_group_id` | Security group ID |
| `db_credentials_secret_arn` | Secrets Manager secret ARN |
| `dr_kms_key_arn` | KMS key ARN in DR region |
| `read_replica_endpoints` | Read replica endpoints |

## Recovery Objectives

| Scenario | RTO | RPO |
|----------|-----|-----|
| **AZ Failure** | 1-2 minutes | 0 (sync replication) |
| **Region Failure** | 30-60 minutes | Up to backup frequency |
| **Data Corruption** | Minutes | Point-in-time recovery |

## Connecting from EKS

### Using Secrets Manager

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: db-credentials
spec:
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: db-credentials
  data:
    - secretKey: DB_HOST
      remoteRef:
        key: pipeops/prod/rds/credentials
        property: endpoint
    - secretKey: DB_USER
      remoteRef:
        key: pipeops/prod/rds/credentials
        property: username
    - secretKey: DB_PASSWORD
      remoteRef:
        key: pipeops/prod/rds/credentials
        property: password
```

### Direct Connection

```bash
# Get credentials from Secrets Manager
aws secretsmanager get-secret-value \
  --secret-id pipeops/prod/rds/credentials \
  --query SecretString --output text | jq

# Connect using psql
psql -h <endpoint> -U postgres -d pipeops
```

## Disaster Recovery

### Cross-Region Backup Restore

```bash
# 1. List available backups in DR region
aws rds describe-db-cluster-automated-backups \
  --region us-east-1 \
  --db-instance-automated-backups-arn <backup-arn>

# 2. Restore from backup
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier pipeops-dr-postgres \
  --db-snapshot-identifier <snapshot-id> \
  --region us-east-1

# 3. Update application to use new endpoint
```

### Point-in-Time Recovery

```bash
# Restore to specific time
aws rds restore-db-instance-to-point-in-time \
  --source-db-instance-identifier pipeops-prod-postgres \
  --target-db-instance-identifier pipeops-prod-postgres-recovered \
  --restore-time 2024-01-15T10:00:00Z
```

## Monitoring

### Key Metrics

| Metric | Alert Threshold | Description |
|--------|-----------------|-------------|
| `CPUUtilization` | > 80% | CPU usage |
| `FreeStorageSpace` | < 10GB | Available storage |
| `DatabaseConnections` | > 90% max | Active connections |
| `ReplicaLag` | > 60 seconds | Replication delay |

### CloudWatch Alarms

```bash
# Check alarm status
aws cloudwatch describe-alarms \
  --alarm-name-prefix "pipeops-prod-rds"
```

## Cost Considerations

| Component | Estimated Cost |
|-----------|----------------|
| **db.r6g.large (Multi-AZ)** | ~$280/month |
| **400GB gp3 Storage** | ~$32/month |
| **Read Replica** | ~$140/month |
| **Cross-Region Backup** | ~$20/month |
| **Data Transfer** | Variable |

## Security

1. **Encryption**: KMS encryption for data at rest
2. **SSL/TLS**: Enforce encrypted connections
3. **Security Groups**: Restrict to EKS nodes only
4. **Secrets Manager**: Automatic credential rotation
5. **IAM Auth**: Optional database authentication
