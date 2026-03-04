provider "aws" {
  region = "ap-south-1"
}

data "aws_vpc" "default" {
  default = true
}

resource "aws_internet_gateway" "test_scp_igw" {
  vpc_id = data.aws_vpc.default.id
}