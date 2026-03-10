resource "aws_eip" "nat_eip" {
  domain = "vpc"
}

resource "aws_nat_gateway" "scp_nat_test" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = "subnet-0b29b7c1bbf347c38"

  tags = {
    Name = "scp-nat-test"
  }
}