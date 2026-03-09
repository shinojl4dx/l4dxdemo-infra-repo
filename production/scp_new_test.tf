resource "aws_s3_bucket" "scp_test_bucket" {
  bucket = "scp-test-bucket-aiswarya-002"

  tags = {
    Name        = "scp-test-bucket134"
    Environment = "test"
  }
}