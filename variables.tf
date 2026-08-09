# ==================================================================
# 基本設定
# ==================================================================
variable "aws_region" {
  description = "AWS region used by this project"
  type        = string
  default     = "ap-northeast-1"
}

variable "project_name" {
  description = "Prefix used for resource names, tags, and the S3 log bucket name"
  type        = string
  default     = "myapp"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,24}$", var.project_name))
    error_message = "project_name must contain 3-24 lowercase letters, numbers, or hyphens."
  }
}

# ==================================================================
# ネットワーク
# ==================================================================
variable "vpc_cidr" {
  description = "IPv4 CIDR of the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Two availability zones. Some accounts cannot use 1b in ap-northeast-1, hence the 1a/1c default."
  type        = list(string)
  default     = ["ap-northeast-1a", "ap-northeast-1c"]
}

variable "public_subnet_cidrs" {
  description = "CIDRs of public-a and public-b (ALB / NAT Gateway)"
  type        = list(string)
  default     = ["10.0.0.0/24", "10.0.1.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDRs of private-a and private-b (Web/App EC2)"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "protected_subnet_cidrs" {
  description = "CIDRs of protected-a and protected-b (RDS / EFS, no default route)"
  type        = list(string)
  default     = ["10.0.20.0/24", "10.0.21.0/24"]
}

# ==================================================================
# EC2 / Compute
# ==================================================================
variable "instance_type" {
  description = "EC2 instance type for the Web/App servers"
  type        = string
  default     = "t3.micro"
}

variable "root_volume_size" {
  description = "Root volume size in GiB"
  type        = number
  default     = 8
}

variable "enable_detailed_monitoring" {
  description = "Enable EC2 one-minute detailed monitoring (incurs a small charge)"
  type        = bool
  default     = false
}

# ==================================================================
# EFS
# ==================================================================
variable "efs_performance_mode" {
  description = "EFS performance mode"
  type        = string
  default     = "generalPurpose"
}

variable "efs_throughput_mode" {
  description = "EFS throughput mode"
  type        = string
  default     = "bursting"
}

# ==================================================================
# RDS
# ==================================================================
variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "db_engine_version" {
  description = "MySQL major version (minor is auto-selected; avoids pinning to an EOL minor version)"
  type        = string
  default     = "8.0"
}

variable "db_allocated_storage" {
  description = "Allocated storage in GiB"
  type        = number
  default     = 20
}

variable "db_name" {
  description = "Initial database name"
  type        = string
  default     = "appdb"
}

variable "db_master_username" {
  description = "Master username (avoid the reserved word 'admin')"
  type        = string
  default     = "dbadmin"
}

variable "db_multi_az" {
  description = "Enable RDS Multi-AZ. Set false to cut cost while testing (~$15/month)."
  type        = bool
  default     = true
}

variable "db_backup_retention_period" {
  description = "Automated backup retention period in days"
  type        = number
  default     = 7
}

variable "db_deletion_protection" {
  description = "Enable RDS deletion protection. If true, terraform destroy will fail until this is turned back off."
  type        = bool
  default     = false
}

# ==================================================================
# ALB / DNS
# ==================================================================
variable "domain_name" {
  description = "Custom domain name for the ALB (e.g. app.example.com). Leave empty to build HTTP-only using the ALB's own DNS name — no certificate or Route 53 record is created."
  type        = string
  default     = ""
}

variable "hosted_zone_id" {
  description = "Existing Route 53 hosted zone ID. Required when domain_name is set (enforced by the check block at the bottom of this file)."
  type        = string
  default     = ""
}

variable "health_check_path" {
  description = "URL path used for the ALB target group health check (not a filesystem path)"
  type        = string
  default     = "/healthcheck.php"
}

variable "enable_access_logs" {
  description = "Enable ALB access logs to S3"
  type        = bool
  default     = true
}

# ==================================================================
# ログ
# ==================================================================
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
  description = "Number of days to retain ALB/flow logs before expiration"
  type        = number
  default     = 90
}

# ==================================================================
# 監視・通知
# ==================================================================
variable "notification_email" {
  description = "Email address subscribed to the SNS alert topic (a confirmation email will be sent after apply)"
  type        = string
}

variable "cpu_alarm_threshold" {
  description = "CPU utilization alarm threshold in percent (EC2 and RDS)"
  type        = number
  default     = 80
}

# ==================================================================
# バックアップ
# ==================================================================
variable "backup_schedule" {
  description = "AWS Backup cron schedule expression. Default: daily at 16:00 UTC (01:00 JST)."
  type        = string
  default     = "cron(0 16 ? * * *)"
}

variable "backup_delete_after_days" {
  description = "Recovery point retention in days"
  type        = number
  default     = 30
}

# ==================================================================
# クロスフィールド検証
# ==================================================================
check "hosted_zone_required_with_domain" {
  assert {
    condition     = var.domain_name == "" || var.hosted_zone_id != ""
    error_message = "hosted_zone_id is required when domain_name is set."
  }
}
