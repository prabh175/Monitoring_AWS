# Route53, your demo zone, and Consul DNS / prepared queries

This document ties together **your public Route53 zone apex** (set via **`route53_public_zone_name`** in gitignored `terraform.tfvars` or **`TF_VAR_route53_public_zone_name`**), **Consul’s `.consul` names**, and **prepared queries**.

## 1. Two different namespaces (both are intentional)

| Namespace | Examples | Who serves it |
|-----------|----------|----------------|
| **Your Route53 zone** | `dc1.<your-zone>`, `dc-vm.<your-zone>`, `frontend.<your-zone>` | **Route53** (public + split-horizon private zone) |
| **Consul service mesh DNS** | `frontend.service.consul`, `postgres.service.consul`, **`geo.query.consul`** (pattern depends on datacenter / partitions) | **Consul agents** on port **8600** (or **53** via **dnsmasq** on the Consul server VM) |

You **do not** create Route53 **sub-zones** that “replace” **`.consul`**. Consul continues to own **`service.consul`**, **`query.consul`**, etc. Your zone is for **stable infrastructure hostnames** (kind nodes, Consul server VM, HashiCups VMs).

## 2. Split-horizon Route53 (configured in Terraform)

**`terraform/aws`** (when `route53_public_zone_name` is set):

- **Public** hosted zone (existing): **`dcN.<zone>`** → kind node **public** IPs.
- **Private** hosted zone (**same apex**, associated with the demo VPC): **`dcN.<zone>`** → kind node **private** IPs.

**Inside the VPC**, the resolver prefers **private** answers for the same FQDNs so east–west traffic can stay on private addresses.

**`terraform/vm-datacenter`** (when the same variable is set):

- **Public** A records (if `enable_public_ip`): **`dc-vm`**, **`postgres`**, **`frontend`**, … → **public** IPs.
- **Private** A records: the **same names** → **private** IPs (always, even without public IPs on instances).

Apply **`terraform/aws` before `terraform/vm-datacenter`** so the **private** zone for that apex already exists.

## 3. Consul catalog and prepared queries

- **Service discovery** from workloads that already use a **Consul agent** (Kubernetes with CoreDNS stub, or VM Docker **`--dns <agent>`**) keeps using **`.service.consul`** as today.
- **From a bastion / kind node** without agent DNS, you can query the **VM Consul server** directly:
  - **Port 8600:** `dig @dc-vm.<zone> -p 8600 frontend.service.consul`
  - **Port 53** (if **`enable_consul_dns_bridge`**): `dig @dc-vm.<zone> -p 53 frontend.service.consul`  
    See [vm/consul/dnsmasq-bridge/README.md](../vm/consul/dnsmasq-bridge/README.md).

**Prepared queries** are usually exercised over **HTTP(S)** on the Consul API, e.g.:

```text
http://dc-vm.<zone>:8500/v1/query/geo-hashicups/execute?near=_geo
```

Replace **`geo-hashicups`** with the name you registered. **Port 8500** must be reachable from where you run **`curl`** (the VM security group already allows **8300–8600** TCP from the VPC CIDR). **ACLs**, if enabled, require a token.

The Terraform output **`prepared_query_http_example`** (vm-datacenter) prints a template URL after apply.

## 4. What we did *not* automate

- **Delegating** your entire **`hashidemos.io`** tree into Consul (not required for this demo).
- **Route53 Resolver** forwarding rules for **`.consul`** (possible in large enterprises; needs a supported forward domain and often more moving parts). The **dnsmasq** bridge is the lightweight stand-in for “**`dig @something` on port 53**” inside the VPC.

## 5. Quick checklist

1. **`terraform apply`** in **`terraform/aws`** with `route53_public_zone_name` set → split-horizon private zone + **`dc1` / `dc2`** records.
2. **`terraform apply`** in **`terraform/vm-datacenter`** with the same zone → **`dc-vm`** + role names in **public** (if applicable) and **private**.
3. Install Consul on the server VM; enable **`enable_consul_dns_bridge`** (default **true**) for **:53 → :8600** forwarding.
4. Register prepared queries (see [PREPARED-QUERIES.md](PREPARED-QUERIES.md)); call them via **`http://dc-vm.<your-zone>:8500/...`** (or HTTPS if you enable TLS on the server).
