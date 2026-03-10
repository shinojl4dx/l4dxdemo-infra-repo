variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "ap-south-1"
}

variable "alert_email" {
  description = "Email address to receive AWS Backup alerts"
  type        = string
}
