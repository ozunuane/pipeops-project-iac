# RDS Complete Guide - High Availability & Disaster Recovery

**Complete reference for RDS setup, configuration, and disaster recovery procedures**

---

## 📋 Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Configuration Options](#configuration-options)
4. [Deployment Guide](#deployment-guide)
5. [Disaster Recovery](#disaster-recovery)
6. [Monitoring & Alerts](#monitoring--alerts)
7. [Cost Analysis](#cost-analysis)
8. [Maintenance & Operations](#maintenance--operations)
9. [Troubleshooting](#troubleshooting)
10. [Quick Reference](#quick-reference)

---

## Overview

### What You Get

Your RDS infrastructure provides **three tiers** of protection:

```
┌─────────────────────────────────────────────────────────────────────┐
│                        PROTECTION TIERS                             │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  Tier 1: Multi-AZ (Single Region)                                 │
│  ├─ Primary Region: us-west-2                                      │
│  ├─ Multi-AZ with automatic failover                               │
│  ├─ Read replicas for scaling                                      │
│  └─ Protects: AZ failures, instance failures                       │
│                                                                     │
│  Tier 2: + Cross-Region Backups                                    │
│  ├─ Tier 1 features +                                              │
│  ├─ Automated backup replication to us-east-1                      │
│  └─ Protects: + Regional failures (slow recovery)                  │
│                                                                     │
│  Tier 3: + Multi-Region DR Replica                                 │
│  ├─ Tier 2 features +                                              │
│  ├─ Live DR replica in us-east-1 (Multi-AZ)                       │
│  ├─ 5-10 second replication lag                                    │
│  └─ Protects: + Regional failures (fast recovery)                  │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Key Capabilities

| Capability | Tier 1 | Tier 2 | Tier 3 |
|------------|--------|--------|--------|
| **Multi-AZ (Primary)** | ✅ Yes | ✅ Yes | ✅ Yes |
| **Read Replicas** | ✅ 2 replicas | ✅ 2 replicas | ✅ 2 replicas |
| **AZ Failure RPO** | 0 sec | 0 sec | 0 sec |
| **AZ Failure RTO** | 1-2 min | 1-2 min | 1-2 min |
| **Region Failure RPO** | N/A | 5 min | 5-10 sec |
| **Region Failure RTO** | N/A | 2-4 hrs | 15-30 min |
| **Monthly Cost** | $1,196 | $1,270 | $1,798 |
| **Use Case** | Standard | Good | Enterprise |

---

## Architecture

### Tier 1: Multi-AZ (Single Region)

```
AWS Region: us-west-2
┌──────────────────────────────────────────────────────────┐
│  AZ: us-west-2a    AZ: us-west-2b    AZ: us-west-2c     │
│  ┌────────────┐    ┌────────────┐    ┌────────────┐    │
│  │  Primary   │◄──►│  Standby   │    │ Replica-1  │    │
│  │    RDS     │    │    RDS     │    │    RDS     │    │
│  │            │    │  (Passive) │    │ (Read-Only)│    │
│  └────────────┘    └────────────┘    └────────────┘    │
│       │                                      │           │
│       │ Synchronous                 Async   │           │
│       │ Replication                         │           │
│       │                             ┌────────────┐      │
│       │                             │ Replica-2  │      │
│       │                             │    RDS     │      │
│       │                             │ (Read-Only)│      │
│       │                             └────────────┘      │
└──────────────────────────────────────────────────────────┘

✅ RPO: 0 seconds (AZ failure)
✅ RTO: 1-2 minutes (automatic)
❌ No region failure protection
```

### Tier 3: Multi-Region DR

```
PRIMARY REGION: us-west-2                    DR REGION: us-east-1
┌─────────────────────────────────┐          ┌─────────────────────────────────┐
│  AZ-A      AZ-B      AZ-C       │          │  AZ-A      AZ-B                 │
│  ┌────┐    ┌────┐    ┌────┐    │          │  ┌────┐    ┌────┐              │
│  │Pri │◄──►│Stby│    │Rep1│    │  Async   │  │ DR │◄──►│ DR │              │
│  │mary│    │    │    │    │    │  Replic  │  │Prim│    │Stby│              │
│  └────┘    └────┘    └────┘    │  ──────► │  └────┘    └────┘              │
│                 ┌────┐          │          │                                 │
│                 │Rep2│          │          │  Multi-AZ in DR region          │
│                 └────┘          │          │  Can be promoted to primary     │
└─────────────────────────────────┘          └─────────────────────────────────┘

✅ RPO: 0 sec (AZ), 5-10 sec (region)
✅ RTO: 1-2 min (AZ), 15-30 min (region)
✅ Complete regional disaster protection
```

### Components

1. **Primary Multi-AZ Instance**
   - Active-passive setup
   - Synchronous replication
   - Automatic failover in 1-2 minutes
   - Zero data loss for AZ failures

2. **Read Replicas (Same Region)**
   - 2 replicas across different AZs
   - Asynchronous replication
   - Distribute read traffic
   - Can be promoted if needed

3. **DR Replica (Different Region)** - Optional
   - Multi-AZ in DR region
   - Asynchronous cross-region replication
   - 5-10 second lag (normal)
   - Manual promotion for regional disasters

4. **Backup Systems**
   - Automated daily backups (30-day retention)
   - Point-in-time recovery
   - Optional cross-region backup replication
   - Encrypted with KMS

---

## Configuration Options

### Environment Configurations

#### Development (Cost-Optimized)
```hcl
# environments/dev/terraform.tfvars

db_instance_class = "db.t4g.medium"
db_allocated_storage = 50
db_backup_retention = 7

db_multi_az = false                    # Single-AZ
db_create_read_replica = false         # No replicas
db_enable_cross_region_dr = false      # No DR
db_enable_cross_region_backups = false # No backup replication

# Cost: ~$150/month
# Use for: Development, testing
```

#### Staging (Balanced)
```hcl
# environments/staging/terraform.tfvars

db_instance_class = "db.r6g.large"
db_allocated_storage = 100
db_backup_retention = 14

db_multi_az = true                     # Multi-AZ enabled
db_create_read_replica = false         # No replicas (cost saving)
db_enable_cross_region_dr = false      # No DR
db_enable_cross_region_backups = false # No backup replication

# Cost: ~$650/month
# Use for: QA, staging, pre-production testing
```

#### Production - Tier 1 (Standard)
```hcl
# environments/prod/terraform.tfvars

db_instance_class = "db.r6g.xlarge"
db_allocated_storage = 200
db_backup_retention = 30

db_multi_az = true                     # Multi-AZ enabled
db_create_read_replica = true          # 2 read replicas
db_read_replica_count = 2
db_enable_cross_region_dr = false      # No DR
db_enable_cross_region_backups = false # No backup replication

# Cost: ~$1,196/month
# Use for: Standard production applications
# RPO: 0 sec (AZ), N/A (region)
# RTO: 1-2 min (AZ), Hours (region)
```

#### Production - Tier 2 (+ Backups)
```hcl
db_multi_az = true
db_create_read_replica = true
db_read_replica_count = 2
db_enable_cross_region_dr = false      # No live DR
db_enable_cross_region_backups = true  # Backup replication ✅

# Cost: ~$1,270/month (+6%)
# Use for: Important applications with backup DR
# RPO: 0 sec (AZ), 5 min (region)
# RTO: 1-2 min (AZ), 2-4 hrs (region)
```

#### Production - Tier 3 (Full DR)
```hcl
db_multi_az = true
db_create_read_replica = true
db_read_replica_count = 2
db_enable_cross_region_dr = true       # Live DR replica ✅
db_dr_multi_az = true                  # Multi-AZ in DR ✅
db_enable_cross_region_backups = true  # Backup replication ✅

dr_region = "us-east-1"
db_dr_instance_class = "db.r6g.xlarge"

# Cost: ~$1,798/month (+50%)
# Use for: Mission-critical applications
# RPO: 0 sec (AZ), 5-10 sec (region)
# RTO: 1-2 min (AZ), 15-30 min (region)
```

### Configuration Variables

#### Required Variables
```hcl
project_name = "pipeops"
environment = "prod"
region = "us-west-2"

db_instance_class = "db.r6g.xlarge"
db_allocated_storage = 200
db_backup_retention = 30
```

#### High Availability
```hcl
db_multi_az = true                     # Enable Multi-AZ
db_create_read_replica = true          # Enable read replicas
db_read_replica_count = 2              # Number of replicas
db_read_replica_instance_class = "db.r6g.large"
db_replica_availability_zones = ["us-west-2b", "us-west-2c"]
```

#### Multi-Region DR
```hcl
dr_region = "us-east-1"
db_enable_cross_region_dr = true
db_dr_instance_class = "db.r6g.xlarge"
db_dr_multi_az = true
db_enable_cross_region_backups = true
```

#### Performance & Monitoring
```hcl
db_iops = 3000                         # Provisioned IOPS
db_monitoring_sns_topic_arn = "arn:aws:sns:..."
db_apply_immediately = false           # Use maintenance window
```

---

## Deployment Guide

### Prerequisites

1. **AWS CLI** configured with appropriate permissions
2. **Terraform** >= 1.5
3. **S3 backend** for state storage (run `./scripts/setup-prerequisites.sh`)
4. **SNS topic** for alerts (optional but recommended)

### Step 1: Create SNS Topic for Alerts

```bash
# Create SNS topic
aws sns create-topic --name pipeops-rds-prod-alerts --region us-west-2

# Get ARN
SNS_ARN=$(aws sns list-topics \
  --query 'Topics[?contains(TopicArn, `pipeops-rds-prod-alerts`)].TopicArn' \
  --output text)

# Subscribe your email
aws sns subscribe \
  --topic-arn $SNS_ARN \
  --protocol email \
  --notification-endpoint your-email@example.com

# Confirm subscription via email
```

### Step 2: Configure Terraform

Variables are **declarative only** via `terraform.tfvars` (no `-var` overrides). Prefer the Makefile with `ENV=prod` so `-var-file=environments/prod/terraform.tfvars` is used.

```bash
# Choose your environment
cd /path/to/pipeops-project-iac

# Option A: Use existing environment config
cp environments/prod/terraform.tfvars terraform.tfvars

# Option B: Copy and customize example
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars
```

### Step 3: Update Configuration

Edit `terraform.tfvars`:

```hcl
# Add SNS topic ARN
db_monitoring_sns_topic_arn = "arn:aws:sns:us-west-2:ACCOUNT:pipeops-rds-prod-alerts"

# Choose DR tier (Tier 1, 2, or 3)
# See "Configuration Options" section above
```

### Step 4: Initialize and Deploy

```bash
# Initialize Terraform (recommended: use Makefile)
make init ENV=prod
# Or: terraform init -backend-config=environments/prod/backend.conf -reconfigure

# Review plan (uses -var-file=environments/prod/terraform.tfvars only)
make plan ENV=prod
# Or: terraform plan -var-file=environments/prod/terraform.tfvars -no-color -input=false

# Deploy (takes 1-2 hours with DR)
make apply ENV=prod
# Or: terraform apply -var-file=environments/prod/terraform.tfvars -input=false

# Verify deployment
terraform output rds_endpoint
terraform output rds_multi_az_enabled
terraform output rds_dr_enabled  # If using Tier 3
```

### Step 5: Verify Setup

```bash
# Check RDS instance
aws rds describe-db-instances \
  --db-instance-identifier pipeops-prod-postgres \
  --query 'DBInstances[0].[DBInstanceStatus,MultiAZ,AvailabilityZone]'

# Test connection
ENDPOINT=$(terraform output -raw rds_endpoint | cut -d: -f1)
psql -h $ENDPOINT -U postgres -d app -c "SELECT version();"

# Verify CloudWatch alarms
aws cloudwatch describe-alarms \
  --alarm-name-prefix "pipeops-prod-rds" \
  --query 'MetricAlarms[*].[AlarmName,StateValue]' \
  --output table
```

---

## Disaster Recovery

### DR Scenarios & Procedures

#### Scenario 1: AZ Failure (Automatic)

**What Happens:**
- Multi-AZ automatically detects failure
- DNS endpoint switches to standby (1-2 minutes)
- Application reconnects automatically

**Your Action:**
- Monitor CloudWatch for failover completion
- Verify application connectivity
- Review RDS events

**No manual intervention required!**

```bash
# Monitor failover
aws rds describe-events \
  --source-identifier pipeops-prod-postgres \
  --duration 30

# Verify new AZ
aws rds describe-db-instances \
  --db-instance-identifier pipeops-prod-postgres \
  --query 'DBInstances[0].AvailabilityZone'
```

#### Scenario 2: Planned Regional Failover (Tier 3)

**Use Case:** Planned maintenance or regional migration

```bash
# 1. Enable application maintenance mode (stop writes)

# 2. Verify replication lag is minimal
aws cloudwatch get-metric-statistics \
  --region us-east-1 \
  --namespace AWS/RDS \
  --metric-name ReplicaLag \
  --dimensions Name=DBInstanceIdentifier,Value=pipeops-prod-postgres-dr \
  --start-time $(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 \
  --statistics Average

# 3. Promote DR replica (takes 15-20 minutes)
aws rds promote-read-replica \
  --region us-east-1 \
  --db-instance-identifier pipeops-prod-postgres-dr

# 4. Wait for promotion
aws rds wait db-instance-available \
  --region us-east-1 \
  --db-instance-identifier pipeops-prod-postgres-dr

# 5. Update application to use DR endpoint
DR_ENDPOINT=$(terraform output -raw rds_dr_endpoint)
# Update DNS or application config

# 6. Resume application operations
```

**Timeline:**
- Preparation: 5 minutes
- Promotion: 15-20 minutes
- **Total Downtime: 20-25 minutes**
- **Data Loss: 0 seconds** (if lag was zero)

#### Scenario 3: Emergency Regional Failure (Tier 3)

**Use Case:** Primary region completely unavailable

```bash
# 1. Verify primary region is unreachable
ping rds.us-west-2.amazonaws.com

# 2. IMMEDIATELY promote DR replica (don't wait)
aws rds promote-read-replica \
  --region us-east-1 \
  --db-instance-identifier pipeops-prod-postgres-dr

# 3. Monitor promotion (check every 30 seconds)
watch -n 30 'aws rds describe-db-instances \
  --region us-east-1 \
  --db-instance-identifier pipeops-prod-postgres-dr \
  --query "DBInstances[0].DBInstanceStatus"'

# 4. Get new endpoint
DR_ENDPOINT=$(terraform output -raw rds_dr_endpoint)
echo "New primary: $DR_ENDPOINT"

# 5. Update application immediately
# Update DNS, connection strings, or load balancer

# 6. Verify connectivity
psql -h $DR_ENDPOINT -U postgres -d app -c "SELECT 1;"
```

**Expected Metrics:**
- **RTO: 15-30 minutes**
- **RPO: 5-10 seconds** (last replication lag)

#### Scenario 4: Restore from Backup (Tier 2)

**Use Case:** Both primary and DR compromised, or point-in-time restore needed

```bash
# 1. List available backups
aws rds describe-db-snapshots \
  --db-instance-identifier pipeops-prod-postgres

# 2. Restore from snapshot
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier pipeops-prod-postgres-restored \
  --db-snapshot-identifier <snapshot-id> \
  --db-instance-class db.r6g.xlarge \
  --multi-az

# 3. Wait for restore (20-40 minutes)
aws rds wait db-instance-available \
  --db-instance-identifier pipeops-prod-postgres-restored

# 4. Update application
RESTORED_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier pipeops-prod-postgres-restored \
  --query 'DBInstances[0].Endpoint.Address' --output text)
```

**Expected Metrics:**
- **RTO: 2-4 hours**
- **RPO: Up to 5 minutes**

### Testing DR

**Monthly DR Drill (Required):**

```bash
#!/bin/bash
# Monthly drill - test DR capabilities without affecting production

# 1. Create test snapshot in DR region
aws rds create-db-snapshot \
  --region us-east-1 \
  --db-instance-identifier pipeops-prod-postgres-dr \
  --db-snapshot-identifier dr-drill-$(date +%Y%m%d)

# 2. Restore to test instance
aws rds restore-db-instance-from-db-snapshot \
  --region us-east-1 \
  --db-instance-identifier pipeops-dr-drill-test \
  --db-snapshot-identifier dr-drill-$(date +%Y%m%d) \
  --db-instance-class db.t4g.large

# 3. Wait and test
sleep 900
psql -h $(aws rds describe-db-instances \
  --region us-east-1 \
  --db-instance-identifier pipeops-dr-drill-test \
  --query 'DBInstances[0].Endpoint.Address' --output text) \
  -U postgres -d app -c "SELECT COUNT(*) FROM your_table;"

# 4. Cleanup
aws rds delete-db-instance \
  --region us-east-1 \
  --db-instance-identifier pipeops-dr-drill-test \
  --skip-final-snapshot

echo "DR Drill completed successfully!"
```

---

## Monitoring & Alerts

### CloudWatch Alarms

The following alarms are automatically created:

| Alarm | Threshold | Action |
|-------|-----------|--------|
| **CPU Utilization** | > 80% for 10 min | SNS notification |
| **Freeable Memory** | < 1 GB for 10 min | SNS notification |
| **Free Storage** | < 10 GB | SNS notification |
| **Database Connections** | > 80 connections | SNS notification |
| **Read Latency** | > 100ms for 10 min | SNS notification |
| **Write Latency** | > 100ms for 10 min | SNS notification |
| **Burst Balance** | < 20% (gp3) | SNS notification |
| **Replica Lag** | > 1 second (same region) | SNS notification |
| **DR Replica Lag** | > 30 seconds (cross-region) | SNS notification |

### Key Metrics to Monitor

```bash
# Check replication lag (same region)
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name ReplicaLag \
  --dimensions Name=DBInstanceIdentifier,Value=pipeops-prod-postgres-replica-1 \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average,Maximum

# Check CPU utilization
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name CPUUtilization \
  --dimensions Name=DBInstanceIdentifier,Value=pipeops-prod-postgres \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average,Maximum

# Check connection count
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name DatabaseConnections \
  --dimensions Name=DBInstanceIdentifier,Value=pipeops-prod-postgres \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average,Maximum
```

### Dashboard Setup

Create a CloudWatch dashboard:

```bash
# Create dashboard JSON
cat > rds-dashboard.json << 'EOF'
{
  "widgets": [
    {
      "type": "metric",
      "properties": {
        "metrics": [
          ["AWS/RDS", "CPUUtilization", {"stat": "Average"}],
          [".", "DatabaseConnections"],
          [".", "FreeableMemory"],
          [".", "FreeStorageSpace"]
        ],
        "period": 300,
        "stat": "Average",
        "region": "us-west-2",
        "title": "RDS Overview"
      }
    }
  ]
}
EOF

# Create dashboard
aws cloudwatch put-dashboard \
  --dashboard-name pipeops-rds-prod \
  --dashboard-body file://rds-dashboard.json
```

---

## Cost Analysis

### Monthly Cost Breakdown

#### Tier 1: Multi-AZ + Read Replicas ($1,196/month)

```
Primary Region (us-west-2)
├─ Primary Instance (Multi-AZ, db.r6g.xlarge)
│  ├─ Primary: $298/month
│  └─ Standby: $298/month ...................... $596
│
├─ Read Replicas
│  ├─ Replica 1 (db.r6g.large): $149/month
│  └─ Replica 2 (db.r6g.large): $149/month ..... $298
│
├─ Storage (600 GB gp3, across 3 instances) ..... $69
├─ Provisioned IOPS (9000 total) ............... $40
├─ Automated Backups (300 GB) .................. $29
├─ Performance Insights ........................ $21
├─ Enhanced Monitoring ......................... $20
└─ Data Transfer ............................... $20
                                    ──────────────────
                                    TOTAL: $1,196/mo
```

#### Tier 2: + Cross-Region Backups ($1,270/month)

```
Tier 1 Cost .................................... $1,196
DR Region Additions:
├─ Backup Storage (300 GB) ..................... $29
└─ Cross-Region Transfer ....................... $45
                                    ──────────────────
                                    TOTAL: $1,270/mo
                                    DELTA: +$74 (+6%)
```

#### Tier 3: Full Multi-Region DR ($1,798/month)

```
Tier 1 Cost .................................... $1,196

DR Region (us-east-1)
├─ DR Instance (Multi-AZ, db.r6g.xlarge)
│  ├─ DR Primary: $298/month
│  └─ DR Standby: $298/month ................... $596
│
├─ Storage (200 GB gp3, mirrored) .............. $46
├─ Cross-Region Data Transfer .................. $40
├─ Backup Replication .......................... $29
└─ Performance Insights & Monitoring ........... $34
                                    ──────────────────
                                    TOTAL: $1,798/mo
                                    DELTA: +$602 (+50%)
```

### Cost by Environment

| Environment | Configuration | Monthly Cost | Annual Cost |
|-------------|--------------|--------------|-------------|
| **Development** | Single-AZ, t4g.medium | $150 | $1,800 |
| **Staging** | Multi-AZ, r6g.large | $650 | $7,800 |
| **Production (Tier 1)** | Multi-AZ + Replicas | $1,196 | $14,352 |
| **Production (Tier 2)** | Tier 1 + Backups | $1,270 | $15,240 |
| **Production (Tier 3)** | Full Multi-Region DR | $1,798 | $21,576 |

### ROI Analysis

**Tier 3 Investment**: $7,224/year additional cost over Tier 1

**Potential Losses Prevented:**
- **Downtime**: $10,000-100,000/hour (varies by business)
- **Data Loss**: $50,000-1,000,000/incident
- **Reputation**: Immeasurable
- **Compliance Fines**: $10,000-10,000,000

**Break-Even**: Preventing 1-2 hours of downtime per year

---

## Maintenance & Operations

### Routine Operations

#### Upgrade RDS Version

```bash
# Check available versions
aws rds describe-db-engine-versions \
  --engine postgres \
  --engine-version 15

# Upgrade (during maintenance window): set in terraform.tfvars (declarative; no -var)
# db_postgres_version = "15.5"
# Then apply:
terraform apply -var-file=environments/prod/terraform.tfvars -input=false
```

#### Scale Instance Size

```bash
# Update environments/<ENV>/terraform.tfvars (declarative; no -var)
db_instance_class = "db.r6g.2xlarge"

# Apply (minimal downtime with Multi-AZ)
make apply ENV=prod
# Or: terraform apply -var-file=environments/prod/terraform.tfvars -input=false
```

#### Add/Remove Read Replicas

```bash
# Update environments/<ENV>/terraform.tfvars
db_read_replica_count = 3  # Changed from 2

# Apply
make apply ENV=prod
# Or: terraform apply -var-file=environments/prod/terraform.tfvars -input=false
```

### Backup Management

```bash
# Create manual snapshot
aws rds create-db-snapshot \
  --db-instance-identifier pipeops-prod-postgres \
  --db-snapshot-identifier manual-backup-$(date +%Y%m%d-%H%M%S)

# List snapshots
aws rds describe-db-snapshots \
  --db-instance-identifier pipeops-prod-postgres

# Delete old snapshot
aws rds delete-db-snapshot \
  --db-snapshot-identifier <snapshot-id>

# Copy snapshot to another region
aws rds copy-db-snapshot \
  --source-db-snapshot-identifier arn:aws:rds:us-west-2:...:snapshot:... \
  --target-db-snapshot-identifier copied-backup \
  --region us-east-1
```

### Maintenance Windows

```bash
# Check current maintenance window
aws rds describe-db-instances \
  --db-instance-identifier pipeops-prod-postgres \
  --query 'DBInstances[0].PreferredMaintenanceWindow'

# Update maintenance window (via Terraform)
# Edit terraform.tfvars or main.tf, then apply
```

---

## Troubleshooting

### High Replication Lag

**Symptoms**: Replica lag > 10 seconds consistently

**Diagnosis**:
```bash
# Check primary write load
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name WriteIOPS \
  --dimensions Name=DBInstanceIdentifier,Value=pipeops-prod-postgres \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average,Maximum
```

**Solutions**:
1. Increase replica instance size
2. Increase IOPS on replicas
3. Reduce write load on primary
4. Check network connectivity

### High CPU Utilization

**Symptoms**: CPU > 80% consistently

**Diagnosis**:
```bash
# Enable Performance Insights (already enabled)
# Check slow queries in Performance Insights dashboard

# Or use pg_stat_statements
psql -h $ENDPOINT -U postgres -d app -c \
  "SELECT query, calls, mean_exec_time 
   FROM pg_stat_statements 
   ORDER BY mean_exec_time DESC 
   LIMIT 10;"
```

**Solutions**:
1. Optimize slow queries
2. Add indexes
3. Increase instance size
4. Use read replicas for read queries

### Connection Pool Exhaustion

**Symptoms**: "Too many connections" errors

**Diagnosis**:
```bash
# Check connection count
psql -h $ENDPOINT -U postgres -d app -c \
  "SELECT count(*) FROM pg_stat_activity;"

# Check max connections
psql -h $ENDPOINT -U postgres -d app -c \
  "SHOW max_connections;"
```

**Solutions**:
1. Implement connection pooling (PgBouncer)
2. Close idle connections
3. Increase instance size (more max_connections)
4. Review application connection management

### Failed Backups

**Symptoms**: Backup failures in CloudWatch

**Diagnosis**:
```bash
# Check RDS events
aws rds describe-events \
  --source-identifier pipeops-prod-postgres \
  --source-type db-instance \
  --duration 1440

# Check backup status
aws rds describe-db-snapshots \
  --db-instance-identifier pipeops-prod-postgres \
  --query 'DBSnapshots[0].[Status,SnapshotCreateTime]'
```

**Solutions**:
1. Check storage space
2. Verify IAM permissions
3. Check KMS key access
4. Contact AWS Support

### DR Replica Issues

**Symptoms**: High cross-region lag or replication stopped

**Diagnosis**:
```bash
# Check DR replica status
aws rds describe-db-instances \
  --region us-east-1 \
  --db-instance-identifier pipeops-prod-postgres-dr \
  --query 'DBInstances[0].[DBInstanceStatus,StatusInfos]'

# Check replication lag
aws cloudwatch get-metric-statistics \
  --region us-east-1 \
  --namespace AWS/RDS \
  --metric-name ReplicaLag \
  --dimensions Name=DBInstanceIdentifier,Value=pipeops-prod-postgres-dr \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average,Maximum
```

**Solutions**:
1. Check network connectivity between regions
2. Verify DR instance has sufficient IOPS
3. Increase DR instance size
4. Check for AWS service issues

---

## Quick Reference

### Terraform Outputs

```bash
# Primary endpoint
terraform output rds_endpoint

# Multi-AZ status
terraform output rds_multi_az_enabled

# Read replica endpoints
terraform output rds_read_replica_endpoints

# DR status (Tier 3)
terraform output rds_dr_enabled
terraform output rds_dr_endpoint

# Secrets Manager ARN
terraform output rds_secrets_manager_secret_arn
```

### Common Commands

```bash
# Configure kubectl
terraform output kubectl_config_command | bash

# Get database password
aws secretsmanager get-secret-value \
  --secret-id pipeops/prod/rds/credentials \
  --query SecretString --output text | jq -r '.password'

# Connect to database
psql -h $(terraform output -raw rds_endpoint | cut -d: -f1) \
  -U postgres -d app

# Test failover (Multi-AZ)
aws rds reboot-db-instance \
  --db-instance-identifier pipeops-prod-postgres \
  --force-failover

# Promote DR replica
aws rds promote-read-replica \
  --region us-east-1 \
  --db-instance-identifier pipeops-prod-postgres-dr
```

### Important Endpoints

```bash
# Primary (write + read)
pipeops-prod-postgres.xxxxx.us-west-2.rds.amazonaws.com:5432

# Read Replicas (read only)
pipeops-prod-postgres-replica-1.xxxxx.us-west-2.rds.amazonaws.com:5432
pipeops-prod-postgres-replica-2.xxxxx.us-west-2.rds.amazonaws.com:5432

# DR Replica (read only, can be promoted)
pipeops-prod-postgres-dr.xxxxx.us-east-1.rds.amazonaws.com:5432
```

### Decision Matrix

**Choose Tier 1 if:**
- ✅ Standard production application
- ✅ Budget-conscious
- ✅ Can tolerate hours for regional recovery
- ❌ Regional failures rare

**Choose Tier 2 if:**
- ✅ Need offsite backups
- ✅ Can tolerate 2-4 hour RTO
- ✅ Want regional protection without high cost
- ✅ Compliance requires backup DR

**Choose Tier 3 if:**
- ✅ Mission-critical application
- ✅ Cannot tolerate regional failures
- ✅ Need fast regional failover (15-30 min)
- ✅ Financial/healthcare/e-commerce
- ✅ 99.99% availability required

### Support Contacts

- **AWS Support**: https://console.aws.amazon.com/support/
- **RDS Documentation**: https://docs.aws.amazon.com/rds/
- **Internal Team**: [Your team contact]
- **On-Call**: [Your on-call process]

---

## Summary Checklist

### Initial Setup
- [ ] Choose DR tier (1, 2, or 3)
- [ ] Create SNS topic for alerts
- [ ] Update terraform.tfvars
- [ ] Run `terraform apply`
- [ ] Verify deployment
- [ ] Test connectivity

### Ongoing Operations
- [ ] Monitor CloudWatch alarms daily
- [ ] Review Performance Insights weekly
- [ ] Check backup status weekly
- [ ] Test DR procedures monthly
- [ ] Review costs monthly
- [ ] Update documentation quarterly

### Disaster Readiness
- [ ] DR runbook documented and accessible
- [ ] Team trained on DR procedures
- [ ] Emergency contacts updated
- [ ] Monthly DR drills scheduled
- [ ] RTO/RPO documented and communicated
- [ ] Stakeholder notification process defined

---

**Your RDS infrastructure is enterprise-ready! 🚀**

For questions or issues, refer to the troubleshooting section or contact your DevOps team.
