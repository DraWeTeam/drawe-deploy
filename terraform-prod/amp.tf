############################################################
# AMP - Amazon Managed Service for Prometheus
#
# Mimir self-host 의 관리형 대체. metric ingest 종량 과금.
# Alloy 가 prometheus.remote_write 로 데이터 push, Grafana 가 query.
#
# 한국 리전 (ap-northeast-2) 에서 정식 제공.
############################################################

resource "aws_prometheus_workspace" "main" {
  alias = "${local.name_prefix}-amp"

  logging_configuration {
    log_group_arn = "${aws_cloudwatch_log_group.amp.arn}:*"
  }

  tags = { Name = "${local.name_prefix}-amp" }
}

resource "aws_cloudwatch_log_group" "amp" {
  name              = "/aws/prometheus/${local.name_prefix}-amp"
  retention_in_days = 14

  tags = { Name = "${local.name_prefix}-amp-logs" }
}
