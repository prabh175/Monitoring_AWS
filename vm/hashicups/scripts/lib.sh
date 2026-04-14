# Sourced by on-*.sh — Docker uses this host's Consul agent for DNS (:8600) where still needed.
# With Connect sidecars, east-west HTTP/TCP to peers uses local_bind ports on 127.0.0.1.

_LIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)
CONNECT_ENVOY_UNIT_SRC="${_LIB_DIR}/../systemd/connect-envoy@.service"

host_ip() {
  curl -fsS --connect-timeout 2 http://169.254.169.254/latest/meta-data/local-ipv4 2>/dev/null || hostname -I | awk '{print $1}'
}

DNS_FLAGS=(--dns "$(host_ip)")
# Reach Connect local_bind ports (Envoy on the host loopback) from bridge-network containers.
DOCKER_HOST_GATEWAY_FLAGS=(--add-host=host.docker.internal:host-gateway)

ensure_connect_envoy_unit_installed() {
  if [[ -f /etc/systemd/system/connect-envoy@.service ]]; then
    return 0
  fi
  if [[ ! -f "${CONNECT_ENVOY_UNIT_SRC}" ]]; then
    echo "Missing ${CONNECT_ENVOY_UNIT_SRC}" >&2
    return 1
  fi
  cp "${CONNECT_ENVOY_UNIT_SRC}" /etc/systemd/system/connect-envoy@.service
  systemctl daemon-reload
}

stop_connect_sidecar() {
  local name="$1"
  systemctl stop "connect-envoy@${name}.service" 2>/dev/null || true
}

restart_connect_sidecar() {
  local name="$1"
  ensure_connect_envoy_unit_installed || return 1
  systemctl enable "connect-envoy@${name}.service"
  systemctl restart "connect-envoy@${name}.service"
}

# Deregister parent service (and its Connect sidecar) then register from an HCL file.
reregister_connect_service() {
  local name="$1"
  local hcl_file="$2"
  stop_connect_sidecar "${name}"
  consul services deregister "${name}" 2>/dev/null || true
  consul services register "${hcl_file}" || {
    rm -f "${hcl_file}"
    return 1
  }
  rm -f "${hcl_file}"
  restart_connect_sidecar "${name}"
}
