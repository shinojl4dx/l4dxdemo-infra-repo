resource "aws_s3_bucket" "scp_test_bucket_demo" {
  bucket = "scp-test-bucket-terraform-demo-12345"

  tags = {
    Name        = "scp-test1908"
    Environment = "test"
  }
}