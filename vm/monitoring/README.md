# Monitoring on VM datacenter hosts

Aligns with [monitoring/README.md](../../monitoring/README.md) (Prometheus / Loki on Kubernetes). VMs export **host metrics** via **node_exporter** and ship **journal logs** (or files) via **Promtail** to your central Loki.

## 1. node_exporter

```bash
sudo bash vm/monitoring/install-node-exporter.sh
```

Open **TCP 9100** to your Prometheus scrapers (tighten source CIDR). Add a static scrape job on Prometheus:

```yaml
- job_name: vm-datacenter-nodes
  static_configs:
    - targets:
        - 10.0.x.x:9100
      labels:
        datacenter: dc-vm
```

Use private IPs from `terraform output` (or DNS).

## 2. Consul agent metrics

With `telemetry { prometheus_retention_time = "60s" }` in `vm/consul/*.hcl`, scrape:

`http://<host>:8500/v1/agent/metrics?format=prometheus`

If you enable ACLs, add a bearer token to the scrape config (same pattern as [monitoring/manifests/podmonitor-consul-server.yaml](../../monitoring/manifests/podmonitor-consul-server.yaml)).

## 3. Promtail → Loki

1. Set `LOKI_URL` in `promtail-config.yaml` (push URL reachable from the VPC, e.g. `http://<loki-host>:3100/loki/api/v1/push`).
2. Install Promtail per [Grafana docs](https://grafana.com/docs/loki/latest/send-data/promtail/installation/) (binary or RPM).
3. Copy the config:

```bash
sudo install -m 0644 vm/monitoring/promtail-config.yaml /etc/promtail/config.yaml
sudo systemctl enable --now promtail   # if you created a unit file
```

Example systemd unit: see comments at bottom of `promtail-config.yaml`.

## 4. Application / container logs

Optional: add a Promtail `docker` or `file` scrape to ship container logs. For Docker, the Docker logging driver or `promtail` `docker_sd` requires mounting Docker socket (understand the security tradeoff).
