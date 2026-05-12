############################################################
# Log Groups
############################################################
resource "aws_cloudwatch_log_group" "backend" {
  name              = "/ecs/${local.name_prefix}-backend"
  retention_in_days = 30
  tags              = { Name = "${local.name_prefix}-backend-logs" }
}

resource "aws_cloudwatch_log_group" "fastapi" {
  name              = "/ecs/${local.name_prefix}-fastapi"
  retention_in_days = 30
  tags              = { Name = "${local.name_prefix}-fastapi-logs" }
}

resource "aws_cloudwatch_log_group" "alloy" {
  name              = "/ecs/${local.name_prefix}-alloy"
  retention_in_days = 14
  tags              = { Name = "${local.name_prefix}-alloy-logs" }
}

resource "aws_cloudwatch_log_group" "observability" {
  name              = "/ecs/${local.name_prefix}-observability"
  retention_in_days = 14
  tags              = { Name = "${local.name_prefix}-observability-logs" }
}

############################################################
# SNS Topic - Critical Alarms
#
# email subscription 은 사용자가 SNS 콘솔에서 manual confirm
############################################################
resource "aws_sns_topic" "alerts" {
  name = "${local.name_prefix}-alerts"
  tags = { Name = "${local.name_prefix}-alerts" }
}

variable "alert_email" {
  description = "Critical alarm 받을 이메일 (선택)"
  type        = string
  default     = ""
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

############################################################
# SAFETY-NET Alarms
#
# ⌁ 핵심 원칙: self-host LGTM stack 이 죽어도 작동해야 함.
# 따라서 모든 critical alarm 은 CloudWatch native metric 사용.
# Loki/Tempo/Grafana 가 다운돼도 SNS 알림은 계속 작동.
############################################################

# ── Backend ECS Service: 정상 task 수 < desired ──────────
resource "aws_cloudwatch_metric_alarm" "backend_unhealthy" {
  alarm_name          = "${local.name_prefix}-backend-unhealthy"
  alarm_description   = "Backend ECS service running task < desired (서비스 다운 또는 기동 실패)"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "RunningTaskCount"
  namespace           = "ECS/ContainerInsights"
  period              = 60
  statistic           = "Average"
  threshold           = var.backend_desired_count

  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.backend.name
  }

  alarm_actions      = [aws_sns_topic.alerts.arn]
  ok_actions         = [aws_sns_topic.alerts.arn]
  treat_missing_data = "breaching"
}

# ── FastAPI ECS: 정상 task 수 < desired ─────────────────
resource "aws_cloudwatch_metric_alarm" "fastapi_unhealthy" {
  alarm_name          = "${local.name_prefix}-fastapi-unhealthy"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "RunningTaskCount"
  namespace           = "ECS/ContainerInsights"
  period              = 60
  statistic           = "Average"
  threshold           = var.fastapi_desired_count

  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.fastapi.name
  }

  alarm_actions      = [aws_sns_topic.alerts.arn]
  treat_missing_data = "breaching"
}

# ── ALB: 5xx 비율 ───────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "alb_5xx_high" {
  alarm_name          = "${local.name_prefix}-alb-5xx-high"
  alarm_description   = "ALB 5xx > 10/min for 3 min - backend 장애 추정"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 10

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
  }

  alarm_actions      = [aws_sns_topic.alerts.arn]
  treat_missing_data = "notBreaching"
}

# ── ALB: target health ─────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_targets" {
  alarm_name          = "${local.name_prefix}-alb-unhealthy-targets"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
    TargetGroup  = aws_lb_target_group.backend.arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}

# ── RDS CPU high ───────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "rds_cpu_high" {
  alarm_name          = "${local.name_prefix}-rds-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 5
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = 80

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.identifier
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}

# ── RDS storage low ────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "rds_storage_low" {
  alarm_name          = "${local.name_prefix}-rds-storage-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 5368709120   # 5 GB

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.identifier
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}

# ── ElastiCache CPU high ──────────────────────────────
resource "aws_cloudwatch_metric_alarm" "valkey_cpu_high" {
  alarm_name          = "${local.name_prefix}-valkey-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "EngineCPUUtilization"
  namespace           = "AWS/ElastiCache"
  period              = 60
  statistic           = "Average"
  threshold           = 80

  dimensions = {
    ReplicationGroupId = aws_elasticache_replication_group.main.id
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}

# ── NAT instance: NetworkOut 비정상적으로 높음 (LLM 비용 폭증 신호) ──
# NAT Gateway 의 BytesOutToDestination 대신 NAT instance EC2 의 NetworkOut 사용.
# t4g.nano 는 burst 100 Mbps 정도라 1 GB/min ≒ ~135Mbps 로 이미 한계 근처.
resource "aws_cloudwatch_metric_alarm" "nat_egress_spike_a" {
  alarm_name          = "${local.name_prefix}-nat-egress-spike-a"
  alarm_description   = "NAT instance (AZ-a) NetworkOut > 1GB/min - abuse 또는 LLM 폭주 의심"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 5
  metric_name         = "NetworkOut"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Sum"
  threshold           = 1073741824   # 1 GB

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.nat_a.name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}

# ── NAT instance × 2: ASG 내 unhealthy → 재기동 안 됨 알림 ──
resource "aws_cloudwatch_metric_alarm" "nat_a_unhealthy" {
  alarm_name          = "${local.name_prefix}-nat-a-unhealthy"
  alarm_description   = "AZ-a NAT instance 가 1 미만 - outbound 끊긴 상태일 수 있음"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "GroupInServiceInstances"
  namespace           = "AWS/AutoScaling"
  period              = 60
  statistic           = "Average"
  threshold           = 1

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.nat_a.name
  }

  alarm_actions      = [aws_sns_topic.alerts.arn]
  treat_missing_data = "breaching"
}

resource "aws_cloudwatch_metric_alarm" "nat_c_unhealthy" {
  alarm_name          = "${local.name_prefix}-nat-c-unhealthy"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "GroupInServiceInstances"
  namespace           = "AWS/AutoScaling"
  period              = 60
  statistic           = "Average"
  threshold           = 1

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.nat_c.name
  }

  alarm_actions      = [aws_sns_topic.alerts.arn]
  treat_missing_data = "breaching"
}
