# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"
}

#Retrieve the list of AZs in the current AWS region
data "aws_availability_zones" "available" {}
data "aws_region" "current" {}

# Terraform Data Block - Lookup Ubuntu 20.04
data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"]
}

#Define the VPC 
resource "aws_vpc" "vpc" {
  cidr_block = var.vpc_cidr

  tags = {
    Name        = var.vpc_name
    Environment = "demo_environment"
    Terraform   = "true"
  }
}

#Deploy the private subnets
resource "aws_subnet" "private_subnets" {
  for_each          = var.private_subnets
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, each.value)
  availability_zone = tolist(data.aws_availability_zones.available.names)[each.value]

  tags = {
    Name      = each.key
    Terraform = "true"
  }
}

#Deploy the public subnets
resource "aws_subnet" "public_subnets" {
  for_each                = var.public_subnets
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, each.value + 100)
  availability_zone       = tolist(data.aws_availability_zones.available.names)[each.value]
  map_public_ip_on_launch = true

  tags = {
    Name      = each.key
    Terraform = "true"
  }
}

#Create route tables for public and private subnets
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internet_gateway.id
    #nat_gateway_id = aws_nat_gateway.nat_gateway.id
  }
  tags = {
    Name      = "demo_public_rtb"
    Terraform = "true"
  }
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    # gateway_id     = aws_internet_gateway.internet_gateway.id
    nat_gateway_id = aws_nat_gateway.nat_gateway.id
  }
  tags = {
    Name      = "demo_private_rtb"
    Terraform = "true"
  }
}

#Create route table associations
resource "aws_route_table_association" "public" {
  depends_on     = [aws_subnet.public_subnets]
  route_table_id = aws_route_table.public_route_table.id
  for_each       = aws_subnet.public_subnets
  subnet_id      = each.value.id
}

resource "aws_route_table_association" "private" {
  depends_on     = [aws_subnet.private_subnets]
  route_table_id = aws_route_table.private_route_table.id
  for_each       = aws_subnet.private_subnets
  subnet_id      = each.value.id
}

#Create Internet Gateway
resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "demo_igw"
  }
}

#Create EIP for NAT Gateway
resource "aws_eip" "nat_gateway_eip" {
  vpc        = true
  depends_on = [aws_internet_gateway.internet_gateway]
  tags = {
    Name = "demo_igw_eip"
  }
}

#Create NAT Gateway
resource "aws_nat_gateway" "nat_gateway" {
  depends_on    = [aws_subnet.public_subnets]
  allocation_id = aws_eip.nat_gateway_eip.id
  subnet_id     = aws_subnet.public_subnets["public_subnet_1"].id
  tags = {
    Name = "demo_nat_gateway"
  }
}

# Terraform Resource Block - To Build EC2 instance in public Subnet
resource "aws_instance" "web_server" {                                     
  ami                    = data.aws_ami.ubuntu.id                          
  instance_type          = "t2.micro"                                      
  subnet_id              = aws_subnet.public_subnets["public_subnet_1"].id 
  key_name               = aws_key_pair.ssh_key_pair.key_name
  vpc_security_group_ids = values(aws_security_group.ec2_sg)[*].id


  tags = {
    Name = "Web EC2 Server"
  }
}

# EC2 Security group
resource "aws_security_group" "ec2_sg" {
  name        = "EC2_SG-${each.key}"
  description = "Grupo de seguridad para EC2"
  # for_each    = toset(var.allowed_ports)
  for_each = toset([for port in var.allowed_ports : tostring(port)])
  vpc_id      = aws_vpc.vpc.id


  ingress {
    from_port   = each.key
    to_port     = each.key
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "Web EC2 sg"
  }
}

# SSH Key assingment
resource "aws_key_pair" "ssh_key_pair" {
  key_name   = "ssh_key"
  public_key = file("ssh_key.pub")
}

# RDS MySQL Data Base
resource "aws_db_instance" "rds_instance" {
  engine                 = "mysql"
  instance_class         = "db.t2.micro"
  allocated_storage      = 20
  storage_type           = "gp2"
  db_subnet_group_name   = aws_db_subnet_group.db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  skip_final_snapshot    = true
  username               = "admin"
  password               = "password"

  tags = {
    Name = "RDS_Instance"
  }
}

# Subnet group RDS
resource "aws_db_subnet_group" "db_subnet_group" {
  name       = "db_subnet_group"
  subnet_ids = values(aws_subnet.private_subnets)[*].id
  tags = {
    Name = "DB_Subnet_Group"
  }
}

# RDS Security Group
resource "aws_security_group" "rds_sg" {
  name        = "RDS_SG"
  description = "Grupo de seguridad para RDS"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = values(aws_security_group.ec2_sg)[*].id
  }
  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "RDS_SG"
  }
}

# SSL certificate ACM
resource "aws_acm_certificate" "ssl_certificate" {
  domain_name       = "leonardotorresbenitez900608.com" # Reemplaza con tu propio dominio
  validation_method = "DNS"

  tags = {
    Name = "SSL_Certificate"
  }
}

