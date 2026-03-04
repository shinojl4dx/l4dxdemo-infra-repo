# Backup Module (Production)

Creates AWS Backup components in the Production account.

## What it creates
- KMS CMK for vault encryption (rotation enabled)
- AWS Backup Vault (encrypted)
- AWS Backup Plan (daily schedule, 30-day retention)
- IAM Role for AWS Backup service
- Backup Selection (Tag-based)

## Tag-based selection
Any supported resource tagged with:

Backup = true

will be protected by this backup plan.

## Usage
1. Ensure AWS SSO login is active:
   aws sso login --profile Administrator-PS-696192989304
   export AWS_PROFILE=Administrator-PS-696192989304

2. Terraform:
   terraform init
   terraform plan
