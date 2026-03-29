variable "aws_region" {
  description = "AWS region to deploy resources in"
  type        = string
  default     = "ap-south-1"
}

variable "environment" {
  description = "The deployment environment. Must be dev, stage, or prod."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "stage", "prod"], var.environment)
    error_message = "The environment tag must be strictly 'dev', 'stage', or 'prod'."
  }
}

variable "project_name" {
  description = "The core project name for tagging"
  type        = string
  default     = "Zero-Tolerance-FinOps"
}

variable "managed_by" {
  description = "The team or tool managing these resources"
  type        = string
  default     = "Terraform"
}

variable "repo_name" {
  description = "GitHub repository in format OWNER/REPO"
  type        = string
  default     = "Nikhil-9391/zero-tolerance-finops"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+$", var.repo_name))
    error_message = "repo_name must be in format OWNER/REPO"
  }
}

variable "security_alert_email" {
  description = "The email address that will receive the Zero-Tolerance FinOps alerts"
  type        = string
  sensitive   = true
  # Notice there is no 'default = ' here! 
  # This forces Terraform to look for your TF_VAR_ environment variable to fill it.
}

variable "is_enabled" {
  description = "Safety Switch: true to deploy, false to destroy."
  type        = bool
  default     = false
}