# VM datacenter: Consul (single server) + HashiCups (one service per VM)

This guide matches **terraform/vm-datacenter**: **one** EC2 instance for the Consul **control plane** and **one EC2 instance per HashiCups microservice**, each with its **own private IP**. Docker runs on every instance (installed via Terraform `user_data`).

**SSH:** these instances are reachable on **port 22 from the VPC only** (not from the open internet). From your **Mac**, connect to the **[terraform/aws](../terraform/aws) bastion** first, then `ssh ec2-user@<vm-private-ip>`. See [docs/ACCESS.md](../docs/ACCESS.md).

## 1. Provision EC2

```bash
cd terraform/vm-datacenter
terraform init
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with vpc_id and subnet_ids from terraform/aws outputs.
terraform apply
terraform output consul_retry_join_hint
```

Use `consul_server_private_ip` / `consul_retry_join_hint` when filling **`retry_join`** in `vm/consul/client.hcl` (see §5). HashiCups east-west traffic uses **Consul Connect** sidecars (**mTLS**): scripts register **`connect.sidecar_service`** and start **`connect-envoy@<service>`**. Containers reach the host’s Envoy **local_bind** ports via **`host.docker.internal`** (`--add-host=host.docker.internal:host-gateway`); see [vm/hashicups/consul/README.md](hashicups/consul/README.md). Consul **DNS** (`--dns <this host's private IP>`) remains for the co-located agent. **TLS/ACL parity with Kubernetes** is optional; see [docs/SECURITY.md](../docs/SECURITY.md) and [vm/consul/security/](consul/security/README.md).

## 2. Linux users and directories (all Consul VMs)

On **consul-server** and **each HashiCups VM**:

```bash
sudo useradd --system --home /etc/consul.d --shell /bin/false consul 2>/dev/null || true
sudo mkdir -p /etc/consul.d /opt/consul/data
sudo chown -R consul:consul /etc/consul.d /opt/consul/data
```

## 3. Install Consul (match your Kubernetes major version, e.g. 1.21.x Enterprise)

Pick **one** method:

- **RPM/DNF (Amazon Linux)** — follow [Consul install](https://developer.hashicorp.com/consul/install) for your distro (Enterprise requires license and entitled repo where applicable).
- **Binary** — download the Linux `amd64` zip from [Consul releases](https://releases.hashicorp.com/consul/), install to `/usr/bin/consul`, `chmod +x`.

Enterprise: copy `license.hclic` to `/etc/consul.d/license.hclic` and **uncomment** `license_path` in `vm/consul/server.hcl`.

Install systemd unit:

```bash
sudo cp vm/consul/consul.service /etc/systemd/system/consul.service
sudo systemctl daemon-reload
```

## 4. Consul server (control plane VM only)

```bash
PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
sudo sed "s/REPLACE_WITH_PRIVATE_IP/${PRIVATE_IP}/g" vm/consul/server.hcl | sudo tee /etc/consul.d/server.hcl
sudo systemctl enable --now consul
sudo systemctl status consul
```

UI (if enabled): `http://<consul-server-private-ip>:8500/ui/`

### Mesh gateway (same server VM, for peering to Kubernetes)

Peers must reach **TCP 8443** on this private IP (allowed from the whole VPC in `terraform/vm-datacenter`).

```bash
sudo sed "s/REPLACE_WITH_PRIVATE_IP/${PRIVATE_IP}/g" vm/consul/mesh-gateway.service | sudo tee /etc/systemd/system/mesh-gateway.service
sudo systemctl daemon-reload
sudo systemctl enable --now mesh-gateway
```

Confirm the registered gateway with `consul catalog services` / UI.

## 5. Consul client (each HashiCups VM)

Replace node name per host (e.g. `hc-postgres`, `hc-product-api`, ...):

```bash
CONSUL_SERVER_IP="<from terraform output>"
PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
NODE_NAME="hc-$(hostname -s)"

sed -e "s/REPLACE_WITH_PRIVATE_IP/${PRIVATE_IP}/g" \
    -e "s/REPLACE_CONSUL_SERVER_IP/${CONSUL_SERVER_IP}/g" \
    -e "s/REPLACE_NODE_NAME/${NODE_NAME}/g" \
    vm/consul/client.hcl | sudo tee /etc/consul.d/client.hcl

sudo cp vm/consul/consul.service /etc/systemd/system/consul.service
sudo systemctl daemon-reload
sudo systemctl enable --now consul
```

## 5b. Connect sidecar unit (each HashiCups VM)

Before running **`on-*.sh`**:

```bash
sudo cp vm/hashicups/systemd/connect-envoy@.service /etc/systemd/system/
sudo systemctl daemon-reload
```

Requires **Docker 20.10+** on Amazon Linux (or equivalent) so **`host.docker.internal:host-gateway`** works for bridge containers.

## 6. HashiCups containers (order matters)

From this repo on your laptop, copy `vm/hashicups/scripts` (including **`lib.sh`**) to each VM (or clone the repo).

```bash
chmod +x vm/hashicups/scripts/*.sh
```

Optional: on the **frontend** VM only, if browsers must call the API by a **non-Consul** URL, create `/etc/hashicups.env` from [vm/hashicups/hashicups.env.example](hashicups/hashicups.env.example) and set `HASHICUPS_PUBLIC_API_URL` (see script header in `on-frontend.sh`).

Run **only** the script that matches the instance role:

| VM role (Terraform tag `Role`) | Script |
|--------------------------------|--------|
| postgres | `sudo ./on-postgres.sh` |
| product-api | `sudo ./on-product-api.sh` |
| payments | `sudo ./on-payments.sh` |
| public-api | `sudo ./on-public-api.sh` |
| frontend | `sudo ./on-frontend.sh` |

Order: **postgres** → **product-api** → **payments** → **public-api** → **frontend**.

Images and env vars follow the public **hashicorpdemoapp** demos (`product-api` / `product-api-db` pins `v4280cf7`; others use `latest` in scripts—**pin tags in production**). If a container fails health checks, compare env names with [Docker Hub](https://hub.docker.com/u/hashicorpdemoapp) or the official HashiCups tutorial you are following.

Each `on-*.sh` registers the service with **Connect** and starts the **Envoy** sidecar. Mesh traffic targets the **sidecar**, not plain `name.service.consul` ports (the scripts configure **`host.docker.internal`** upstream ports—see [hashicups/consul/README.md](hashicups/consul/README.md)).

## 7. Consul DNS, Connect, and browsers

- **East-west (mesh):** Connect **local_bind** ports on the host, reached from containers as **`http://host.docker.internal:<port>`** (or Postgres on **`host.docker.internal:15432`**). **`--dns=<host IP>`** still points containers at the agent for `.consul` if you use it elsewhere.
- **Browsers:** laptops do not use Consul DNS or the mesh. For **NEXT_PUBLIC_** client-side API URLs, set **`HASHICUPS_PUBLIC_API_URL`** in **`/etc/hashicups.env`** to a browser-reachable endpoint (VPC LB/NLB, SSH tunnel to **public-api**, or similar). This repo does **not** run Consul API Gateway on VMs.

Manual registration examples: [vm/hashicups/consul/README.md](hashicups/consul/README.md).

## 8. Peering to Kubernetes

Use the mesh gateway on this server VM as the WAN entry for **dc-vm**. On Kubernetes, keep **mesh gateway NodePort 31443** and follow HashiCorp **cluster peering** docs for K8s ↔ external (VM) peers for your Consul version.

## 9. Monitoring

See [vm/monitoring/README.md](monitoring/README.md) for **node_exporter**, **Promtail** (logs to Loki), and scraping Consul metrics from this datacenter.
