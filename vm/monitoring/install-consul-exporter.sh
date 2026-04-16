#!/usr/bin/env bash
# Install consul_exporter on the Consul server VM.
# Exposes service catalog and health-check metrics at :9107/metrics.
# Run as root (or with sudo) on the consul-server EC2 instance.
set -euo pipefail

VERSION="${CONSUL_EXPORTER_VERSION:-0.13.0}"
ARCH="${ARCH:-amd64}"
URL="https://github.com/prometheus/consul_exporter/releases/download/v${VERSION}/consul_exporter-${VERSION}.linux-${ARCH}.tar.gz"

useradd --no-create-home --shell /bin/false consul_exporter 2>/dev/null || true

curl -fsSL "$URL" | tar xz -C /tmp
install -m 0755 "/tmp/consul_exporter-${VERSION}.linux-${ARCH}/consul_exporter" /usr/local/bin/consul_exporter
rm -rf "/tmp/consul_exporter-${VERSION}.linux-${ARCH}"

# If ACLs are enabled, set CONSUL_HTTP_TOKEN below (or source from /etc/consul.d/consul.env).
cat > /etc/systemd/system/consul_exporter.service <<'UNIT'
[Unit]
Description=Prometheus Consul Exporter
After=consul.service
Requires=consul.service

[Service]
User=consul_exporter
Group=consul_exporter
EnvironmentFile=-/etc/consul.d/consul.env

# --consul.server        points at the local Consul agent HTTP API
# --web.listen-address   port that Prometheus will scrape
ExecStart=/usr/local/bin/consul_exporter \
  --consul.server=http://127.0.0.1:8500 \
  --web.listen-address=:9107

Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now consul_exporter
echo "consul_exporter listening on :9107/metrics"
