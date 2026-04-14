# Monitoring on Consul / HashiCups VMs

Prefer the maintained path under **[vm/monitoring/README.md](../../vm/monitoring/README.md)** (install scripts and Promtail config next to the VM datacenter docs).

Use **node_exporter** for host metrics (CPU, memory, disk, network) and **Promtail** for logs. Scrape node_exporter from the Prometheus that can reach the VM (same VPC, firewall open on port 9100).

## node_exporter (example: RHEL / Amazon Linux)

```bash
sudo useradd --no-create-home --shell /bin/false node_exporter 2>/dev/null || true
curl -sL "https://github.com/prometheus/node_exporter/releases/download/v1.8.2/node_exporter-1.8.2.linux-amd64.tar.gz" | tar xz
sudo mv node_exporter-1.8.2.linux-amd64/node_exporter /usr/local/bin/
# systemd unit (minimal)
sudo tee /etc/systemd/system/node_exporter.service >/dev/null <<'EOF'
[Unit]
Description=Prometheus Node Exporter
After=network.target

[Service]
User=node_exporter
ExecStart=/usr/local/bin/node_exporter --web.listen-address=:9100
Restart=always

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now node_exporter
```

Open **TCP 9100** only from your Prometheus subnets or security groups.

### Add scrape job (Kubernetes Prometheus)

Append a static scrape to `kube-prometheus-stack` (via `additionalScrapeConfigs` or a `ServiceMonitor` if you run exporters in k8s), for example:

```yaml
- job_name: vm-node-exporters
  static_configs:
    - targets:
        - 10.0.1.20:9100
        - 10.0.1.21:9100
        - 10.0.1.22:9100
      labels:
        role: consul-vm
```

Use your real private IPs.

## Promtail (VM → Loki)

Install Promtail on each VM and point it at the **Loki push URL** (same as Kubernetes Promtail: `http://<loki-host>:3100/loki/api/v1/push`).

1. Download a Promtail release matching your Loki major version from [Grafana releases](https://github.com/grafana/loki/releases).
2. Use a minimal `config.yml`:

```yaml
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://LOKI_HOST:3100/loki/api/v1/push

scrape_configs:
  - job_name: journal
    journal:
      max_age: 12h
      labels:
        job: systemd-journal
    relabel_configs:
      - source_labels: [__journal__systemd_unit]
        target_label: unit
```

3. Run under systemd (see Promtail docs) or containerize.

Replace `LOKI_HOST` with a reachable address (private LB, NodePort, or bastion tunnel).

## Consul process metrics on VMs

If the Consul agent exposes Prometheus metrics (`telemetry { prometheus_retention_time = "60s" }` or equivalent), add another static scrape target on the agent’s metrics port (often **8500** with ACL—mirror the Kubernetes PodMonitor pattern with a token).
