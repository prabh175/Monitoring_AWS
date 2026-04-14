#!/usr/bin/env bash
# Run on the frontend VM.
# Server-side calls use Connect upstream to public-api on host.docker.internal:18080.
# For browser-side NEXT_PUBLIC_* from a laptop, set HASHICUPS_PUBLIC_API_URL in
# /etc/hashicups.env to a URL the browser can reach (e.g. public LB or SSH tunnel).
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

test -f /etc/hashicups.env && source /etc/hashicups.env
API_BASE="${HASHICUPS_PUBLIC_API_URL:-http://host.docker.internal:18080}"

docker rm -f frontend 2>/dev/null || true
docker run -d --name frontend --restart unless-stopped \
  "${DNS_FLAGS[@]}" \
  "${DOCKER_HOST_GATEWAY_FLAGS[@]}" \
  -p 80:80 \
  -e NEXT_PUBLIC_PUBLIC_API_HOST="${API_BASE}" \
  hashicorpdemoapp/frontend:latest

sleep 3

tmp=$(mktemp)
tee "${tmp}" >/dev/null <<'EOF'
service {
  name = "frontend"
  port = 80
  connect {
    sidecar_service {
      proxy {
        upstreams = [
          {
            destination_name = "public-api"
            local_bind_port  = 18080
          }
        ]
      }
    }
  }
  check {
    tcp      = "127.0.0.1:80"
    interval = "10s"
  }
}
EOF
reregister_connect_service frontend "${tmp}"

echo "frontend registered with Connect sidecar (API base for app: ${API_BASE})"
