############################################################
# ALB
#
# inbound: Cloudflare IPv4 만 :443 허용 (Full Strict).
# :80 은 listener 도 SG 도 없음 - CF 가 :443 으로만 connect 함.
############################################################
resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb-sg"
  description = "ALB ingress - Cloudflare edges only on :443"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS from Cloudflare edge only"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = local.cloudflare_ipv4_ranges
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-alb-sg" }
}

############################################################
# ECS instances (ASG members)
############################################################
resource "aws_security_group" "ecs_instance" {
  name        = "${local.name_prefix}-ecs-instance-sg"
  description = "ECS EC2 hosts"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-ecs-instance-sg" }
}

############################################################
# Backend task ENI
############################################################
resource "aws_security_group" "ecs_backend" {
  name        = "${local.name_prefix}-ecs-backend-sg"
  description = "Backend Spring Boot task"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "From ALB on 8080"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-ecs-backend-sg" }
}

############################################################
# FastAPI task ENI (내부 호출만)
############################################################
resource "aws_security_group" "ecs_fastapi" {
  name        = "${local.name_prefix}-ecs-fastapi-sg"
  description = "FastAPI CLIP task"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "From Backend on 8000"
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_backend.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-ecs-fastapi-sg" }
}

############################################################
# Observability task ENI (Loki, Tempo, Grafana)
############################################################
resource "aws_security_group" "ecs_observability" {
  name        = "${local.name_prefix}-ecs-observability-sg"
  description = "Loki / Tempo / Grafana"
  vpc_id      = aws_vpc.main.id

  # Loki HTTP - app Alloy sidecar 가 push
  ingress {
    description     = "Loki HTTP from app tasks"
    from_port       = 3100
    to_port         = 3100
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_backend.id, aws_security_group.ecs_fastapi.id]
  }

  # Tempo OTLP gRPC + HTTP - app Alloy sidecar 가 push
  ingress {
    description     = "Tempo OTLP gRPC from app tasks"
    from_port       = 4317
    to_port         = 4317
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_backend.id, aws_security_group.ecs_fastapi.id]
  }
  ingress {
    description     = "Tempo OTLP HTTP from app tasks"
    from_port       = 4318
    to_port         = 4318
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_backend.id, aws_security_group.ecs_fastapi.id]
  }

  # Grafana HTTP - ALB 만
  ingress {
    description     = "Grafana from ALB"
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # Grafana → Loki/Tempo (self ingress for observability stack)
  ingress {
    description = "Grafana to Loki query / Tempo query (self)"
    from_port   = 3200
    to_port     = 3200
    protocol    = "tcp"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-ecs-observability-sg" }
}

############################################################
# RDS
############################################################
resource "aws_security_group" "rds" {
  name        = "${local.name_prefix}-rds-sg"
  description = "RDS MySQL - only from ECS tasks"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "MySQL from backend"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_backend.id]
  }

  ingress {
    description     = "MySQL from grafana (session DB)"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_observability.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-rds-sg" }
}

############################################################
# ElastiCache (Valkey)
############################################################
resource "aws_security_group" "valkey" {
  name        = "${local.name_prefix}-valkey-sg"
  description = "ElastiCache Valkey"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Valkey from backend"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_backend.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-valkey-sg" }
}

############################################################
# VPC endpoints (interface)
############################################################
resource "aws_security_group" "vpce" {
  name        = "${local.name_prefix}-vpce-sg"
  description = "VPC interface endpoints"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-vpce-sg" }
}
