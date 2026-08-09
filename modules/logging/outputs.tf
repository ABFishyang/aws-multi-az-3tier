output "log_bucket_name" {
  description = "Name of the S3 log bucket"
  value       = aws_s3_bucket.logs.id
}

output "log_bucket_arn" {
  description = "ARN of the S3 log bucket"
  value       = aws_s3_bucket.logs.arn
}

output "alb_log_prefix" {
  description = "S3 key prefix used for ALB access logs"
  value       = var.alb_log_prefix
}

output "bucket_policy_id" {
  description = "ID of the bucket policy resource — depend on this to force ALB creation to wait for the policy"
  value       = aws_s3_bucket_policy.logs.id
}
