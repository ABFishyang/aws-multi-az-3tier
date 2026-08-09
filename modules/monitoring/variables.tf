variable "project_name" {
  description = "Prefix used for resource names"
  type        = string
}

variable "notification_email" {
  description = "Email address subscribed to the SNS alert topic (a confirmation email will be sent)"
  type        = string

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "notification_email must be a valid email address."
  }
}

variable "web_instance_ids" {
  description = "Map of Web/App EC2 instance IDs (a, b) to create CPU alarms for"
  type        = map(string)
}

variable "target_group_arn_suffix" {
  description = "ALB target group ARN suffix (from the loadbalancer module), used as the CloudWatch alarm dimension"
  type        = string
}

variable "alb_arn_suffix" {
  description = "ALB ARN suffix (from the loadbalancer module), used as the CloudWatch alarm dimension"
  type        = string
}

variable "db_instance_identifier" {
  description = "RDS DB instance identifier, used as the CloudWatch alarm dimension"
  type        = string
}

variable "cpu_alarm_threshold" {
  description = "CPU utilization alarm threshold in percent (applies to EC2 and RDS alarms)"
  type        = number
  default     = 80

  validation {
    condition     = var.cpu_alarm_threshold >= 1 && var.cpu_alarm_threshold <= 100
    error_message = "cpu_alarm_threshold must be between 1 and 100."
  }
}
