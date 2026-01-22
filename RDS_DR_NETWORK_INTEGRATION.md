# 🔗 RDS DR Network Integration Guide

## Critical AWS RDS Limitation

**⚠️ RDS instances CANNOT change VPC/subnet after creation!**

Once an RDS instance (including read replicas) is created, you **cannot**:
- ❌ Move it to a different VPC
- ❌ Change the DB subnet group  
- ❌ Modify network configuration

The **only** way to change VPC is to create a snapshot and restore to a new instance.

## Solution: RDS DR Managed by DR Workspace

To ensure the RDS DR replica uses the DR VPC network, we manage it in the **DR workspace** instead of the primary workspace.

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│              PRIMARY WORKSPACE (us-west-2)                  │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  VPC: 10.0.0.0/16                                    │   │
│  │  ┌────────────┐  ┌────────────┐                      │   │
│  │  │ EKS Cluster│  │    RDS     │                      │   │
│  │  │  (Active)  │──│ (Primary)  │                      │   │
│  │  └────────────┘  └────────────┘                      │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                              │
                              │ Cross-Region Replication
                              ▼
┌─────────────────────────────────────────────────────────────┐
│               DR WORKSPACE (us-east-1)                      │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  VPC: 10.1.0.0/16                                    │   │
│  │  ┌────────────┐  ┌────────────┐                      │   │
│  │  │ EKS Cluster│  │    RDS     │                      │   │
│  │  │ (Standby)  │──│ (Replica)  │ ← Managed by DR WS  │   │
│  │  └────────────┘  └────────────┘                      │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## 🚀 Deployment Order

### Step 1: Deploy Primary Infrastructure

```bash
# Setup primary prerequisites
./scripts/setup-prerequisites.sh prod us-west-2

# Deploy primary infrastructure (VPC, EKS, RDS)
./scripts/deploy.sh prod apply
```

**What gets created:**
- ✅ Primary VPC (10.0.0.0/16) in us-west-2
- ✅ Primary EKS cluster
- ✅ Primary RDS instance (Multi-AZ)
- ✅ In-region read replicas (optional)

**Get the primary RDS ARN:**
```bash
terraform output rds_arn
# Output: arn:aws:rds:us-west-2:123456789012:db:pipeops-prod-postgres
```

### Step 2: Setup DR Workspace

```bash
cd dr-infrastructure

# Setup DR prerequisites
./scripts/setup-dr-prerequisites.sh prod us-east-1
```

### Step 3: Configure DR RDS Replica

Edit `dr-infrastructure/environments/prod/terraform.tfvars`:

```hcl
# Set the primary RDS ARN from Step 1
primary_rds_arn = "arn:aws:rds:us-west-2:123456789012:db:pipeops-prod-postgres"

# Enable RDS DR replica
enable_rds_dr_replica = true
dr_rds_instance_class = "db.r6g.xlarge"
dr_rds_multi_az       = true
```

### Step 4: Deploy DR Infrastructure

```bash
# Still in dr-infrastructure/
./scripts/deploy-dr.sh prod plan
./scripts/deploy-dr.sh prod apply
```

**What gets created:**
- ✅ DR VPC (10.1.0.0/16) in us-east-1
- ✅ DR EKS cluster (standby mode)
- ✅ **DR RDS replica in DR VPC** ← Connected to DR EKS!
- ✅ Security groups allowing DR EKS → DR RDS

### Step 5: Verify Network Connectivity

```bash
# Configure kubectl for DR cluster
aws eks update-kubeconfig --region us-east-1 --name pipeops-prod-dr-eks

# Get DR RDS endpoint
cd dr-infrastructure
terraform output dr_rds_replica_endpoint

# Test connectivity from DR EKS
kubectl run -it --rm debug --image=postgres:15 --restart=Never -- \
  psql -h <DR_RDS_ENDPOINT> -U postgres -d pipeops
```

## 📊 What's Different

### Old Approach (Doesn't Work)
```
Primary Workspace:
  - Creates primary RDS
  - Tries to create DR RDS replica
  - Problem: No DR VPC exists yet!
  - DR replica ends up in default VPC
  - DR EKS can't reach DR RDS ❌
```

### New Approach (Works!)
```
Primary Workspace:
  - Creates primary RDS only
  
DR Workspace:
  - Creates DR VPC first
  - Creates DR EKS
  - Creates DR RDS replica in DR VPC ✅
  - DR EKS can reach DR RDS ✅
```

## 🔧 Configuration Files

### Primary Workspace (main.tf)

The primary workspace **no longer** creates the DR RDS replica:

```hcl
# RDS Module - Primary only
module "rds" {
  source = "./modules/rds"
  
  # ... primary configuration ...
  
  # DR replica is now managed by DR workspace
  enable_cross_region_dr = false  # ← Disabled
}
```

### DR Workspace (dr-infrastructure/main.tf)

The DR workspace creates the RDS replica:

```hcl
# DR RDS Read Replica
resource "aws_db_instance" "dr_replica" {
  identifier          = "pipeops-prod-postgres-dr"
  replicate_source_db = var.primary_rds_arn  # ← From primary
  
  # Network - Uses DR VPC
  db_subnet_group_name   = module.dr_vpc.database_subnet_group_name
  vpc_security_group_ids = [aws_security_group.dr_rds.id]
  
  # Connected to DR EKS ✅
}
```

## 💰 Cost Impact

No change in costs - same resources, just managed differently:

| Component | Cost | Managed By |
|-----------|------|------------|
| Primary RDS (Multi-AZ) | ~$600/month | Primary workspace |
| DR RDS Replica (Multi-AZ) | ~$600/month | **DR workspace** ← Changed |
| DR EKS Cluster | ~$243/month | DR workspace |

## 🔄 Updates and Changes

### Updating Primary RDS

```bash
# In root directory
./scripts/deploy.sh prod apply
```

Changes to primary RDS automatically replicate to DR.

### Updating DR RDS Configuration

```bash
# In dr-infrastructure/
./scripts/deploy-dr.sh prod apply
```

You can modify:
- Instance class
- Multi-AZ setting
- Monitoring configuration
- Security groups

**Cannot modify:**
- VPC/subnet (fixed at creation)
- Source DB (primary RDS ARN)

## 🚨 Important Notes

### 1. Primary RDS ARN Required

The DR workspace **requires** the primary RDS ARN. Get it from:

```bash
# In root directory
terraform output rds_arn
```

### 2. Deployment Order Matters

**Correct order:**
1. Primary infrastructure first
2. Get primary RDS ARN
3. Configure DR workspace with ARN
4. Deploy DR infrastructure

**Wrong order:**
- ❌ Deploying DR before primary → No source RDS to replicate from
- ❌ Not setting primary_rds_arn → DR RDS won't be created

### 3. Network Connectivity

The DR RDS replica:
- ✅ Uses DR VPC (10.1.0.0/16)
- ✅ In DR database subnets
- ✅ Security group allows DR EKS nodes
- ✅ Can be reached by DR applications

### 4. Promoting DR Replica

To promote DR replica to standalone (during DR activation):

```bash
aws rds promote-read-replica \
  --db-instance-identifier pipeops-prod-postgres-dr \
  --region us-east-1
```

After promotion:
- Becomes a standalone RDS instance
- No longer replicates from primary
- Can accept writes
- Update Terraform to ignore `replicate_source_db`

## 📋 Verification Checklist

After deployment, verify:

```bash
# 1. Check DR VPC exists
cd dr-infrastructure
terraform output dr_vpc_id

# 2. Check DR RDS replica exists
terraform output dr_rds_replica_endpoint

# 3. Check DR RDS is in correct VPC
aws rds describe-db-instances \
  --db-instance-identifier pipeops-prod-postgres-dr \
  --region us-east-1 \
  --query 'DBInstances[0].DBSubnetGroup.VpcId'
# Should match DR VPC ID

# 4. Check security group allows DR EKS
aws ec2 describe-security-groups \
  --group-ids $(terraform output -raw dr_rds_security_group_id) \
  --region us-east-1

# 5. Test connectivity from DR EKS
kubectl run -it --rm psql-test --image=postgres:15 --restart=Never -- \
  psql -h $(terraform output -raw dr_rds_replica_endpoint) \
  -U postgres -c "SELECT version();"
```

## 🎓 Best Practices

1. **Always deploy primary first** - DR needs the primary RDS ARN
2. **Document the primary RDS ARN** - Store it securely for DR deployment
3. **Test connectivity regularly** - Ensure DR EKS can reach DR RDS
4. **Monitor replication lag** - Check CloudWatch metrics
5. **Practice DR drills** - Test promotion and application failover
6. **Keep configurations in sync** - Match instance classes and settings

## 🔍 Troubleshooting

### Issue: DR RDS replica not created

**Check:**
```bash
cd dr-infrastructure
terraform output dr_status
```

**Solution:**
- Ensure `enable_rds_dr_replica = true`
- Ensure `primary_rds_arn` is set correctly
- Check primary RDS exists and is available

### Issue: DR EKS cannot connect to DR RDS

**Check security group:**
```bash
aws ec2 describe-security-groups \
  --group-ids $(terraform output -raw dr_rds_security_group_id) \
  --region us-east-1
```

**Solution:**
- Verify security group allows port 5432
- Check DR EKS node security group is in allowed list
- Verify both are in same VPC

### Issue: Replication lag

**Check replication status:**
```bash
aws rds describe-db-instances \
  --db-instance-identifier pipeops-prod-postgres-dr \
  --region us-east-1 \
  --query 'DBInstances[0].StatusInfos'
```

**Monitor CloudWatch:**
- `ReplicaLag` metric
- Should be < 10 seconds normally

## 📚 Related Documentation

- [DR_WORKSPACE_SETUP.md](./DR_WORKSPACE_SETUP.md) - DR workspace overview
- [dr-infrastructure/README.md](./dr-infrastructure/README.md) - DR deployment guide
- [RDS_COMPLETE_GUIDE.md](./RDS_COMPLETE_GUIDE.md) - RDS HA/DR features
- [ENVIRONMENT_DEPLOYMENT_GUIDE.md](./ENVIRONMENT_DEPLOYMENT_GUIDE.md) - Primary deployment

---

**Summary:** The RDS DR replica is now managed by the DR workspace to ensure it's created in the DR VPC from the start. This provides proper network connectivity between DR EKS and DR RDS for disaster recovery scenarios.
