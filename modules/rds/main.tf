# RDS PostgreSQL instance with Multi-AZ support
resource "aws_db_instance" "main" {
  identifier = "${var.project_name}-${var.environment}-postgres"

  # Engine options
  engine         = "postgres"
  engine_version = var.postgres_version
  instance_class = var.db_instance_class

  # High Availability - Multi-AZ deployment
  multi_az = var.multi_az

  # Storage
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = aws_kms_key.rds.arn
  # iops                  = var.iops

  # Database name and credentials
  db_name  = var.database_name
  username = var.database_username
  password = var.database_password

  # Network & Security
  db_subnet_group_name   = var.db_subnet_group_name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  port                   = 5432

  # Backup & Maintenance
  backup_retention_period    = var.backup_retention_period
  backup_window              = "03:00-04:00"
  maintenance_window         = "Mon:04:00-Mon:05:00"
  auto_minor_version_upgrade = true
  deletion_protection        = var.deletion_protection
  apply_immediately          = var.apply_immediately

  # Parameter and Option Groups
  parameter_group_name = aws_db_parameter_group.main.name
  option_group_name    = aws_db_option_group.main.name

  # Monitoring
  monitoring_interval             = 60
  monitoring_role_arn             = aws_iam_role.rds_monitoring.arn
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  # Performance Insights
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.rds.arn
  performance_insights_retention_period = var.performance_insights_retention

  # Enhanced monitoring
  copy_tags_to_snapshot     = true
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.project_name}-${var.environment}-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"

  tags = merge(var.tags, {
    Name        = "${var.project_name}-${var.environment}-postgres"
    Role        = "primary"
    Environment = var.environment
  })
}

# Read Replicas for load distribution and additional HA
resource "aws_db_instance" "read_replica" {
  count = var.create_read_replica ? var.read_replica_count : 0

  identifier          = "${var.project_name}-${var.environment}-postgres-replica-${count.index + 1}"
  replicate_source_db = aws_db_instance.main.identifier
  instance_class      = var.read_replica_instance_class

  # Place replicas in different AZs for additional redundancy
  availability_zone = length(var.replica_availability_zones) > 0 ? element(var.replica_availability_zones, count.index) : null

  # Storage
  storage_type      = "gp3"
  storage_encrypted = true
  # iops              = var.iops

  # Network & Security
  publicly_accessible    = false
  vpc_security_group_ids = [aws_security_group.rds.id]

  # Monitoring
  monitoring_interval             = 60
  monitoring_role_arn             = aws_iam_role.rds_monitoring.arn
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  # Performance Insights
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.rds.arn
  performance_insights_retention_period = var.performance_insights_retention

  # Backup settings (replicas can be promoted to standalone)
  backup_retention_period = var.backup_retention_period

  # Parameter and Option Groups
  parameter_group_name = aws_db_parameter_group.main.name
  option_group_name    = aws_db_option_group.main.name

  # Apply changes
  apply_immediately          = var.apply_immediately
  auto_minor_version_upgrade = true

  # Snapshots
  copy_tags_to_snapshot = true
  skip_final_snapshot   = true

  tags = merge(var.tags, {
    Name        = "${var.project_name}-${var.environment}-postgres-replica-${count.index + 1}"
    Role        = "read-replica"
    Environment = var.environment
  })

  depends_on = [aws_db_instance.main]
}

# Security Group for RDS
resource "aws_security_group" "rds" {
  name        = "${var.project_name}-${var.environment}-rds-sg"
  description = "Security group for RDS PostgreSQL"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL from EKS"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = var.allowed_security_groups
  }

  ingress {
    description = "PostgreSQL from private subnets"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-rds-sg"
  })
}

# KMS key for RDS encryption
resource "aws_kms_key" "rds" {
  description             = "KMS key for RDS encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-rds-key"
  })
}

resource "aws_kms_alias" "rds" {
  name          = "alias/${var.project_name}-${var.environment}-rds"
  target_key_id = aws_kms_key.rds.key_id
}

# IAM role for RDS monitoring
resource "aws_iam_role" "rds_monitoring" {
  name = "${var.project_name}-${var.environment}-rds-monitoring"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# Parameter group for PostgreSQL
# Family must match the major version (e.g., postgres16 for version 16.x)
resource "aws_db_parameter_group" "main" {
  family = "postgres${split(".", var.postgres_version)[0]}"
  name   = "${var.project_name}-${var.environment}-postgres${split(".", var.postgres_version)[0]}-params"

  # Static parameters require pending-reboot apply method
  parameter {
    name         = "shared_preload_libraries"
    value        = "pg_stat_statements"
    apply_method = "pending-reboot"
  }

  # Dynamic parameters can use immediate apply
  parameter {
    name         = "log_statement"
    value        = "all"
    apply_method = "immediate"
  }

  parameter {
    name         = "log_min_duration_statement"
    value        = "1000"
    apply_method = "immediate"
  }

  parameter {
    name         = "log_connections"
    value        = "1"
    apply_method = "immediate"
  }

  parameter {
    name         = "log_disconnections"
    value        = "1"
    apply_method = "immediate"
  }

  tags = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

# Option group for PostgreSQL
# Major version must match the engine version
resource "aws_db_option_group" "main" {
  name                     = "${var.project_name}-${var.environment}-postgres${split(".", var.postgres_version)[0]}-options"
  option_group_description = "Option group for ${var.project_name} ${var.environment} PostgreSQL"
  engine_name              = "postgres"
  major_engine_version     = split(".", var.postgres_version)[0]

  tags = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

# CloudWatch Log Groups for RDS logs
resource "aws_cloudwatch_log_group" "postgresql" {
  name              = "/aws/rds/instance/${var.project_name}-${var.environment}-postgres/postgresql"
  retention_in_days = 30

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "upgrade" {
  name              = "/aws/rds/instance/${var.project_name}-${var.environment}-postgres/upgrade"
  retention_in_days = 30

  tags = var.tags
}

# AWS Secrets Manager secret for database credentials
resource "aws_secretsmanager_secret" "db_credentials" {
  name        = "${var.project_name}/${var.environment}/rds/credentials"
  description = "Database credentials for ${var.project_name} ${var.environment}"

  # Set to 0 to allow immediate recreation if deleted
  # This prevents "secret scheduled for deletion" errors
  recovery_window_in_days = 0

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = var.database_username
    password = var.database_password
    endpoint = aws_db_instance.main.endpoint
    port     = aws_db_instance.main.port
    dbname   = var.database_name
    read_replicas = var.create_read_replica ? [
      for replica in aws_db_instance.read_replica : {
        endpoint = replica.endpoint
        id       = replica.identifier
      }
    ] : []
  })
}

# CloudWatch Alarms for proactive monitoring
resource "aws_cloudwatch_metric_alarm" "database_cpu" {
  count = var.sns_topic_arn != "" ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-rds-cpu-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors RDS CPU utilization"
  alarm_actions       = [var.sns_topic_arn]
  ok_actions          = [var.sns_topic_arn]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.id
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "database_memory" {
  count = var.sns_topic_arn != "" ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-rds-freeable-memory"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "FreeableMemory"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "1000000000" # 1GB in bytes
  alarm_description   = "This metric monitors RDS freeable memory"
  alarm_actions       = [var.sns_topic_arn]
  ok_actions          = [var.sns_topic_arn]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.id
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "database_storage" {
  count = var.sns_topic_arn != "" ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-rds-free-storage"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "10000000000" # 10GB in bytes
  alarm_description   = "This metric monitors RDS free storage space"
  alarm_actions       = [var.sns_topic_arn]
  ok_actions          = [var.sns_topic_arn]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.id
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "database_connections" {
  count = var.sns_topic_arn != "" ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-rds-database-connections"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors RDS database connections"
  alarm_actions       = [var.sns_topic_arn]
  ok_actions          = [var.sns_topic_arn]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.id
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "database_replica_lag" {
  count = var.create_read_replica && var.sns_topic_arn != "" ? var.read_replica_count : 0

  alarm_name          = "${var.project_name}-${var.environment}-rds-replica-lag-${count.index + 1}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ReplicaLag"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "1000" # 1 second in milliseconds
  alarm_description   = "This metric monitors RDS read replica lag"
  alarm_actions       = [var.sns_topic_arn]
  ok_actions          = [var.sns_topic_arn]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.read_replica[count.index].id
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "database_burst_balance" {
  count = var.sns_topic_arn != "" ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-rds-burst-balance"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "BurstBalance"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "20"
  alarm_description   = "This metric monitors RDS burst balance for gp3 volumes"
  alarm_actions       = [var.sns_topic_arn]
  ok_actions          = [var.sns_topic_arn]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.id
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "database_read_latency" {
  count = var.sns_topic_arn != "" ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-rds-read-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ReadLatency"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "0.1" # 100ms
  alarm_description   = "This metric monitors RDS read latency"
  alarm_actions       = [var.sns_topic_arn]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.id
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "database_write_latency" {
  count = var.sns_topic_arn != "" ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-rds-write-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "WriteLatency"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "0.1" # 100ms
  alarm_description   = "This metric monitors RDS write latency"
  alarm_actions       = [var.sns_topic_arn]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.id
  }

  tags = var.tags
}

# ==========================================
# MULTI-REGION DISASTER RECOVERY
# ==========================================

# KMS key for DR region encryption
resource "aws_kms_key" "rds_dr" {
  count = var.enable_cross_region_dr && var.dr_kms_key_id == "" ? 1 : 0

  provider = aws.disaster_recovery

  description             = "KMS key for RDS DR encryption in ${var.dr_region}"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = merge(var.tags, {
    Name   = "${var.project_name}-${var.environment}-rds-dr-key"
    Region = var.dr_region
    Role   = "disaster-recovery"
  })
}

resource "aws_kms_alias" "rds_dr" {
  count = var.enable_cross_region_dr && var.dr_kms_key_id == "" ? 1 : 0

  provider = aws.disaster_recovery

  name          = "alias/${var.project_name}-${var.environment}-rds-dr"
  target_key_id = aws_kms_key.rds_dr[0].key_id
}

# Security group for DR RDS replica
resource "aws_security_group" "rds_dr" {
  count = var.enable_cross_region_dr && var.dr_vpc_id != "" ? 1 : 0

  provider = aws.disaster_recovery

  name        = "${var.project_name}-${var.environment}-rds-dr-sg"
  description = "Security group for DR RDS replica"
  vpc_id      = var.dr_vpc_id

  # Ingress from DR EKS nodes
  dynamic "ingress" {
    for_each = var.dr_allowed_security_groups
    content {
      description     = "PostgreSQL from EKS nodes"
      from_port       = 5432
      to_port         = 5432
      protocol        = "tcp"
      security_groups = [ingress.value]
    }
  }

  # Ingress from DR CIDR blocks
  dynamic "ingress" {
    for_each = var.dr_allowed_cidr_blocks
    content {
      description = "PostgreSQL from VPC"
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  # Egress (allow all outbound)
  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name   = "${var.project_name}-${var.environment}-rds-dr-sg"
    Region = var.dr_region
    Role   = "disaster-recovery"
  })
}

# Cross-region read replica for disaster recovery
resource "aws_db_instance" "cross_region_replica" {
  count = var.enable_cross_region_dr ? 1 : 0

  provider = aws.disaster_recovery

  identifier          = "${var.project_name}-${var.environment}-postgres-dr"
  replicate_source_db = aws_db_instance.main.arn
  instance_class      = var.dr_instance_class

  # Multi-AZ in DR region for additional redundancy
  multi_az = var.dr_multi_az

  # Storage encryption
  storage_encrypted = true
  kms_key_id        = var.dr_kms_key_id != "" ? var.dr_kms_key_id : aws_kms_key.rds_dr[0].arn

  # Network - Use DR VPC if provided
  db_subnet_group_name   = var.dr_db_subnet_group_name != "" ? var.dr_db_subnet_group_name : null
  vpc_security_group_ids = var.dr_vpc_id != "" ? [aws_security_group.rds_dr[0].id] : null
  publicly_accessible    = false

  # Backup configuration (can be promoted to standalone)
  backup_retention_period = var.backup_retention_period

  # Parameter and Option Groups (will be created from source)
  auto_minor_version_upgrade = true

  # Monitoring
  monitoring_interval             = 60
  monitoring_role_arn             = aws_iam_role.rds_monitoring.arn
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  # Performance Insights
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = var.dr_kms_key_id != "" ? var.dr_kms_key_id : aws_kms_key.rds_dr[0].arn
  performance_insights_retention_period = var.performance_insights_retention

  # Snapshots
  copy_tags_to_snapshot     = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.project_name}-${var.environment}-dr-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"

  # Apply changes
  apply_immediately = var.apply_immediately

  tags = merge(var.tags, {
    Name        = "${var.project_name}-${var.environment}-postgres-dr"
    Role        = "disaster-recovery"
    Region      = var.dr_region
    Environment = var.environment
  })

  depends_on = [aws_db_instance.main]
}

# Cross-region automated backup replication
# Note: This is independent of DR replica (which is in DR workspace)
resource "aws_db_instance_automated_backups_replication" "cross_region" {
  count = var.enable_cross_region_backups ? 1 : 0

  provider = aws.disaster_recovery

  source_db_instance_arn = aws_db_instance.main.arn
  retention_period       = var.backup_retention_period

  # Use provided KMS key or default AWS-managed key
  kms_key_id = var.dr_kms_key_id != "" ? var.dr_kms_key_id : null
}

# CloudWatch alarms for DR replica (if enabled)
resource "aws_cloudwatch_metric_alarm" "dr_replica_lag" {
  count = var.enable_cross_region_dr && var.sns_topic_arn != "" ? 1 : 0

  provider = aws.disaster_recovery

  alarm_name          = "${var.project_name}-${var.environment}-rds-dr-replica-lag"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "3"
  metric_name         = "ReplicaLag"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "30000" # 30 seconds (cross-region can have higher lag)
  alarm_description   = "This metric monitors DR replica lag (cross-region)"
  alarm_actions       = [var.sns_topic_arn]
  ok_actions          = [var.sns_topic_arn]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.cross_region_replica[0].id
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "dr_replica_cpu" {
  count = var.enable_cross_region_dr && var.sns_topic_arn != "" ? 1 : 0

  provider = aws.disaster_recovery

  alarm_name          = "${var.project_name}-${var.environment}-rds-dr-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors DR replica CPU utilization"
  alarm_actions       = [var.sns_topic_arn]
  ok_actions          = [var.sns_topic_arn]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.cross_region_replica[0].id
  }

  tags = var.tags
}

# Update Secrets Manager with DR endpoint
resource "aws_secretsmanager_secret_version" "db_credentials_dr" {
  count = var.enable_cross_region_dr ? 1 : 0

  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = var.database_username
    password = var.database_password
    endpoint = aws_db_instance.main.endpoint
    port     = aws_db_instance.main.port
    dbname   = var.database_name
    read_replicas = var.create_read_replica ? [
      for replica in aws_db_instance.read_replica : {
        endpoint = replica.endpoint
        id       = replica.identifier
        region   = var.region
      }
    ] : []
    dr_replica = {
      endpoint = aws_db_instance.cross_region_replica[0].endpoint
      id       = aws_db_instance.cross_region_replica[0].identifier
      region   = var.dr_region
      multi_az = var.dr_multi_az
    }
  })

  depends_on = [
    aws_secretsmanager_secret_version.db_credentials,
    aws_db_instance.cross_region_replica
  ]
}