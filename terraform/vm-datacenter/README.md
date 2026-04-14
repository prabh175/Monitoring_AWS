# VM datacenter (Consul server + HashiCups per VM)

Creates **one** EC2 instance tagged `consul-server` and **one instance per HashiCups role** (default: `postgres`, `product-api`, `payments`, `public-api`, `frontend`), each with its **own private IP**.

## Prerequisites

1. Apply [terraform/aws](../aws) first (or supply an existing `vpc_id` and `subnet_ids`).
2. An EC2 **key pair** in the same region; set **`ssh_key_name`** in gitignored **`terraform.tfvars`** (see **`terraform.tfvars.example`**).
3. A **public Route53 hosted zone** in this account; set **`route53_public_zone_name`** the same way. Apply **`terraform/aws` first** so the **split-horizon private** zone for that apex exists. This module creates **`dc-vm`** and **`<role>`** records in **public** (if `enable_public_ip`) and **private** (always). See [docs/DNS-ROUTE53-CONSUL.md](../../docs/DNS-ROUTE53-CONSUL.md). With **`enable_consul_dns_bridge`** (default **true**), the Consul server also runs **dnsmasq** on **:53** → **:8600** ([vm/consul/dnsmasq-bridge/README.md](../../vm/consul/dnsmasq-bridge/README.md)). Optional **`consul_enterprise_license_path`**: local path validated at plan; not uploaded ([docs/SECRETS-AND-LOCAL-CONFIG.md](../../docs/SECRETS-AND-LOCAL-CONFIG.md)).

## Apply

```bash
cd terraform/vm-datacenter
terraform init

# From root aws outputs (example):
terraform apply \
  -var="vpc_id=$(terraform -chdir=../aws output -raw vpc_id)" \
  -var='subnet_ids=["'"$(terraform -chdir=../aws output -json public_subnet_ids | jq -r '.[0]')"'","'"$(terraform -chdir=../aws output -json public_subnet_ids | jq -r '.[1]')"'"]' \
  -var="ssh_key_name=your-ec2-keypair-name"
```

Or copy `terraform.tfvars.example` to `terraform.tfvars` and run `terraform apply`.

## Outputs

- `consul_server_private_ip` / `consul_retry_join_hint` — use in `retry_join` for Consul clients (`vm/consul/client.hcl`).
- `hashicups_private_ips` — map of role to IP (monitoring scrape lists, SSH, optional browser URL overrides—not required for app wiring; apps use **Consul DNS**).
- `cluster_dns_names` (from `terraform/aws`) — **`dc1.<your-zone>`**, **`dc2.<your-zone>`** for kind hosts.
- `dc_vm_dns_name`, `hashicups_dns_names`, `consul_dns_bridge_hint`, `prepared_query_http_example` — when the zone is set; **in-VPC** resolvers use **private** IPs for the same FQDNs (split horizon). **Consul `.consul` DNS** is separate; use **`dig @dc-vm.<zone> -p 53`** after Consul + dnsmasq are up.

Install Consul and HashiCups using [vm/README.md](../../vm/README.md).
