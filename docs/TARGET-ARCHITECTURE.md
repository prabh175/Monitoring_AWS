# Target diagram vs this repository

Your reference diagram shows **two Kubernetes clusters**, a **VM-based site**, full **observability** (Prometheus, Grafana, Loki, Promtail), **mesh gateways** everywhere, and **API gateways** for ingress. Below is how the **current repo** lines up and what differs.

## What matches

| Diagram | This repo |
|---------|-----------|
| Two K8s clusters (logical DCs) | `kubernetes/kind/kind-dc1.yaml`, `kind-dc2.yaml` + Helm per cluster |
| Consul servers + Connect + mesh gateway in K8s | `kubernetes/helm/consul/values-dc*.yaml` (`meshGateway`, `connectInject`, `apiGateway`) |
| Mesh GW between K8s and VMs | NodePort **31443** (K8s) ↔ **8443** on VM Consul server ([`vm/consul/mesh-gateway.service`](../vm/consul/mesh-gateway.service)) |
| API Gateway on K8s (public LB) | `connectInject.apiGateway.managedGatewayClass.serviceType: LoadBalancer` |
| Central Loki in primary cluster, Promtail shipping logs | [monitoring/README.md](../monitoring/README.md) |
| Prometheus + Grafana | kube-prometheus-stack values under `monitoring/helm/` |
| HashiCups on K8s + VMs | K8s: tutorial manifests; VMs: `vm/hashicups/scripts/` |

## What differs (important)

| Diagram | This repo today |
|---------|-----------------|
| **4 VMs**: Server, Mesh GW, HashiCups, API GW | **1** Consul server (mesh GW **on the same** VM), **no** Consul API Gateway on VMs, **5** HashiCups **microservice** VMs (postgres, product-api, payments, public-api, frontend) instead of one “HashiCups” box |
| Second Mesh GW pod inside app namespace on K8s 2 | Single mesh gateway Deployment per cluster (replica count configurable); add a second gateway via chart/Gateway API if you need the exact layout |
| All user access via implied public paths | **SSH** is **VPC-only** to nodes; use a **bastion** for Mac access ([terraform/aws](../terraform/aws)). **Consul UI / HashiCups on Kubernetes** can use **API GW + HTTPRoute** ([ACCESS.md](ACCESS.md)). **VM HashiCups** uses **SSH tunnel, LB, or direct VPC access**—no Consul API Gateway on VMs in this repo. |

## If you want the diagram literally

1. **Dedicated VM mesh gateway**: stop the mesh-gateway unit on the Consul server; run a **second small EC2** with only `consul` client + `consul connect envoy -gateway=mesh` (new Terraform role).
2. **Single “HashiCups” VM**: replace the five service instances with **one** EC2 running **docker compose** (or Nomad), at the cost of one IP for all services.
3. **API Gateway on VMs**: **out of scope** for this repo (use K8s API Gateway for cluster ingress only, or expose VM apps via LB / SSH as in [ACCESS.md](ACCESS.md)).

## Diagram file

If you add your image to the repo (e.g. `docs/images/reference-architecture.png`), link it here from the README for workshops.
