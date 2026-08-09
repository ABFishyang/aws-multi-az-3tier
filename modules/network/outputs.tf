output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "IPv4 CIDR of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "Map of public subnet IDs (a, b)"
  value       = { for k, s in aws_subnet.public : k => s.id }
}

output "private_subnet_ids" {
  description = "Map of private subnet IDs (a, b)"
  value       = { for k, s in aws_subnet.private : k => s.id }
}

output "protected_subnet_ids" {
  description = "Map of protected subnet IDs (a, b)"
  value       = { for k, s in aws_subnet.protected : k => s.id }
}

output "private_route_table_ids" {
  description = "Map of private route table IDs (a, b) — used by the S3 gateway endpoint"
  value       = { for k, t in aws_route_table.private : k => t.id }
}
