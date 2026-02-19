# =============================================================================
# terraform/backend/variables.tf
# =============================================================================

variable "aws_region" {
  description = "AWS region in which to provision the backend resources"
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]+$", var.aws_region))
    error_message = "Must be a valid AWS region (e.g. us-east-1, eu-west-2)."
  }
}

variable "s3_bucket_name" {
  description = "Name for the S3 state bucket (globally unique)"
  type        = string

  validation {
    condition     = length(var.s3_bucket_name) >= 3 && length(var.s3_bucket_name) <= 63
    error_message = "S3 bucket names must be between 3 and 63 characters."
  }
}

variable "dynamodb_table_name" {
  description = "Name for the DynamoDB state lock table"
  type        = string

  validation {
    condition     = length(var.dynamodb_table_name) >= 3
    error_message = "DynamoDB table name must be at least 3 characters."
  }
}
