output "db_endpoint_address" {
  description = "RDS endpoint address"
  value       = aws_db_instance.main.address
}

output "db_endpoint_port" {
  description = "RDS endpoint port"
  value       = aws_db_instance.main.port
}

output "db_name" {
  description = "Initial database name"
  value       = aws_db_instance.main.db_name
}

output "db_instance_identifier" {
  description = "RDS DB instance identifier (used by CloudWatch alarm dimensions and AWS Backup selection)"
  value       = aws_db_instance.main.identifier
}

output "db_instance_arn" {
  description = "ARN of the RDS DB instance"
  value       = aws_db_instance.main.arn
}

output "db_secret_arn" {
  description = "ARN of the RDS-managed master user secret in Secrets Manager"
  value       = aws_db_instance.main.master_user_secret[0].secret_arn
}
