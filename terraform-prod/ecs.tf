# ECS-optimized AMI
data "aws_ssm_parameter" "ecs_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2023/arm64/recommended/image_id"
}

# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "${local.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = { Name = "${local.name_prefix}-cluster" }
}

resource "aws_ecs_capacity_provider" "ec2" {
  name = "${local.name_prefix}-ec2-cp"

  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.ecs.arn
    managed_termination_protection = "DISABLED"

    managed_scaling {
      status                    = "ENABLED"
      target_capacity           = 100
      minimum_scaling_step_size = 1
      maximum_scaling_step_size = 2
    }
  }
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name       = aws_ecs_cluster.main.name
  capacity_providers = [aws_ecs_capacity_provider.ec2.name]

  default_capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.ec2.name
    weight            = 1
    base              = var.ecs_desired_instances
  }
}

# Launch Template
resource "aws_launch_template" "ecs" {
  name_prefix   = "${local.name_prefix}-ecs-"
  image_id      = data.aws_ssm_parameter.ecs_ami.value
  instance_type = var.ecs_instance_type
  key_name      = var.key_pair_name

  iam_instance_profile {
    arn = aws_iam_instance_profile.ecs_instance.arn
  }

  vpc_security_group_ids = [aws_security_group.ecs_instance.id]

  user_data = base64encode(<<-USERDATA
    #!/bin/bash
    echo "ECS_CLUSTER=${aws_ecs_cluster.main.name}" >> /etc/ecs/ecs.config
    echo "ECS_ENABLE_TASK_ENI=true" >> /etc/ecs/ecs.config
    echo "ECS_AWSVPC_BLOCK_IMDS=true" >> /etc/ecs/ecs.config
    echo "ECS_ENABLE_CONTAINER_METADATA=true" >> /etc/ecs/ecs.config
  USERDATA
  )

  monitoring { enabled = true }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = 30
      volume_type = "gp3"
      encrypted   = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${local.name_prefix}-ecs-instance"
    }
  }

  lifecycle { create_before_destroy = true }
}

# Auto Scaling Group - Multi-AZ
resource "aws_autoscaling_group" "ecs" {
  name_prefix         = "${local.name_prefix}-ecs-"
  vpc_zone_identifier = [aws_subnet.private_a.id, aws_subnet.private_c.id]
  min_size            = var.ecs_desired_instances
  max_size            = 6
  desired_capacity    = var.ecs_desired_instances

  launch_template {
    id      = aws_launch_template.ecs.id
    version = "$Latest"
  }

  protect_from_scale_in = false

  tag {
    key                 = "AmazonECSManaged"
    value               = true
    propagate_at_launch = true
  }

  lifecycle {
    ignore_changes        = [desired_capacity]
    create_before_destroy = true
  }
}

############################################################
# Cloud Map (내부 DNS - fastapi, loki, tempo)
############################################################
resource "aws_service_discovery_private_dns_namespace" "internal" {
  name = "${local.name_prefix}.local"
  vpc  = aws_vpc.main.id
}

resource "aws_service_discovery_service" "fastapi" {
  name = "fastapi"
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
# Alloy sidecar locals
############################################################
locals {
  alloy_sidecar = {
    name      = "alloy"
    image     = "grafana/alloy:v1.9.0"
    essential = false
    entryPoint = ["/bin/sh", "-c"]
    command = [
      "echo $ALLOY_CONFIG_B64 | base64 -d | gunzip > /tmp/config.alloy && exec /bin/alloy run /tmp/config.alloy --stability.level=public-preview"
    ]
    portMappings = [
      { containerPort = 4317, protocol = "tcp" },
      { containerPort = 4318, protocol = "tcp" },
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.alloy.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "sidecar"
      }
    }

    stopTimeout = 30
  }

  otel_env = [
    { name = "OTEL_EXPORTER_OTLP_ENDPOINT", value = "http://localhost:4317" },
    { name = "OTEL_EXPORTER_OTLP_PROTOCOL", value = "grpc" },
    { name = "OTEL_RESOURCE_ATTRIBUTES", value = "deployment.environment=${var.env},service.namespace=drawe" },
    { name = "OTEL_TRACES_SAMPLER", value = "parentbased_always_on" },
  ]

  # prod alloy env - Grafana Cloud 가 아닌 self-host endpoint 들
  alloy_env = [
    { name = "ALLOY_DEPLOY_ENV",         value = var.env },
    { name = "ALLOY_SAMPLING_RATE",      value = var.otel_sampling_rate },
    { name = "AMP_REMOTE_WRITE_URL",     value = "${aws_prometheus_workspace.main.prometheus_endpoint}api/v1/remote_write" },
    { name = "AWS_REGION",               value = var.aws_region },
    { name = "LOKI_URL",                 value = "http://loki.${local.name_prefix}.local:3100" },
    { name = "TEMPO_OTLP_ENDPOINT",      value = "tempo.${local.name_prefix}.local:4317" },
  ]

  alloy_secrets = [
    { name = "ALLOY_CONFIG_B64", valueFrom = aws_ssm_parameter.alloy_config.arn },
  ]
}

############################################################
# Layer 1 - DAEMON Alloy
############################################################
resource "aws_ecs_task_definition" "alloy_daemon" {
  family                   = "${local.name_prefix}-alloy-daemon"
  requires_compatibilities = ["EC2"]
  network_mode             = "host"
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name      = "alloy-daemon"
    image     = "grafana/alloy:v1.9.0"
    essential = true
    cpu       = 128
    memory    = 256

    entryPoint = ["/bin/sh", "-c"]
    command = [
      "echo $ALLOY_CONFIG_B64 | base64 -d | gunzip > /tmp/config.alloy && exec /bin/alloy run /tmp/config.alloy --stability.level=public-preview"
    ]

    environment = [
      { name = "ALLOY_SERVICE_NAME",   value = "infra-daemon" },
      { name = "ALLOY_DEPLOY_ENV",     value = var.env },
      { name = "ALLOY_SAMPLING_RATE",  value = "100" },
      { name = "AMP_REMOTE_WRITE_URL", value = "${aws_prometheus_workspace.main.prometheus_endpoint}api/v1/remote_write" },
      { name = "AWS_REGION",           value = var.aws_region },
      { name = "LOKI_URL",             value = "http://loki.${local.name_prefix}.local:3100" },
      { name = "TEMPO_OTLP_ENDPOINT",  value = "tempo.${local.name_prefix}.local:4317" },
    ]

    secrets = [
      { name = "ALLOY_CONFIG_B64", valueFrom = aws_ssm_parameter.alloy_daemon_config.arn },
    ]

    mountPoints = [
      { sourceVolume = "docker-sock", containerPath = "/var/run/docker.sock", readOnly = true },
      { sourceVolume = "proc", containerPath = "/host/proc", readOnly = true },
      { sourceVolume = "sys", containerPath = "/host/sys", readOnly = true },
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.alloy.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "daemon"
      }
    }
  }])

  volume {
    name      = "docker-sock"
    host_path = "/var/run/docker.sock"
  }
  volume {
    name      = "proc"
    host_path = "/proc"
  }
  volume {
    name      = "sys"
    host_path = "/sys"
  }
}

resource "aws_ecs_service" "alloy_daemon" {
  name                = "${local.name_prefix}-alloy-daemon"
  cluster             = aws_ecs_cluster.main.id
  task_definition     = aws_ecs_task_definition.alloy_daemon.arn
  scheduling_strategy = "DAEMON"
  launch_type         = "EC2"   # ← 이 줄 추가 (cluster default capacity provider strategy 우회)

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  depends_on = [aws_ecs_cluster_capacity_providers.main]

  lifecycle { ignore_changes = [task_definition] }
}

############################################################
# Layer 2 - Backend
############################################################
resource "aws_ecs_task_definition" "backend" {
  family                   = "${local.name_prefix}-backend"
  requires_compatibilities = ["EC2"]
  network_mode             = "awsvpc"
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "backend"
      image     = "${aws_ecr_repository.backend.repository_url}:latest"
      essential = true
      cpu       = var.backend_cpu
      memory    = var.backend_memory

      portMappings = [{ containerPort = 8080, protocol = "tcp" }]

      dependsOn = [{ containerName = "alloy", condition = "START" }]

      healthCheck = {
        command     = ["CMD-SHELL", "wget -qO- http://localhost:8080/actuator/health || exit 1"]
        interval    = 30
        timeout     = 10
        retries     = 3
        startPeriod = 90
      }

      environment = concat([
        { name = "SERVER_PORT", value = "8080" },
        { name = "DB_HOST", value = aws_db_instance.main.address },
        { name = "DB_PORT", value = "3306" },
        { name = "DB_NAME", value = var.db_name },
        { name = "DB_SSL_MODE", value = "VERIFY_IDENTITY" },
        # ⌁ prod: ElastiCache primary endpoint (single primary 또는 reader endpoint)
        { name = "REDIS_HOST", value = aws_elasticache_replication_group.main.primary_endpoint_address },
        { name = "REDIS_PORT", value = "6379" },
        { name = "REDIS_TLS", value = "true" },              # ElastiCache transit encryption
        { name = "JPA_DDL_AUTO", value = "validate" },        # ⌁ prod: validate (Flyway 사용)
        { name = "JPA_SHOW_SQL", value = "false" },
        { name = "LOG_LEVEL_SQL", value = "warn" },
        { name = "APP_CORS_ALLOWED_ORIGINS", value = var.frontend_url },
        { name = "APP_OAUTH2_REDIRECT_URI", value = "${var.frontend_url}/oauth/callback" },
        { name = "FASTAPI_URL", value = "http://fastapi.${local.name_prefix}.local:8000" },
        { name = "OTEL_SERVICE_NAME", value = "backend" },
      ], local.otel_env)

      secrets = [
        { name = "DB_USERNAME",          valueFrom = aws_ssm_parameter.db_username.arn },
        { name = "DB_PASSWORD",          valueFrom = aws_ssm_parameter.db_password.arn },
        { name = "REDIS_PASSWORD",       valueFrom = aws_ssm_parameter.redis_password.arn },
        { name = "JWT_SECRET",           valueFrom = aws_ssm_parameter.jwt_secret.arn },
        { name = "GROK_API_KEY",         valueFrom = aws_ssm_parameter.grok_api_key.arn },
        { name = "CLAUDE_API_KEY",       valueFrom = aws_ssm_parameter.claude_api_key.arn },
        { name = "GEMINI_API_KEY",       valueFrom = aws_ssm_parameter.gemini_api_key.arn },
        { name = "GOOGLE_CLIENT_ID",     valueFrom = aws_ssm_parameter.google_client_id.arn },
        { name = "GOOGLE_CLIENT_SECRET", valueFrom = aws_ssm_parameter.google_client_secret.arn },
        { name = "PINECONE_API_KEY",     valueFrom = aws_ssm_parameter.pinecone_api_key.arn },
        { name = "PINECONE_HOST",        valueFrom = aws_ssm_parameter.pinecone_host.arn },
        { name = "PINECONE_INDEX",       valueFrom = aws_ssm_parameter.pinecone_index.arn },
        { name = "BRIA_API_KEY",     valueFrom = aws_ssm_parameter.bria_api_key.arn },
        { name = "BRIA_BASE_URL",    valueFrom = aws_ssm_parameter.bria_base_url.arn },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.backend.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    },

    merge(local.alloy_sidecar, {
      cpu    = var.alloy_sidecar_cpu
      memory = var.alloy_sidecar_memory
      environment = concat(local.alloy_env, [
        { name = "ALLOY_SERVICE_NAME", value = "backend" },
      ])
      secrets = local.alloy_secrets
    })
  ])
}

############################################################
# Layer 2 - FastAPI
############################################################
resource "aws_ecs_task_definition" "fastapi" {
  family                   = "${local.name_prefix}-fastapi"
  requires_compatibilities = ["EC2"]
  network_mode             = "awsvpc"
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "fastapi"
      image     = "${aws_ecr_repository.fastapi.repository_url}:latest"
      essential = true
      cpu       = var.fastapi_cpu
      memory    = var.fastapi_memory

      portMappings = [{ containerPort = 8000, protocol = "tcp" }]
      dependsOn    = [{ containerName = "alloy", condition = "START" }]

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:8000/health || exit 1"]
        interval    = 30
        timeout     = 10
        retries     = 3
        startPeriod = 120
      }

      environment = concat([
        { name = "PORT", value = "8000" },
        { name = "WORKERS", value = "2" },   # ⌁ prod: 2 workers
        # ── CLIP 모델 설정 (main.py 의 env 변수와 매칭) ──
        { name = "CLIP_MODEL_NAME", value = "openai/clip-vit-large-patch14" },
        { name = "DEVICE", value = "cpu" },
        { name = "OTEL_SERVICE_NAME", value = "ai-server" },
      ], local.otel_env)

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.fastapi.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    },

    merge(local.alloy_sidecar, {
      cpu    = var.alloy_sidecar_cpu
      memory = var.alloy_sidecar_memory
      environment = concat(local.alloy_env, [
        { name = "ALLOY_SERVICE_NAME", value = "ai-server" },
      ])
      secrets = local.alloy_secrets
    })
  ])
}

############################################################
# ECS Services
############################################################
resource "aws_ecs_service" "backend" {
  name            = "${local.name_prefix}-backend"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.backend.arn
  desired_count   = var.backend_desired_count

  enable_execute_command = true   # ECS Exec - debug shell

  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.ec2.name
    weight            = 1
    base              = var.backend_desired_count
  }

  network_configuration {
    subnets          = [aws_subnet.private_a.id, aws_subnet.private_c.id]
    security_groups  = [aws_security_group.ecs_backend.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.backend.arn
    container_name   = "backend"
    container_port   = 8080
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  depends_on = [aws_lb_listener.https, aws_ecs_cluster_capacity_providers.main]

  lifecycle { ignore_changes = [desired_count, task_definition] }
}

resource "aws_ecs_service" "fastapi" {
  name            = "${local.name_prefix}-fastapi"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.fastapi.arn
  desired_count   = var.fastapi_desired_count

  enable_execute_command = true

  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.ec2.name
    weight            = 1
  }

  network_configuration {
    subnets          = [aws_subnet.private_a.id, aws_subnet.private_c.id]
    security_groups  = [aws_security_group.ecs_fastapi.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.fastapi.arn
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  depends_on = [aws_ecs_cluster_capacity_providers.main]

  lifecycle { ignore_changes = [desired_count, task_definition] }
}
