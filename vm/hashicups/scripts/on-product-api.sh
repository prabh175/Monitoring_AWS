#!/usr/bin/env bash
# Run on the product-api VM. DB traffic goes through the Connect sidecar (mTLS) to postgres.
# Upstream: host.docker.internal:15432 → Envoy local_bind → postgres service mesh.
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

install -d -m 0755 /opt/hashicups
cat >/opt/hashicups/product-api-config.json <<'EOF'
{
  "db_connection": "host=host.docker.internal port=15432 user=postgres password=password dbname=products sslmode=disable"
}
EOF

docker rm -f product-api 2>/dev/null || true
docker run -d --name product-api --restart unless-stopped \
  "${DNS_FLAGS[@]}" \
  "${DOCKER_HOST_GATEWAY_FLAGS[@]}" \
  -p 9090:9090 \
  -v /opt/hashicups/product-api-config.json:/config/config.json:ro \
  -e CONFIG_FILE=/config/config.json \
  hashicorpdemoapp/product-api:v4280cf7

sleep 3

tmp=$(mktemp)
tee "${tmp}" >/dev/null <<'EOF'
service {
  name = "product-api"
  port = 9090
  connect {
    sidecar_service {
      proxy {
        upstreams = [
          {
            destination_name = "postgres"
            local_bind_port  = 15432
          }
        ]
      }
    }
  }
  check {
    tcp      = "127.0.0.1:9090"
    interval = "10s"
  }
}
EOF
reregister_connect_service product-api "${tmp}"

echo "product-api registered with Connect sidecar (upstream postgres @ host.docker.internal:15432)"
