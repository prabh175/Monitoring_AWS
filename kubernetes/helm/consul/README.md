# Consul on Kubernetes (Helm)

Install the official chart from HashiCorp (pin chart version to match `consul-k8s-control-plane` 1.8.x):

```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update
kubectl create namespace consul
export CONSUL_LICENSE_FILE=/absolute/path/to/license.hclic   # do not commit
../../../scripts/k8s-consul-license-secret.sh
```

**Image pull:** Enterprise UBI images require registry credentials. Create `imagePullSecrets` and reference them in values (`global.imagePullSecrets`).

**Per cluster:**

```bash
export KUBECONFIG=~/.kube/kind-dc1
helm upgrade --install consul hashicorp/consul -n consul -f values-dc1.yaml
```

Repeat with `kind-dc2` and `values-dc2.yaml`.

**OpenShift:** add `global.openshift.enabled: true` (and any SCC-related settings from the Consul on OpenShift guide). Replace `gp2` / kind storage classes with your platform default.

**Prometheus URL in Consul UI:** after installing kube-prometheus-stack, run `kubectl get svc -n monitoring` and set `ui.metrics.baseURL` to the in-cluster Prometheus URL (often includes release name).

**Security (mesh, TLS, ACLs):** `values-dc*.yaml` set **`connectInject.enabled`**, **`global.tls.enabled`**, and **`global.acls.manageSystemACLs`**. See [docs/SECURITY.md](../../../docs/SECURITY.md) for how that compares to **dc-vm**.
