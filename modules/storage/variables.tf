variable "project_name" {
  description = "Prefix used for resource names"
  type        = string
}

variable "protected_subnet_ids" {
  description = "Map of protected subnet IDs (a, b) to place EFS mount targets in"
  type        = map(string)
}

variable "efs_security_group_id" {
  description = "Security group ID for the EFS mount targets"
  type        = string
}

variable "performance_mode" {
  description = "EFS performance mode"
  type        = string
  default     = "generalPurpose"

  validation {
    condition     = contains(["generalPurpose", "maxIO"], var.performance_mode)
    error_message = "performance_mode must be generalPurpose or maxIO."
  }
}

variable "throughput_mode" {
  description = "EFS throughput mode"
  type        = string
  default     = "bursting"

  validation {
    condition     = contains(["bursting", "elastic", "provisioned"], var.throughput_mode)
    error_message = "throughput_mode must be bursting, elastic, or provisioned."
  }
}
