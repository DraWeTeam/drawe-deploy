############################################################
# VPC Endpoints — prod 아키텍처 반영
#
# private subnet 에서 NAT 를 경유하지 않고
# AWS 서비스에 직접 연결 → 비용 절감 + 속도 향상
############################################################

# ── S3 Gateway Endpoint (무료) ────────────────────────────
# ECR 이미지 레이어가 S3 에 저장되므로 이미지 pull 시 필수
resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.main.id
  service_name = "com.amazonaws.${var.aws_region}.s3"

  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = { Name = "${local.name_prefix}-vpce-s3" }
}

# 비용 절감 목적으로 S3 게이트웨이만 남기고 VPC 엔드포인트 제거
# ── ECR API Endpoint ──────────────────────────────────────
# docker login / image manifest 조회
#resource "aws_security_group" "vpce" {
#  name   = "${local.name_prefix}-vpce-sg"
#  vpc_id = aws_vpc.main.id

#  ingress {
#    description = "HTTPS from VPC"
#    from_port   = 443
#    to_port     = 443
#    protocol    = "tcp"
#    cidr_blocks = [var.vpc_cidr]
#  }

#  egress {
#    from_port   = 0
#    to_port     = 0
#    protocol    = "-1"
#    cidr_blocks = ["0.0.0.0/0"]
#  }

#  tags = { Name = "${local.name_prefix}-vpce-sg" }
#}

#resource "aws_vpc_endpoint" "ecr_api" {
#  vpc_id              = aws_vpc.main.id
#  service_name        = "com.amazonaws.${var.aws_region}.ecr.api"
#  vpc_endpoint_type   = "Interface"
#  private_dns_enabled = true

#  subnet_ids         = [aws_subnet.private_a.id, aws_subnet.private_c.id]
#  security_group_ids = [aws_security_group.vpce.id]

#  tags = { Name = "${local.name_prefix}-vpce-ecr-api" }
#}

# ── ECR Docker Endpoint ──────────────────────────────────
# docker pull (이미지 레이어 다운로드 요청)
#resource "aws_vpc_endpoint" "ecr_dkr" {
#  vpc_id              = aws_vpc.main.id
#  service_name        = "com.amazonaws.${var.aws_region}.ecr.dkr"
#  vpc_endpoint_type   = "Interface"
#  private_dns_enabled = true

#  subnet_ids         = [aws_subnet.private_a.id, aws_subnet.private_c.id]
#  security_group_ids = [aws_security_group.vpce.id]

#  tags = { Name = "${local.name_prefix}-vpce-ecr-dkr" }
#}

# ── CloudWatch Logs Endpoint ─────────────────────────────
# ECS 컨테이너 로그 전송 시 NAT 미경유
#resource "aws_vpc_endpoint" "logs" {
#  vpc_id              = aws_vpc.main.id
#  service_name        = "com.amazonaws.${var.aws_region}.logs"
#  vpc_endpoint_type   = "Interface"
#  private_dns_enabled = true

#  subnet_ids         = [aws_subnet.private_a.id, aws_subnet.private_c.id]
#  security_group_ids = [aws_security_group.vpce.id]

#  tags = { Name = "${local.name_prefix}-vpce-logs" }
#}
