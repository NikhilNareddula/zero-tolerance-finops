# I pin the AWS provider to the 5.x major version. 
# This ensures the pipeline automatically pulls minor security patches 
# and bug fixes, but strictly blocks 6.x to prevent breaking API changes.
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
     # --- FOR ARCHIVE BLOCK ---
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4.0"
  }
}


# I configure the AWS provider to dynamically accept the target region 
# via variables, keeping the module entirely stateless and reusable.
provider "aws" {
  region = var.aws_region

  # I apply global default_tags to automatically stamp every resource 
  # created by this pipeline. This guarantees accurate cost-allocation 
  # tracking and explicitly marks resources as managed by automation.
  default_tags {
    tags = {
      Project     = var.project_name
      ManagedBy   = var.managed_by
      Environment = var.environment
    }
  }
}