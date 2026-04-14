# Brief for future sessions (copy into your prompt)

Paste the **“Quick prompt”** block below at the start of a new chat when working on this repository, or keep this file open as the source of truth.

---

## Quick prompt (copy-paste)

You are helping with **Monitoring_AWS**: a **learning-oriented**, **layered** demo (not a single black-box automation) for **Consul Enterprise** across **two Kubernetes datacenters** (`dc1` / `dc2`, e.g. **kind** on EC2 or OpenShift) plus a **VM datacenter** **`dc-vm`**, with **cluster peering**, **mesh gateways** (K8s **NodePort 31443**, VM mesh gateway **TCP 8443** on the Consul server VM), **observability** (Prometheus, Grafana, Loki, Promtail), **prepared queries**, and optional **Consul API Gateway on Kubernetes only** (Helm `connectInject.apiGateway`).

**Hard constraints**

- **Thin automation**: prefer Terraform + Helm + explicit manifests/docs over opaque scripts.
- **Enterprise**: UBI image pins in `kubernetes/helm/consul/values-dc*.yaml` (e.g. consul-enterprise, consul-k8s-control-plane **1.8.3**, consul-dataplane **1.8.3**); license secret required.
- **Topology**: mesh gateway runs **as pods in each K8s cluster**, not a dedicated EC2 for that. VM side: **one** Consul server EC2 with **mesh gateway on the same host**; **one EC2 per HashiCups microservice** (not one VM for all services).
- **VM HashiCups** uses **Consul Connect** sidecars (`connect-envoy@`), **`host.docker.internal` + local_bind** for bridge Docker (not K8s-style transparent proxy on VMs).
- **Consul API Gateway on VMs is out of scope** (explicitly dropped); K8s API GW + HTTPRoute is the ingress path for clusters only.
- **Security matrix**: K8s Helm enables **connectInject**, **global.tls**, **global.acls.manageSystemACLs**, **transparentProxy** (explicit in values). VM base `server.hcl` / `client.hcl` do **not** enable ACL/TLS by default; optional parity via `vm/consul/security/*.example` and `docs/SECURITY.md`.

**Operator-specific values (never commit real values; use gitignored `terraform.tfvars` or `export TF_VAR_...`)**

- **`ssh_key_name`**, **`route53_public_zone_name`**, **`bastion_ssh_cidr_blocks`**: see `terraform/*/terraform.tfvars.example` and **`.env.example`**.
- **`consul_enterprise_license_path`** (`terraform/vm-datacenter`): optional local path to `.hclic`; Terraform **validates** the file exists at plan time but **does not** upload it (no license content in state). Use **`scripts/k8s-consul-license-secret.sh`** for Kubernetes secrets.
- **Split-horizon DNS**: `terraform/aws` creates a **private** hosted zone with the **same apex** as the public zone for the demo VPC; **in-VPC** queries return **private** A records for `dc1`, `dc2`, …; **internet** still uses **public** A records.
- `terraform/vm-datacenter` adds **`dc-vm`** and **`<hashicups-role>`** records (private always; public if `enable_public_ip`). Apply **`terraform/aws` before `terraform/vm-datacenter`** so the private zone exists.
- **`enable_consul_dns_bridge`** (default **true**): Consul **server** user_data installs **dnsmasq** on **:53** forwarding **`*.consul`** to **127.0.0.1:8600**; SG allows **53** from VPC CIDR.
- **Route53 names ≠ Consul domains**: `*.<your-public-zone>` are **infrastructure** hostnames; **`*.service.consul`** / **`*.query.consul`** remain **Consul DNS**. See `docs/DNS-ROUTE53-CONSUL.md`. Prepared-query **HTTP** example: `http://dc-vm.<your-zone>:8500/v1/query/<name>/execute?...`.
- **Bastion**: optional in `terraform/aws`; SSH is **VPC-scoped** to nodes; see `docs/ACCESS.md`. See **`docs/SECRETS-AND-LOCAL-CONFIG.md`** for gitignore and leak checks.

**Repo map**

- `terraform/aws` — VPC, kind nodes, bastion, split-horizon Route53 for `dcN`.
- `terraform/vm-datacenter` — Consul server + HashiCups VMs, Route53 records, dnsmasq bridge.
- `kubernetes/kind/`, `kubernetes/helm/consul/`, `kubernetes/manifests/` — kind, Helm values, peering, storageclass notes; **`.tmpchart/consul`** is reference-only (install from HashiCorp Helm repo).
- `vm/` — Consul systemd configs, HashiCups scripts, mesh-gateway unit, monitoring stubs.
- `monitoring/` — kube-prometheus-stack, Loki, Promtail, PodMonitor for Consul.
- `docs/` — architecture, security, DNS, prepared queries, target diagram vs repo, access.

**When changing behavior**

- Match existing naming and comment style; avoid drive-by refactors and unsolicited new markdown except when the user asks.
- If touching Terraform Route53, preserve **split-horizon** semantics and document apply order.
- Do not reintroduce **VM Consul API Gateway** unless the user explicitly changes scope.

---

## Optional shorter prompt

> Consul Enterprise multi-DC demo repo: 2× K8s (`kind`/Helm) + VM `dc-vm`, peering, mesh GW (31443/8443), observability, prepared queries. Set **key pair** and **Route53 zone** via gitignored tfvars / `TF_VAR_*` (see `.env.example`). Split-horizon + dnsmasq :53→:8600 on Consul server. VM HashiCups uses Connect sidecars + `host.docker.internal`. No API GW on VMs. K8s has TLS/ACL/mesh via Helm; VM TLS/ACL optional. Thin automation; read `docs/AI-SESSION-BRIEF.md`, `docs/SECRETS-AND-LOCAL-CONFIG.md`, and `README.md`.
