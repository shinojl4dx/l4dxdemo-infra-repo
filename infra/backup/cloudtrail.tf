# S3 bucket for CloudTrail logs
resource "aws_s3_bucket" "cloudtrail_logs" {
  bucket        = "backup-cloudtrail-logs-696192989304"
  force_destroy = true
}

# Allow CloudTrail to write logs
resource "aws_s3_bucket_policy" "cloudtrail_policy" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action = [
          "s3:GetBucketAcl",
          "s3:GetBucketLocation"
        ]
        Resource = aws_s3_bucket.cloudtrail_logs.arn
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail_logs.arn}/AWSLogs/696192989304/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

# CloudTrail
resource "aws_cloudtrail" "backup_trail" {
  name                          = "backup-monitoring-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail_logs.id
  include_global_service_events = true
  is_multi_region_trail         = true

  depends_on = [aws_s3_bucket_policy.cloudtrail_policy]
}

# EventBridge rule
resource "aws_cloudwatch_event_rule" "backup_plan_modified" {
  name        = "backup-plan-modified"
  description = "Alert if backup configuration is modified"

  event_pattern = jsonencode({
    source      = ["aws.backup"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventSource = ["backup.amazonaws.com"]
      eventName = [
        "UpdateBackupPlan",
        "DeleteBackupPlan",
        "DeleteBackupVault",
        "DeleteRecoveryPoint"
      ]
    }
  })
}

# Send alert to SNS
resource "aws_cloudwatch_event_target" "backup_change_to_sns" {
  rule      = aws_cloudwatch_event_rule.backup_plan_modified.name
  target_id = "SendBackupChangeAlert"
  arn       = aws_sns_topic.backup_alerts.arn
}
