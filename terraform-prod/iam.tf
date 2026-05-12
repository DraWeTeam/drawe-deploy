############################################################
# data
############################################################
data "aws_caller_identity" "current" {}

############################################################
# ECS EC2 Instance Role + Profile
############################################################
resource "aws_iam_role" "ecs_instance" {
  name = "${local.name_prefix}-ecs-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_instance_ecs" {
  role       = aws_iam_role.ecs_instance.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_role_policy_attachment" "ecs_instance_ssm" {
  role       = aws_iam_role.ecs_instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ecs_instance" {
  name = "${local.name_prefix}-ecs-instance-profile"
  role = aws_iam_role.ecs_instance.name
}

############################################################
# ECS Task Execution Role
############################################################
resource "aws_iam_role" "ecs_execution" {
  name = "${local.name_prefix}-ecs-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution_base" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "ecs_execution_ssm" {
  name = "${local.name_prefix}-ecs-exec-ssm"
  role = aws_iam_role.ecs_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ssm:GetParameters",
        "ssm:GetParameter",
        "ssm:GetParametersByPath"
      ]
      Resource = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/${var.project}/${var.env}/*"
    }]
  })
}

############################################################
# ECS Task Role - 앱 (backend, fastapi)
############################################################
resource "aws_iam_role" "ecs_task" {
  name = "${local.name_prefix}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "ecs_task_policy" {
  name = "${local.name_prefix}-ecs-task-policy"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords",
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel",
        ]
        Resource = "*"
      }
    ]
  })
}

############################################################
# ECS Task Role - Observability stack (Loki, Tempo, Grafana)
############################################################
resource "aws_iam_role" "observability_task" {
  name = "${local.name_prefix}-observability-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "observability_s3" {
  name = "${local.name_prefix}-observability-s3"
  role = aws_iam_role.observability_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["s3:ListBucket"]
        Resource = [
          aws_s3_bucket.loki.arn,
          aws_s3_bucket.tempo.arn,
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
        ]
        Resource = [
          "${aws_s3_bucket.loki.arn}/*",
          "${aws_s3_bucket.tempo.arn}/*",
        ]
      },
    ]
  })
}

resource "aws_iam_role_policy" "observability_amp" {
  name = "${local.name_prefix}-observability-amp"
  role = aws_iam_role.observability_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "aps:RemoteWrite",
        "aps:QueryMetrics",
        "aps:GetSeries",
        "aps:GetLabels",
        "aps:GetMetricMetadata",
      ]
      Resource = aws_prometheus_workspace.main.arn
    }]
  })
}

resource "aws_iam_role_policy" "observability_xray_read" {
  name = "${local.name_prefix}-observability-xray-read"
  role = aws_iam_role.observability_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "xray:GetServiceGraph",
        "xray:GetTraceSummaries",
        "xray:GetTraceGraph",
        "xray:BatchGetTraces",
        "xray:GetGroups",
        "xray:GetTimeSeriesServiceStatistics",
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy" "observability_logs" {
  name = "${local.name_prefix}-observability-logs"
  role = aws_iam_role.observability_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents",
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy" "ecs_task_amp_write" {
  name = "${local.name_prefix}-ecs-task-amp-write"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["aps:RemoteWrite"]
      Resource = aws_prometheus_workspace.main.arn
    }]
  })
}

############################################################
# GitHub Actions OIDC Deploy Role
#
# ⚠ 변경: OIDC provider 자체는 dev terraform (terraform/iam-github.tf) 가 만든다.
#   AWS 계정당 OIDC provider 는 1개만 존재 가능 - prod 가 새로 만들면 충돌.
#   여기서는 data source 로 dev 가 만든 것을 reference.
#
# dev 에서 OIDC 를 안 만든 경우:
#   - dev tfvars 에 github_owner 설정 후 dev apply 먼저
#   - 또는 이 파일에서 data → resource 로 되돌려 prod 가 만들도록
############################################################
variable "github_owner" {
  description = "GitHub org/user"
  type        = string
  default     = ""
}

variable "github_repos" {
  description = "Deploy 권한 줄 레포 이름 목록"
  type        = list(string)
  default     = ["drawe-backend", "drawe-fastapi"]
}

# ── data source: dev 가 만든 OIDC provider 참조 ──
resource "aws_iam_openid_connect_provider" "github" {
  count = var.github_owner != "" ? 1 : 0
  
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = { Name = "${local.name_prefix}-github-oidc" }
}

data "aws_iam_policy_document" "github_assume" {
  count = var.github_owner != "" ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github[0].arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # ⌁ prod 는 main branch 만 deploy 허용 (보안)
    # ⌁ prod 는 main branch 또는 prod environment 에서만 deploy
    # environment 는 GitHub 의 Selected branches=main 제한과 함께 적용됨 (이중 안전망)
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = flatten([
        for repo in var.github_repos : [
          "repo:${var.github_owner}/${repo}:ref:refs/heads/main",
          "repo:${var.github_owner}/${repo}:environment:prod",
        ]
      ])
    }
  }
}

resource "aws_iam_role" "github_deploy" {
  count              = var.github_owner != "" ? 1 : 0
  name               = "${local.name_prefix}-github-deploy-role"
  assume_role_policy = data.aws_iam_policy_document.github_assume[0].json

  tags = { Name = "${local.name_prefix}-github-deploy-role" }
}

resource "aws_iam_role_policy" "github_deploy" {
  count = var.github_owner != "" ? 1 : 0
  name  = "${local.name_prefix}-github-deploy-policy"
  role  = aws_iam_role.github_deploy[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage",
          "ecr:BatchGetImage",
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecs:DescribeServices",
          "ecs:DescribeTaskDefinition",
          "ecs:RegisterTaskDefinition",
          "ecs:UpdateService",
          "ecs:DescribeTasks",
          "ecs:ListTasks",
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = ["iam:PassRole"]
        Resource = [
          aws_iam_role.ecs_task.arn,
          aws_iam_role.ecs_execution.arn,
        ]
      },
    ]
  })
}
