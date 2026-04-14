# Monitoring stack (Prometheus, Grafana, Loki, Promtail)

Layered installs using community Helm charts. Install into namespace **`monitoring`** on each Kubernetes cluster (adjust names if your standards differ).

## Prerequisites

- Helm 3
- Prometheus Operator CRDs (installed **with** kube-prometheus-stack)
- Network: for a **single** Grafana/Loki on DC1 and Promtail on DC2, DC2 must reach DC1’s Loki URL (NodePort, LoadBalancer, or private connectivity)

Add Helm repos:

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
```

## 1. kube-prometheus-stack (Prometheus + Grafana + operators)

**DC1 (primary UI):** Prometheus, Grafana, Alertmanager, and permissive selectors so **PodMonitors** in `consul` (and elsewhere) are discovered.

```bash
kubectl create namespace monitoring

helm upgrade --install kps prometheus-community/kube-prometheus-stack -n monitoring \
  -f helm/kube-prometheus-stack-values.yaml
```

Access Grafana (change the default password in `kube-prometheus-stack-values.yaml` first):

```bash
kubectl -n monitoring port-forward svc/kps-grafana 3000:80
# http://127.0.0.1:3000  user admin
```

If the Grafana service name differs, run `kubectl get svc -n monitoring | grep grafana`.

**DC2 (metrics only, optional):** run a second Prometheus for local scraping; Grafana is disabled to avoid duplication.

```bash
kubectl create namespace monitoring

helm upgrade --install kps prometheus-community/kube-prometheus-stack -n monitoring \
  -f helm/kube-prometheus-stack-values-dc2.yaml
```

After install, discover the in-cluster Prometheus URL for the Consul UI:

```bash
kubectl -n monitoring get svc | grep -i prometheus
# Often: kps-kube-prometheus-prometheus (ClusterIP:9090) — exact name follows your Helm release name.
```

Set `ui.metrics.baseURL` in [kubernetes/helm/consul/values-dc1.yaml](../kubernetes/helm/consul/values-dc1.yaml) (and DC2 if you use the UI there) to that service URL, then:

```bash
helm upgrade consul hashicorp/consul -n consul -f kubernetes/helm/consul/values-dc1.yaml
```

## 2. Consul server scrape (ACL-aware)

With `global.acls.manageSystemACLs: true`, Prometheus needs a **Consul ACL token** to scrape `/v1/agent/metrics?format=prometheus`.

1. Create a Consul policy allowing metrics (see [server metrics tutorial](https://developer.hashicorp.com/consul/tutorials/observe-your-network/server-metrics-and-logs)).
2. Create a token and Kubernetes secret in `consul`:

```bash
kubectl create secret generic consul-prometheus-token \
  --from-literal=token="$CONSUL_METRICS_TOKEN" \
  -n consul
```

3. Apply the PodMonitor:

```bash
kubectl apply -f manifests/podmonitor-consul-server.yaml
```

If the PodMonitor CRD is not found, wait until `kube-prometheus-stack` finishes installing CRDs.

**Connect / Envoy sidecars:** injected pods can expose merged metrics on port `20100` when `connectInject.metrics.defaultEnabled` is true. The PodMonitor in this folder includes a second endpoint for pods labeled as connect-injected; tune selectors to match your chart labels if needed.

## 3. Loki (log aggregation)

Install on **one** cluster (typically DC1) in `monitoring`:

```bash
kubectl config use-context kind-dc1
helm upgrade --install loki grafana/loki -n monitoring -f helm/loki-values.yaml
```

Confirm the Loki push base URL (service name/port vary slightly by chart version):

```bash
kubectl get svc -n monitoring | grep -i loki
```

Expose Loki to other clusters only if Promtail on DC2 must push cross-cluster (NodePort, LoadBalancer, or mesh—your choice). If the in-cluster URL is not `http://loki.monitoring.svc:3100`, update `helm/promtail-values.yaml` and `grafana.additionalDataSources` in `kube-prometheus-stack-values.yaml` before or via `helm upgrade`.

## 4. Promtail (Kubernetes)

**Same cluster as Loki:**

```bash
helm upgrade --install promtail grafana/promtail -n monitoring \
  -f helm/promtail-values.yaml
```

**Remote Loki (e.g. Promtail on DC2):** copy `helm/promtail-values.yaml` to `promtail-values-dc2.yaml` and set `config.clients[0].url` to a reachable URL, for example `http://<dc1-node-ip>:<loki-nodeport>/loki/api/v1/push`, then:

```bash
kubectl config use-context kind-dc2
helm upgrade --install promtail grafana/promtail -n monitoring -f promtail-values-dc2.yaml
```

## 5. VMs (Promtail + node_exporter)

See [vm/README.md](vm/README.md) for Promtail against journald/files and **node_exporter** (host metrics). Point Promtail at the same Loki push URL as above.

## Dashboards

- In Grafana: **Explore** → Prometheus for ad-hoc queries.
- Import community dashboards (search “Consul”, “Envoy”, “Loki”) from [Grafana dashboards](https://grafana.com/grafana/dashboards/), or build panels from:
  - Consul: `consul_*` and `envoy_*` metrics (after scrapes succeed)
  - Logs: Loki labels from Promtail (`namespace`, `pod`, `app`, etc.)

## Uninstall

```bash
helm uninstall promtail -n monitoring
helm uninstall loki -n monitoring
helm uninstall kps -n monitoring
kubectl delete crd -l app.kubernetes.io/part-of=kube-prometheus-stack  # only if you want CRDs gone; affects other stacks
```

Use care deleting CRDs cluster-wide in shared environments.
