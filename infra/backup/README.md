# AWS Backup Module (Production)

This Terraform module implements an automated backup solution for the production account using **AWS Backup**.

## Overview

The solution protects AWS resources using **tag-based backup selection** and provides monitoring for backup failures and backup configuration changes.

Resources tagged with:

Backup = true

are automatically protected by the backup plan.

---

## Architecture

EC2 / RDS
   ↓
Lambda automatically tags resources (Backup=true)
   ↓
AWS Backup detects tagged resources
   ↓
Backup jobs run based on backup plan
   ↓
Recovery points stored in encrypted backup vault
   ↓
CloudTrail logs backup configuration changes
   ↓
EventBridge detects events
   ↓
SNS sends alert emails

---

## Resources Created

### Backup Infrastructure
- KMS key for backup vault encryption
- AWS Backup Vault
- AWS Backup Plan
- Backup Selection (tag-based)

### Monitoring
- SNS topic for alerts
- EventBridge rule for backup job failures
- EventBridge rule for restore job failures

### Security Monitoring
- CloudTrail trail
- S3 bucket for CloudTrail logs
- EventBridge rule for backup plan modifications

---

## Backup Configuration

Backup Plan:

- Frequency: Daily
- Retention: 30 days
- Backup Vault: `production-backup-vault`

---

## Tag-based Backup

Any supported AWS resource with the tag:

Backup = true

will automatically be included in the backup plan.

Example:

EC2
RDS
EBS

---

## Alerts

SNS email alerts are triggered for:

- Backup job failure
- Restore job failure
- Backup plan modification

---

## Deployment

1. Login using AWS SSO:
2. Initialize Terraform:
3. Review changes:
4. Apply infrastructure:


---

## Testing Performed

The following scenarios were tested:

- Successful backup creation
- On-demand backup
- Backup plan modification alerts
- SNS notifications

---
