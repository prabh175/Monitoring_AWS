#!/usr/bin/env bash
# Create or update the consul-enterprise-license secret in Kubernetes.
# Usage:
#   export CONSUL_LICENSE_FILE=/path/to/license.hclic
#   ./scripts/k8s-consul-license-secret.sh
# Or: ./scripts/k8s-consul-license-secret.sh /path/to/license.hclic

set -euo pipefail
NS="${CONSUL_NAMESPACE:-consul}"
FILE="${CONSUL_LICENSE_FILE:-${1:-}}"
if [[ -z "${FILE}" || ! -f "${FILE}" ]]; then
  echo "Set CONSUL_LICENSE_FILE or pass path to .hclic as first argument." >&2
  exit 1
fi

kubectl create secret generic consul-enterprise-license \
  --from-file=key="${FILE}" \
  -n "${NS}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Secret consul-enterprise-license applied in namespace ${NS}."
