

resource "aws_vpc" "production_vpc" {
  cidr_block           = var.production_vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "production-vpc"
  }
}


# Public Subnet 1


resource "aws_subnet" "public_subnet_1" {
  vpc_id            = aws_vpc.production_vpc.id
  cidr_block        = var.production_subnet1_cidr


  tags = {
    Name = "production-public-subnet-1"
  }
}

# Private Subnet 2

resource "aws_subnet" "private_subnet_1" {
  vpc_id            = aws_vpc.production_vpc.id
  cidr_block        = var.production_subnet2_cidr

  tags = {
    Name = "production-private-subnet-2"
  }
}

# Private Subnet 3


resource "aws_subnet" "private_subnet_2" {
  vpc_id            = aws_vpc.production_vpc.id
  cidr_block        = var.production_subnet3_cidr


  tags = {
    Name = "production-private-subnet-3"
  }
}

# INTERNET GATEWAY

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.production_vpc.id

  tags = {
    Name = "production-igw"
  }
}

# ELASTIC IP FOR NAT

resource "aws_eip" "nat_eip" {
  domain = "vpc"
}


# NAT GATEWAY (Placed in Public Subnet)

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnet_1.id

  tags = {
    Name = "production-nat"
  }

  depends_on = [aws_internet_gateway.igw]
}
# Public Route Table

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.production_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "production-public-rt"
  }
}
resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public_subnet_1.id
  route_table_id = aws_route_table.public_route_table.id
}

# Private Route Table

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.production_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "production-private-rt"
  }
}

# Route Table Associations



resource "aws_route_table_association" "private_assoc_1" {
  subnet_id      = aws_subnet.private_subnet_1.id
  route_table_id = aws_route_table.private_route_table.id
}

resource "aws_route_table_association" "private_assoc_2" {
  subnet_id      = aws_subnet.private_subnet_2.id
  route_table_id = aws_route_table.private_route_table.id
}


# EC2 Security Group
/* resource "aws_security_group" "ec2_sg" {
  name        = "ec2-security-group"
  description = "Allow SSH and HTTP"
  vpc_id      = aws_vpc.production_vpc.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#AMI 
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

# EC2 INSTANCE IN PUBLIC SUBNET 
resource "aws_instance" "public_ec2" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.public_subnet_1.id
  vpc_security_group_ids      = [aws_security_group.ec2_sg.id]
  associate_public_ip_address = true
  key_name               = "test-key" 

  tags = {
    Name = "production-public-ec2"
  }
}

# EC2 IN PRIVATE SUBNET 2

resource "aws_instance" "private_ec2" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.private_subnet_1.id
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  key_name               = "test-key" 

  tags = {
    Name = "production-private-ec2"
  }
} */