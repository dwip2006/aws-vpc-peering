# ---------------- VPC A : 28.0.0.0/16 ----------------
resource "aws_vpc" "a" {
  cidr_block           = "28.0.0.0/16"
  enable_dns_hostnames = true
  tags                 = { Name = "vpc-a" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.a.id
  cidr_block              = "28.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.region}a"
  tags                    = { Name = "public-subnet" }
}

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.a.id
  cidr_block        = "28.0.2.0/24"
  availability_zone = "${var.region}a"
  tags              = { Name = "private-subnet-a" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.a.id
  tags   = { Name = "igw-a" }
}

# ---------------- VPC B : 28.200.0.0/16 ----------------
resource "aws_vpc" "b" {
  cidr_block = "28.200.0.0/16"
  tags       = { Name = "vpc-b" }
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.b.id
  cidr_block        = "28.200.1.0/24"
  availability_zone = "${var.region}a"
  tags              = { Name = "private-subnet-b" }
}

# ---------------- Peering ----------------
resource "aws_vpc_peering_connection" "ab" {
  vpc_id      = aws_vpc.a.id
  peer_vpc_id = aws_vpc.b.id
  auto_accept = true
  tags        = { Name = "peering-a-b" }
}

# ---------------- Route tables ----------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.a.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  # Needed so the public EC2 can also reach VPC B (e.g. as a jump host)
  route {
    cidr_block                = "28.200.0.0/16"
    vpc_peering_connection_id = aws_vpc_peering_connection.ab.id
  }

  tags = { Name = "rt-public" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private_a" {
  vpc_id = aws_vpc.a.id

  route {
    cidr_block                = "28.200.0.0/16"
    vpc_peering_connection_id = aws_vpc_peering_connection.ab.id
  }

  tags = { Name = "rt-private-a" }
}

resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private_a.id
}

resource "aws_route_table" "private_b" {
  vpc_id = aws_vpc.b.id

  route {
    cidr_block                = "28.0.0.0/16"
    vpc_peering_connection_id = aws_vpc_peering_connection.ab.id
  }

  tags = { Name = "rt-private-b" }
}

resource "aws_route_table_association" "private_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private_b.id
}

# ---------------- Security groups ----------------
resource "aws_security_group" "public" {
  name        = "sg-public"
  description = "SSH from client C"
  vpc_id      = aws_vpc.a.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "private_a" {
  name        = "sg-private-a"
  description = "From public subnet and VPC B"
  vpc_id      = aws_vpc.a.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["28.0.1.0/24", "28.200.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "private_b" {
  name        = "sg-private-b"
  description = "From VPC A"
  vpc_id      = aws_vpc.b.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["28.0.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ---------------- EC2 ----------------
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_instance" "public" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.public.id]
  key_name               = var.key_name
  tags                   = { Name = "ec2-public" }
}

resource "aws_instance" "private_a" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private_a.id
  vpc_security_group_ids = [aws_security_group.private_a.id]
  key_name               = var.key_name
  tags                   = { Name = "ec2-private-a" }
}

resource "aws_instance" "private_b" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private_b.id
  vpc_security_group_ids = [aws_security_group.private_b.id]
  key_name               = var.key_name
  tags                   = { Name = "ec2-private-b" }
}
