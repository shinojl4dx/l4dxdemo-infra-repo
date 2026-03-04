provider "aws" {
  region  = var.aws_region
  profile = "Administrator-PS-696192989304"
}

# KMS Key for Backup Vault Encryption
resource "aws_kms_key" "backup_key" {
  description             = "KMS key for AWS Backup Vault encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true
}

resource "aws_kms_alias" "backup_alias" {
  name          = "alias/backup-vault-key"
  target_key_id = aws_kms_key.backup_key.id
}

# Backup Vault
resource "aws_backup_vault" "production_vault" {
  name        = "production-backup-vault"
  kms_key_arn = aws_kms_key.backup_key.arn
}

# Backup Plan
resource "aws_backup_plan" "production_plan" {
  name = "production-backup-plan"

  rule {
    rule_name         = "daily-backup"
    target_vault_name = aws_backup_vault.production_vault.name
    schedule          = "cron(0 2 * * ? *)" # 2 AM daily

    lifecycle {
      delete_after = 30
    }
  }
}

# Backup Selection (tag based)
resource "aws_backup_selection" "production_selection" {
  name         = "production-backup-selection"
  plan_id      = aws_backup_plan.production_plan.id
  iam_role_arn = aws_iam_role.backup_role.arn

  selection_tag {
    type  = "STRINGEQUALS"
    key   = "Backup"
    value = "true"
  }
}

# IAM role used by AWS Backup to perform backups
resource "aws_iam_role" "backup_role" {
  name = "aws-backup-service-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect    = "Allow",
        Principal = { Service = "backup.amazonaws.com" },
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

# Attach AWS managed policy for backup operations
resource "aws_iam_role_policy_attachment" "backup_role_attach" {
  role       = aws_iam_role.backup_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}
