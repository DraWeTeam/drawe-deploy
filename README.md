# DraWe — 배포 인프라

DraWe 서비스의 AWS 인프라를 Terraform 으로 관리합니다.

> 현재 인프라 구조를 지속적으로 개선 중이며, 구성과 비용 전략은 프로젝트 진행에 따라 변경될 수 있습니다.

dev / prod 환경을 별도 AWS 계정으로 운영하며,
ECS EC2 (Graviton ARM) 기반으로 애플리케이션과 observability 스택을 구성합니다.

## 핵심 설계

* dev / prod 별도 AWS 계정 운영
* ECS EC2 + Graviton (`t4g.*`) 기반 비용 최적화
* Terraform 기반 IaC 관리
* Alloy 기반 OpenTelemetry 수집 (DAEMON + sidecar 구조)
* Cloudflare + ALB 기반 HTTPS 구성
* dev 환경은 EventBridge 스케줄 기반 자동 on/off 로 비용 절감

## 디렉토리 구조

```text
drawe-deploy/
├── terraform-dev/           # dev 환경 Terraform
├── terraform-prod/          # prod 환경 Terraform
├── configs/                 # Alloy / Grafana / Loki / Tempo config
├── scripts/                 # 운영 보조 스크립트
└── docker-compose.local.yml # 로컬 observability 스택
```

## 환경 비교

| 항목     | dev                        | prod                               |
| ------ | -------------------------- | ---------------------------------- |
| AWS 계정 | 분리 운영                      | 분리 운영                              |
| 운영 시간  | 평일 13:00~18:00 KST         | 24/7                               |
| NAT    | NAT instance (`t4g.micro`) | fck-nat Multi-AZ (ASG)             |
| Redis  | EC2 Valkey                 | ElastiCache                        |
| 관측     | Grafana Cloud              | AMP + self-host Grafana/Loki/Tempo |

## 트래픽 흐름

```text
User → Cloudflare → ALB → ECS
                          ├── Backend (+ alloy sidecar)
                          ├── FastAPI (+ alloy sidecar)
                          └── alloy-daemon (DAEMON, host당 1)
```

dev / prod 는 동일 구조이며 observability destination 만 다릅니다.

## 배포

### Prerequisites

* Terraform >= 1.5
* AWS CLI v2
* AWS 인증 설정 (`aws configure`, SSO, IAM Identity Center 등)
* Cloudflare API Token 필요

### dev

```bash
cd terraform-dev

cp terraform.tfvars.example terraform.tfvars

export CLOUDFLARE_API_TOKEN="<token>"

terraform init
terraform plan -out tfplan
terraform apply tfplan
```

### prod

```bash
cd terraform-prod

cp terraform.tfvars.example terraform.tfvars

export CLOUDFLARE_API_TOKEN="<token>"

terraform init
terraform plan -out tfplan
terraform apply tfplan
```

## 참고 사항

* ECS EC2 인스턴스는 ARM64 (`t4g.*`) 기반으로 운영
* 컨테이너 이미지도 ARM64 호환 빌드 필요 (`docker buildx --platform linux/arm64`)
* 주요 시크릿은 AWS SSM Parameter Store (SecureString) 로 관리
* Alloy config 는 gzip + base64 로 압축 저장
* ECS Exec 활성화 상태로 운영
* ECS service 의 `task_definition` 은 `ignore_changes` 처리되어 있어 수동 force deployment 방식 사용
