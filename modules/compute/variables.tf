variable "project_name" {
  description = "Prefix used for resource names"
  type        = string
}

variable "private_subnet_ids" {
  description = "Map of private subnet IDs (a, b)"
  type        = map(string)
}

variable "ec2_security_group_id" {
  description = "Security group ID for the Web/App EC2 instances"
  type        = string
}

variable "iam_instance_profile_name" {
  description = "Name of the IAM instance profile"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "root_volume_size" {
  description = "Root volume size in GiB"
  type        = number
  default     = 8

  validation {
    condition     = var.root_volume_size >= 8 && var.root_volume_size <= 100
    error_message = "root_volume_size must be between 8 and 100 GiB."
  }
}

variable "enable_detailed_monitoring" {
  description = "Enable EC2 one-minute detailed monitoring"
  type        = bool
  default     = false
}

variable "user_data" {
  description = "Rendered bootstrap script (plain text; this module base64-encodes it)"
  type        = string
  sensitive   = true
}
