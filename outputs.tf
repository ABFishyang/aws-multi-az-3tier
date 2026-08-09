output "vpc_id" {
  description = "ID of the VPC"
  value       = module.network.vpc_id
}

output "alb_dns_name" {
  description = "DNS name of the ALB"
  value       = module.loadbalancer.alb_dns_name
}

output "site_url" {
  description = "URL to reach the application (HTTPS custom domain if configured, otherwise the ALB DNS name over HTTP)"
  value       = var.domain_name != "" ? "https://${var.domain_name}/" : "http://${module.loadbalancer.alb_dns_name}/"
}

output "db_endpoint_address" {
  description = "RDS endpoint address"
  value       = module.database.db_endpoint_address
}

output "db_secret_arn" {
  description = "ARN of the RDS-managed master user secret in Secrets Manager"
  value       = module.database.db_secret_arn
}

output "web_instance_ids" {
  description = "Map of Web/App EC2 instance IDs (a, b)"
  value       = module.compute.instance_ids
}

output "log_bucket_name" {
  description = "S3 bucket name for ALB access logs and VPC flow logs"
  value       = module.logging.log_bucket_name
}

output "alert_topic_arn" {
  description = "ARN of the SNS alert topic"
  value       = module.monitoring.alert_topic_arn
}

output "backup_vault_name" {
  description = "Name of the AWS Backup vault"
  value       = module.backup.backup_vault_name
}
