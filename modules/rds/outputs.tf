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