#!/usr/bin/env bash
set -euo pipefail
VERSION="${NODE_EXPORTER_VERSION:-1.8.2}"
ARCH="${ARCH:-amd64}"
URL="https://github.com/prometheus/node_exporter/releases/download/v${VERSION}/node_exporter-${VERSION}.linux-${ARCH}.tar.gz"

useradd --no-create-home --shell /bin/false node_exporter 2>/dev/null || true
curl -fsSL "$URL" | tar xz -C /tmp
install -m 0755 "/tmp/node_exporter-${VERSION}.linux-${ARCH}/node_exporter" /usr/local/bin/node_exporter
rm -rf "/tmp/node_exporter-${VERSION}.linux-${ARCH}"

cat >/etc/systemd/system/node_exporter.service <<'UNIT'
[Unit]
Description=Prometheus Node Exporter
After=network-online.target
Wants=network-online.target

[Service]
User=node_exporter
Group=node_exporter
ExecStart=/usr/local/bin/node_exporter --web.listen-address=:9100
Restart=always

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now node_exporter
echo "node_exporter on :9100"
