# Prepared queries for geo-style failover

Prepared queries are **Consul configuration objects**, not Kubernetes CRDs. Register them with the Consul API or CLI against a server or agent with appropriate ACL permissions.

## Example: failover across datacenters (peering / WAN-agnostic template)

After clusters are peered and services are exported, a query can prefer local instances then fail over to remote peers. Adjust `Datacenters` / `Peer` blocks to match your 1.21 Enterprise peering naming (see current Consul prepared query docs for the exact `Peer` field support in your version).

### Register (HTTP API)

```bash
consul login  # or export CONSUL_HTTP_TOKEN
curl --request POST --header "X-Consul-Token: $CONSUL_HTTP_TOKEN" \
  --data @scripts/prepared-query-geo.json \
  http://127.0.0.1:8500/v1/query
```

### Execute

```bash
curl "http://127.0.0.1:8500/v1/query/geo-hashicups/execute?near=_geo"
```

### DNS (when using Consul’s DNS interface)

If your clients query Consul DNS (e.g. via forwarded `consul` zone), prepared queries are typically exposed as `<query-name>.query[.<partition>].consul` depending on partition and configuration—verify against your `recursors` and `domains` settings.

For this repo’s AWS layout, see [DNS-ROUTE53-CONSUL.md](DNS-ROUTE53-CONSUL.md): **`dig @dc-vm.<your-zone> -p 53`** (dnsmasq bridge) or **`-p 8600`** directly.

### Execute over HTTP from the VPC (stable hostname)

After Route53 records exist (VM Consul defaults to **HTTP** on **8500** unless you enable TLS):

```bash
curl "http://dc-vm.<your-public-zone>:8500/v1/query/geo-hashicups/execute?near=_geo"
```

Use **HTTPS** only when your `server.hcl` enables TLS; add **`-k`** for self-signed certs.

## Relationship to `geo.consul` in Route53

- **Route53** is best used for **human-facing** or **bootstrap** names (UI, mesh gateway VIP, bastion).
- **Geo failover for service instances** belongs in the **prepared query** (or in service resolver defaults), executed through Consul’s API/DNS path—not by listing multiple Consul NS records in Route53.

See `scripts/prepared-query-geo.json` for a starter template to edit after your service names and peers exist.
