############################################################
# Self-host Observability Stack on ECS
#
# - Loki   (logs)   monolithic 단일 바이너리, S3 backend
# - Tempo  (traces) monolithic 단일 바이너리, S3 backend
# - Grafana (UI)    AMP/Loki/Tempo 를 데이터소스로 연결
#
# Mimir 는 self-host 안 함 - AMP 사용 (amp.tf 참조)
############################################################

# ── Cloud Map: 내부 서비스 디스커버리 ────────────────────
resource "aws_service_discovery_service" "loki" {
  name = "loki"
  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.internal.id
    dns_records {
      type = "A"
      ttl  = 10
    }
    routing_policy = "MULTIVALUE"
  }
  health_check_custom_config { failure_threshold = 1 }
}

resource "aws_service_discovery_service" "tempo" {
  name = "tempo"
  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.internal.id
    dns_records {
      type = "A"
      ttl  = 10
    }
    routing_policy = "MULTIVALUE"
  }
  health_check_custom_config { failure_threshold = 1 }
}

############################################################
# Loki - monolithic mode, S3 backend
############################################################
resource "aws_ecs_task_definition" "loki" {
  family                   = "${local.name_prefix}-loki"
  requires_compatibilities = ["EC2"]
  network_mode             = "awsvpc"
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.observability_task.arn

  container_definitions = jsonencode([{
    name      = "loki"
    image     = "grafana/loki:3.3.0"
    essential = true
    cpu       = var.loki_cpu
    memory    = var.loki_memory

    command = ["-config.file=/etc/loki/loki-config.yaml", "-target=all"]

    portMappings = [
      { containerPort = 3100, protocol = "tcp" },   # HTTP
      { containerPort = 9095, protocol = "tcp" },   # gRPC
    ]

    environment = [
      { name = "LOKI_S3_BUCKET", value = aws_s3_bucket.loki.id },
      { name = "AWS_REGION", value = var.aws_region },
    ]

    secrets = [
      { name = "LOKI_CONFIG_B64", valueFrom = aws_ssm_parameter.loki_config.arn },
    ]

    # Config 를 SSM 에서 받아 파일로 떨어뜨린 뒤 loki 실행
    entryPoint = [
      "sh", "-c",
      "echo $LOKI_CONFIG_B64 | base64 -d > /etc/loki/loki-config.yaml && exec /usr/bin/loki -config.file=/etc/loki/loki-config.yaml -target=all"
    ]

    healthCheck = {
      command     = ["CMD-SHELL", "wget -qO- http://localhost:3100/ready || exit 1"]
      interval    = 30
      timeout     = 10
      retries     = 3
      startPeriod = 60
    }

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.observability.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "loki"
      }
    }
  }])

  tags = { Name = "${local.name_prefix}-loki-td" }
}

resource "aws_ecs_service" "loki" {
  name            = "${local.name_prefix}-loki"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.loki.arn
  desired_count   = 1   # monolithic 단일 - 더 키우려면 microservices 모드로 분리

  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.ec2.name
    weight            = 1
  }

  network_configuration {
    subnets          = [aws_subnet.private_a.id, aws_subnet.private_c.id]
    security_groups  = [aws_security_group.ecs_observability.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.loki.arn
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  depends_on = [aws_ecs_cluster_capacity_providers.main]
  tags       = { Name = "${local.name_prefix}-loki-svc" }

  lifecycle {
    ignore_changes = [desired_count, task_definition]
  }
}

############################################################
# Tempo - monolithic mode, S3 backend
############################################################
resource "aws_ecs_task_definition" "tempo" {
  family                   = "${local.name_prefix}-tempo"
  requires_compatibilities = ["EC2"]
  network_mode             = "awsvpc"
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.observability_task.arn

  container_definitions = jsonencode([{
    name      = "tempo"
    image     = "grafana/tempo:2.7.0"
    essential = true
    cpu       = var.tempo_cpu
    memory    = var.tempo_memory

    portMappings = [
      { containerPort = 3200, protocol = "tcp" },   # HTTP / query
      { containerPort = 4317, protocol = "tcp" },   # OTLP gRPC
      { containerPort = 4318, protocol = "tcp" },   # OTLP HTTP
    ]

    environment = [
      { name = "TEMPO_S3_BUCKET", value = aws_s3_bucket.tempo.id },
      { name = "AWS_REGION", value = var.aws_region },
    ]

    secrets = [
      { name = "TEMPO_CONFIG_B64", valueFrom = aws_ssm_parameter.tempo_config.arn },
    ]

    entryPoint = [
      "sh", "-c",
      "echo $TEMPO_CONFIG_B64 | base64 -d > /etc/tempo/tempo.yaml && exec /tempo -config.file=/etc/tempo/tempo.yaml"
    ]

    healthCheck = {
      command     = ["CMD-SHELL", "wget -qO- http://localhost:3200/ready || exit 1"]
      interval    = 30
      timeout     = 10
      retries     = 3
      startPeriod = 60
    }

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.observability.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "tempo"
      }
    }
  }])

  tags = { Name = "${local.name_prefix}-tempo-td" }
}

resource "aws_ecs_service" "tempo" {
  name            = "${local.name_prefix}-tempo"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.tempo.arn
  desired_count   = 1

  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.ec2.name
    weight            = 1
  }

  network_configuration {
    subnets          = [aws_subnet.private_a.id, aws_subnet.private_c.id]
    security_groups  = [aws_security_group.ecs_observability.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.tempo.arn
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  depends_on = [aws_ecs_cluster_capacity_providers.main]
  tags       = { Name = "${local.name_prefix}-tempo-svc" }

  lifecycle {
    ignore_changes = [desired_count, task_definition]
  }
}

############################################################
# Grafana - UI (AMP / Loki / Tempo / X-Ray 데이터소스)
############################################################
resource "aws_ecs_task_definition" "grafana" {
  family                   = "${local.name_prefix}-grafana"
  requires_compatibilities = ["EC2"]
  network_mode             = "awsvpc"
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.observability_task.arn

  container_definitions = jsonencode([{
    name      = "grafana"
    image     = "grafana/grafana:11.4.0"
    essential = true
    cpu       = var.grafana_cpu
    memory    = var.grafana_memory

    portMappings = [{ containerPort = 3000, protocol = "tcp" }]

    environment = [
      { name = "GF_SERVER_ROOT_URL", value = "https://grafana.${var.domain_name}" },
      { name = "GF_AUTH_ANONYMOUS_ENABLED", value = "false" },
      { name = "GF_USERS_ALLOW_SIGN_UP", value = "false" },
      { name = "GF_INSTALL_PLUGINS", value = "grafana-x-ray-datasource" },
      # Datasource provisioning 은 SSM 으로 주입
      { name = "AWS_REGION", value = var.aws_region },
      { name = "AMP_QUERY_URL", value = aws_prometheus_workspace.main.prometheus_endpoint },
      { name = "LOKI_URL", value = "http://loki.${local.name_prefix}.local:3100" },
      { name = "TEMPO_URL", value = "http://tempo.${local.name_prefix}.local:3200" },
    ]

    secrets = [
      { name = "GF_SECURITY_ADMIN_PASSWORD", valueFrom = aws_ssm_parameter.grafana_admin_password.arn },
      { name = "GF_DATABASE_PASSWORD",       valueFrom = aws_ssm_parameter.db_password.arn },
    ]

    healthCheck = {
      command     = ["CMD-SHELL", "wget -qO- http://localhost:3000/api/health || exit 1"]
      interval    = 30
      timeout     = 10
      retries     = 3
      startPeriod = 30
    }

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.observability.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "grafana"
      }
    }
  }])

  tags = { Name = "${local.name_prefix}-grafana-td" }
}

resource "aws_ecs_service" "grafana" {
  name            = "${local.name_prefix}-grafana"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.grafana.arn
  desired_count   = 1

  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.ec2.name
    weight            = 1
  }

  network_configuration {
    subnets          = [aws_subnet.private_a.id, aws_subnet.private_c.id]
    security_groups  = [aws_security_group.ecs_observability.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.grafana.arn
    container_name   = "grafana"
    container_port   = 3000
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  depends_on = [aws_ecs_cluster_capacity_providers.main]
  tags       = { Name = "${local.name_prefix}-grafana-svc" }

  lifecycle {
    ignore_changes = [desired_count, task_definition]
  }
}
