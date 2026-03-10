resource "aws_instance" "public_test" {
  ami                         = "ami-019715e0d74f695be"
  instance_type               = "t2.micro"
  subnet_id                   = "subnet-0b29b7c1bbf347c38"
  associate_public_ip_address = true

  tags = {
    Name = "scp-test-instance"
  }
}