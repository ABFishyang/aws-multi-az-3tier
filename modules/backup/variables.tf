variable "project_name" {
  description = "Prefix used for resource names"
  type        = string
}

variable "backup_role_arn" {
  description = "ARN of the AWS Backup service role (from the iam module)"
  type        = string
}

variable "db_instance_arn" {
  description = "ARN of the RDS DB instance to include in the backup selection"
  type        = string
}

variable "backup_schedule" {
  description = "AWS Backup cron schedule expression. No default on purpose — omitting ScheduleExpression is the exact silent-failure bug found when reviewing the reference CloudFormation series (plan/rule are created but backups never run)."
  type        = string

  validation {
    condition     = can(regex("^cron\\(", var.backup_schedule))
    error_message = "backup_schedule must be a cron() expression, e.g. cron(0 16 ? * * *)."
  }
}

variable "delete_after_days" {
  description = "Recovery point retention in days (RPO 24h / RTO 1 day requirement)"
  type        = number
  default     = 30

  validation {
    condition     = var.delete_after_days >= 1 && var.delete_after_days <= 365
    error_message = "delete_after_days must be between 1 and 365."
  }
}
