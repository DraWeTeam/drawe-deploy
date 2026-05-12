############################################################
# DraWe - prod 환경 Terraform
#
# dev (terraform/) 와 다른 점:
#   - 24/7 운영 (EventBridge schedule 없음)
#   - Multi-AZ NAT instance × 2
#   - ElastiCache for Valkey (EC2 Valkey 대신)
#   - RDS Multi-AZ
#   - HTTPS 필수 (ACM + domain_name)
#   - 관측 stack: AMP + self-host Loki/Tempo/Grafana on ECS
#   - 더 큰 인스턴스 (t4g.xlarge ECS, db.t4g.small RDS)
#   - 백업 보유기간 30일
#
# Terraform state 는 dev 와 분리:
#   backend "s3" { key = "drawe/prod/terraform.tfstate" }
############################################################

terraform {
  required_version = ">= 1.11"

  required_providers {
    aws        = { source = "hashicorp/aws", version = "~> 5.100" }
    random     = { source = "hashicorp/random", version = "~> 3.6" }
    http       = { source = "hashicorp/http", version = "~> 3.4" }
    cloudflare = { source = "cloudflare/cloudflare", version = "~> 4.52" }
  }

  backend "s3" {
    bucket         = "drawe-tfstate-933832340498"
    key            = "drawe/prod/terraform.tfstate"
    region         = "ap-northeast-2"
    use_lockfile   = true
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

############################################################
# Cloudflare provider
#
# api_token: var.cloudflare_api_token 비어있으면 CLOUDFLARE_API_TOKEN
# 환경변수 자동 사용. 한정 권한 token 권장:
#   Zone > DNS > Edit (해당 zone 만)
############################################################
provider "cloudflare" {
  api_token = var.cloudflare_api_token != "" ? var.cloudflare_api_token : null
}

# AL2023 ARM AMI (Graviton)
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-arm64"]
  }
}
