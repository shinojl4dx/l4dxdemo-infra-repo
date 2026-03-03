# Production - VPC Flow Logs
resource "aws_flow_log" "prod_flow" {
  provider             = aws.production
  vpc_id               = "vpc-019343da7bf39376a"
  traffic_type         = "ALL"
  log_destination_type = "s3"

  log_destination = "arn:aws:s3:::l4dx-security-vpc-logs-696192989304"
}

# Production - CloudTrail

resource "aws_cloudtrail" "prod_trail" {
  provider                      = aws.production
  name                          = "prod-api-trail"

  s3_bucket_name                = "l4dx-security-cloudtrail-696192989304"

  include_global_service_events = true
  is_multi_region_trail         = true
  enable_logging                = true
}





