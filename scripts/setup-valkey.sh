#!/bin/bash
set -euo pipefail

# ── SSM Agent 설치 (AL2023 minimal AMI 대비) ─────────────
sudo dnf install -y amazon-ssm-agent || \
  sudo dnf install -y https://s3.ap-northeast-2.amazonaws.com/amazon-ssm-ap-northeast-2/latest/linux_arm64/amazon-ssm-agent.rpm
sudo systemctl enable --now amazon-ssm-agent

VALKEY_VERSION="8.1.6"
VALKEY_PASSWORD="${valkey_password}"

exec > /var/log/valkey-setup.log 2>&1
echo "=== Valkey setup started at $(date) ==="

# ── 시스템 패키지 ────────────────────────────────────────
dnf update -y
dnf install -y gcc make jemalloc-devel systemd-devel

# ── Valkey 빌드 및 설치 ──────────────────────────────────
cd /tmp
curl -fsSL "https://github.com/valkey-io/valkey/archive/refs/tags/$${VALKEY_VERSION}.tar.gz" -o valkey.tar.gz
tar xzf valkey.tar.gz
cd "valkey-$${VALKEY_VERSION}"
make -j"$(nproc)" USE_SYSTEMD=yes BUILD_TLS=no
make install PREFIX=/usr/local

# ── 사용자 및 디렉토리 ───────────────────────────────────
useradd --system --no-create-home --shell /sbin/nologin valkey || true
mkdir -p /etc/valkey /var/lib/valkey /var/log/valkey
chown valkey:valkey /var/lib/valkey /var/log/valkey

# ── 설정 파일 ────────────────────────────────────────────
cat > /etc/valkey/valkey.conf << 'CONF'
bind 0.0.0.0
port 6379
protected-mode yes

# AUTH
requirepass ${valkey_password}

# 메모리
maxmemory 200mb
maxmemory-policy allkeys-lru

# 영속성 (dev — RDB 만, AOF 비활성)
save 900 1
save 300 10
dbfilename dump.rdb
dir /var/lib/valkey

# 로깅
logfile /var/log/valkey/valkey.log
loglevel notice

# 성능
tcp-backlog 511
timeout 300
tcp-keepalive 300

# 보안
rename-command FLUSHALL ""
rename-command FLUSHDB ""
rename-command CONFIG "CONFIG_SECRET"
CONF

chown valkey:valkey /etc/valkey/valkey.conf
chmod 640 /etc/valkey/valkey.conf

# ── systemd 서비스 등록 ──────────────────────────────────
cat > /etc/systemd/system/valkey.service << 'SERVICE'
[Unit]
Description=Valkey In-Memory Data Store
After=network.target

[Service]
Type=simple
User=valkey
Group=valkey
ExecStart=/usr/local/bin/valkey-server /etc/valkey/valkey.conf
ExecStop=/usr/local/bin/valkey-cli -a ${valkey_password} shutdown save
Restart=always
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable valkey
systemctl start valkey

# ── 커널 튜닝 ────────────────────────────────────────────
echo "vm.overcommit_memory = 1" >> /etc/sysctl.conf
echo "net.core.somaxconn = 511" >> /etc/sysctl.conf
sysctl -p

# ── 헬스체크 ─────────────────────────────────────────────
sleep 2
if /usr/local/bin/valkey-cli -a "$${VALKEY_PASSWORD}" PING | grep -q PONG; then
  echo "=== Valkey setup complete. PING → PONG ==="
else
  echo "=== WARNING: Valkey PING failed ==="
fi
