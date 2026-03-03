#####################################
# Security Account - S3 Buckets
#####################################

resource "aws_s3_bucket" "vpc_logs" {
  provider = aws.security
  bucket   = "l4dx-security-vpc-logs-696192989304"
  force_destroy = true
}

resource "aws_s3_bucket" "cloudtrail_logs" {
  provider = aws.security
  bucket   = "l4dx-security-cloudtrail-696192989304"
  force_destroy = true
}

#####################################
# Block Public Access (IMPORTANT)
#####################################

resource "aws_s3_bucket_public_access_block" "vpc_block" {
  provider = aws.security
  bucket   = aws_s3_bucket.vpc_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "cloudtrail_block" {
  provider = aws.security
  bucket   = aws_s3_bucket.cloudtrail_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

#####################################
# Enable Versioning
#####################################

resource "aws_s3_bucket_versioning" "vpc_versioning" {
  provider = aws.security
  bucket   = aws_s3_bucket.vpc_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "cloudtrail_versioning" {
  provider = aws.security
  bucket   = aws_s3_bucket.cloudtrail_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}
