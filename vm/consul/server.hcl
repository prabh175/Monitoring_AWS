# Consul server (single-node control plane) — Enterprise demo
# 1) Copy to /etc/consul.d/server.hcl on the consul-server VM.
# 2) Replace REPLACE_WITH_PRIVATE_IP with this host's VPC private IP (terraform output).
# 3) Place license at /etc/consul.d/license.hclic (Enterprise) or use OSS binary and remove license_path.

datacenter = "dc-vm"
data_dir   = "/opt/consul/data"
node_name  = "consul-server-1"

server           = true
bootstrap_expect = 1

bind_addr   = "0.0.0.0"
client_addr = "0.0.0.0"
advertise_addr = "REPLACE_WITH_PRIVATE_IP"

ui_config {
  enabled = true
}

# Connect service mesh (required for mesh gateway and peering to Kubernetes peers)
connect {
  enabled = true
}

ports {
  grpc = 8502
}

# Prometheus-friendly agent metrics (scrape needs ACL token if ACLs enabled)
telemetry {
  prometheus_retention_time = "60s"
  disable_hostname          = true
}

# Enterprise only: place license file on server and uncomment.
# license_path = "/etc/consul.d/license.hclic"

# Optional: ACLs + TLS for Consul RPC (Helm enables both on K8s). See:
#   vm/consul/security/README.md and vm/consul/security/*.example
# acl { ... } and tls { ... } blocks are shipped there for merge into /etc/consul.d/

# Optional: audit logging (Enterprise) — see https://developer.hashicorp.com/consul/docs/monitor/log/audit
# audit {
#   sink "stdout" {
#     type   = "file"
#     format = "json"
#     path   = "/dev/stdout"
#   }
# }

log_level = "INFO"
