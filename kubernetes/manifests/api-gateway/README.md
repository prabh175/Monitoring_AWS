# Consul API Gateway (public HTTP to HashiCups + Consul UI)

**Scope:** **Kubernetes clusters only.** This repo does **not** deploy Consul API Gateway on the VM datacenter; see [docs/ACCESS.md](../../../docs/ACCESS.md) for VM browser/LB options.

Helm values enable the managed GatewayClass (`connectInject.apiGateway.managedGatewayClass.serviceType: LoadBalancer`). After install, create **Gateway API** objects so the cloud LB has routes.

## Goals

- **HashiCups** at path `/` or host `app.example.com`
- **Consul UI** at `/ui` or a dedicated host (often HTTPS to the `consul-ui` Service)

Exact `Gateway`, `HTTPRoute`, and TLS fields depend on your Consul-K8s chart version. Use the official guide and copy `parentRefs` / service names from your cluster:

```bash
kubectl get svc -n consul
kubectl get gateway -A
kubectl api-resources | grep -i gateway
```

## References

- [API Gateway on Kubernetes](https://developer.hashicorp.com/consul/docs/api-gateway/k8s)
- [Route configuration](https://developer.hashicorp.com/consul/docs/api-gateway/k8s/route)

## Note

Publishing **Consul’s full HTTP API** (prepared queries, ACL admin) through a public API Gateway is risky; prefer **SSH port-forward** for API demos ([docs/ACCESS.md](../../../docs/ACCESS.md)).
