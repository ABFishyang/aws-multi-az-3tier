variable "project_name" {
  description = "Prefix used for resource names"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs (a, b) for the ALB"
  type        = list(string)
}

variable "alb_security_group_id" {
  description = "Security group ID for the ALB"
  type        = string
}

variable "web_instance_ids" {
  description = "Map of Web/App EC2 instance IDs to register as targets"
  type        = map(string)
}

variable "certificate_arn" {
  description = "ACM certificate ARN. Empty string builds HTTP-only (no HTTPS listener)."
  type        = string
  default     = ""
}

variable "health_check_path" {
  description = "URL path used for the target group health check (not a filesystem path)"
  type        = string
  default     = "/healthcheck.php"
}

variable "enable_access_logs" {
  description = "Enable ALB access logs to S3"
  type        = bool
  default     = true
}

variable "log_bucket_name" {
  description = "S3 bucket name for ALB access logs (required when enable_access_logs is true)"
  type        = string
  default     = ""
}

variable "alb_log_prefix" {
  description = "S3 key prefix for ALB access logs (must match the bucket policy's allowed path)"
  type        = string
  default     = "alb"
}
