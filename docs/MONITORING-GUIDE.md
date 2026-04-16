# Monitoring Architecture Guide

**Consul Enterprise 1.21 on EKS — Multi-Cluster, Multi-Tenant**

This guide documents every monitoring decision made for this deployment, the tradeoffs evaluated, and the reasoning behind each choice. It is intended for the platform engineering team who maintains this infrastructure and for application teams who operate within it.

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Decision: Prometheus Deployment Model](#2-decision-prometheus-deployment-model)
3. [Decision: No Prometheus Operator](#3-decision-no-prometheus-operator)
4. [Decision: Auto-Discovery without an Operator](#4-decision-auto-discovery-without-an-operator)
5. [Decision: Metrics Merging (20100 local, 20200 scrape)](#5-decision-metrics-merging-20100-local-20200-scrape)
6. [Decision: Transparent Proxy and mTLS Compatibility](#6-decision-transparent-proxy-and-mtls-compatibility)
7. [Decision: Alert Rules Self-Service via CronJob](#7-decision-alert-rules-self-service-via-cronjob)
8. [Decision: Grafana Multi-Tenancy Model](#8-decision-grafana-multi-tenancy-model)
9. [Decision: Log Aggregation with Loki](#9-decision-log-aggregation-with-loki)
10. [Decision: Multi-Cluster Observability](#10-decision-multi-cluster-observability)
11. [What We Would Change at Larger Scale](#11-what-we-would-change-at-larger-scale)
12. [Team Onboarding Checklist](#12-team-onboarding-checklist)
13. [Metric Reference by Source](#13-metric-reference-by-source)

---

## 1. Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│ EKS: consul-dc1                                                  │
│                                                                  │
│  ┌─────────────────┐    ┌─────────────────┐                     │
│  │  Consul Servers  │    │  Mesh Gateway   │                     │
│  │  (3 pods)        │    │  (NLB, port 443)│                     │
│  │  metrics: 8501   │    │  metrics: 20200 │                     │
│  └─────────────────┘    └─────────────────┘                     │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  Application Pods (connect-injected)                    │    │
│  │  app + Envoy → merged; scrape pod-ip:20200/metrics      │    │
│  │  (internal merge at :20100/stats/prometheus; tproxy ok) │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  monitoring namespace                                    │    │
│  │  Prometheus (standalone) ← scrapes everything above     │    │
│  │  Grafana (standalone)    ← queries Prometheus + Loki    │    │
│  │  Loki                    ← receives logs from Promtail  │    │
│  │  Rule Merger CronJob     ← merges team alert rules      │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ EKS: consul-dc2                                                  │
│                                                                  │
│  Consul Servers, Mesh Gateway, Application Pods                  │
│  Prometheus (standalone) → remote_write → dc1 Prometheus        │
│  Promtail → dc1 Loki                                            │
└─────────────────────────────────────────────────────────────────┘
```

**Key design principle:** The platform team provisions the monitoring foundation once. Application teams self-service scrape targets, alert rules, and dashboards with no platform intervention.

---

## 2. Decision: Prometheus Deployment Model

### What we chose
Standalone Prometheus via `prometheus-community/prometheus` Helm chart — one per EKS cluster, with dc2 shipping metrics to dc1 via `remote_write`.

### Options evaluated

| Option | Description | Verdict |
|--------|-------------|---------|
| **A: kube-prometheus-stack** | All-in-one: Prometheus Operator + Prometheus + Grafana + Alertmanager | Rejected — requires operator CRDs |
| **B: Standalone Prometheus** | `prometheus-community/prometheus` chart, no operator | **Chosen** |
| **C: HCP Terraform-managed** | External managed Prometheus service | Out of scope |
| **D: Thanos** | Sidecar per Prometheus, global query layer | Future option for cross-cluster queries |

### Tradeoffs

**Standalone is simpler to operate:**
- No CRD lifecycle management — upgrades never block on CRD migrations
- Scrape config is a single `prometheus.yml` ConfigMap — readable by anyone
- No reconciliation loops to debug when a target isn't being scraped

**Standalone loses auto-scaling:**
- A single Prometheus handles both clusters via `remote_write`
- At very large scale (>1M series), you need sharding or Thanos/Mimir
- For this deployment (2 EKS clusters, ~50 services), single Prometheus is appropriate

**Why not kube-prometheus-stack?**
The constraint was no Prometheus/Grafana operators. Beyond the constraint, the operator adds ~30 CRDs that have their own version lifecycle separate from Kubernetes. In environments with strict change management, CRD upgrades require additional approval cycles. The standalone approach avoids this entirely.

---

## 3. Decision: No Prometheus Operator

### Context
The customer's platform team does not permit Kubernetes operators in their environment. This was the starting constraint.

### What the operator provides that we lose

| Feature | With Operator | Without Operator (our approach) |
|---------|--------------|--------------------------------|
| Auto-discovery of new services | `ServiceMonitor` CR | Pod/service annotations |
| Team self-service scrape config | Apply a CR | Apply an annotation |
| Alert rules per team | `PrometheusRule` CR | ConfigMap + merger CronJob |
| Hot-reload on change | Operator reconciles | Config-reloader sidecar |
| Multi-instance Prometheus | Operator manages sharding | Manual or Thanos |

### Our mitigations

We replicate the operator's most important feature — self-service without platform bottleneck — using:
1. **`kubernetes_sd_configs`** for annotation-based auto-discovery (built into Prometheus)
2. **A CronJob** that merges team ConfigMaps into a central rules file
3. **Grafana's config-reload sidecar** for dashboard hot-loading

### Recommendation to revisit

**If the operator constraint is relaxed**, the kube-prometheus-stack should be adopted. In a multi-tenant environment with 10+ teams, the operator is the right tool. The constraint that teams "can't use operators" is often really a concern about:
- **Upgrade risk**: Mitigated by pinning operator and CRD versions separately
- **CRD proliferation**: 6 CRDs for monitoring (PrometheusRule, ServiceMonitor, etc.) is manageable
- **Unknown reconciliation**: Mitigated by clear RBAC — teams can only create CRs in their namespace

The conversation worth having with the customer is: the operator is **the platform team's tool for getting out of the way**. Without it, the platform team is a bottleneck for every new scrape target forever.

---

## 4. Decision: Auto-Discovery without an Operator

### What we built
Prometheus `kubernetes_sd_configs` with relabeling rules that watch for standard `prometheus.io/*` annotations on pods and services across all namespaces.

### How it works

Teams add annotations to their pod spec:
```yaml
annotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "8080"       # optional, defaults to first container port
  prometheus.io/path: "/metrics"   # optional, defaults to /metrics
```

Prometheus discovers the pod within one scrape interval (15 seconds). No platform ticket. No ConfigMap edit. No restart.

### Compared to ServiceMonitor

```
ServiceMonitor (operator):          Annotation (our approach):
  kubectl apply -f monitor.yaml       Add 3 lines to pod template
  Operator reconciles                 Prometheus picks up in 15s
  Prometheus config updated           Same result
  Pod scraped                         Pod scraped
```

The operational outcome is identical. The annotation approach has one advantage: the scrape configuration lives alongside the application manifest, making it visible in the same PR.

### Tradeoff: less expressive

`ServiceMonitor` supports multiple endpoints, TLS config per endpoint, OAuth2, and complex relabeling per service. Pod annotations are flat key-value pairs. For the majority of cases (one metrics port, path `/metrics`, no auth), annotations are sufficient.

For Consul servers (HTTPS **:8501**, bearer token, `scrape_protocols` for promhttp) and mesh gateways (port **20200**, Envoy Prometheus listener), we use explicit scrape jobs in `prometheus-values.yaml` — these are platform-owned and don't need team involvement.

### Automatic label enrichment

Every scraped metric gets these labels automatically via relabeling:
- `namespace` — the Kubernetes namespace (used for team isolation in Grafana)
- `pod` — the pod name
- `app` — from `app` pod label
- `team` — from the `team` label on the namespace (set by `onboard-team.sh`)

This means Grafana dashboards can always filter by `team` without any team-specific configuration.

---

## 5. Decision: Metrics Merging (20100 local, 20200 scrape)

### What we chose
Enable `connectInject.metrics.defaultEnableMerging: true` with `defaultMergedMetricsPort: "20100"`. Per [Consul K8s telemetry](https://developer.hashicorp.com/consul/docs/observe/telemetry/k8s), the **dataplane merged server** listens at **`127.0.0.1:20100/stats/prometheus`**, and Envoy exposes the **external Prometheus listener** at **`0.0.0.0:20200`** with path **`/metrics`** (`defaultPrometheusScrapePort` / `defaultPrometheusScrapePath`). **Prometheus must scrape `pod-ip:20200/metrics`**, not `20100/metrics` (that returns **404**).

### Why merging matters

Without merging, a connect-injected pod has **two** metrics endpoints:
- **App metrics**: `pod-ip:8080/metrics` (application)
- **Envoy metrics**: `pod-ip:15090/metrics` (sidecar proxy)

Prometheus would need two scrape configs per pod, and the Envoy metrics would not have app-level labels.

With merging, Consul Dataplane combines streams and serves them for scraping at **`pod-ip:20200/metrics`**. One scrape job covers everything. App metrics and Envoy metrics share the same `pod`, `namespace`, `app`, and `team` labels.

### What teams get for free

Every connect-injected pod automatically emits:

| Metric type | Source | Example metrics |
|-------------|--------|-----------------|
| Application metrics | App container | Your custom business metrics |
| HTTP request rates | Envoy | `envoy_cluster_upstream_rq_total` |
| HTTP error rates | Envoy | `envoy_cluster_upstream_rq_xx{envoy_response_code_class="5"}` |
| Latency histograms | Envoy | `envoy_cluster_upstream_rq_time_bucket` |
| Connection stats | Envoy | `envoy_cluster_upstream_cx_total` |
| mTLS cert expiry | Consul | `consul_agent_tls_cert_expiry` |

Teams get L7 observability on every service-to-service call **without writing any instrumentation code**.

### Troubleshooting: `ParseFloat` / `parsing "to"` on `pod-ip:20200/metrics`

After **`scrape_protocols`** is applied, this error almost always means the **merged exposition includes a non-metric line**. When Consul dataplane cannot scrape the application’s metrics URL (wrong `prometheus.io/port`, app not listening on `127.0.0.1`, path not `/metrics`, returns HTML, timeout), it may **append a line like** `failed to scrape metrics at url "http://127.0.0.1:9090/metrics"` to the response. Prometheus then tries to parse that text as metrics and fails (often on the word **`to`**). This matches [reported behavior](https://stackoverflow.com/questions/74752867) for Consul Envoy merged endpoints.

**What to do**

1. From any container in the pod that has `wget`/`curl`, fetch **`http://127.0.0.1:<your-app-port>/<metrics-path>`** — it must return **only** valid Prometheus text (HTTP 200). Fix the app or annotations until it does.
2. Inspect the merged stream: **`wget -qO- http://127.0.0.1:20200/metrics | tail -30`** — if you see **`failed to scrape`**, the problem is the **upstream app scrape**, not Prometheus relabeling.
3. **Temporary:** disable merging for that workload with **`consul.hashicorp.com/enable-metrics-merging: "false"`** (Envoy-only on **20200**, or use tproxy exclude for the app port — see options below). You lose merged app+Envoy in one series set until the app endpoint is fixed.

**UI-only pods (e.g. port 3000, no `/metrics`):** If the error line shows **`127.0.0.1:3000/metrics`** (or your HTTP port), the service is registered on that port but the process does not expose Prometheus text there. Either **add a real `/metrics` handler** on that port, or point Consul at a metrics port/path with **`consul.hashicorp.com/service-metrics-port`** / **`consul.hashicorp.com/service-metrics-path`**, or **disable merging** for that pod so **20200** returns Envoy metrics only and the bad line disappears.

### Tradeoff: merged metrics can be large

Envoy emits a high cardinality of cluster-level metrics. For a service with 20 upstream dependencies, this can be thousands of time series per pod. Monitor Prometheus memory usage and consider dropping unused Envoy metrics via relabeling if series count becomes a problem:

```yaml
# Add to the consul-connect-envoy scrape job to drop high-cardinality Envoy internals
metric_relabel_configs:
  - source_labels: [__name__]
    regex: "envoy_http_downstream_.*"   # drop downstream metrics if not needed
    action: drop
```

---

## 6. Decision: Transparent Proxy and mTLS Compatibility

### The problem
When transparent proxy (tproxy) is enabled, `iptables` rules on every mesh pod redirect **all inbound traffic through Envoy**, which enforces mTLS. Prometheus has no sidecar and cannot present mTLS certificates. Left unaddressed, all scraping of mesh pods fails.

### How we resolved it — Metrics listener and tproxy

When merging is enabled, Consul configures the **20200** Prometheus listener (and the internal **20100** merge path) so external scrapes hit **`pod-ip:20200`** without traversing the mTLS datapath the same way as app traffic. Follow current Consul Helm defaults for which ports are excluded from transparent proxy; the platform scrape job uses **`20200/metrics`** per upstream docs.

This is intentional design: Consul recognises that the merged metrics port exists for external scraping and removes it from the mTLS enforcement boundary automatically.

### What still breaks

Custom application metrics ports (for example **8080**) remain behind tproxy unless excluded. If a team exposes metrics on 8080 directly (without Consul merging), scraping that port from outside the mesh fails unless you exclude it or use merging to **20200**.

### Fix options for teams

**Option 1 — Use Consul metrics merging (recommended)**
```yaml
annotations:
  consul.hashicorp.com/connect-inject: "true"
  prometheus.io/scrape: "true"
  prometheus.io/port: "8080"    # app metrics source; merged scrape is 20200/metrics
  # No exclusion needed — merging handles it
```
Consul reads `prometheus.io/port`, scrapes the app on 8080, and merges into the stream served at **20200**. Prometheus scrapes **`pod-ip:20200/metrics`**.

**Option 2 — Explicit tproxy exclusion**
```yaml
annotations:
  consul.hashicorp.com/connect-inject: "true"
  prometheus.io/scrape: "true"
  prometheus.io/port: "8080"
  consul.hashicorp.com/transparent-proxy-exclude-inbound-ports: "8080"
```
Tells tproxy to leave port 8080 alone. Prometheus reaches it directly. Simple, but the metrics endpoint is no longer protected by mTLS — acceptable for metrics, but worth documenting as a deliberate decision.

**Option 3 — Put Prometheus in the mesh**
Deploy Prometheus with `consul.hashicorp.com/connect-inject: "true"` and create intentions allowing it to reach all services. This maintains mTLS end-to-end but adds complexity: Prometheus becomes a mesh-aware client and needs an intention to every service it scrapes.

### Our recommendation
Option 1 for all standard cases. Option 2 as a fallback when an app cannot route metrics through Consul merging. Document Option 3 as the path for strict zero-trust environments.

### Platform-wide exclusion (if needed)

To exclude a port globally for all mesh pods without per-pod annotation:
```yaml
# In values-dc1.yaml and values-dc2.yaml
connectInject:
  metrics:
    # Uncomment to exclude a platform-wide port from tproxy globally
    # defaultToproxyExcludeInboundPorts: "9090,8080"
```

---

## 7. Decision: Alert Rules Self-Service via CronJob

### What we built
A CronJob (`monitoring/rule-merger/rule-merger-cronjob.yaml`) that runs every 60 seconds, scans all namespaces for ConfigMaps labelled `monitoring/rules=true`, and merges them into a single ConfigMap consumed by Prometheus.

### Why not just edit the central ConfigMap?

If the platform team owns all alert rules:
- Every new service requires a platform ticket
- Platform team has no context for application-level SLOs
- Teams can't iterate quickly on their own alerting
- Single ConfigMap becomes a merge conflict nightmare with multiple teams

### How it works

```
Team namespace (team-a):              monitoring namespace:
  ConfigMap: team-a-alert-rules   →   rule-merger CronJob reads it
  label: monitoring/rules=true    →   merges into prometheus-team-rules
                                  →   Prometheus reloads within 15s
```

Teams create and update their rules independently. The CronJob is the only cross-namespace coordination point.

### Tradeoffs

**Simple, no new dependencies:** Uses `kubectl` in a CronJob — no new tools, no CRDs, no operator.

**60 second lag:** Rules are not live immediately. For a demo or development environment this is fine. For production alerting, consider reducing the cron schedule or switching to inotify-based watching.

**No validation:** The CronJob merges ConfigMaps without validating PromQL syntax. A team with a bad rule expression will break their rule group silently. Mitigation: provide a `promtool check rules` step in the team's CI pipeline using the template as a base.

**Scaling limit:** With 50+ teams each with large rule files, the merged ConfigMap can become very large. At that scale, Prometheus supports loading rules from a directory — switch to per-team files in a PVC mounted by Prometheus.

---

## 8. Decision: Grafana Multi-Tenancy Model

### What we built
Single Grafana instance with:
- **Folder per team** created by `onboard-team.sh`
- **Team service account** with Editor permission on their folder only
- **Sidecar for dashboard hot-loading** — teams deploy dashboard ConfigMaps in their namespace, the Grafana sidecar picks them up automatically
- **Platform dashboards** in a locked `Platform` folder (Consul cluster health, mesh topology)

### Folder-based isolation

```
Grafana:
  ├── Platform/           ← locked, platform team only
  │   ├── Consul Cluster Health
  │   └── Service Mesh Overview
  ├── Team: payments/     ← Editor access for payments-team only
  │   └── (their dashboards)
  └── Team: orders/       ← Editor access for orders-team only
      └── (their dashboards)
```

Teams cannot see or edit other teams' folders. The platform team can see everything.

### Dashboard self-service via ConfigMap

Teams create a ConfigMap in their namespace with their Grafana dashboard JSON:
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: payments-dashboard
  namespace: payments-team
  labels:
    grafana_dashboard: "1"          # triggers Grafana sidecar
  annotations:
    grafana_folder: "Team: payments"  # lands in their folder
data:
  payments.json: |
    { ... Grafana dashboard JSON ... }
```

The Grafana sidecar (watches all namespaces) picks it up and hot-loads it within seconds. No Grafana restart. No platform ticket.

### Tradeoff: single Grafana instance

All teams share one Grafana. A misconfigured dashboard or a heavy query can affect other teams. Mitigations:
- Set query timeout in Grafana: `dataproxy.timeout = 30`
- Set Prometheus query limits: `query_timeout: 2m`
- For strict isolation, a Grafana instance per team is possible but operationally expensive

### Why not Grafana Operator?

Same constraint as Prometheus — no operators. Grafana's native provisioning (datasources via ConfigMap, dashboards via sidecar) achieves equivalent self-service without any CRDs.

---

## 9. Decision: Log Aggregation with Loki

### What we chose
Grafana Loki for log aggregation, with Promtail as the agent on each cluster. dc2 Promtail ships logs to dc1 Loki — single pane of glass for cross-cluster logs.

### Why Loki over alternatives

| Option | Pros | Cons |
|--------|------|------|
| **Loki** | Integrates with Grafana, label-based indexing, cheap S3 storage | Less powerful query language than Elasticsearch |
| Elasticsearch + Kibana | Powerful full-text search | Expensive, separate UI from Grafana |
| CloudWatch Logs | No infrastructure to manage | Vendor lock-in, expensive at scale, no Grafana integration |
| Fluentd + Splunk | Enterprise-grade | Very expensive, separate from Grafana |

Loki's label model mirrors Prometheus — teams query logs with the same `{namespace="team-a", app="payments"}` selectors they use for metrics. Correlation between metrics and logs in Grafana becomes natural.

### Cross-cluster log flow

```
dc2 Promtail → dc1 Loki NLB (port 3100) → dc1 Loki → dc1 Grafana
dc1 Promtail → dc1 Loki (in-cluster)
```

Both datacenters' logs are queryable in a single Grafana datasource. When debugging a peering issue, you can correlate logs from dc1 and dc2 in the same Grafana panel.

### Label strategy for multi-tenancy

Promtail is configured to add these labels to every log line:
- `namespace` — Kubernetes namespace (maps to team)
- `pod`, `container` — for pod-level filtering
- `datacenter` — `dc1` or `dc2` (added via Promtail pipeline stage)

Teams query their logs with `{namespace="payments-team"}`. They cannot accidentally query another team's logs (though there is no hard ACL enforcement in Loki OSS — that requires Loki Enterprise with multi-tenancy).

### Tradeoff: no full-text indexing

Loki does not index log content — only labels. Full-text search (`grep`-style) works but requires scanning all log chunks matching the label selector. For high-volume logs, queries can be slow. Loki is appropriate when teams know what they're looking for via labels. If the customer needs full-text search across all logs, Elasticsearch is the right tool.

---

## 10. Decision: Multi-Cluster Observability

### Current state
- dc1: Prometheus + Grafana + Loki (full stack)
- dc2: Prometheus only, with `remote_write` to dc1 Prometheus

### Why remote_write instead of a separate Grafana on dc2

A second Grafana on dc2 requires:
- Two separate datasources to manage
- Dashboards duplicated across both Grafanas
- No cross-cluster queries (can't compare dc1 and dc2 on one panel)

With `remote_write`, all metrics flow into dc1 Prometheus. A single Grafana dashboard can show dc1 and dc2 metrics side by side with a `datacenter` label filter. This is essential for the geo-failover demo: you can watch traffic shift from dc2 to dc1 in a single panel.

### Tradeoff: dc2 loses local observability during a partition

If dc2 cannot reach dc1 (network partition or NLB failure), dc2 `remote_write` will buffer metrics locally and replay when connectivity returns. However, during the partition, dc2 metrics are not visible in Grafana. For a demo environment this is acceptable.

For production, the recommendation is **Thanos or Grafana Mimir**:

```
dc1 Prometheus + Thanos Sidecar ──┐
                                   ├──► Thanos Query ──► Grafana
dc2 Prometheus + Thanos Sidecar ──┘
```

Each cluster retains full local observability. Thanos provides a global query layer that merges results. Cross-cluster dashboards work even during a partition (showing each cluster's local data independently).

### Adding a datacenter label to all metrics

All dc2 metrics scraped by dc2 Prometheus need a `datacenter=dc2` label so they're distinguishable from dc1 metrics after `remote_write`. Add to dc2 `prometheus-values.yaml`:

```yaml
server:
  global:
    external_labels:
      datacenter: dc2
      cluster: consul-dc2
```

dc1 Prometheus should similarly have `datacenter: dc1`. This label is attached to all metrics and preserved through `remote_write`.

---

## 11. What We Would Change at Larger Scale

| Current (demo) | At scale (10+ teams, 500+ services) |
|----------------|-------------------------------------|
| Standalone Prometheus | Thanos or Grafana Mimir for horizontal scaling |
| Annotation-based discovery | Prometheus Operator with `ServiceMonitor` CRDs per namespace |
| CronJob rule merger | Prometheus Operator `PrometheusRule` CRDs per namespace |
| Single Grafana | Grafana with LDAP/SAML integration + Grafana Enterprise for strict folder ACLs |
| Single Loki | Loki with multi-tenancy enabled (X-Scope-OrgID header per team) |
| remote_write dc2→dc1 | Thanos with S3 object storage for long-term retention |
| Manual team onboarding script | GitOps (Argo CD Application per team) |

---

## 12. Team Onboarding Checklist

When a new application team joins the platform:

### Platform team does once
```bash
export GRAFANA_URL=http://<grafana-nlb>
export GRAFANA_ADMIN_PASSWORD=<password>
./monitoring/scripts/onboard-team.sh <team-name>
```

This creates:
- [ ] Kubernetes namespace `<team-name>` with `team=<team-name>` label
- [ ] RBAC — team can deploy workloads in their namespace
- [ ] Grafana folder `Team: <team-name>` with Editor access
- [ ] Example alert rules ConfigMap in their namespace

### Application team does per service
```yaml
# Add to pod spec — that's it
metadata:
  annotations:
    # Metrics auto-discovery
    prometheus.io/scrape: "true"
    prometheus.io/port: "8080"         # your app's metrics port

    # Consul service mesh
    consul.hashicorp.com/connect-inject: "true"
    # Envoy + app metrics merged; platform scrapes pod-ip:20200/metrics
```

### Application team alert rules
```bash
cp monitoring/templates/team-alert-rules.yaml my-rules.yaml
# Edit with your PromQL expressions
kubectl apply -f my-rules.yaml -n <team-namespace>
# Rules live in Prometheus within 60 seconds
```

### Application team dashboards
```bash
# Create a ConfigMap with your Grafana dashboard JSON
# Label it grafana_dashboard=1 and annotate with your folder name
# Deploy to your namespace — Grafana sidecar picks it up automatically
```

---

## 13. Metric Reference by Source

### Consul ACL token for Prometheus

Prometheus needs a Consul ACL token to scrape `/v1/agent/metrics`. Use a **scoped token**, not the bootstrap token. The bootstrap token has superuser access and must never be distributed to other services.

The required policy grants read-only access to agent and node information:
```hcl
agent_prefix "" { policy = "read" }
node_prefix  "" { policy = "read" }
```

The token is stored in a Kubernetes Secret (`consul-metrics-token`) in the `monitoring` namespace and mounted into the Prometheus pod at `/var/run/secrets/consul/token`. It is never embedded in the Helm values file or committed to git.

---

### Consul servers (scraped by platform, HTTPS port 8501)

Prometheus scrapes **`https://<pod>:8501/v1/agent/metrics?format=prometheus`** with a bearer token, **`tls_config.insecure_skip_verify`** (pod IP vs cert SAN), and **`scrape_protocols: [PrometheusText1.0.0]`** so OpenMetrics negotiation does not hit promhttp **400** on this path. With `httpsOnly: false`, HTTP **:8500** is still available for ad hoc **`curl`** checks ([HashiCorp article](https://support.hashicorp.com/hc/en-us/articles/15106289764627-How-to-enable-Prometheus-in-Consul-on-Kubernetes)). To avoid duplicate broken scrapes, the chart default **`kubernetes-pods`** job is disabled and **`component=server`** is dropped from **`annotated-pods`** (those paths used **`http://…:8501`** without honoring `prometheus.io/scheme`).

| Metric | Description | Alert threshold |
|--------|-------------|-----------------|
| `consul_raft_leader` | Raft leader present (1=yes, 0=no) | == 0 for >30s |
| `consul_raft_peers` | Number of Raft peers | < 3 |
| `consul_catalog_service_node_healthy` | Service health by node | == 0 |
| `consul_runtime_alloc_bytes` | Consul server memory | > 1GB |
| `consul_agent_tls_cert_expiry` | TLS cert expiry (seconds) | < 7 days |

### Consul mesh gateways (scraped by platform, port 20200)

| Metric | Description |
|--------|-------------|
| `envoy_cluster_upstream_cx_active` | Active upstream connections through gateway |
| `envoy_listener_downstream_cx_total` | Total inbound connections to gateway |
| `envoy_cluster_upstream_rq_total` | Requests proxied through gateway |

### Envoy sidecars — per service (scraped by platform via port 20200)

**Scrape shows `404` on 20100:** **`/metrics` on 20100 is wrong** — use **`http://pod-ip:20200/metrics`** (or locally **`127.0.0.1:20100/stats/prometheus`**). **Scrape shows `EOF`:** stale target after restart, merging off, pod not ready, or **NetworkPolicy** blocking **20200** from `monitoring`. Confirm `connectInject.metrics.defaultEnableMerging: true` in Consul Helm values (see [Transparent proxy and mTLS](#6-decision-transparent-proxy-and-mtls-compatibility)).

**`ParseFloat` / `parsing "to"` / scrape “down”:** Usually a **`failed to scrape metrics at url "…"`** line embedded in the merged **20200** body because dataplane could not scrape the app (see **Troubleshooting** in [Metrics merging (20100 local, 20200 scrape)](#5-decision-metrics-merging-20100-local-20200-scrape)). The values file sets **`scrape_protocols: [PrometheusText1.0.0]`** for Envoy jobs; if the error remains, fix the **app metrics URL** inside the pod, not Prometheus.

| Metric | Description | PromQL example |
|--------|-------------|----------------|
| Request rate | Requests per second | `rate(envoy_cluster_upstream_rq_total{app="frontend"}[5m])` |
| Error rate | 5xx responses | `rate(envoy_cluster_upstream_rq_xx{envoy_response_code_class="5"}[5m])` |
| P99 latency | 99th percentile response time | `histogram_quantile(0.99, rate(envoy_cluster_upstream_rq_time_bucket[5m]))` |
| Active connections | Current open connections | `envoy_cluster_upstream_cx_active` |

### Application metrics (team-owned, auto-discovered via annotation)

Teams own the definition of their application metrics. The platform guarantees:
- Scraped every 15 seconds
- Labelled with `namespace`, `pod`, `app`, `team`
- Available in Grafana via the `Prometheus-dc1` datasource
- Filterable per team using `{team="<team-name>"}`

---

*Last updated: April 2026*
*Maintained by: Platform Engineering*
*Questions: open an issue in this repository*
