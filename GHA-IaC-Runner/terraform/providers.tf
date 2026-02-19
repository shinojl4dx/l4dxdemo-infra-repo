# =============================================================================
# terraform/providers.tf
#
# Provider and backend configuration for APPLICATION infrastructure.
#
# This is the root Terraform module that GitHub Actions runs on every push.
# The backend values (bucket, table, region) are injected dynamically at
# `terraform init` time from the workflow — they are NOT hardcoded here.
#
# This keeps the config portable and avoids committing account-specific
# values into version control.
# =============================================================================

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Backend is configured at runtime via -backend-config flags in CI.
  # See .github/workflows/terraform-apply.yaml → "Terraform Init" step.
  backend "s3" {}
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      ManagedBy   = "terraform"
      Repository  = var.github_repo
      Environment = "production"
    }
  }
}

# ─── Root-level variables ─────────────────────────────────────────────────────

variable "aws_region" {
  description = "AWS region for application infrastructure"
  type        = string
  default     = "us-east-1"
}

variable "github_repo" {
  description = "GitHub repository name (used in default tags)"
  type        = string
  default     = "unknown"
}

# =============================================================================
# Add your application infrastructure modules below.
#
# Example:
#   module "networking" {
#     source  = "./modules/networking"
#     region  = var.aws_region
#   }
#
#   module "app" {
#     source = "./modules/app"
#     vpc_id = module.networking.vpc_id
#   }
# =============================================================================
