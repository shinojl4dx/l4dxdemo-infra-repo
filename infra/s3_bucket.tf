resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "example" {
  bucket = "my-sample-bucket-${random_id.suffix.hex}"
}
