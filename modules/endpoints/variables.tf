variable "project_name" {
  description = "Prefix used for resource names"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for the Interface endpoints (a, b)"
  type        = list(string)
}

variable "private_route_table_ids" {
  description = "Private route table IDs for the S3 Gateway endpoint (a, b)"
  type        = list(string)
}

variable "vpce_security_group_id" {
  description = "Security group ID for the Interface endpoints"
  type        = string
}
