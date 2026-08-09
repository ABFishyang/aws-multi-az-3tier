output "interface_endpoint_ids" {
  description = "Map of Interface VPC endpoint IDs, keyed by service (ssm, ssmmessages, ec2messages)"
  value       = { for k, e in aws_vpc_endpoint.interface : k => e.id }
}

output "s3_endpoint_id" {
  description = "ID of the S3 Gateway endpoint"
  value       = aws_vpc_endpoint.s3.id
}
