############################################################
# VPC Endpoints
#
# NAT GW 트래픽 비용 절감 + 속도 향상
# (vpce SG 는 security-groups.tf 에 정의됨)
############################################################

# ── S3 Gateway Endpoint (무료) ────────────────────────────
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"

  # prod 는 AZ 별 route table 분리 - 둘 다 등록
  route_table_ids = [
    aws_route_table.private_a.id,
    aws_route_table.private_c.id,
  ]

  tags = { Name = "${local.name_prefix}-vpce-s3" }
}

# ── ECR API ──────────────────────────────────────────────
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids         = [aws_subnet.private_a.id, aws_subnet.private_c.id]
  security_group_ids = [aws_security_group.vpce.id]

  tags = { Name = "${local.name_prefix}-vpce-ecr-api" }
}

# ── ECR Docker ───────────────────────────────────────────
resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids         = [aws_subnet.private_a.id, aws_subnet.private_c.id]
  security_group_ids = [aws_security_group.vpce.id]

  tags = { Name = "${local.name_prefix}-vpce-ecr-dkr" }
}

# ── CloudWatch Logs ──────────────────────────────────────
resource "aws_vpc_endpoint" "logs" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.logs"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids         = [aws_subnet.private_a.id, aws_subnet.private_c.id]
  security_group_ids = [aws_security_group.vpce.id]

  tags = { Name = "${local.name_prefix}-vpce-logs" }
}

# ── SSM (Parameter Store 접근) ───────────────────────────
resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ssm"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids         = [aws_subnet.private_a.id, aws_subnet.private_c.id]
  security_group_ids = [aws_security_group.vpce.id]

  tags = { Name = "${local.name_prefix}-vpce-ssm" }
}
