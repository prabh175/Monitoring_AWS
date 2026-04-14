# kind cluster configs

## Layout

- **`kind-dc1.yaml` / `kind-dc2.yaml`:** each defines a **single-node** cluster (one `control-plane` node). That matches **one VM (or one Docker host) per Kubernetes cluster**.
- **Mesh gateways** are installed by the Consul Helm chart as **pods in that same cluster** alongside Consul servers and your apps. You do **not** need a separate machine for mesh gateway.

## Peering between two kind clusters on two VMs

Each VM gets a **node IP** (or EC2 public/private IP). Mesh gateway **NodePort `31443`** must be reachable between those nodes (security groups / firewall). Consul registers the gateway’s WAN address using `meshGateway.wanAddress.source: Service` and NodePort as in `kubernetes/helm/consul/values-*.yaml`.

## Single laptop

You can still run **both** `kind create cluster` commands on one machine; you get two isolated clusters for learning, but cross-cluster networking uses the Docker bridge / host networking rules for that host instead of two cloud VMs.
