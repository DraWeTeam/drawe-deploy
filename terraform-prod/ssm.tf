############################################################
# SSM Parameter Store - prod
#
# dev 와 차이:
# - Grafana Cloud 시크릿 없음 (self-host 라)
# - Loki / Tempo config (base64 encoded YAML)
# - Grafana admin 비밀번호
############################################################

# ── TF 가 진실의 소스 ──────────────────────────────────
resource "aws_ssm_parameter" "db_username" {
  name  = "/${var.project}/${var.env}/db-username"
  type  = "String"
  value = var.db_username
}

resource "aws_ssm_parameter" "db_password" {
  name  = "/${var.project}/${var.env}/db-password"
  type  = "SecureString"
  value = local.db_password
}

resource "aws_ssm_parameter" "redis_password" {
  name  = "/${var.project}/${var.env}/redis-password"
  type  = "SecureString"
  value = local.valkey_auth_token
}

resource "random_password" "grafana_admin" {
  length           = 24
  special          = true
  override_special = "!#$%&*-_=+"
}

resource "aws_ssm_parameter" "grafana_admin_password" {
  name  = "/${var.project}/${var.env}/grafana-admin-password"
  type  = "SecureString"
  value = random_password.grafana_admin.result
}

# Loki / Tempo config - tier="Standard" (압축 안 함, entrypoint 가 gunzip 안 하므로)
resource "aws_ssm_parameter" "loki_config" {
  name  = "/${var.project}/${var.env}/loki-config-b64"
  type  = "SecureString"
  value = base64encode(file("${path.module}/../configs/loki-config.yaml"))
  tier  = "Standard"
}

resource "aws_ssm_parameter" "tempo_config" {
  name  = "/${var.project}/${var.env}/tempo-config-b64"
  type  = "SecureString"
  value = base64encode(file("${path.module}/../configs/tempo-config.yaml"))
  tier  = "Standard"
}

# Alloy config (prod) — base64gzip + Standard
resource "aws_ssm_parameter" "alloy_config" {
  name  = "/${var.project}/${var.env}/alloy-config-b64"
  type  = "SecureString"
  value = base64gzip(file("${path.module}/../configs/alloy-sidecar-prod.alloy"))
  tier  = "Standard"
}

resource "aws_ssm_parameter" "alloy_daemon_config" {
  name  = "/${var.project}/${var.env}/alloy-daemon-config-b64"
  type  = "SecureString"
  value = base64gzip(file("${path.module}/../configs/alloy-daemon.alloy"))
  tier  = "Standard"
}

# ── 사용자 manual update ─────────────────────────────
resource "aws_ssm_parameter" "jwt_secret" {
  name  = "/${var.project}/${var.env}/jwt-secret"
  type  = "SecureString"
  value = "CHANGE_ME_jwt_secret_base64_at_least_64_chars"
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "grok_api_key" {
  name  = "/${var.project}/${var.env}/grok-api-key"
  type  = "SecureString"
  value = "CHANGE_ME"
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "claude_api_key" {
  name  = "/${var.project}/${var.env}/claude-api-key"
  type  = "SecureString"
  value = "CHANGE_ME"
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "gemini_api_key" {
  name  = "/${var.project}/${var.env}/gemini-api-key"
  type  = "SecureString"
  value = "CHANGE_ME"
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "google_client_id" {
  name  = "/${var.project}/${var.env}/google-client-id"
  type  = "SecureString"
  value = "CHANGE_ME"
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "google_client_secret" {
  name  = "/${var.project}/${var.env}/google-client-secret"
  type  = "SecureString"
  value = "CHANGE_ME"
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "pinecone_api_key" {
  name  = "/${var.project}/${var.env}/pinecone-api-key"
  type  = "SecureString"
  value = "CHANGE_ME"
  lifecycle { ignore_changes = [value] }
}

# ── Pinecone host & index - backend application.properties 신규 키 ──
resource "aws_ssm_parameter" "pinecone_host" {
  name  = "/${var.project}/${var.env}/pinecone-host"
  type  = "String"
  value = "CHANGE_ME_pinecone_host_url"
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "pinecone_index" {
  name  = "/${var.project}/${var.env}/pinecone-index"
  type  = "String"
  value = "CHANGE_ME_pinecone_index_name"
  lifecycle { ignore_changes = [value] }
}
