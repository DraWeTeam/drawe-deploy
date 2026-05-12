#!/usr/bin/env bash
# ── Alloy 설정 + Grafana 비밀번호를 SSM에 업로드 ─────────
set -euo pipefail

PROJECT="drawe"
ENV="${1:?usage: $0 <dev|prod>}"
REGION="ap-northeast-2"

SIDECAR_FILE=$([ "$ENV" = "prod" ] && echo "configs/alloy-sidecar-prod.alloy" || echo "configs/alloy-sidecar.alloy")

upload_b64() {
  local file="$1" key="$2" label="$3"
  if [ ! -f "$file" ]; then echo "ERROR: $file not found"; exit 1; fi

  local b64
  # gzip 으로 압축 후 base64 — entrypoint 의 `base64 -d | gunzip` 와 짝
  b64=$(gzip -c "$file" | base64 -w 0 2>/dev/null || gzip -c "$file" | base64 | tr -d '\n')

  echo "▶ ${label}: $(echo -n "$b64" | wc -c) bytes → ${key}"
  aws ssm put-parameter \
    --name "$key" --value "$b64" \
    --type SecureString --tier Advanced \
    --overwrite --region "$REGION"
}

# ── Alloy 설정 두 개 업로드 ──────────────────────────────
upload_b64 "$SIDECAR_FILE" \
  "/${PROJECT}/${ENV}/alloy-config-b64" "Sidecar config"

upload_b64 "configs/alloy-daemon.alloy" \
  "/${PROJECT}/${ENV}/alloy-daemon-config-b64" "Daemon config"

echo ""
echo "✅ Alloy 설정 업로드 완료"
echo ""
echo "▶ Grafana Cloud 시크릿 3개는 별도로 입력해주세요 (Grafana Cloud 가입 후):"
echo "  aws ssm put-parameter --name /${PROJECT}/${ENV}/grafana-otlp-endpoint --value \"<url>\" --type String --overwrite --region ${REGION}"
echo "  aws ssm put-parameter --name /${PROJECT}/${ENV}/grafana-instance-id   --value \"<id>\" --type String --overwrite --region ${REGION}"
echo "  aws ssm put-parameter --name /${PROJECT}/${ENV}/grafana-cloud-token   --value \"<token>\" --type SecureString --overwrite --region ${REGION}"