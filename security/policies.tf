resource "aws_s3_bucket_policy" "vpc_flow_policy" {
  provider = aws.security
  bucket   = aws_s3_bucket.vpc_logs.id

  # Ensure public access block is applied first
  depends_on = [
    aws_s3_bucket_public_access_block.vpc_block
  ]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSLogDeliveryWrite"
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action = "s3:PutObject"
        Resource = "${aws_s3_bucket.vpc_logs.arn}/AWSLogs/696192989304/*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = "696192989304",
            "s3:x-amz-acl"      = "bucket-owner-full-control"
          }
        }
      },
      {
        Sid    = "AWSLogDeliveryAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.vpc_logs.arn
      }
    ]
  })
}
#####################################
# CloudTrail Bucket Policy
#####################################

resource "aws_s3_bucket_policy" "cloudtrail_policy" {
  provider = aws.security
  bucket   = aws_s3_bucket.cloudtrail_logs.id

  depends_on = [
    aws_s3_bucket_public_access_block.cloudtrail_block
  ]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail_logs.arn
      },
      {
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail_logs.arn}/AWSLogs/696192989304/*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = "696192989304"
          }
        }
      }
    ]
  })
}
