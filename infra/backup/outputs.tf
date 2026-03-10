output "backup_vault_name" {
  description = "Name of the AWS Backup vault"
  value       = aws_backup_vault.production_vault.name
}

output "backup_vault_arn" {
  description = "ARN of the AWS Backup vault"
  value       = aws_backup_vault.production_vault.arn
}

output "backup_plan_id" {
  description = "ID of the AWS Backup plan"
  value       = aws_backup_plan.production_plan.id
}

output "backup_plan_arn" {
  description = "ARN of the AWS Backup plan"
  value       = aws_backup_plan.production_plan.arn
}

output "backup_kms_key_arn" {
  description = "ARN of the KMS key used to encrypt the backup vault"
  value       = aws_kms_key.backup_key.arn
}

output "backup_role_arn" {
  description = "ARN of the IAM role assumed by AWS Backup"
  value       = aws_iam_role.backup_role.arn
}

output "backup_selection_id" {
  description = "ID of the AWS Backup selection"
  value       = aws_backup_selection.production_selection.id
}
