variable "project_name" {
  description = "Prefix used for resource names"
  type        = string
}

variable "protected_subnet_ids" {
  description = "Protected subnet IDs (a, b) for the DB subnet group"
  type        = list(string)
}

variable "rds_security_group_id" {
  description = "Security group ID for the RDS instance"
  type        = string
}

variable "instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "engine_version" {
  description = "MySQL major version (minor is auto-selected)"
  type        = string
  default     = "8.0"
}

variable "allocated_storage" {
  description = "Allocated storage in GiB"
  type        = number
  default     = 20

  validation {
    condition     = var.allocated_storage >= 20 && var.allocated_storage <= 100
    error_message = "allocated_storage must be between 20 and 100 GiB."
  }
}

variable "db_name" {
  description = "Initial database name"
  type        = string
  default     = "appdb"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9]*$", var.db_name))
    error_message = "db_name must start with a letter and contain only alphanumeric characters."
  }
}

variable "master_username" {
  description = "Master username (avoid the reserved word 'admin')"
  type        = string
  default     = "dbadmin"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", var.master_username))
    error_message = "master_username must start with a letter and contain only alphanumeric characters or underscores."
  }
}

variable "multi_az" {
  description = "Enable Multi-AZ. Set false to reduce cost during learning/testing."
  type        = bool
  default     = true
}

variable "backup_retention_period" {
  description = "Automated backup retention period in days"
  type        = number
  default     = 7

  validation {
    condition     = var.backup_retention_period >= 0 && var.backup_retention_period <= 35
    error_message = "backup_retention_period must be between 0 and 35."
  }
}

variable "deletion_protection" {
  description = "Enable RDS deletion protection. If true, terraform destroy will fail until this is turned back off."
  type        = bool
  default     = false
}
