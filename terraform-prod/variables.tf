############################################################
# General
############################################################
variable "project" {
  default = "drawe"
}

variable "env" {
  default = "prod"
}

variable "aws_region" {
  default = "ap-northeast-2"
}

############################################################
# VPC / Network
############################################################
variable "vpc_cidr" {
  default = "10.10.0.0/16"   # dev (10.0/16) 와 분리
}

variable "az_a" {
  default = "ap-northeast-2a"
}

variable "az_c" {
  default = "ap-northeast-2c"
}

############################################################
# ECS - prod 는 더 큰 instance + Multi-AZ
############################################################
variable "ecs_instance_type" {
  description = "prod ECS 인스턴스 - observability stack 까지 올리므로 t4g.xlarge"
  default     = "t4g.xlarge"   # 4 vCPU / 16 GB
}

variable "ecs_desired_instances" {
  description = "prod ASG - Multi-AZ 분산 위해 최소 2"
  default     = 2
}

# ── Backend ──
variable "backend_cpu"           { default = 1024 }
variable "backend_memory"        { default = 2048 }
variable "backend_desired_count" { default = 2 }
variable "backend_min_capacity"  { default = 2 }
variable "backend_max_capacity"  { default = 8 }

# ── FastAPI ──
variable "fastapi_cpu"           { default = 1024 }
variable "fastapi_memory"        { default = 2048 }
variable "fastapi_desired_count" { default = 2 }
variable "fastapi_min_capacity"  { default = 2 }
variable "fastapi_max_capacity"  { default = 6 }

# ── Alloy sidecar ──
variable "alloy_sidecar_cpu"    { default = 256 }
variable "alloy_sidecar_memory" { default = 512 }

# ── Self-host Observability stack ──
variable "loki_cpu"     { default = 512 }
variable "loki_memory"  { default = 1024 }
variable "tempo_cpu"    { default = 512 }
variable "tempo_memory" { default = 1024 }
variable "grafana_cpu"    { default = 256 }
variable "grafana_memory" { default = 512 }

############################################################
# Observability
############################################################
variable "otel_sampling_rate" {
  description = "Trace sampling - prod 는 100% (또는 head sampling 비율)"
  default     = "100"
}

############################################################
# RDS - Multi-AZ + 더 큰 instance
############################################################
variable "db_instance_class" {
  default = "db.t4g.small"
}

variable "db_name" {
  default = "drawe_db"
}

variable "db_username" {
  default = "drawe_admin"
}

variable "db_backup_retention_days" {
  default = 30   # prod 는 30일 보유
}

variable "rds_multi_az" {
  description = <<-EOT
    RDS Multi-AZ 활성화 여부.

    false (기본): single-AZ. ~$25/월 절감. AZ 장애 시 다운타임 감수.
    true:         Multi-AZ. 60~120초 자동 failover.

    나중에 false → true 로 바꾸려면:
    1) terraform.tfvars 에서 rds_multi_az = true 로 변경
    2) terraform apply
    AWS 가 in-place 로 standby 생성 + 동기 복제 셋업.
    데이터 마이그레이션 / endpoint 변경 없음.
  EOT
  type    = bool
  default = false
}

variable "db_password" {
  description = "RDS master password. 비워두면 32자 random 자동 생성. 본인 지정 시 환경변수 TF_VAR_db_password 권장."
  type        = string
  default     = ""
  sensitive   = true
}

variable "valkey_auth_token" {
  description = "ElastiCache Valkey AUTH 토큰. 비워두면 32자 random 자동 생성."
  type        = string
  default     = ""
  sensitive   = true
}

############################################################
# ElastiCache for Valkey
############################################################
variable "elasticache_node_type" {
  description = "ElastiCache node type - Valkey/Redis 호환"
  default     = "cache.t4g.small"
}

variable "elasticache_replicas" {
  description = "Read replicas (Multi-AZ failover 용 최소 1)"
  default     = 1
}

############################################################
# Domain / Cloudflare
#
# prod 는 항상 Cloudflare + Full Strict (TLS 종단 CF + ACM at ALB).
# 가비아 등에서 산 도메인이 Cloudflare DNS 에 등록되어 있다고 가정.
############################################################
variable "domain_name" {
  description = "Public hostname (예: api.drawe.com)"
  type        = string
}

variable "cloudflare_api_token" {
  description = <<-EOT
    Cloudflare API token (Zone > DNS > Edit 권한).
    빈 문자열이면 CLOUDFLARE_API_TOKEN 환경변수 사용.

    Token 만들기:
      Cloudflare → My Profile → API Tokens → Create Token
      → "Edit zone DNS" 템플릿 → 해당 zone 선택
  EOT
  type      = string
  sensitive = true
  default   = ""
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID (대시보드 Overview 우측 사이드바)"
  type        = string
}

variable "frontend_url" {
  description = "Frontend URL (Cloudflare Pages 또는 같은 zone)"
  type        = string
}

variable "key_pair_name" {
  description = "EC2 SSH key pair"
  type        = string
}

############################################################
# Tags
############################################################
locals {
  common_tags = {
    Project     = var.project
    Environment = var.env
    ManagedBy   = "terraform"
  }
  name_prefix = "${var.project}-${var.env}"
}
