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
      version = "~> 2.7.0"
    }
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
      Project      = var.project_name
      ManagedBy    = var.managed_by
      Environments = var.environment
    }
  }
}


# -------------------------------------------------------------------------
# S3 STATE BUCKET FINOPS OPTIMIZATION
# -------------------------------------------------------------------------

# I dynamically fetch the current AWS Account ID to keep the module reusable.
# I implement an S3 Lifecycle Rule to balance FinOps cost savings with 
# Disaster Recovery (DR). It purges old state files to save money, but 
# strictly retains a minimum of 10 historical versions to guarantee safe rollbacks.
resource "aws_s3_bucket_lifecycle_configuration" "state_cleanup" {
  bucket = "zero-tolerance-state-${data.aws_caller_identity.current.account_id}"

  rule {
    id     = "auto-delete-old-state-versions"
    status = "Enabled"

    # THE FIX: An empty filter explicitly tells AWS to apply this to the entire bucket
    filter {}

    # Delete files older than 30 days, BUT always keep the 10 most recent versions
    noncurrent_version_expiration {
      noncurrent_days           = 30
      newer_noncurrent_versions = 10
    }

    # Clean up broken/failed uploads after 7 days to eliminate hidden storage waste
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}