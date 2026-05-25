############################################################
# GitHub Actions OIDC — Deploy Role
#
# 백엔드/FastAPI 레포의 CD workflow 가 이 role 을 assume 해서
# ECR push + ECS deploy 수행. AWS access key 를 GitHub secret 으로
# 두지 않아 token 유출 위험 회피.
#
# 첫 apply 시 OIDC provider thumbprint 를 GitHub 에서 가져옴.
# var.github_owner 와 var.github_repos 에 등록된 레포만 assume 가능.
############################################################

variable "github_owner" {
  description = "GitHub org/user (예: my-team)"
  type        = string
  default     = ""
}

variable "github_repos" {
  description = "Deploy 권한 줄 레포 이름 목록 (owner 제외)"
  type        = list(string)
  default     = ["drawe-backend", "drawe-fastapi", "drawe"]
}

# ── OIDC Provider (계정당 1개만 존재해야 함) ──────────────
# 이미 다른 환경에서 만들어져 있으면 import:
#   terraform import aws_iam_openid_connect_provider.github \
#     arn:aws:iam::<acct>:oidc-provider/token.actions.githubusercontent.com
resource "aws_iam_openid_connect_provider" "github" {
  count = var.github_owner != "" ? 1 : 0

  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  # GitHub OIDC 의 현재 thumbprint (2023~ 이후 안정적으로 사용됨)
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = { Name = "${local.name_prefix}-github-oidc" }
}

# ── Trust Policy ─────────────────────────────────────────
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

    # 등록된 레포의 어떤 ref/branch 든 assume 허용
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [for repo in var.github_repos : "repo:${var.github_owner}/${repo}:*"]
    }
  }
}

# ── Deploy Role ──────────────────────────────────────────
resource "aws_iam_role" "github_deploy" {
  count = var.github_owner != "" ? 1 : 0

  name               = "${local.name_prefix}-github-deploy-role"
  assume_role_policy = data.aws_iam_policy_document.github_assume[0].json

  tags = { Name = "${local.name_prefix}-github-deploy-role" }
}

resource "aws_iam_role_policy" "github_deploy" {
  count = var.github_owner != "" ? 1 : 0

  name = "${local.name_prefix}-github-deploy-policy"
  role = aws_iam_role.github_deploy[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # ECR push
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
        # ECS deploy
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
        # Task role / execution role 을 ECS 에 PassRole
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
