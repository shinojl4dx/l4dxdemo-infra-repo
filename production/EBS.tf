resource "aws_ebs_volume" "unencrypted_test" {
  availability_zone = "ap-south-1a"
  size              = 10
  encrypted         = false
}