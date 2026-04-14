# Multi-cluster Consul service mesh and observability (AWS / Kubernetes / VMs)

Layered demo material for **Consul Enterprise** on **two Kubernetes clusters** (for example `kind` on EC2 or OpenShift) plus a **VM Consul datacenter**, with **cluster peering**, **mesh gateways** (NodePort `31443`), **metrics**, and **prepared queries**. Automation is intentionally thin so the steps stay visible for learning.

## Documentation in this repo

| Document | Purpose |
|----------|---------|
| [docs/AI-SESSION-BRIEF.md](docs/AI-SESSION-BRIEF.md) | **Start here for new AI chats:** goals, topology, operator settings via gitignored tfvars / `TF_VAR_*` |
| [docs/SECRETS-AND-LOCAL-CONFIG.md](docs/SECRETS-AND-LOCAL-CONFIG.md) | Gitignored files, `TF_VAR_*`, license path variable, leak checks |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Topology, DNS vs prepared queries, mesh gateway notes, OpenShift vs kind |
| [docs/PREPARED-QUERIES.md](docs/PREPARED-QUERIES.md) | How to register and execute prepared queries |
| [monitoring/README.md](monitoring/README.md) | Prometheus / Grafana / Loki / Promtail install order |
| [kubernetes/helm/consul/README.md](kubernetes/helm/consul/README.md) | Helm-specific notes (license, image pull, Prometheus URL) |
| [kubernetes/manifests/peering/README.md](kubernetes/manifests/peering/README.md) | Peering secret export/import flow |
| [kubernetes/manifests/api-gateway/README.md](kubernetes/manifests/api-gateway/README.md) | Public HTTP routes (Gateway API) for HashiCups / Consul UI |
| [terraform/aws/README.md](terraform/aws/README.md) | VPC, kind nodes, bastion variables and outputs |
| [kubernetes/kind/README.md](kubernetes/kind/README.md) | Single-node kind per VM; mesh gateway on-cluster |
| [vm/README.md](vm/README.md) | VM Consul server + HashiCups (one service per VM), Terraform, monitoring |
| [terraform/vm-datacenter/README.md](terraform/vm-datacenter/README.md) | EC2 layout for VM datacenter |
| [docs/DNS-ROUTE53-CONSUL.md](docs/DNS-ROUTE53-CONSUL.md) | Route53 zone vs `.consul`, split-horizon, prepared-query URLs, optional dnsmasq :53 bridge |
| [docs/SECURITY.md](docs/SECURITY.md) | Mesh, mTLS, Consul TLS, ACLs: K8s (Helm) vs VM (dc-vm) |
| [docs/TARGET-ARCHITECTURE.md](docs/TARGET-ARCHITECTURE.md) | How this repo compares to the target diagram (4 VMs vs 6, API GW on VMs, etc.) |
| [docs/ACCESS.md](docs/ACCESS.md) | Bastion SSH, API Gateway public access, prepared queries from your laptop |

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

## Installation procedure (recommended order)

### 1. AWS networking and hosts (optional)

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

### 2. Kubernetes clusters

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

### 3. Consul Enterprise license secret (each cluster)

Do **not** commit the license file. From the repo root (after `kubectl create namespace consul`):

```bash
export CONSUL_LICENSE_FILE=/absolute/path/to/license.hclic
./scripts/k8s-consul-license-secret.sh
```

Or use `kubectl create secret generic ... --from-file=key=...` as in [kubernetes/helm/consul/README.md](kubernetes/helm/consul/README.md). For Terraform, optional **`consul_enterprise_license_path`** in **gitignored** `terraform/vm-datacenter/terraform.tfvars` validates the file at plan time only; you still **copy** the license to the VM Consul server yourself.

If images pull from a private registry, create a pull secret and list it under `global.imagePullSecrets` in [kubernetes/helm/consul/values-dc1.yaml](kubernetes/helm/consul/values-dc1.yaml) and [values-dc2.yaml](kubernetes/helm/consul/values-dc2.yaml).

### 4. Install Consul with Helm (each cluster)

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

### 5. Cluster peering (manual)

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

### 6. Workloads (HashiCups)

Deploy HashiCups with Connect injection enabled. Pointers: [kubernetes/workloads/hashicups/README.md](kubernetes/workloads/hashicups/README.md) and the [Kubernetes observability tutorial](https://developer.hashicorp.com/consul/tutorials/get-started-kubernetes/kubernetes-gs-observability#deploy-observability-suite).

### 7. VM datacenter (optional third site)

Use **[terraform/vm-datacenter](terraform/vm-datacenter)** for EC2: **one** Consul server VM and **one VM per HashiCups service** (each with its own private IP). Follow **[vm/README.md](vm/README.md)** for Consul (`vm/consul/*`), HashiCups Docker scripts (`vm/hashicups/scripts/`), mesh gateway on the server VM, and **[vm/monitoring/README.md](vm/monitoring/README.md)** for node_exporter and Promtail. Peer **dc-vm** to Kubernetes using your Consul version’s **VM ↔ K8s peering** guidance and the mesh gateway on **TCP 8443**.

### 8. Observability (Prometheus, Grafana, Loki, Promtail)

Follow **[monitoring/README.md](monitoring/README.md)** for Helm values and apply order:

1. **kube-prometheus-stack** on DC1 (Prometheus + Grafana) and optionally on DC2 (Prometheus only).
2. **ACL token secret** + **PodMonitor** for Consul server metrics.
3. **Loki** (single binary) on DC1.
4. **Promtail** on each cluster (and on VMs: [vm/monitoring/README.md](vm/monitoring/README.md), legacy copy in [monitoring/vm/README.md](monitoring/vm/README.md)).

Consul Helm values already set `ui.metrics.baseURL` for release name **`kps`**. If you change the Helm release name, run `kubectl get svc -n monitoring` and update [kubernetes/helm/consul/values-dc1.yaml](kubernetes/helm/consul/values-dc1.yaml) / `values-dc2.yaml`, then `helm upgrade consul`.

### 9. Prepared queries

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
