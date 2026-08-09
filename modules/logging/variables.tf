variable "project_name" {
  description = "Prefix used for resource names"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "alb_log_prefix" {
  description = "S3 key prefix for ALB access logs (no trailing slash)"
  type        = string
  default     = "alb"
}

variable "flow_log_prefix" {
  description = "S3 key prefix for VPC flow logs (no trailing slash)"
  type        = string
  default     = "vpcflowlogs"
}

variable "log_retention_days" {
  description = "Number of days to retain logs before expiration"
  type        = number
  default     = 90

  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 3650
    error_message = "log_retention_days must be between 1 and 3650."
  }
}
