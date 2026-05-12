############################################################
# Outputs - prod
############################################################
output "alb_dns_name" {
  description = "ALB DNS name (cloudflare_record 가 가리키는 대상)"
  value       = aws_lb.main.dns_name
}

output "api_url" {
  value = "https://${var.domain_name}"
}

output "grafana_url" {
  value = "https://grafana.${var.domain_name}"
}

output "rds_endpoint" {
  value     = aws_db_instance.main.address
  sensitive = true
}

output "elasticache_primary_endpoint" {
  value     = aws_elasticache_replication_group.main.primary_endpoint_address
  sensitive = true
}

output "amp_workspace_id" {
  value = aws_prometheus_workspace.main.id
}

output "amp_query_url" {
  value = aws_prometheus_workspace.main.prometheus_endpoint
}

output "ecr_backend_url" {
  value = aws_ecr_repository.backend.repository_url
}

output "ecr_fastapi_url" {
  value = aws_ecr_repository.fastapi.repository_url
}

output "github_deploy_role_arn" {
  value = var.github_owner != "" ? aws_iam_role.github_deploy[0].arn : null
}

output "fastapi_internal_url" {
  value = "http://fastapi.${local.name_prefix}.local:8000"
}

output "loki_internal_url" {
  value = "http://loki.${local.name_prefix}.local:3100"
}

output "tempo_internal_url" {
  value = "http://tempo.${local.name_prefix}.local:3200"
}

output "alerts_sns_topic_arn" {
  value = aws_sns_topic.alerts.arn
}

output "nat_eips" {
  description = "NAT instance public IPs (외부 화이트리스트 등록 시 사용)"
  value = {
    az_a = aws_eip.nat_a.public_ip
    az_c = aws_eip.nat_c.public_ip
  }
}

############################################################
# 다음 단계 가이드
############################################################
output "next_steps" {
  value = <<-EOT

    ──────────────────────────────────────────────────────
    📋 terraform apply 후 manual 단계
    ──────────────────────────────────────────────────────

    1. Cloudflare 대시보드 → SSL/TLS → Overview
       모드를 "Full (strict)" 로 설정 (zone-level 설정 - 한 번만)

    2. Cloudflare DNS 레코드 확인
       - ${var.domain_name}            CNAME → ALB (proxied ⚡)
       - grafana.${var.domain_name}    CNAME → ALB (proxied ⚡)
       - _xxx.${var.domain_name}       CNAME → ACM 검증용 (DNS only)
       (Terraform 이 자동 등록함 - 대시보드에서 확인만)

    3. SSM Parameter 시크릿 채우기
       aws ssm put-parameter --name "/drawe/prod/jwt-secret" \
           --value "$(openssl rand -base64 64)" --type SecureString --overwrite
       (jwt-secret, grok-api-key, claude-api-key, gemini-api-key,
        google-client-id, google-client-secret, pinecone-api-key)

    4. ECS service 강제 재배포 (시크릿 새로 읽도록)
       aws ecs update-service --cluster drawe-prod-cluster \
           --service drawe-prod-backend --force-new-deployment
       aws ecs update-service --cluster drawe-prod-cluster \
           --service drawe-prod-fastapi --force-new-deployment

    5. Grafana 첫 로그인
       URL : https://grafana.${var.domain_name}
       User: admin
       Pwd : aws ssm get-parameter --name /drawe/prod/grafana-admin-password \
                 --with-decryption --query Parameter.Value --output text

    6. Google OAuth Console 에 redirect URI 등록
       https://${var.domain_name}/login/oauth2/code/google

    7. SNS 이메일 alert confirm (var.alert_email 설정 시 inbox 확인)

    ──────────────────────────────────────────────────────
  EOT
}
