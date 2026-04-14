# Cluster peering (manual steps)

1. On **dc1**, create an acceptor (adjust namespace to your Consul install namespace):

```bash
kubectl apply -f peering-acceptor-dc1.yaml
kubectl get secret -n consul peering-token-dc2 -o yaml > peering-token-dc2.export.yaml
# Edit: change namespace if importing into another cluster; strip resourceVersion/uid.
```

2. On **dc2**, apply the exported secret, then the dialer:

```bash
kubectl apply -f peering-token-dc2.export.yaml
kubectl apply -f peering-dialer-dc2.yaml
```

3. Export services from each peer with `ExportedServices` CRs so the remote mesh can resolve them.

4. For **VMs ↔ Kubernetes**, generate an acceptor on K8s (or VM), exchange the peering token, and dial from the other side using the CR on K8s and equivalent peering stanza on VM agents (Consul 1.14+ peering from agents—confirm version-specific docs).

Official guide: [Cluster peering on Kubernetes](https://developer.hashicorp.com/consul/docs/connect/cluster-peering/k8s).
