variable "project_name" {
  description = "Prefix used for resource names"
  type        = string
}

variable "vpc_cidr" {
  description = "IPv4 CIDR of the VPC"
  type        = string
}

variable "availability_zones" {
  description = "Two availability zones"
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) == 2
    error_message = "Exactly two availability zones are required."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDRs of public-a and public-b (ALB / NAT Gateway)"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDRs of private-a and private-b (Web/App EC2)"
  type        = list(string)
}

variable "protected_subnet_cidrs" {
  description = "CIDRs of protected-a and protected-b (RDS / EFS, no default route)"
  type        = list(string)
}
