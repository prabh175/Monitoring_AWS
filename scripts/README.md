# Scripts

| Script | Purpose |
|--------|---------|
| [k8s-consul-license-secret.sh](k8s-consul-license-secret.sh) | Create/update **`consul-enterprise-license`** in Kubernetes from **`CONSUL_LICENSE_FILE`** (or first argument). |
| [prepared-query-geo.json](prepared-query-geo.json) | Template for registering a geo-style prepared query ([docs/PREPARED-QUERIES.md](../docs/PREPARED-QUERIES.md)). |

Do not commit license files or exported cluster secrets; see [docs/SECRETS-AND-LOCAL-CONFIG.md](../docs/SECRETS-AND-LOCAL-CONFIG.md).
