# Multi-cluster Consul Service Mesh and Observability (EKS)

**Consul Enterprise 1.21** across two **EKS** datacenters (`dc1`, `dc2`) with cluster peering, mesh gateways, Connect-injected workloads, and full observability (Prometheus, Grafana, Loki, Promtail). Optionally adds a third **VM** datacenter (`dc-vm`).

> Everything is managed from **your laptop** — no bastion needed. The EKS API endpoints are public; `kubectl`, `helm`, and `terraform` all run locally.

---

## Quick start — fastest path

| | Step | Time |
|-|------|------|
| ✅ | [Step 0](#step-0--workstation-setup) — Install tools, fill secrets | 10 min |
| ✅ | [Step 1](#step-1--vpc) — VPC | 2 min |
| ✅ | [Step 2](#step-2--eks-clusters) — Two EKS clusters (3 nodes each) | ~15 min |
| ✅ | [Step 3](#step-3--consul-on-eks) — Consul Enterprise via Helm | 5 min |
| ✅ | [Step 4](#step-4--cluster-peering) — Peer dc1 ↔ dc2 | 5 min |
| ✅ | [Step 5](#step-5--workloads-hashicups) — Deploy HashiCups | 5 min |
| ⏩ | [Step 6](#step-6--observability) — Prometheus, Grafana, Loki, Promtail | 10 min |
| ⏩ | [Step 7](#step-7--vm-datacenter-optional) — VM datacenter `dc-vm` (optional) | 30 min |
| ⏩ | [Step 8](#step-8--monitoring-on-vms) — VM monitoring (optional) | 10 min |
| ⏩ | [Step 9](#step-9--prepared-queries) — Geo-failover queries (optional) | 5 min |

**Total for a working multi-cluster mesh with workloads: ~45 minutes.**

---

## Cluster layout

```
┌─────────────────────────────────────────────────────────────────┐
│ AWS VPC (10.0.0.0/16)   us-east-1                              │
│                                                                  │
│  ┌──────────────────────┐    ┌──────────────────────┐           │
│  │  EKS: consul-dc1     │    │  EKS: consul-dc2     │           │
│  │  3 × m5.xlarge       │◄──►│  3 × m5.xlarge       │           │
│  │                      │    │                      │           │
│  │  Consul server ×3    │    │  Consul server ×3    │           │
│  │  Mesh gateway (NLB)  │    │  Mesh gateway (NLB)  │           │
│  │  HashiCups           │    │  HashiCups           │           │
│  │  Prometheus+Grafana  │    │  Prometheus          │           │
│  │  Loki + Promtail     │    │  Promtail            │           │
│  └──────────────────────┘    └──────────────────────┘           │
│                                                                  │
│  (optional) EC2 VM datacenter: dc-vm                            │
│  Consul server + HashiCups services + Promtail                  │
└─────────────────────────────────────────────────────────────────┘
```

Mesh gateways use AWS **NLB** (`type: LoadBalancer`) — EKS provisions them automatically. No NodePort workarounds, no bastion.

---

## What is in this repo

```
terraform/aws/            VPC, subnets, optional Route53, optional bastion (for VM dc only)
terraform/eks/            Two EKS clusters (consul-dc1, consul-dc2) — apply after terraform/aws
terraform/vm-datacenter/  EC2 instances for the optional VM datacenter
kubernetes/helm/consul/   Consul Enterprise Helm values (dc1 and dc2)
kubernetes/manifests/     Peering CRs, exported services, API gateway manifests
kubernetes/workloads/     HashiCups deployment pointers
monitoring/               Prometheus, Grafana, Loki, Promtail Helm values + PodMonitor
vm/                       Consul + HashiCups install docs for the VM datacenter
scripts/                  License secret helper, prepared-query JSON
docs/                     Architecture, DNS, security, access, prepared queries
```

---

## Reference documentation

| Document | When to open it |
|----------|----------------|
| [docs/SECRETS-AND-LOCAL-CONFIG.md](docs/SECRETS-AND-LOCAL-CONFIG.md) | License, tfvars, `.env` — what must not be committed |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Full topology, mesh gateway placement, DNS |
| [docs/SECURITY.md](docs/SECURITY.md) | TLS, ACLs, mesh defaults on Kubernetes vs VM |
| [docs/DNS-ROUTE53-CONSUL.md](docs/DNS-ROUTE53-CONSUL.md) | Route53 split-horizon, `.consul` DNS |
| [docs/ACCESS.md](docs/ACCESS.md) | UI port-forwarding, prepared query access |
| [docs/PREPARED-QUERIES.md](docs/PREPARED-QUERIES.md) | Register and test geo-failover queries |
| [terraform/aws/README.md](terraform/aws/README.md) | VPC variables and outputs |
| [terraform/eks/README.md](terraform/eks/README.md) | EKS variables, kubeconfig setup, storage |
| [kubernetes/helm/consul/README.md](kubernetes/helm/consul/README.md) | Chart version pin, license secret, image pull |
| [kubernetes/manifests/peering/README.md](kubernetes/manifests/peering/README.md) | Peering acceptor → dialer → exported services |
| [vm/README.md](vm/README.md) | Consul + HashiCups on the VM datacenter |
| [monitoring/README.md](monitoring/README.md) | Helm value tuning, Loki cross-cluster config |

---

## Prerequisites

- **Consul Enterprise license** (`.hclic`) and HashiCorp container registry access
- **AWS account** with credentials (`aws sts get-caller-identity` works) and an EC2 key pair
- **Consul Helm chart** version matching `consul-k8s-control-plane:1.8.3` — find it at [releases.hashicorp.com](https://releases.hashicorp.com/consul-k8s/)

Tool install commands are in [Step 0](#step-0--workstation-setup).

---

## Step 0 — Workstation setup

> **Skip if** Terraform ≥ 1.5, AWS CLI, kubectl, helm, and your `.env` / `terraform.tfvars` files are already set up.

**Read:** [docs/SECRETS-AND-LOCAL-CONFIG.md](docs/SECRETS-AND-LOCAL-CONFIG.md)

### Install tools (macOS)

```bash
brew tap hashicorp/tap
brew install hashicorp/tap/terraform awscli kubernetes-cli helm

aws configure        # Access Key ID, Secret, region (us-east-1), output format (json)
aws sts get-caller-identity   # verify credentials work
```

### Install tools (Linux / Amazon Linux 2023)

```bash
# Terraform
sudo dnf config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
sudo dnf install -y terraform

# AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
unzip -q /tmp/awscliv2.zip -d /tmp && sudo /tmp/aws/install
aws configure

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl && sudo mv kubectl /usr/local/bin/

# Helm 3
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

### Set up secrets files

```bash
# From the repository root — these files are gitignored, never commit them.
cp .env.example .env
# Edit .env:
#   CONSUL_LICENSE_FILE  — absolute path to your .hclic file
#   TF_VAR_ssh_key_name  — your EC2 key pair name (needed only if using the bastion)
source .env

cp terraform/aws/terraform.tfvars.example terraform/aws/terraform.tfvars
# Edit if you want Route53 or a bastion. Defaults work for VPC-only.
```

---

## Step 1 — VPC

> **Skip if** you already have a VPC with 3 public subnets in 3 AZs.

**Read:** [terraform/aws/README.md](terraform/aws/README.md)

Creates the VPC, 3 public subnets (one per AZ), Internet gateway, and route tables. Route53 and bastion are disabled by default — enable them in `terraform.tfvars` only if needed.

```bash
cd terraform/aws
terraform init
terraform apply
```

Record the outputs — you need them for Step 2:

```bash
terraform output vpc_id            # e.g. vpc-0abc1234
terraform output public_subnet_ids # e.g. ["subnet-0a...", "subnet-0b...", "subnet-0c..."]
```

> **Bastion:** not needed for EKS. Enable (`enable_bastion = true`) only if you add the VM datacenter in Step 7 and need SSH into private VPC instances.

---

## Step 2 — EKS clusters

**Read:** [terraform/eks/README.md](terraform/eks/README.md)

Provisions **consul-dc1** and **consul-dc2** — each a 3-node managed EKS cluster using `m5.xlarge` (16 GiB, 4 vCPU per node). Takes ~15 minutes.

```bash
cd terraform/eks
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with the VPC outputs from Step 1:

```hcl
vpc_id     = "vpc-0abc1234def56789a"       # from step 1
subnet_ids = ["subnet-0aaa...", "subnet-0bbb...", "subnet-0ccc..."]
```

Then apply:

```bash
terraform init
terraform apply
```

### Configure kubectl on your laptop

```bash
# Run the two kubeconfig commands printed in the output:
terraform output -json clusters | jq -r '.[] .kubeconfig_cmd' | bash

# Verify — you should see two contexts (dc1 and dc2):
kubectl config get-contexts

# Verify 3 Ready nodes on each:
kubectl config use-context dc1 && kubectl get nodes
kubectl config use-context dc2 && kubectl get nodes
```

---

## Step 3 — Consul on EKS

**Read:** [kubernetes/helm/consul/README.md](kubernetes/helm/consul/README.md)

### Create the Enterprise license Secret on each cluster

```bash
# Run from the repository root — license.hclic is already here
cd <repo-root>
export CONSUL_LICENSE_FILE="$(pwd)/license.hclic"

for cluster in dc1 dc2; do
  kubectl config use-context $cluster
  kubectl create namespace consul --dry-run=client -o yaml | kubectl apply -f -
  ./scripts/k8s-consul-license-secret.sh
done
```

### Find the correct Helm chart version

```bash
helm repo add hashicorp https://helm.releases.hashicorp.com && helm repo update
helm search repo hashicorp/consul --versions | grep 1.8.3
# Note the CHART VERSION in the first column (e.g. 1.6.3)
```

### Install Consul

```bash
CHART_VERSION=<version from above>

kubectl config use-context dc1
helm upgrade --install consul hashicorp/consul \
  --namespace consul \
  --version "$CHART_VERSION" \
  --values kubernetes/helm/consul/values-dc1.yaml \
  --wait

kubectl config use-context dc2
helm upgrade --install consul hashicorp/consul \
  --namespace consul \
  --version "$CHART_VERSION" \
  --values kubernetes/helm/consul/values-dc2.yaml \
  --wait
```

### Verify

```bash
kubectl config use-context dc1
kubectl get pods -n consul
# Expected: consul-server-0/1/2, consul-mesh-gateway-*, consul-connect-injector-*, consul-webhook-cert-manager-*
```

### Access the Consul UI

The Consul UI service is `type: LoadBalancer`. Get the URL:

```bash
kubectl config use-context dc1
kubectl get svc consul-ui -n consul
# EXTERNAL-IP column shows the ELB DNS name — open https://<that-name>
```

Or port-forward if the LB is not ready yet:

```bash
kubectl port-forward -n consul svc/consul-ui 8501:443
# https://localhost:8501
```

---

## Step 4 — Cluster peering

**Read:** [kubernetes/manifests/peering/README.md](kubernetes/manifests/peering/README.md)

```bash
cd <repo-root>

# 1. Enable peer-through-mesh-gateways on both clusters FIRST.
#    Without this, tokens embed the Consul server IP instead of the mesh gateway NLB address.
kubectl config use-context dc1
kubectl apply -f kubernetes/manifests/peering/mesh-config-dc1.yaml
kubectl config use-context dc2
kubectl apply -f kubernetes/manifests/peering/mesh-config-dc2.yaml

# 2. Create acceptor on dc1 — generates the peering token
kubectl config use-context dc1
kubectl apply -f kubernetes/manifests/peering/peering-acceptor-dc1.yaml
kubectl wait --for=condition=Ready peeringacceptor/dc2 -n consul --timeout=120s

# 3. Export the token and sanitize it for import into dc2
kubectl get secret peering-token-dc2 -n consul -o yaml > /tmp/peering-token-dc2.yaml
# Edit /tmp/peering-token-dc2.yaml:
#   - Remove "resourceVersion" and "uid" from metadata
#   - Confirm namespace: consul

# 4. Apply the token and dialer on dc2
kubectl config use-context dc2
kubectl apply -f /tmp/peering-token-dc2.yaml
kubectl apply -f kubernetes/manifests/peering/peering-dialer-dc2.yaml
kubectl wait --for=condition=Ready peeringdialer/dc1 -n consul --timeout=120s

# 5. Export dc1 services to dc2
kubectl config use-context dc1
kubectl apply -f kubernetes/manifests/peering/exported-services-hashicups-dc1.yaml
```

**Verify peering is Active:**

```bash
kubectl config use-context dc1
kubectl get peeringacceptor -n consul   # STATUS should be Active
```

---

## Step 5 — Workloads (HashiCups)

**Read:** [kubernetes/workloads/hashicups/README.md](kubernetes/workloads/hashicups/README.md)

Deploy HashiCups from the [Consul Kubernetes observability tutorial](https://developer.hashicorp.com/consul/tutorials/get-started-kubernetes/kubernetes-gs-observability#deploy-observability-suite). Use the tutorial's version-matched manifests for your Consul version.

Requirements:
- Pods must include annotation `consul.hashicorp.com/connect-inject: "true"` to join the mesh
- Deploy into a namespace where Connect injection is enabled (default: all namespaces)

**API Gateway (north–south access — no port-forwarding needed):**

```bash
kubectl config use-context dc1

# Install Kubernetes Gateway API CRDs (one-time)
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.1.0/standard-install.yaml

# Wait for Consul to register the GatewayClass
kubectl wait --for=condition=Accepted gatewayclass/consul --timeout=60s

# Deploy the gateway, route, and cross-namespace grant
kubectl apply -f kubernetes/manifests/api-gateway/gateway.yaml
kubectl apply -f kubernetes/manifests/api-gateway/referencegrant.yaml
kubectl apply -f kubernetes/manifests/api-gateway/httproute-hashicups.yaml

# Get the NLB URL (wait ~2 min for AWS to provision it)
kubectl get svc -n consul -l gateway.consul.hashicorp.com/name=hashicups
# Open http://<EXTERNAL-IP> in your browser
```

---

## Step 6 — Observability

> **Skip if** you do not need Prometheus / Grafana / Loki.

**Read:** [monitoring/README.md](monitoring/README.md) · [docs/MONITORING-GUIDE.md](docs/MONITORING-GUIDE.md)

> **Why standalone charts, not `kube-prometheus-stack`?**
> `kube-prometheus-stack` installs the Prometheus Operator and ~30 CRDs. We use the standalone
> `prometheus` and `grafana` charts instead — no operator, no CRDs, equivalent functionality.
> See [docs/MONITORING-GUIDE.md](docs/MONITORING-GUIDE.md) for the full decision rationale.

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
```

### dc1 — full stack (Prometheus + Grafana + Loki + Promtail)

```bash
kubectl config use-context dc1
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

# RBAC — allows Prometheus to discover pods/services across all namespaces
kubectl apply -f monitoring/rbac/prometheus-cluster-role.yaml

# Rule merger CronJob — syncs team alert rule ConfigMaps into Prometheus every 60s
kubectl apply -f monitoring/rule-merger/rule-merger-cronjob.yaml

# Standalone Prometheus (no operator)
helm upgrade --install prometheus prometheus-community/prometheus \
  --namespace monitoring --values monitoring/helm/prometheus-values.yaml --wait

# Standalone Grafana (no operator)
helm upgrade --install grafana grafana/grafana \
  --namespace monitoring --values monitoring/helm/grafana-values.yaml --wait

# Loki (log aggregation)
helm upgrade --install loki grafana/loki \
  --namespace monitoring --values monitoring/helm/loki-values.yaml --wait

# Promtail (log shipping — dc1)
helm upgrade --install promtail grafana/promtail \
  --namespace monitoring --values monitoring/helm/promtail-values.yaml
```

### dc2 — Prometheus + Promtail (ships to dc1)

```bash
kubectl config use-context dc2
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f monitoring/rbac/prometheus-cluster-role.yaml
kubectl apply -f monitoring/rule-merger/rule-merger-cronjob.yaml

helm upgrade --install prometheus prometheus-community/prometheus \
  --namespace monitoring --values monitoring/helm/prometheus-values-dc2.yaml --wait

# Promtail on dc2 — points to dc1 Loki NLB
# Get dc1 Loki URL first:
#   kubectl get svc loki -n monitoring --context dc1
# Then edit monitoring/helm/promtail-values-dc2.yaml with the EXTERNAL-IP, then:
helm upgrade --install promtail grafana/promtail \
  --namespace monitoring --values monitoring/helm/promtail-values-dc2.yaml
```

### Create a scoped Consul metrics token (do not use the bootstrap token)

```bash
kubectl port-forward svc/consul-server 8500:8500 -n consul &
sleep 2
CONSUL_TOKEN=$(kubectl get secret consul-bootstrap-acl-token \
  -n consul -o jsonpath='{.data.token}' | base64 -d)

# Create a read-only metrics policy
curl -sk --header "X-Consul-Token: $CONSUL_TOKEN" --request PUT \
  --data '{"Name":"prometheus-metrics","Rules":"agent_prefix \"\" { policy = \"read\" } node_prefix \"\" { policy = \"read\" }"}' \
  http://localhost:8500/v1/acl/policy

# Create a token scoped to that policy
METRICS_TOKEN=$(curl -sk --header "X-Consul-Token: $CONSUL_TOKEN" --request PUT \
  --data '{"Description":"Prometheus metrics scraper","Policies":[{"Name":"prometheus-metrics"}]}' \
  http://localhost:8500/v1/acl/token | jq -r '.SecretID')

# Store in monitoring namespace — Prometheus mounts this secret
kubectl create secret generic consul-metrics-token \
  --from-literal=token="$METRICS_TOKEN" -n monitoring
```

### Access Grafana

```bash
kubectl config use-context dc1
kubectl get svc grafana -n monitoring
# Open http://<EXTERNAL-IP>  (admin / see monitoring/helm/grafana-values.yaml for password)
```

### Onboard a new application team

```bash
export GRAFANA_URL=http://<grafana-nlb-dns>
export GRAFANA_ADMIN_PASSWORD=<password>
./monitoring/scripts/onboard-team.sh <team-name>
# Creates namespace, RBAC, Grafana folder, and example alert rules in one command
```


---

## Step 7 — VM datacenter (optional)

> **Skip if** you only need the two EKS datacenters.

**Read:** [terraform/vm-datacenter/README.md](terraform/vm-datacenter/README.md) · [vm/README.md](vm/README.md) · [docs/DNS-ROUTE53-CONSUL.md](docs/DNS-ROUTE53-CONSUL.md)

> Enable the bastion in `terraform/aws` if you need SSH access to the VM instances (`enable_bastion = true`).

```bash
cd terraform/vm-datacenter
cp terraform.tfvars.example terraform.tfvars
# Edit: vpc_id, subnet_ids (from terraform/aws outputs), ssh_key_name
terraform init
terraform apply
```

Then on each EC2 instance, follow [vm/README.md](vm/README.md) to install Consul, HashiCups, and the mesh gateway on TCP **8443**.

---

## Step 8 — Monitoring on VMs

> **Skip if** Step 7 was skipped.

**Read:** [vm/monitoring/README.md](vm/monitoring/README.md)

Install **node_exporter**, **Consul exporter**, and **Promtail** on each VM. Point Promtail at the same Loki NLB URL used in Step 6.

---

## Step 9 — Prepared queries

> **Skip if** you do not need geo-failover demos.

**Read:** [docs/PREPARED-QUERIES.md](docs/PREPARED-QUERIES.md) · [docs/ACCESS.md](docs/ACCESS.md)

```bash
# 1. Edit the query to match your datacenter names
vi scripts/prepared-query-geo.json

# 2. Port-forward to Consul HTTP (or use the LB if exposed)
kubectl config use-context dc1
kubectl port-forward -n consul svc/consul-server 8500:8500 &

# 3. Register the query
curl --header "X-Consul-Token: $CONSUL_HTTP_TOKEN" \
     --request POST \
     --data @scripts/prepared-query-geo.json \
     http://127.0.0.1:8500/v1/query

# 4. Test execution
curl http://127.0.0.1:8500/v1/query/<query-name>/execute
```

---

## Demo checklist

| Audience | What to show |
|----------|-------------|
| **Application teams** | Merged sidecar + app metrics on **20200** (`/metrics`), per-service request rates and error rates in Grafana |
| **Platform / operations** | Consul server + mesh gateway metrics, Loki log aggregation across dc1 and dc2, ACL token management |
| **Resilience** | Scale Consul server pods to 0 in dc2, watch prepared query fail over to dc1; restore and watch traffic return |

---

## Teardown

```bash
# Remove Consul and monitoring from each cluster
for ctx in dc1 dc2; do
  kubectl config use-context $ctx
  helm uninstall consul -n consul
  helm uninstall kps loki promtail -n monitoring
  kubectl delete namespace consul monitoring
done

# Destroy in reverse order (EKS first, then VPC)
cd terraform/vm-datacenter && terraform destroy   # skip if Step 7 was skipped
cd terraform/eks && terraform destroy             # takes ~10 minutes
cd terraform/aws && terraform destroy
```

---

## License

**Consul Enterprise** requires a valid HashiCorp license. This repository is for demonstration purposes. Review your organization's compliance and security standards before any production use.
