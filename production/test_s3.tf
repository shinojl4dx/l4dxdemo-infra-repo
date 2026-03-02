data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "pipeline_test" {
  bucket_prefix = "l4dxdemo-production-test-"
  force_destroy = true

  tags = {
    Name        = "l4dxdemo-production-pipeline-test"
    TriggerNote = "retrigger-final-validation"
  }
}

resource "aws_s3_bucket_ownership_controls" "pipeline_test" {
  bucket = aws_s3_bucket.pipeline_test.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_public_access_block" "pipeline_test" {
  bucket = aws_s3_bucket.pipeline_test.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
