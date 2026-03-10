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
    schedule          = "cron(0 2 * * ? *)"

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
# Monitoring: SNS + EventBridge


resource "aws_sns_topic" "backup_alerts" {
  name = "backup-alerts"
}

resource "aws_sns_topic_subscription" "backup_alerts_email" {
  topic_arn = aws_sns_topic.backup_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# Allow EventBridge to publish to SNS
resource "aws_sns_topic_policy" "backup_alerts_policy" {
  arn = aws_sns_topic.backup_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid       = "AllowEventBridgePublish",
        Effect    = "Allow",
        Principal = { Service = "events.amazonaws.com" },
        Action    = "sns:Publish",
        Resource  = aws_sns_topic.backup_alerts.arn
      }
    ]
  })
}

# Backup job failed/aborted
resource "aws_cloudwatch_event_rule" "backup_job_failed" {
  name        = "backup-job-failed"
  description = "Alert when AWS Backup job fails or aborts"

  event_pattern = jsonencode({
    source      = ["aws.backup"],
    detail-type = ["Backup Job State Change"],
    detail = {
      state = ["FAILED", "ABORTED"]
    }
  })
}

resource "aws_cloudwatch_event_target" "backup_job_failed_to_sns" {
  rule      = aws_cloudwatch_event_rule.backup_job_failed.name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.backup_alerts.arn
}

# Restore job failed/aborted
resource "aws_cloudwatch_event_rule" "restore_job_failed" {
  name        = "restore-job-failed"
  description = "Alert when AWS Backup restore job fails or aborts"

  event_pattern = jsonencode({
    source      = ["aws.backup"],
    detail-type = ["Restore Job State Change"],
    detail = {
      status = ["FAILED", "ABORTED"]
    }
  })
}

resource "aws_cloudwatch_event_target" "restore_job_failed_to_sns" {
  rule      = aws_cloudwatch_event_rule.restore_job_failed.name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.backup_alerts.arn
}
