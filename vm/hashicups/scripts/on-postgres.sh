#!/usr/bin/env bash
# Run on the postgres VM. Connect sidecar terminates mesh mTLS and forwards to local Postgres.
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

docker rm -f postgres 2>/dev/null || true
docker run -d --name postgres --restart unless-stopped \
  "${DNS_FLAGS[@]}" \
  -p 5432:5432 \
  -e POSTGRES_DB=products \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=password \
  hashicorpdemoapp/product-api-db:v4280cf7

sleep 3

tmp=$(mktemp)
tee "${tmp}" >/dev/null <<'EOF'
service {
  name = "postgres"
  port = 5432
  connect {
    sidecar_service {}
  }
  check {
    tcp      = "127.0.0.1:5432"
    interval = "10s"
  }
}
EOF
reregister_connect_service postgres "${tmp}"

echo "postgres registered with Connect sidecar (mesh → local :5432)"
