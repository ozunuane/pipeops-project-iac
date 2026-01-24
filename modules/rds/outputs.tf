output "db_instance_endpoint" {
  description = "RDS instance endpoint"
  value       = aws_db_instance.main.endpoint
}

output "db_instance_id" {
  description = "RDS instance ID"
  value       = aws_db_instance.main.id
}

output "db_instance_arn" {
  description = "RDS instance ARN"
  value       = aws_db_instance.main.arn
}

output "db_instance_address" {
  description = "RDS instance hostname"
  value       = aws_db_instance.main.address
}

output "db_instance_port" {
  description = "RDS instance port"
  value       = aws_db_instance.main.port
}

output "db_instance_name" {
  description = "RDS database name"
  value       = aws_db_instance.main.db_name
}

output "db_instance_username" {
  description = "RDS database username"
  value       = aws_db_instance.main.username
  sensitive   = true
}

output "db_security_group_id" {
  description = "RDS security group ID"
  value       = aws_security_group.rds.id
}

output "secrets_manager_secret_arn" {
  description = "ARN of the secrets manager secret containing database credentials"
  value       = aws_secretsmanager_secret.db_credentials.arn
}

output "secrets_manager_secret_name" {
  description = "Name of the secrets manager secret containing database credentials"
  value       = aws_secretsmanager_secret.db_credentials.name
}

output "db_instance_multi_az" {
  description = "Whether the RDS instance is multi-AZ"
  value       = aws_db_instance.main.multi_az
}

output "db_read_replica_endpoints" {
  description = "List of read replica endpoints"
  value       = var.create_read_replica ? aws_db_instance.read_replica[*].endpoint : []
}

output "db_read_replica_ids" {
  description = "List of read replica IDs"
  value       = var.create_read_replica ? aws_db_instance.read_replica[*].id : []
}

output "db_read_replica_count" {
  description = "Number of read replicas created"
  value       = var.create_read_replica ? var.read_replica_count : 0
}

output "cloudwatch_alarm_arns" {
  description = "ARNs of CloudWatch alarms created"
  value = {
    cpu_utilization      = var.sns_topic_arn != "" ? aws_cloudwatch_metric_alarm.database_cpu[0].arn : null
    freeable_memory      = var.sns_topic_arn != "" ? aws_cloudwatch_metric_alarm.database_memory[0].arn : null
    free_storage         = var.sns_topic_arn != "" ? aws_cloudwatch_metric_alarm.database_storage[0].arn : null
    database_connections = var.sns_topic_arn != "" ? aws_cloudwatch_metric_alarm.database_connections[0].arn : null
    read_latency         = var.sns_topic_arn != "" ? aws_cloudwatch_metric_alarm.database_read_latency[0].arn : null
    write_latency        = var.sns_topic_arn != "" ? aws_cloudwatch_metric_alarm.database_write_latency[0].arn : null
  }
}

# Multi-Region DR Outputs
output "dr_replica_enabled" {
  description = "Whether cross-region DR is enabled"
  value       = var.enable_cross_region_dr
}

output "dr_replica_endpoint" {
  description = "DR replica endpoint (empty if DR not enabled)"
  value       = var.enable_cross_region_dr ? aws_db_instance.cross_region_replica[0].endpoint : ""
}

output "dr_replica_region" {
  description = "DR region"
  value       = var.enable_cross_region_dr ? var.dr_region : ""
}

output "dr_replica_id" {
  description = "DR replica identifier"
  value       = var.enable_cross_region_dr ? aws_db_instance.cross_region_replica[0].id : ""
}

output "dr_replica_arn" {
  description = "DR replica ARN"
  value       = var.enable_cross_region_dr ? aws_db_instance.cross_region_replica[0].arn : ""
}

output "dr_replica_multi_az" {
  description = "Whether DR replica is Multi-AZ"
  value       = var.enable_cross_region_dr ? var.dr_multi_az : false
}

output "cross_region_backups_enabled" {
  description = "Whether cross-region backup replication is enabled"
  value       = var.enable_cross_region_backups
}

output "dr_kms_key_arn" {
  description = "KMS key ARN in DR region (created for cross-region backups or DR replica)"
  value = (var.enable_cross_region_dr || var.enable_cross_region_backups) && var.dr_kms_key_id == "" ? aws_kms_key.rds_dr[0].arn : (
    var.dr_kms_key_id != "" ? var.dr_kms_key_id : null
  )
}

output "dr_kms_key_id" {
  description = "KMS key ID in DR region (created for cross-region backups or DR replica)"
  value = (var.enable_cross_region_dr || var.enable_cross_region_backups) && var.dr_kms_key_id == "" ? aws_kms_key.rds_dr[0].id : (
    var.dr_kms_key_id != "" ? var.dr_kms_key_id : null
  )
}