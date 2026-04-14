# Multi-cluster Consul mesh: architecture and design notes

This repository is intentionally **layered** so you can bring up infrastructure, then Kubernetes, then Consul, then observability, and finally cross-platform workloads—without hiding the learning steps behind one giant automation script.

## Reference material

- [Server metrics and logs](https://developer.hashicorp.com/consul/tutorials/observe-your-network/server-metrics-and-logs)
- [Kubernetes get started: observability](https://developer.hashicorp.com/consul/tutorials/get-started-kubernetes/kubernetes-gs-observability#deploy-observability-suite)
- [Audit logging](https://developer.hashicorp.com/consul/docs/monitor/log/audit)
- [EKS Helm example (learn-consul-get-started-kubernetes)](https://github.com/hashicorp-education/learn-consul-get-started-kubernetes/tree/main/self-managed/eks/helm)

## Topology (target)

| Layer | What | Purpose |
|-------|------|--------|
| AWS (Terraform) | VPC, subnets, EC2 for Kind hosts and/or VM Consul nodes, optional NLBs, Route53 | Stable networking and DNS integration points |
| Kubernetes ×2 | `kind` (or OpenShift) clusters, one logical datacenter each; often **one VM (or host) per cluster** | Consul servers + Connect + **mesh gateway pods** + API Gateway + workloads (all in-cluster) |
| VMs (EC2) | **One** Consul server + **mesh gateway on that VM**; HashiCups **one microservice per VM** (see `terraform/vm-datacenter`); each service runs a **Connect Envoy sidecar** (`connect-envoy@`) for **mTLS** | Peering target **dc-vm** from Kubernetes; each service has its own IP |
| Observability | Prometheus, Grafana, Loki, Promtail, node_exporter | App-team vs platform-team views |

**Version pins (your requirement):** use Enterprise UBI images and matching `consul-k8s` / `consul-dataplane` tags. Set `global.enterpriseLicense` in Helm and create the license secret before install.

## Cluster peering and mesh gateways

**Mesh gateways do not need their own VM.** The Helm chart runs them as **Deployments in the same Kubernetes cluster** as Consul servers and your services. Peering traffic enters/exits each cluster through that cluster’s mesh gateway pods (for example via **NodePort `31443`** on the kind/VM node’s IP).

1. **Enable peering in Helm:** `global.peering.enabled: true` on every cluster that participates in peering.
2. **Enable mesh gateways:** required for peering traffic across non-flat networks. Your choice of **NodePort `31443`** is valid when every peer can reach **node IP:31443** (security groups, host firewalls, and any cloud LB in front must allow it).
3. **WAN address registration:** with `meshGateway.service.type: NodePort` and `meshGateway.service.nodePort: 31443`, set `meshGateway.wanAddress.source: Service` so Consul registers the correct WAN port (see chart defaults and comments in `kubernetes/helm/consul/values-*.yaml`).
4. **Peering flow (manual learning path):** create `PeeringAcceptor` in the “server” cluster, copy the generated secret into the “client” cluster namespace, then apply `PeeringDialer`. Export services with `ExportedServices` CRDs (or equivalent config on VMs). This is easier to understand than automating it away.

**API Gateway:** keep `connectInject.apiGateway.managedGatewayClass.serviceType: LoadBalancer` where your environment provisions external LBs (EKS, ROSA). For bare metal / kind, switch to `NodePort` or use port-forward for demos.

## DNS: `geo.consul`, per-cluster names, and prepared queries

### Where the mental model needs adjustment

DNS **does not** give you “try nameserver 1, then 2, then 3” the way a client-side failover list might. Resolvers choose among NS records without a guaranteed order, and caching can pin clients to a failed target.

**Recommended patterns:**

1. **Per-cluster stable names (your `<cluster>.consul` idea, adapted):** use **Route53 records** (private zone) pointing at **one well-known endpoint per Consul datacenter**—for example an **NLB** in front of Consul’s HTTPS/UI, or a **mesh/API gateway**—not necessarily the raw Consul DNS port unless you run a small DNS forwarder with health checks.
2. **Geo / failover for service discovery:** implement failover **inside Consul** with **prepared queries** (`Failover`, `NearestN`, etc.) and execute them via:
   - Consul HTTP API: `/v1/query/<name>/execute`, or
   - Consul DNS: `myquery.query.consul` (when queries reach a Consul agent that knows the query).
3. **If you still want Route53 in the story:** use **Route53 health checks + failover (or weighted) routing** on **A/AAAA alias targets**, not chained NS delegation, to steer traffic to a **single** healthy entry point. Optionally that entry point is a **DNS proxy** that forwards to the current primary Consul cluster (advanced; usually skipped for a first demo).

**For prepared-query demos:** treat **`geo.consul` as a logical name** in docs and scripts (e.g. “clients use prepared query `geo-hashicups`”), while **per-cluster UI/API** use real DNS names you create in Route53 (e.g. `dc1.consul.example.com` → DC1 NLB).

### OpenShift vs kind

- **OpenShift (ROSA / self-managed):** add SCC-compatible settings, often `global.openshift.enabled: true` in the Consul chart, and ensure `LoadBalancer` services map to your platform (MetalLB, cloud LB, etc.).
- **kind:** there is no AWS `gp2` `StorageClass`; use `standard` or install a provisioner (see `kubernetes/manifests/storageclass-kind.yaml`). `LoadBalancer` usually stays `<pending>` unless you use **MetalLB** or **cloud-provider-kind**—plan UI access via `kubectl port-forward` or NodePort for local labs.

## Demo goals (mapping)

| Goal | How this repo supports it |
|------|---------------------------|
| App team monitoring | Sidecar merged metrics, service dashboards, Loki logs from Promtail |
| Ops monitoring | Consul server metrics, Envoy gateway metrics, audit logs (optional) |
| Prepared queries | Example query + execution path documented; create via CLI/API (no first-class PreparedQuery CRD) |
| Failover K8s ↔ VMs | Peering + exported services + prepared query failover across DCs; mesh gateways on both sides |

## Layer order (suggested)

1. `terraform/aws` — network and instances (optional: NLB, Route53 zone).
2. `kubernetes/kind` — bring up two clusters (or use OpenShift).
3. `kubernetes/helm/consul` — install servers, connect inject, mesh gateway, API gateway.
4. `kubernetes/manifests/peering` — peering CRs and exports (manual apply).
5. `terraform/vm-datacenter` + `vm/` — single Consul server VM, Consul clients + Docker HashiCups per service VM, mesh gateway on server (see [vm/README.md](../vm/README.md)).
6. `monitoring/` — Prometheus, Grafana, Loki; scrape configs for Consul and Envoy.
7. `scripts/` — prepared query registration, smoke tests.

This matches the official tutorials: metrics and logs on servers and sidecars first, then expand to centralized Grafana/Loki.
