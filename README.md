# Multi-cluster Consul service mesh and observability (AWS / Kubernetes / VMs)

Layered demo material for **Consul Enterprise** on **two Kubernetes clusters** (for example `kind` on EC2 or OpenShift) plus a **VM Consul datacenter**, with **cluster peering**, **mesh gateways** (NodePort `31443`), **metrics**, and **prepared queries**. Automation is intentionally thin so the steps stay visible for learning.

## How to use this README

1. **Do the install in order:** follow [End-to-end install (step-by-step)](#end-to-end-install-step-by-step). Each step lists **Skip if**, **Read**, and **Run**.
2. **Look up details** in the [Documentation index](#documentation-index-reference) when you need depth (security, DNS, architecture).
3. **Local secrets:** [docs/SECRETS-AND-LOCAL-CONFIG.md](docs/SECRETS-AND-LOCAL-CONFIG.md) and [`.env.example`](.env.example) — copy to gitignored `terraform.tfvars` / `.env`.

**Typical paths**

| Path | Steps |
|------|--------|
| **Full AWS lab** (VPC, kind on EC2, optional VM dc, monitoring) | [0](#step-0--local-config-first) through [9](#step-9--prepared-queries) in order |
| **Laptop only** (two kind clusters already local) | [0](#step-0--local-config-first) → skip [1](#step-1--aws-vpc-and-hosts-optional), [7](#step-7--vm-datacenter-optional), [8](#step-8--monitoring-on-vms) → run [2](#step-2--kubernetes-clusters) … [6](#step-6--observability-kubernetes), then [9](#step-9--prepared-queries) if needed |

---

## Documentation index (reference)

| Document | When to read it |
|----------|-----------------|
| [docs/AI-SESSION-BRIEF.md](docs/AI-SESSION-BRIEF.md) | Whole-project context for you or an AI assistant |
| [docs/SECRETS-AND-LOCAL-CONFIG.md](docs/SECRETS-AND-LOCAL-CONFIG.md) | What must stay out of git; `TF_VAR_*`; license handling |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Topology, mesh gateways, DNS vs prepared queries |
| [docs/SECURITY.md](docs/SECURITY.md) | Mesh, TLS, ACLs on Kubernetes vs VM defaults |
| [docs/DNS-ROUTE53-CONSUL.md](docs/DNS-ROUTE53-CONSUL.md) | Route53 hostnames vs Consul `.consul`; split horizon |
| [docs/ACCESS.md](docs/ACCESS.md) | Bastion, SSH jump, port-forward, optional API GW pattern |
| [docs/PREPARED-QUERIES.md](docs/PREPARED-QUERIES.md) | Register / execute prepared queries |
| [docs/TARGET-ARCHITECTURE.md](docs/TARGET-ARCHITECTURE.md) | How this repo differs from a reference diagram |
| [terraform/aws/README.md](terraform/aws/README.md) | AWS Terraform variables, outputs, bastion |
| [terraform/vm-datacenter/README.md](terraform/vm-datacenter/README.md) | VM EC2 Terraform (after `terraform/aws` if using Route53) |
| [kubernetes/kind/README.md](kubernetes/kind/README.md) | kind configs (`dc1` / `dc2`) |
| [kubernetes/helm/consul/README.md](kubernetes/helm/consul/README.md) | Helm install, license secret, chart version pin |
| [kubernetes/manifests/peering/README.md](kubernetes/manifests/peering/README.md) | Peering acceptor / dialer / exported services |
| [kubernetes/manifests/api-gateway/README.md](kubernetes/manifests/api-gateway/README.md) | Optional HTTPRoutes on **Kubernetes only** |
| [kubernetes/workloads/hashicups/README.md](kubernetes/workloads/hashicups/README.md) | HashiCups on Kubernetes pointers |
| [vm/README.md](vm/README.md) | Consul + HashiCups on VMs after Terraform |
| [monitoring/README.md](monitoring/README.md) | Prometheus, Grafana, Loki, Promtail on K8s |
| [vm/monitoring/README.md](vm/monitoring/README.md) | Metrics/logs on Consul / HashiCups VMs |

## Prerequisites

- **Terraform** ≥ 1.5 (optional AWS layer)
- **AWS account** and credentials (if using `terraform/aws`)
- **EC2 key pair** (same key name used for bastion and kind nodes when `enable_bastion` is true)
- **Docker**, **kind**, **kubectl**, **Helm** 3.x
- **Consul Enterprise** license file and registry access for UBI images (`hashicorp/consul-enterprise`, `consul-k8s-control-plane`, `consul-dataplane`)
- **Consul Helm chart** version compatible with **consul-k8s-control-plane 1.8.3** (pin the chart when you install)

Official references:

- [Server metrics and logs](https://developer.hashicorp.com/consul/tutorials/observe-your-network/server-metrics-and-logs)
- [Kubernetes observability tutorial](https://developer.hashicorp.com/consul/tutorials/get-started-kubernetes/kubernetes-gs-observability#deploy-observability-suite)
- [Cluster peering on Kubernetes](https://developer.hashicorp.com/consul/docs/k8s/connect/cluster-peering)
- [EKS Helm example](https://github.com/hashicorp-education/learn-consul-get-started-kubernetes/tree/main/self-managed/eks/helm)

---

## End-to-end install (step-by-step)

Each step below lists **Skip if**, **Read**, and **Run**. Subsections that follow are the detailed commands.

### Step 0 — Local config (first)

- **Skip if:** License and tfvars are already set locally and nothing sensitive is committed.
- **Read:** [docs/SECRETS-AND-LOCAL-CONFIG.md](docs/SECRETS-AND-LOCAL-CONFIG.md)
- **Run:** [`.env.example`](.env.example) → `.env`; `terraform/aws/terraform.tfvars.example` → gitignored `terraform.tfvars`; export `CONSUL_LICENSE_*` / `TF_VAR_*` as needed.

### Step 1 — AWS VPC and hosts (optional)

- **Skip if:** You are not using `terraform/aws` (e.g. local kind only).
- **Read:** [terraform/aws/README.md](terraform/aws/README.md), [docs/ACCESS.md](docs/ACCESS.md)
- **Run:** [AWS networking and hosts (detailed commands)](#aws-networking-and-hosts-optional) below.

### Step 2 — Kubernetes clusters

- **Skip if:** `dc1` and `dc2` contexts already exist as in [kubernetes/kind/README.md](kubernetes/kind/README.md).
- **Read:** [kubernetes/kind/README.md](kubernetes/kind/README.md)
- **Run:** [Kubernetes clusters (detailed commands)](#kubernetes-clusters) below.

### Step 3 — Consul on Kubernetes (license + Helm)

- **Read:** [kubernetes/helm/consul/README.md](kubernetes/helm/consul/README.md)
- **Run:** [License secret](#consul-enterprise-license-secret-each-cluster) and [Helm install](#install-consul-with-helm-each-cluster) below.

### Step 4 — Cluster peering

- **Read:** [kubernetes/manifests/peering/README.md](kubernetes/manifests/peering/README.md)
- **Run:** [Cluster peering (detailed commands)](#cluster-peering-manual) below.

### Step 5 — Workloads and optional API Gateway

- **Skip if:** You only need an empty mesh (unusual for this demo).
- **Read:** [kubernetes/workloads/hashicups/README.md](kubernetes/workloads/hashicups/README.md); optional HTTP routes: [kubernetes/manifests/api-gateway/README.md](kubernetes/manifests/api-gateway/README.md) (**Kubernetes only**; VMs use Connect per [vm/README.md](vm/README.md)).
- **Run:** [Workloads (HashiCups)](#workloads-hashicups) below.

### Step 6 — Observability (Kubernetes)

- **Skip if:** You are not deploying Prometheus / Grafana / Loki on the kind clusters.
- **Read:** [monitoring/README.md](monitoring/README.md)
- **Run:** [Observability on Kubernetes](#observability-prometheus-grafana-loki-promtail) below.

### Step 7 — VM datacenter (optional)

- **Skip if:** You only need the two Kubernetes datacenters.
- **Read:** [terraform/vm-datacenter/README.md](terraform/vm-datacenter/README.md), [vm/README.md](vm/README.md), [docs/DNS-ROUTE53-CONSUL.md](docs/DNS-ROUTE53-CONSUL.md)
- **Run:** [VM datacenter](#vm-datacenter-optional-third-site) below.

### Step 8 — Monitoring on VMs

- **Skip if:** Step 7 skipped or you do not need metrics/logs on Consul / HashiCups VMs.
- **Read:** [vm/monitoring/README.md](vm/monitoring/README.md)
- **Run:** As part of VM bring-up in [vm/README.md](vm/README.md) and [vm/monitoring/README.md](vm/monitoring/README.md) (legacy copy: [monitoring/vm/README.md](monitoring/vm/README.md)).

### Step 9 — Prepared queries

- **Skip if:** You do not need geo / failover query demos.
- **Read:** [docs/PREPARED-QUERIES.md](docs/PREPARED-QUERIES.md), [docs/ACCESS.md](docs/ACCESS.md)
- **Run:** [Prepared queries (detailed commands)](#prepared-queries) below.

---

## Detailed commands (same order as Steps 1–9 above; Step 0 is config-only)

### AWS networking and hosts (optional)

From `terraform/aws` (see [terraform/aws/README.md](terraform/aws/README.md) and [terraform/aws/terraform.tfvars.example](terraform/aws/terraform.tfvars.example)):

```bash
cd terraform/aws
cp terraform.tfvars.example terraform.tfvars
# Set ssh_key_name, bastion_ssh_cidr_blocks (your Mac public IP /32), enable_bastion.
terraform init
terraform apply
```

Outputs include **`bastion_public_ip`**, **`node_private_ips`**, **`vpc_id`**, **`public_subnet_ids`**, and (when **`route53_public_zone_name`** is set) **`cluster_dns_names`** like **`dc1.<your-zone>`** / **`dc2.<your-zone>`**. Put real **`ssh_key_name`**, zone, and **`bastion_ssh_cidr_blocks`** in **gitignored** `terraform.tfvars` or **`export TF_VAR_...`** (see [`.env.example`](.env.example), [docs/SECRETS-AND-LOCAL-CONFIG.md](docs/SECRETS-AND-LOCAL-CONFIG.md)). SSH from your **Mac to the bastion**, then **jump to private IPs** of kind hosts or other instances ([docs/ACCESS.md](docs/ACCESS.md)). Set **`enable_bastion = false`** only if you use VPN/SSM and do not want a jump host.

Default **`node_count` is 2** so you can use **one EC2 instance per kind cluster** (install Docker + kind on each, run `dc1` on VM A and `dc2` on VM B). Add instances if you also run a **separate VM Consul** datacenter.

- **Mesh gateways** are **pods inside each kind cluster**, not extra VMs.
- Use additional instances for **bare-metal-style** Consul + HashiCups if you keep that part of the demo.

Open **TCP 31443** between sites that must reach mesh gateways (already allowed in the example security group for the VPC CIDR—adjust for your real topology).

### Kubernetes clusters

**Option A — kind (local or on EC2)**

The kind configs are **single-node** clusters (one control-plane node each): good for **one VM per datacenter**. Install Docker and kind on each VM, create only the cluster for that site (`dc1` on VM 1, `dc2` on VM 2), or run both on one laptop with two kind clusters for local testing.

```bash
kind create cluster --name dc1 --config kubernetes/kind/kind-dc1.yaml
kind create cluster --name dc2 --config kubernetes/kind/kind-dc2.yaml

# Kubeconfig contexts are usually kind-dc1 and kind-dc2
kubectl config use-context kind-dc1
```

On a **small VM**, consider lowering `server.replicas` in the Consul Helm values (for example `1` for a lab); three server pods plus mesh gateway and apps can be memory-heavy on one node.

**Option B — OpenShift / ROSA**

Provision two clusters (or two logical datacenters). Set `global.openshift.enabled: true` in Helm values and use your platform `StorageClass` instead of `standard`.

**Storage**

- **kind:** if server PVCs fail to bind, apply [kubernetes/manifests/storageclass-kind.yaml](kubernetes/manifests/storageclass-kind.yaml) and set `server.storageClass` in Helm to that name, or use the default `standard` if it already exists.
- **EKS:** set `server.storageClass` to `gp2` or `gp3` in the values files.

### Consul Enterprise license secret (each cluster)

Do **not** commit the license file. From the repo root (after `kubectl create namespace consul`):

```bash
export CONSUL_LICENSE_FILE=/absolute/path/to/license.hclic
./scripts/k8s-consul-license-secret.sh
```

Or use `kubectl create secret generic ... --from-file=key=...` as in [kubernetes/helm/consul/README.md](kubernetes/helm/consul/README.md). For Terraform, optional **`consul_enterprise_license_path`** in **gitignored** `terraform/vm-datacenter/terraform.tfvars` validates the file at plan time only; you still **copy** the license to the VM Consul server yourself.

If images pull from a private registry, create a pull secret and list it under `global.imagePullSecrets` in [kubernetes/helm/consul/values-dc1.yaml](kubernetes/helm/consul/values-dc1.yaml) and [values-dc2.yaml](kubernetes/helm/consul/values-dc2.yaml).

### Install Consul with Helm (each cluster)

```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update
```

**DC1:**

```bash
kubectl config use-context kind-dc1
helm upgrade --install consul hashicorp/consul -n consul \
  --version <CHART_VERSION_MATCHING_1.8.3> \
  -f kubernetes/helm/consul/values-dc1.yaml
```

**DC2:**

```bash
kubectl config use-context kind-dc2
helm upgrade --install consul hashicorp/consul -n consul \
  --version <CHART_VERSION_MATCHING_1.8.3> \
  -f kubernetes/helm/consul/values-dc2.yaml
```

Wait until Consul server pods and connect injector are ready. If the Consul UI `LoadBalancer` stays pending on kind, use port-forward:

```bash
kubectl port-forward -n consul svc/consul-ui 8501:443
```

### Cluster peering (manual)

Follow [kubernetes/manifests/peering/README.md](kubernetes/manifests/peering/README.md). Summary:

1. On **dc1**, apply `peering-acceptor-dc1.yaml`.
2. Export the generated secret `peering-token-dc2` from **dc1** and apply it on **dc2** in the `consul` namespace (edit `namespace` if needed; remove `resourceVersion`/`uid`).
3. On **dc2**, apply `peering-dialer-dc2.yaml`.
4. Apply `ExportedServices` (and the reverse direction as needed). Example: [exported-services-hashicups-dc1.yaml](kubernetes/manifests/peering/exported-services-hashicups-dc1.yaml).

If your installed CRDs differ from the examples, align with the live schema:

```bash
kubectl explain peeringacceptor.spec --api-version=consul.hashicorp.com/v1alpha1
kubectl explain peeringdialer.spec --api-version=consul.hashicorp.com/v1alpha1
```

### Workloads (HashiCups)

Deploy HashiCups with Connect injection enabled. Pointers: [kubernetes/workloads/hashicups/README.md](kubernetes/workloads/hashicups/README.md) and the [Kubernetes observability tutorial](https://developer.hashicorp.com/consul/tutorials/get-started-kubernetes/kubernetes-gs-observability#deploy-observability-suite).

### Observability (Prometheus, Grafana, Loki, Promtail)

Follow **[monitoring/README.md](monitoring/README.md)** for Helm values and apply order:

1. **kube-prometheus-stack** on DC1 (Prometheus + Grafana) and optionally on DC2 (Prometheus only).
2. **ACL token secret** + **PodMonitor** for Consul server metrics.
3. **Loki** (single binary) on DC1.
4. **Promtail** on each cluster (and on VMs: [vm/monitoring/README.md](vm/monitoring/README.md), legacy copy in [monitoring/vm/README.md](monitoring/vm/README.md)).

Consul Helm values already set `ui.metrics.baseURL` for release name **`kps`**. If you change the Helm release name, run `kubectl get svc -n monitoring` and update [kubernetes/helm/consul/values-dc1.yaml](kubernetes/helm/consul/values-dc1.yaml) / `values-dc2.yaml`, then `helm upgrade consul`.

### VM datacenter (optional third site)

Use **[terraform/vm-datacenter](terraform/vm-datacenter)** for EC2: **one** Consul server VM and **one VM per HashiCups service** (each with its own private IP). Follow **[vm/README.md](vm/README.md)** for Consul (`vm/consul/*`), HashiCups Docker scripts (`vm/hashicups/scripts/`), mesh gateway on the server VM, and **[vm/monitoring/README.md](vm/monitoring/README.md)** for node_exporter and Promtail. Peer **dc-vm** to Kubernetes using your Consul version’s **VM ↔ K8s peering** guidance and the mesh gateway on **TCP 8443**.

### Prepared queries

Edit and register [scripts/prepared-query-geo.json](scripts/prepared-query-geo.json) per [docs/PREPARED-QUERIES.md](docs/PREPARED-QUERIES.md). Datacenter and failover fields must match your real `datacenter` names and peering topology.

---

## Repository layout

```
.gitignore              # terraform.tfvars, .env, *.hclic, state, peering exports
.env.example            # TF_VAR_* and CONSUL_LICENSE_FILE (copy to gitignored .env)
terraform/aws/          # VPC, subnets, EC2, optional Route53 zone
terraform/vm-datacenter/  # Consul server + HashiCups (one EC2 per service)
vm/                       # Consul + HashiCups + VM monitoring install docs and configs
kubernetes/kind/        # kind cluster configs (dc1 / dc2)
kubernetes/helm/consul/ # Helm values (Enterprise UBI pins, mesh gw NodePort)
kubernetes/manifests/   # StorageClass helper, peering + exported-services examples
kubernetes/workloads/   # HashiCups pointers
monitoring/             # Prometheus, Grafana, Loki, Promtail (Helm values + PodMonitor)
scripts/                # K8s license secret helper, prepared query JSON
docs/                   # Architecture, DNS, secrets, security, queries
```

The `.tmpchart/consul/` directory is a vendored chart reference only; install from **HashiCorp’s Helm repo** for real deployments.

## Demo checklist

- **Application teams:** service metrics via merged sidecar metrics and app dashboards in Grafana.
- **Operations:** Consul server and gateway metrics; optional [audit logging](https://developer.hashicorp.com/consul/docs/monitor/log/audit).
- **Prepared queries:** register via API/CLI, execute via HTTP or Consul DNS path (see docs).
- **Failover:** stop pods or fail a DC and show prepared query or exported-service behavior across peers and mesh gateways.

---

## Uninstall / teardown

```bash
# Per cluster
helm uninstall consul -n consul
kubectl delete namespace consul

kind delete cluster --name dc1
kind delete cluster --name dc2

cd terraform/vm-datacenter && terraform destroy
cd terraform/aws && terraform destroy
```

---

## License

HashiCorp **Consul Enterprise** requires a valid license. Demo YAML in this repository is for education; adjust for your organization’s compliance and security standards before production use.
