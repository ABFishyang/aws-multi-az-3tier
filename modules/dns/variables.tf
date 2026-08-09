variable "project_name" {
  description = "Prefix used for resource names"
  type        = string
}

variable "domain_name" {
  description = "Domain name for the ACM certificate. Empty string skips certificate creation entirely (HTTP-only build)."
  type        = string
  default     = ""

  validation {
    condition     = var.domain_name == "" || can(regex("^[a-z0-9.-]+\\.[a-z]{2,}$", var.domain_name))
    error_message = "domain_name must be empty or a valid domain name, e.g. app.example.com."
  }
}

variable "hosted_zone_id" {
  description = "Existing Route 53 hosted zone ID (required when domain_name is set)"
  type        = string
  default     = ""
}
