resource "aws_s3_bucket" "scp_test_bucket" {
  bucket = "scp-test-bucket-aiswarya-001"

  tags = {
    Name        = "scp-test-bucket"
    Environment = "test"
  }
}

resource "aws_s3_bucket" "scp_test_bucket_2" {
  bucket = "scp-test-bucket-aiswarya-002"

  tags = {
    Name        = "scp-test-bucket-2"
    Environment = "test"
  }
}