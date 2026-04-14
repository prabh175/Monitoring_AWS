# Consul service registration (HashiCups on VMs)

The **`vm/hashicups/scripts/on-*.sh`** scripts register each workload with **Consul Connect**: a **`connect.sidecar_service`** block and a **`connect-envoy@<service-name>`** systemd unit run **`consul connect envoy -sidecar-for <name>`** for **mTLS** on the mesh.

## Discovery and upstreams

- **Catalog / SRV:** each service still has a logical name (`postgres`, `product-api`, …) for the mesh and UI.
- **Inside containers:** HTTP and Postgres clients use **`host.docker.internal`** and fixed **local bind** ports that the **host** Envoy opens (`vm/hashicups/scripts/lib.sh`, `DOCKER_HOST_GATEWAY_FLAGS`). That maps container traffic into the local sidecar’s upstream listeners (bridge networks cannot see the host’s `127.0.0.1`).

| Service     | Connect upstream local_bind (on host) | Used by container as                          |
|------------|----------------------------------------|-----------------------------------------------|
| product-api | `15432` → `postgres`                   | `host.docker.internal:15432` (Postgres wire)  |
| public-api  | `19090` → `product-api`, `19091` → `payments` | `http://host.docker.internal:19090` / `:19091` |
| frontend    | `18080` → `public-api`                 | default `http://host.docker.internal:18080` (override with `HASHICUPS_PUBLIC_API_URL` for browsers) |

## Systemd

Install once per VM that runs HashiCups:

```bash
sudo cp vm/hashicups/systemd/connect-envoy@.service /etc/systemd/system/
sudo systemctl daemon-reload
```

The **`on-*.sh`** scripts enable **`connect-envoy@<service>.service`** after registration.

## ACLs

If you merge **`vm/consul/security/`** ACL snippets, set **`CONSUL_HTTP_TOKEN`** in **`/etc/consul.d/consul.env`** for the **`consul` user** so **`consul connect envoy`** and **`consul services register`** succeed. See [docs/SECURITY.md](../../../docs/SECURITY.md).

## Legacy (DNS-only) registration

Plain catalog registration without Connect looked like:

```hcl
service {
  name = "postgres"
  port = 5432
  check {
    tcp      = "127.0.0.1:5432"
    interval = "10s"
  }
}
```

The current scripts **replace** this with Connect + sidecar.
