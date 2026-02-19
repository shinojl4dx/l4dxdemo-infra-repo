# =============================================================================
# terraform/iam/variables.tf
# =============================================================================

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID (used to scope resource ARNs in IAM policies)"
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "Must be a 12-digit AWS account ID."
  }
}

variable "iam_role_name" {
  description = "Name for the GitHub Actions IAM role"
  type        = string

  validation {
    condition     = length(var.iam_role_name) <= 64
    error_message = "IAM role names must be 64 characters or fewer."
  }
}

variable "github_org" {
  description = "GitHub organization or username (e.g. my-org)"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name (e.g. my-repo)"
  type        = string
}

variable "s3_bucket_name" {
  description = "S3 bucket name — used to scope S3 IAM permissions"
  type        = string
  default     = ""
}

variable "dynamodb_table_name" {
  description = "DynamoDB table name — used to scope DynamoDB IAM permissions"
  type        = string
  default     = ""
}
