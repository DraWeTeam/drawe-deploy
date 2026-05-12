############################################################
# SSM Parameter Store
#
# 두 카테고리:
# 1) Terraform 이 직접 관리하는 시크릿 (db_password, redis_password)
#    → random_password 로 생성된 값. 사용자가 만질 일 없음.
# 2) 사용자가 직접 입력해야 하는 시크릿 (API keys, OAuth, JWT)
#    → placeholder 로 생성, lifecycle ignore_changes 로 보호
############################################################

# ── Category 1: TF 가 진실의 소스 ───────────────────────
resource "aws_ssm_parameter" "db_username" {
  name  = "/${var.project}/${var.env}/db-username"
  type  = "String"
  value = var.db_username
  tags  = { Name = "${local.name_prefix}-db-username" }
}

resource "aws_ssm_parameter" "db_password" {
  name  = "/${var.project}/${var.env}/db-password"
  type  = "SecureString"
  value = local.db_password
  tags  = { Name = "${local.name_prefix}-db-password" }
}

resource "aws_ssm_parameter" "redis_password" {
  name  = "/${var.project}/${var.env}/redis-password"
  type  = "SecureString"
  value = local.valkey_password
  tags  = { Name = "${local.name_prefix}-redis-password" }
}

# ── Category 2: 사용자가 manual update ─────────────────
# 첫 apply 후 다음 명령으로 실제 값 입력:
#   aws ssm put-parameter --name "/drawe/dev/jwt-secret" \
#       --value "<base64 64chars+>" --type SecureString --overwrite
resource "aws_ssm_parameter" "jwt_secret" {
  name  = "/${var.project}/${var.env}/jwt-secret"
  type  = "SecureString"
  value = "CHANGE_ME_jwt_secret_base64_at_least_64_chars"
  tags  = { Name = "${local.name_prefix}-jwt-secret" }

  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "grok_api_key" {
  name  = "/${var.project}/${var.env}/grok-api-key"
  type  = "SecureString"
  value = "CHANGE_ME"
  tags  = { Name = "${local.name_prefix}-grok-api-key" }
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "claude_api_key" {
  name  = "/${var.project}/${var.env}/claude-api-key"
  type  = "SecureString"
  value = "CHANGE_ME"
  tags  = { Name = "${local.name_prefix}-claude-api-key" }
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "gemini_api_key" {
  name  = "/${var.project}/${var.env}/gemini-api-key"
  type  = "SecureString"
  value = "CHANGE_ME"
  tags  = { Name = "${local.name_prefix}-gemini-api-key" }
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "google_client_id" {
  name  = "/${var.project}/${var.env}/google-client-id"
  type  = "SecureString"
  value = "CHANGE_ME"
  tags  = { Name = "${local.name_prefix}-google-client-id" }
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "google_client_secret" {
  name  = "/${var.project}/${var.env}/google-client-secret"
  type  = "SecureString"
  value = "CHANGE_ME"
  tags  = { Name = "${local.name_prefix}-google-client-secret" }
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "pinecone_api_key" {
  name  = "/${var.project}/${var.env}/pinecone-api-key"
  type  = "SecureString"
  value = "CHANGE_ME"
  tags  = { Name = "${local.name_prefix}-pinecone-api-key" }
  lifecycle { ignore_changes = [value] }
}

# ── Pinecone host & index — backend application.properties 신규 키 ──
# host:  https://<index-name>-<project>.svc.<environment>.pinecone.io
# index: 인덱스 이름 (drawe-images 등)
resource "aws_ssm_parameter" "pinecone_host" {
  name  = "/${var.project}/${var.env}/pinecone-host"
  type  = "String"
  value = "CHANGE_ME_pinecone_host_url"
  tags  = { Name = "${local.name_prefix}-pinecone-host" }
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "pinecone_index" {
  name  = "/${var.project}/${var.env}/pinecone-index"
  type  = "String"
  value = "CHANGE_ME_pinecone_index_name"
  tags  = { Name = "${local.name_prefix}-pinecone-index" }
  lifecycle { ignore_changes = [value] }
}

############################################################
# Observability — Grafana Cloud (dev only)
#
# prod 환경에선 self-host 라 다른 시크릿 셋. terraform-prod/ssm.tf 참조.
############################################################
resource "aws_ssm_parameter" "alloy_config" {
  name  = "/${var.project}/${var.env}/alloy-config-b64"
  type  = "SecureString"
  value = base64gzip(file("${path.module}/../configs/alloy-sidecar.alloy"))
  tier  = "Advanced"
  tags  = { Name = "${local.name_prefix}-alloy-config" }
}

resource "aws_ssm_parameter" "alloy_daemon_config" {
  name  = "/${var.project}/${var.env}/alloy-daemon-config-b64"
  type  = "SecureString"
  value = "CHANGE_ME_base64_encoded_alloy_daemon_config"
  tier  = "Advanced"
  tags  = { Name = "${local.name_prefix}-alloy-daemon-config" }
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "grafana_otlp_endpoint" {
  name  = "/${var.project}/${var.env}/grafana-otlp-endpoint"
  type  = "String"
  value = "CHANGE_ME_https_otlp_gateway_prod_xx_grafana_net_otlp"
  tags  = { Name = "${local.name_prefix}-grafana-otlp-endpoint" }
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "grafana_instance_id" {
  name  = "/${var.project}/${var.env}/grafana-instance-id"
  type  = "String"
  value = "CHANGE_ME_instance_id"
  tags  = { Name = "${local.name_prefix}-grafana-instance-id" }
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "grafana_cloud_token" {
  name  = "/${var.project}/${var.env}/grafana-cloud-token"
  type  = "SecureString"
  value = "CHANGE_ME_grafana_cloud_token"
  tags  = { Name = "${local.name_prefix}-grafana-cloud-token" }
  lifecycle { ignore_changes = [value] }
}
