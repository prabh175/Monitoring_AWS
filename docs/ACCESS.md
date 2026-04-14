# Access from your Mac: bastion, API Gateway, prepared queries

## Bastion (SSH into the VPC)

With **`enable_bastion = true`** in [terraform/aws](../terraform/aws), Terraform creates a small instance with a **public** IP. Only **`bastion_ssh_cidr_blocks`** (e.g. your home `/32`) may SSH to port **22** on the bastion.

```bash
# After apply
terraform -chdir=terraform/aws output bastion_public_ip

ssh -i ~/.ssh/your-key.pem ec2-user@<bastion_public_ip>
```

From the bastion, SSH to **private IPs** of kind hosts or VM-datacenter instances (same key; security groups already allow SSH from the **VPC CIDR**, which includes the bastion).

```bash
# Example: kind host
ssh -i ~/.ssh/your-key.pem ec2-user@<node_private_ip>
```

**kubectl:** run on the kind host, or copy `~/.kube/config` and use **SSH tunnel** for the API server (see kind docs) or `ProxyJump` in `~/.ssh/config`.

---

## Consul UI and HashiCups on the API Gateway public IP

Consul on Kubernetes can expose an **API Gateway** (Gateway API) with a **LoadBalancer** service. That gives you a **stable public hostname/IP** for north–south HTTP.

High-level steps (names depend on your Helm release and Gateway object):

1. Install Consul with `connectInject.apiGateway` enabled ([values-dc1.yaml](../kubernetes/helm/consul/values-dc1.yaml)).
2. Create a **Gateway** (or use the managed GatewayClass from the chart) so a **LoadBalancer** is provisioned.
3. Add **HTTPRoute** rules, for example:
   - Path prefix `/` or `/shop` → **HashiCups frontend** `Service` (port 80/3000 as deployed).
   - Path prefix `/consul-ui` or host `consul.example.com` → **Consul UI** `Service` (often HTTPS on 443; you may need TLS settings on the route).

Exact YAML varies by Consul-K8s version; use the current tutorial: [API Gateway on Kubernetes](https://developer.hashicorp.com/consul/docs/api-gateway/k8s) and align `parentRefs` / `backendRefs` with:

```bash
kubectl get svc -n consul
kubectl get gateway -A
kubectl get httproute -A
```

**VM HashiCups (dc-vm)** is **not** exposed with Consul API Gateway on the VM site in this repo. For a browser or shared demo URL, use something you control in the VPC or edge—for example **SSH local forward** to the **frontend** VM’s **:80**, an **NLB/ALB** targeting that instance, or **K8s-only** north–south if you later add HTTPRoutes that reach peered mesh services (separate exercise).

---

## Prepared queries from your laptop

The HTTP API is:

`GET /v1/query/<query-name>/execute` (and related) on Consul’s **HTTP port (8500/8501)**.

Your Mac usually **cannot** reach private `10.x` addresses directly. Practical options:

### A. SSH local port forward (simplest)

From your **Mac**, open a tunnel **via the bastion** to the **Consul server VM private IP** (Consul HTTP on `8500` with `client_addr = 0.0.0.0` in `vm/consul/server.hcl`):

```bash
ssh -N -i ~/.ssh/your-key.pem \
  -L 8500:<consul-server-private-ip>:8500 \
  -J ec2-user@<bastion_public_ip> \
  ec2-user@<consul-server-private-ip>
```

Leave that session running; on the Mac use `http://127.0.0.1:8500/`.

Optional `~/.ssh/config`:

```text
Host bastion
  HostName <bastion_public_ip>
  User ec2-user
  IdentityFile ~/.ssh/your-key.pem

Host consul-vm
  HostName <consul_server_private_ip>
  User ec2-user
  ProxyJump bastion
  IdentityFile ~/.ssh/your-key.pem
```

Then: `ssh -N -L 8500:127.0.0.1:8500 consul-vm` (Consul listens on all interfaces; loopback on the server is enough.)

Then on the Mac:

```bash
export CONSUL_HTTP_TOKEN=...
curl -s -H "X-Consul-Token: $CONSUL_HTTP_TOKEN" \
  "http://127.0.0.1:8500/v1/query/geo-hashicups/execute?near=_geo"
```

### B. Expose Consul HTTP via NLB/Ingress (demo only)

Not recommended for production: put an **internal** or **public** load balancer in front of `:8500` with tight security groups and ACL tokens.

### C. API Gateway to Consul HTTP

Possible in theory (HTTPRoute to consul-server **8500**), but you must **protect** the admin API; prefer **A** for prepared-query demos.

---

## Summary

| Goal | Approach |
|------|----------|
| SSH / kubectl | **Bastion** + jump to private IPs |
| HashiCups + Consul UI in browser | **K8s API Gateway** `LoadBalancer` + **HTTPRoute** (you define paths/backends) |
| Prepared queries / API from Mac | **SSH -L** or **ProxyJump** tunnel to Consul HTTP; then `curl` / `consul` CLI |

See also [TARGET-ARCHITECTURE.md](TARGET-ARCHITECTURE.md) for diagram vs repo.
