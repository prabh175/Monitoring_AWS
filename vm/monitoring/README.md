# VM datacenter monitoring

Prometheus runs inside EKS (dc1) and scrapes the VM datacenter over the VPC private network.
Logs ship via Promtail on each VM to the central Loki instance on dc1.

---

## Which exporter does what

| Metric type | Tool | Port | Installed on |
|-------------|------|------|--------------|
| Host OS — CPU, memory, disk, network, filesystem | `node_exporter` | **9100** | Every VM |
| Consul catalog — service count, health check pass/fail/warn | `consul_exporter` | **9107** | Consul server VM only |
| Consul internal — Raft, RPC, GC, memory, client activity | Consul agent built-in (`telemetry {}`) | **8500** `/v1/agent/metrics?format=prometheus` | Every VM (server and clients) |
| Envoy sidecar — upstream/downstream requests, latency, retries, circuit-breaker | Envoy admin API (native Prometheus) | **19000** `/stats/prometheus` | Every HashiCups service VM |
| Log shipping | Promtail | **9080** | Every VM |

> **node_exporter** = OS only. It knows nothing about Consul or Envoy.
>
> **consul_exporter** = Consul service catalog and health check state. Use it on the Consul server to show which services are passing/failing.
>
> **Consul agent telemetry** = Consul's own internal performance. Already enabled in `vm/consul/server.hcl` and `vm/consul/client.hcl` (`telemetry { prometheus_retention_time = "60s" }`).
>
> **Envoy admin `/stats/prometheus`** = Envoy proxy metrics per service. Not node_exporter, not consul_exporter. Envoy exposes this natively — just bind it to a reachable address.

---

## Security group requirements

Before scraping works, open these ports **from the EKS node security group to the VM security group**:

| Port | Protocol | Source | Purpose |
|------|----------|--------|---------|
| 9100 | TCP | EKS node SG | node_exporter |
| 9107 | TCP | EKS node SG | consul_exporter |
| 8500 | TCP | EKS node SG | Consul agent metrics |
| 19000 | TCP | EKS node SG | Envoy admin / sidecar metrics |

Add these rules in `terraform/vm-datacenter` or via the AWS Console.

---

## 1. node_exporter (all VMs)

```bash
sudo bash vm/monitoring/install-node-exporter.sh
# Listens on :9100/metrics
```

Verify: `curl http://localhost:9100/metrics | head`

---

## 2. consul_exporter (Consul server VM only)

Exposes service catalog health and member state — things Consul's own telemetry endpoint does not cover (e.g. number of passing/failing service instances).

```bash
sudo bash vm/monitoring/install-consul-exporter.sh
# Listens on :9107/metrics
```

If ACLs are enabled, add a token with `agent:read` and `node:read` to `/etc/consul.d/consul.env`:

```bash
echo 'CONSUL_HTTP_TOKEN=<metrics-policy-token>' | sudo tee -a /etc/consul.d/consul.env
sudo systemctl restart consul_exporter
```

Verify: `curl http://localhost:9107/metrics | grep consul_up`

---

## 3. Consul agent metrics (all VMs — already enabled)

The Consul agent itself exposes a Prometheus endpoint when `telemetry { prometheus_retention_time }` is set. Both `vm/consul/server.hcl` and `vm/consul/client.hcl` already include this block — no extra install needed.

Verify on any VM: `curl 'http://localhost:8500/v1/agent/metrics?format=prometheus' | head`

If ACLs are enabled, Prometheus needs a bearer token. Add to the scrape job in `monitoring/helm/kube-prometheus-stack-values.yaml`:

```yaml
- job_name: vm-datacenter-consul-agent-metrics
  bearer_token: <token-with-agent-read-policy>
  ...
```

---

## 4. Envoy sidecar metrics (HashiCups service VMs)

Each service VM runs one Consul Connect Envoy sidecar (`connect-envoy@<service>.service`). Envoy's admin API at `/stats/prometheus` is the native Prometheus endpoint — **no separate exporter is needed**.

The `vm/hashicups/systemd/connect-envoy@.service` already starts Envoy with `--admin-bind 0.0.0.0:19000` so Prometheus in EKS can reach it over the VPC.

Verify on a HashiCups VM:

```bash
curl http://localhost:19000/stats/prometheus | grep envoy_cluster_upstream_rq_total | head
```

Key Envoy metrics to watch:

| Metric | Meaning |
|--------|---------|
| `envoy_cluster_upstream_rq_total` | Total requests sent to an upstream |
| `envoy_cluster_upstream_rq_time_bucket` | Latency histogram per upstream |
| `envoy_cluster_upstream_cx_connect_fail` | Failed mTLS connections |
| `envoy_http_downstream_rq_5xx` | 5xx responses seen by this service |

---

## 5. Promtail → Loki (all VMs)

Install and configure Promtail to ship systemd journal logs to Loki on dc1.

**Install Promtail binary:**

```bash
PROMTAIL_VERSION=3.0.0
curl -fsSL \
  "https://github.com/grafana/loki/releases/download/v${PROMTAIL_VERSION}/promtail-linux-amd64.zip" \
  -o /tmp/promtail.zip
unzip -q /tmp/promtail.zip -d /tmp
sudo install -m 0755 /tmp/promtail-linux-amd64 /usr/local/bin/promtail
```

**Configure and start:**

```bash
# Get the Loki NLB DNS name from EKS:
#   kubectl config use-context dc1
#   kubectl get svc loki -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

sudo mkdir -p /etc/promtail
sudo sed "s|REPLACE_LOKI_HOST|<loki-nlb-dns>|g" \
  vm/monitoring/promtail-config.yaml | sudo tee /etc/promtail/config.yaml

sudo tee /etc/systemd/system/promtail.service <<'UNIT'
[Unit]
Description=Grafana Promtail
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/local/bin/promtail -config.file=/etc/promtail/config.yaml
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT

sudo systemctl daemon-reload
sudo systemctl enable --now promtail
```

---

## 6. Update Prometheus scrape config in EKS

Edit `monitoring/helm/kube-prometheus-stack-values.yaml` and replace the `10.0.X.X` placeholder IPs with the actual VM private IPs from Terraform:

```bash
cd terraform/vm-datacenter
terraform output   # shows consul_server_private_ip and hashicups VM IPs
```

Then re-apply the Prometheus Helm chart on dc1:

```bash
cd monitoring
kubectl config use-context dc1
helm upgrade kps prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values helm/kube-prometheus-stack-values.yaml
```

Verify the targets are up in Grafana → Explore → Prometheus → `up{datacenter="dc-vm"}`.

---

## Quick reference — what runs where

| VM | node_exporter | consul_exporter | Consul agent metrics | Envoy metrics | Promtail |
|----|:---:|:---:|:---:|:---:|:---:|
| consul-server | ✅ :9100 | ✅ :9107 | ✅ :8500 | — | ✅ |
| hashicups-postgres | ✅ :9100 | — | ✅ :8500 | ✅ :19000 | ✅ |
| hashicups-product-api | ✅ :9100 | — | ✅ :8500 | ✅ :19000 | ✅ |
| hashicups-payments | ✅ :9100 | — | ✅ :8500 | ✅ :19000 | ✅ |
| hashicups-public-api | ✅ :9100 | — | ✅ :8500 | ✅ :19000 | ✅ |
| hashicups-frontend | ✅ :9100 | — | ✅ :8500 | ✅ :19000 | ✅ |
