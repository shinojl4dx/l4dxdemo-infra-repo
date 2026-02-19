# =============================================================================
# terraform/backend/main.tf
#
# Provisions the Terraform remote state backend:
#   - S3 bucket (versioned, encrypted, private)
#   - DynamoDB table (state locking)
# =============================================================================

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      ManagedBy = "terraform"
      Platform  = "ci-bootstrap"
      Component = "backend"
    }
  }
}

# ─── S3 State Bucket ──────────────────────────────────────────────────────────

resource "aws_s3_bucket" "state" {
  bucket        = var.s3_bucket_name
  force_destroy = false
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    # Empty prefix = apply rule to all objects (required by AWS provider >= 4.x)
    filter {
      prefix = ""
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# ─── DynamoDB Lock Table ──────────────────────────────────────────────────────

resource "aws_dynamodb_table" "lock" {
  name         = var.dynamodb_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }
}

# ─── Outputs ──────────────────────────────────────────────────────────────────

output "s3_bucket_name" {
  description = "Name of the Terraform state S3 bucket"
  value       = aws_s3_bucket.state.id
}

output "s3_bucket_arn" {
  description = "ARN of the Terraform state S3 bucket"
  value       = aws_s3_bucket.state.arn
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB state lock table"
  value       = aws_dynamodb_table.lock.name
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB state lock table"
  value       = aws_dynamodb_table.lock.arn
}
