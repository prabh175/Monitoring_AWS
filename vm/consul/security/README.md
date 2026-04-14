# Optional TLS and ACLs for dc-vm (parity with Helm defaults)

Base **`vm/consul/server.hcl`** and **`client.hcl`** leave **RPC TLS** and **ACLs** off so you can stand up the lab quickly. On Kubernetes, **`global.tls.enabled`** and **`global.acls.manageSystemACLs`** are **true** in `kubernetes/helm/consul/values-*.yaml`.

Use this directory when you want **dc-vm** to use **encrypted Consul RPC** and **ACLs** as well.

## 1. Generate TLS material (on each node, or build on one and distribute)

With the Consul binary installed:

```bash
sudo mkdir -p /etc/consul.d/tls
cd /etc/consul.d/tls
sudo consul tls ca create
```

**Server** (on the Consul server VM; set IP and name to match `server.hcl`):

```bash
# Example: single server, datacenter dc-vm, IP from metadata
PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
sudo consul tls cert create -server -additional-ipaddress="$PRIVATE_IP" -days=1825
sudo bash -c 'mv *.pem /etc/consul.d/tls/'
```

Rename or symlink files to match paths in **`server-tls.hcl.example`** (edit paths to your filenames).

**Clients** (each HashiCups / agent VM) need a **client** cert trusted by the same CA:

```bash
PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
NODE_NAME="hc-postgres"   # match client.hcl node_name
sudo consul tls cert create -client -node="$NODE_NAME" -additional-ipaddress="$PRIVATE_IP" -days=1825
sudo bash -c 'mv *.pem /etc/consul.d/tls/'
```

Adjust **`-node`** to each host’s **`node_name`**. For **`verify_server_hostname = true`**, SANs must match how agents present themselves—see [TLS encryption](https://developer.hashicorp.com/consul/docs/security/tls).

## 2. Merge TLS into Consul configuration

Copy **`server-tls.hcl.example`** → `/etc/consul.d/server-tls.hcl` on the server and **`client-tls.hcl.example`** → `/etc/consul.d/client-tls.hcl` on clients. **Edit** `ca_file`, `cert_file`, and `key_file` paths to your real PEM locations.

**Do not start Consul** until paths are valid.

## 3. ACL bootstrap (server first)

Choose one approach:

- **Known initial management token** (simplest for a lab): generate a UUID, put it in **`acl.hcl.example`** as `initial_management`, merge into `/etc/consul.d/` on the **first** server only, start Consul once, then create **agent** and **default** tokens for clients and DNS as needed.
- **`consul acl bootstrap`** (interactive): start with ACL enabled but without `initial_management` only if your Consul version/docs support your chosen flow.

Merge **`acl.hcl.example`** into `/etc/consul.d/` on the server. On **clients**, use **`acl.hcl.client.example`** with **`tokens.agent`** (and optionally **`tokens.default`**) set to tokens you create after the server is up.

## 4. Tokens for Connect and CLI

Create **`/etc/consul.d/consul.env`** (mode `0600`, owner root or consul):

```bash
CONSUL_HTTP_TOKEN=<token with connect + service:write + agent:read as needed>
```

**`connect-envoy@.service`**, **`mesh-gateway.service`**, and **`consul services register`** from scripts need a token when ACLs are enabled.

## 5. Helm-style default deny

Helm commonly sets **default deny**. Plain DNS from Docker without a token may stop resolving. You will need:

- Policies bound to the **anonymous** token or a **default** token with **`service:read`** / **`node:read`** for discovery, **or** agents configured with a suitable **`tokens.default`**, and  
- **Service intentions** (or equivalent) for Connect paths.

This repo does not generate those policies automatically; use [ACL tutorial](https://developer.hashicorp.com/consul/tutorials/security/access-control-setup-production) and [intentions](https://developer.hashicorp.com/consul/docs/connect/intentions) as references.

## Files

| File | Purpose |
|------|---------|
| `server-tls.hcl.example` | TLS `tls { ... }` for the server agent |
| `client-tls.hcl.example` | TLS `tls { ... }` for client agents |
| `acl.hcl.example` | ACL stanza for **server** (initial management placeholder) |
| `acl.hcl.client.example` | ACL stanza for **clients** (agent token placeholder) |
