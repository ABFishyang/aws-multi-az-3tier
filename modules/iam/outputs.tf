output "ec2_role_arn" {
  description = "ARN of the EC2 IAM role"
  value       = aws_iam_role.ec2.arn
}

output "ec2_instance_profile_name" {
  description = "Name of the EC2 instance profile"
  value       = aws_iam_instance_profile.ec2.name
}

output "backup_role_arn" {
  description = "ARN of the AWS Backup service role"
  value       = aws_iam_role.backup.arn
}
