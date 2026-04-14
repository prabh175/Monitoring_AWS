# Secrets, local config, and what not to commit

If **`terraform.tfvars`** was ever committed before `.gitignore` existed, remove it from the index (and rotate any exposed values): `git rm --cached terraform/aws/terraform.tfvars terraform/vm-datacenter/terraform.tfvars` (paths as applicable).

## Gitignored by default (see repository `.gitignore`)

| Pattern | Why |
|---------|-----|
| **`terraform.tfvars`**, **`*.auto.tfvars`** | Operator-specific values: key pair name, Route53 zone, CIDRs, license **paths** |
| **`.env`**, **`.env.local`** | `TF_VAR_*`, `CONSUL_LICENSE_FILE`, etc. |
| **`*.tfstate`**, **`.terraform/`** | State can embed secrets; use remote backend in real use |
| **`*.hclic`**, **`license.hclic`** | Consul Enterprise license files |
| **`*peering*export*.yaml`** | Exported Kubernetes peering secrets |
| **Private keys** (`*-key.pem`, agent CA) except `*.example` under `vm/consul/security/` | TLS material |

**Committed** files should use **placeholders only**: `terraform.tfvars.example`, `.env.example`, `*.example` snippets.

## Variables (Terraform)

Set real values in **`terraform.tfvars`** (gitignored) or **`export TF_VAR_<name>=...`**.

| Variable | Module | Purpose |
|----------|--------|---------|
| **`ssh_key_name`** | `terraform/aws`, `terraform/vm-datacenter` | EC2 key pair name |
| **`route53_public_zone_name`** | both | Existing public hosted zone apex |
| **`bastion_ssh_cidr_blocks`** | `terraform/aws` | Your public IP `/32` for SSH to bastion |
| **`consul_enterprise_license_path`** | `terraform/vm-datacenter` | Local path to `.hclic`; Terraform **validates** the file exists at plan time but **does not** upload it (keeps license out of state). Copy to the server manually or use SSM in your own process. |

## Consul license on Kubernetes

Use **`scripts/k8s-consul-license-secret.sh`** with **`CONSUL_LICENSE_FILE`** (or first argument). Do not commit the license file or a script that embeds it.

## Demo defaults that are not “your” credentials

- HashiCups **Postgres** uses **`password=password`** in `vm/hashicups/scripts` (public demo image pattern). Replace for anything beyond a lab.
- **`bastion_ssh_cidr_blocks`** in **`terraform.tfvars.example`** uses documentation CIDR **`203.0.113.50/32`** (TEST-NET-3); replace with your IP.

## Scanning the repo

Before commit, search for accidental leaks:

```bash
rg -n "BEGIN (RSA|OPENSSH|EC) PRIVATE|AKIA[0-9A-Z]{16}|api_key\\s*[:=]" --glob '!**/.tmpchart/**'
```

Review any real **`*.yaml`** exports under `kubernetes/manifests/` (examples should stay generic).
