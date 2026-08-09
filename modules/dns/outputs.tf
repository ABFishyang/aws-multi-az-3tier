output "certificate_arn" {
  description = "Validated ACM certificate ARN, or empty string when domain_name is not set"
  value       = var.domain_name != "" ? aws_acm_certificate_validation.main[0].certificate_arn : ""
}
