# dnsmasq bridge (Consul DNS on port 53)

When **`enable_consul_dns_bridge`** is true in **`terraform/vm-datacenter`**, the Consul **server** instance’s `user_data` installs **dnsmasq** so you can run:

```bash
dig @dc-vm.<your-zone> -p 53 frontend.service.consul
# or @<consul-server-private-ip>
```

Traffic is forwarded to **Consul agent DNS** on **`127.0.0.1:8600`**. The security group allows **UDP/TCP 53** from the **VPC CIDR** to all instances in the VM datacenter SG (only the Consul server listens).

## Config reference

The generated file is equivalent to:

```conf
bind-interfaces
listen-address=0.0.0.0
no-resolv
cache-size=0
server=/consul/127.0.0.1#8600
```

## Manual install (if you disabled the Terraform hook)

```bash
sudo dnf install -y dnsmasq
sudo tee /etc/dnsmasq.d/10-consul-bridge.conf >/dev/null <<'CFG'
bind-interfaces
listen-address=0.0.0.0
no-resolv
cache-size=0
server=/consul/127.0.0.1#8600
CFG
sudo systemctl enable --now dnsmasq
```

## Notes

- **Consul must be running** on the server before answers return (port **8600**).
- **Prepared queries** in DNS form use **`*.query.consul`** (and related); **HTTP** execution does not use this bridge: **`https://dc-vm.<zone>:8500/v1/query/...`**
- To turn the bridge off, set **`enable_consul_dns_bridge = false`** and re-apply (remove dnsmasq on the instance by hand if already provisioned).
