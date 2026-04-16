# AWS base layer (VPC, kind hosts, bastion)

Creates a VPC, public subnets, Internet gateway, and EC2 instances for **kind** (or other use). Optionally provisions a **bastion** so you can SSH from your laptop into the VPC using **private IPs** on worker nodes.

**Kind node size:** `node_instance_type` defaults to **`m6i.2xlarge`** (32 GiB RAM) so each single-node kind cluster can run three Consul server replicas, the mesh gateway, demo workloads (for example HashiCups), and the monitoring stack without constant memory pressure. Override in `terraform.tfvars` if you shrink the Helm footprint (for example `server.replicas: 1`).

## Required when `enable_bastion` is true

| Variable | Example |
|----------|---------|
| `ssh_key_name` | Name of an existing EC2 key pair (same key used on `aws_instance.node`). Set in gitignored `terraform.tfvars` or `TF_VAR_ssh_key_name`. |
| `bastion_ssh_cidr_blocks` | `["203.0.113.50/32"]` — your **public** IP, not `10.0.0.0/8`. |
| `route53_public_zone_name` | Optional. Existing **public** hosted zone in this account. Creates **`dc1`**, **`dc2`**, … in **public** (→ public IP) and a **split-horizon private** zone with the **same apex** (→ **private** IP in-VPC). See [docs/DNS-ROUTE53-CONSUL.md](../../docs/DNS-ROUTE53-CONSUL.md). |
| `private_zone_domain` | Optional **separate** private zone attached to the VPC (different apex). Do **not** reuse your public demo zone name here. |

## Apply

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars
terraform init
terraform apply
```

## Outputs

- `bastion_public_ip` — `ssh -i KEY ec2-user@<value>`
- `node_private_ips` / `node_public_ips` — use **private** IPs from the bastion for SSH and in-cluster work
- `vpc_id`, `public_subnet_ids` — inputs to `terraform/vm-datacenter`

## Disable bastion

Set `enable_bastion = false`. The `check` block will not require `bastion_ssh_cidr_blocks`; you can omit `ssh_key_name` on nodes if you rely on SSM only (not configured in this minimal example).
