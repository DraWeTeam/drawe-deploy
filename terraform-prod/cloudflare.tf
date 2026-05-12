############################################################
# Cloudflare - Full Strict 셋업
#
# 1) Cloudflare 의 공개 IP 대역을 fetch (ALB SG inbound 화이트리스트용)
# 2) ACM 검증용 CNAME 등록 (proxied=false)
# 3) api.{domain} / grafana.{domain} CNAME 등록 (proxied=true, orange cloud)
#
# 사용자가 dashboard 에서 해야 할 것: SSL/TLS 모드를 "Full (strict)" 로 설정
# (이건 zone-level 설정이라 cloudflare_record 로 안 잡힘 - 한 번만 manual)
############################################################

# ── Cloudflare IPv4 대역 (https://www.cloudflare.com/ips-v4) ──
data "http" "cloudflare_ipv4" {
  url = "https://www.cloudflare.com/ips-v4"

  request_headers = {
    Accept = "text/plain"
  }
}

locals {
  cloudflare_ipv4_ranges = compact(split("\n", trimspace(data.http.cloudflare_ipv4.response_body)))
}

############################################################
# DNS records - apex/api + grafana
############################################################
resource "cloudflare_record" "api" {
  zone_id = var.cloudflare_zone_id
  name    = var.domain_name        # FQDN - CF 가 알아서 zone 매칭
  type    = "CNAME"
  content = aws_lb.main.dns_name
  ttl     = 1                      # 1 = "Auto" (proxied 면 무시됨)
  proxied = true                   # orange cloud - TLS 종단 + WAF
  comment = "Managed by Terraform - DraWe prod API"
}

resource "cloudflare_record" "grafana" {
  zone_id = var.cloudflare_zone_id
  name    = "grafana.${var.domain_name}"
  type    = "CNAME"
  content = aws_lb.main.dns_name
  ttl     = 1
  proxied = true
  comment = "Managed by Terraform - DraWe prod Grafana"
}

############################################################
# ACM 검증용 CNAME
#
# AWS 가 발급한 _xxx.acm-validations.aws 로 향하는 CNAME.
# proxied=false 필수 - proxy 켜면 ACM 검증 query 가 깨짐.
############################################################
resource "cloudflare_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.main.domain_validation_options :
    dvo.domain_name => {
      name    = dvo.resource_record_name
      content = dvo.resource_record_value
      type    = dvo.resource_record_type
    }
  }

  zone_id = var.cloudflare_zone_id
  name    = each.value.name
  content = each.value.content
  type    = each.value.type
  ttl     = 60
  proxied = false
  comment = "ACM cert DNS validation"
}
