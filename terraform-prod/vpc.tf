############################################################
# VPC - prod
############################################################
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${local.name_prefix}-vpc" }
}

############################################################
# Subnets - public/private × 2 AZ
############################################################
resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.10.1.0/24"
  availability_zone       = var.az_a
  map_public_ip_on_launch = true
  tags                    = { Name = "${local.name_prefix}-pub-a" }
}

resource "aws_subnet" "public_c" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.10.2.0/24"
  availability_zone       = var.az_c
  map_public_ip_on_launch = true
  tags                    = { Name = "${local.name_prefix}-pub-c" }
}

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.10.10.0/24"
  availability_zone = var.az_a
  tags              = { Name = "${local.name_prefix}-priv-a" }
}

resource "aws_subnet" "private_c" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.10.11.0/24"
  availability_zone = var.az_c
  tags              = { Name = "${local.name_prefix}-priv-c" }
}

############################################################
# Internet Gateway
############################################################
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${local.name_prefix}-igw" }
}

############################################################
# Public Route Table
############################################################
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${local.name_prefix}-rt-pub" }

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "pub_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "pub_c" {
  subnet_id      = aws_subnet.public_c.id
  route_table_id = aws_route_table.public.id
}

############################################################
# Private Route Tables - AZ 별로 분리
#
# 0.0.0.0/0 route 는 inline 으로 안 정의함.
# fck-nat instance 가 부팅 시 자기 ENI 로 route 를 dynamic 하게 추가/갱신.
# 따라서 lifecycle ignore_changes 로 Terraform 이 그 route 를 안 건드리게 함.
# (S3 prefix list route 는 vpc-endpoints.tf 의 aws_vpc_endpoint 가 관리 - 별도)
############################################################
resource "aws_route_table" "private_a" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${local.name_prefix}-rt-priv-a" }

  lifecycle {
    ignore_changes = [route]
  }
}

resource "aws_route_table" "private_c" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${local.name_prefix}-rt-priv-c" }

  lifecycle {
    ignore_changes = [route]
  }
}

resource "aws_route_table_association" "priv_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private_a.id
}

resource "aws_route_table_association" "priv_c" {
  subnet_id      = aws_subnet.private_c.id
  route_table_id = aws_route_table.private_c.id
}
