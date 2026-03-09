resource "aws_internet_gateway" "example_igw" {
  vpc_id = "vpc-019343da7bf39376a"

  tags = {
    Name = "example-new-igw"
  }
}