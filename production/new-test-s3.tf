resource "aws_s3_bucket" "scp_test_bucket" {
  bucket = "scp-test-bucket-aiswarya-007"

  tags = {
    Name        = "scp-test-bucket90023"
    Environment = "test"
  }
}