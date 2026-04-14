# Security posture: Kubernetes datacenters vs VM datacenter

This page answers **service mesh**, **Consul TLS**, **ACLs**, and **service mTLS** for the three datacenters in this repo: **dc1**, **dc2** (Helm on Kubernetes), and **dc-vm** (VMs).

## Summary matrix

| Capability | dc1 / dc2 (Helm `values-*.yaml`) | dc-vm (`vm/consul/*.hcl` + scripts) |
|------------|-----------------------------------|-------------------------------------|
| **Service mesh (Connect)** | **Yes** — `connectInject.enabled: true` injects **consul-dataplane / Envoy** for eligible pods. **`transparentProxy.defaultEnabled: true`** (explicit in `values-dc*.yaml`) sends pod traffic through Envoy without app rewrites to `localhost` ports; probes are rewritten when **`defaultOverwriteProbes: true`**. | **Yes** (HashiCups path) — each `on-*.sh` registers **`connect.sidecar_service`** and **`connect-envoy@<service>.service`** runs **`consul connect envoy -sidecar-for <name>`**. There is **no** Kubernetes-style transparent proxy on Docker bridge; apps use **`host.docker.internal` + `local_bind`** ports instead. |
| **mTLS between services** | **Yes** for workloads that use Connect (injected sidecars; L7/L4 per config). | **Yes** between VM HashiCups services once sidecars run; east-west uses **local_bind** ports on the host, reached from containers via **`host.docker.internal`** (see `vm/hashicups/scripts/lib.sh`). |
| **TLS for Consul (servers / agents)** | **Yes** — `global.tls.enabled: true` (Helm-managed certs). `httpsOnly: false` still allows HTTP on 8500 for some flows; tighten in production. | **Not in base `server.hcl` / `client.hcl`** — RPC is plain by default. For parity, merge files from **`vm/consul/security/`** after running the TLS bootstrap (see that README). |
| **ACLs** | **Yes** — `global.acls.manageSystemACLs: true` (Helm bootstraps tokens and component ACLs). | **Not in base configs** — ACL block is commented in `server.hcl`. Optional merge + bootstrap in **`vm/consul/security/`**. |

## Kubernetes (dc1 / dc2)

From `kubernetes/helm/consul/values-dc1.yaml` and `values-dc2.yaml`:

- **`connectInject.enabled: true`** — the data plane is injected so pod traffic can use the mesh (mTLS, intentions, etc.) per annotations and CRDs.
- **`global.tls.enabled: true`** — Consul server and client communication uses the chart’s TLS material.
- **`global.acls.manageSystemACLs: true`** — ACL system is on and the chart manages bootstrap and component tokens.

Workloads **without** injection or **without** Connect remain **outside** the mesh for their traffic (plain cluster networking).

## VMs (dc-vm)

- **Connect** is **`connect { enabled = true }`** on server and clients (`server.hcl`, `client.hcl`); the **mesh gateway** uses **`consul connect envoy -gateway=mesh`**.
- **HashiCups** uses **explicit** service registration with **`sidecar_service`** and a **systemd** sidecar unit (`vm/hashicups/systemd/connect-envoy@.service`). This is **not** transparent proxy; apps use **explicit upstream URLs** pointing at **`host.docker.internal:<local_bind_port>`** so bridge-network containers reach the host’s Envoy listeners.

### Optional: VM TLS + ACL parity with Helm

Helm turns on **TLS** and **ACLs** by default for K8s. To approximate that on **dc-vm**, use **`vm/consul/security/README.md`**: generate CA and node certs, merge the supplied `*.hcl` snippets **before** the first `systemctl start consul`, and set **`CONSUL_HTTP_TOKEN`** in **`/etc/consul.d/consul.env`** for **`connect-envoy@`**, **mesh-gateway**, and the **`consul` CLI** when registering services.

With **ACL default deny** (Helm-style), you must add **policies** (and often **service intentions**) for DNS, health checks, and Connect—see HashiCorp docs. The security README describes a **lab-friendly** starting point.

## Cross-cluster note

Peering and mesh gateways assume compatible **CA trust** and **ACL/token** behavior across peers. Mixing **ACL-enabled K8s** clusters with a **non-ACL dc-vm** is possible for early demos but is **not** a full enterprise posture; align ACLs and TLS when you harden the lab.
