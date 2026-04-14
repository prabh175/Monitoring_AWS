# Consul client — run on each HashiCups VM (and optionally tune the same on the server for local services)
# 1) Copy to /etc/consul.d/client.hcl
# 2) Replace REPLACE_WITH_PRIVATE_IP with THIS host's private IP.
# 3) Replace REPLACE_CONSUL_SERVER_IP with the consul-server VM private IP.

datacenter = "dc-vm"
data_dir   = "/opt/consul/data"
node_name  = "REPLACE_NODE_NAME"

server = false

bind_addr   = "0.0.0.0"
client_addr = "0.0.0.0"
advertise_addr = "REPLACE_WITH_PRIVATE_IP"

retry_join = ["REPLACE_CONSUL_SERVER_IP"]

connect {
  enabled = true
}

ports {
  grpc = 8502
}

telemetry {
  prometheus_retention_time = "60s"
  disable_hostname          = true
}

log_level = "INFO"

# Optional: merge TLS + ACL snippets from vm/consul/security/*.example for parity with Helm (see docs/SECURITY.md).
