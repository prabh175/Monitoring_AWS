#!/usr/bin/env bash
# onboard-team.sh — Run once per new team to give them a self-service monitoring experience.
#
# WHAT THIS DOES:
#   1. Creates the team namespace with a `team` label (used by Prometheus for the `team` metric label)
#   2. Creates RBAC so the team can deploy their apps
#   3. Creates a Grafana folder for the team (via Grafana API)
#   4. Creates a Grafana service account for the team with Editor role on their folder
#   5. Drops an example alert rules ConfigMap template into the team namespace
#   6. Prints a "getting started" summary for the team
#
# USAGE:
#   export GRAFANA_URL=http://<grafana-nlb-dns>
#   export GRAFANA_ADMIN_PASSWORD=changeme
#   ./monitoring/scripts/onboard-team.sh <team-name>
#
# EXAMPLE:
#   ./monitoring/scripts/onboard-team.sh payments-team

set -euo pipefail

TEAM="${1:-}"
if [[ -z "$TEAM" ]]; then
  echo "Usage: $0 <team-name>" >&2
  exit 1
fi

NAMESPACE="${TEAM}"
GRAFANA_URL="${GRAFANA_URL:-http://localhost:3000}"
GRAFANA_USER="${GRAFANA_ADMIN_USER:-admin}"
GRAFANA_PASS="${GRAFANA_ADMIN_PASSWORD:-changeme}"
MONITORING_NS="monitoring"

echo ""
echo "=== Onboarding team: $TEAM ==="
echo ""

# ----------------------------------------------------------------
# 1. Create namespace with team label
# ----------------------------------------------------------------
echo "1. Creating namespace: $NAMESPACE"
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml \
  | kubectl label --local -f - "team=$TEAM" --dry-run=client -o yaml \
  | kubectl apply -f -

kubectl label namespace "$NAMESPACE" "team=$TEAM" --overwrite
echo "   ✓ Namespace $NAMESPACE created with label team=$TEAM"

# ----------------------------------------------------------------
# 2. RBAC — team can deploy workloads in their namespace
# ----------------------------------------------------------------
echo "2. Creating RBAC for team $TEAM"
kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ${TEAM}-deployer
  namespace: ${NAMESPACE}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: edit
subjects:
  - kind: Group
    name: ${TEAM}
    apiGroup: rbac.authorization.k8s.io
EOF
echo "   ✓ RoleBinding ${TEAM}-deployer created in namespace $NAMESPACE"

# ----------------------------------------------------------------
# 3. Create Grafana folder via API
# ----------------------------------------------------------------
echo "3. Creating Grafana folder for team $TEAM"
FOLDER_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST "$GRAFANA_URL/api/folders" \
  -H "Content-Type: application/json" \
  -u "$GRAFANA_USER:$GRAFANA_PASS" \
  -d "{\"uid\": \"team-${TEAM}\", \"title\": \"Team: ${TEAM}\"}")

if [[ "$FOLDER_RESPONSE" == "200" || "$FOLDER_RESPONSE" == "409" ]]; then
  echo "   ✓ Grafana folder 'Team: ${TEAM}' ready"
else
  echo "   ⚠ Grafana folder creation returned HTTP $FOLDER_RESPONSE — check Grafana URL and credentials"
fi

# ----------------------------------------------------------------
# 4. Create Grafana service account for team (Editor on their folder)
# ----------------------------------------------------------------
echo "4. Creating Grafana service account for team $TEAM"
SA_RESPONSE=$(curl -s \
  -X POST "$GRAFANA_URL/api/serviceaccounts" \
  -H "Content-Type: application/json" \
  -u "$GRAFANA_USER:$GRAFANA_PASS" \
  -d "{\"name\": \"${TEAM}\", \"role\": \"Viewer\"}")
SA_ID=$(echo "$SA_RESPONSE" | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2)

if [[ -n "$SA_ID" ]]; then
  # Grant Editor permission on the team folder
  FOLDER_UID="team-${TEAM}"
  curl -s -X POST "$GRAFANA_URL/api/folders/${FOLDER_UID}/permissions" \
    -H "Content-Type: application/json" \
    -u "$GRAFANA_USER:$GRAFANA_PASS" \
    -d "{\"items\": [{\"userId\": ${SA_ID}, \"permission\": 2}]}" > /dev/null

  # Create and print a token for the team
  TOKEN_RESPONSE=$(curl -s \
    -X POST "$GRAFANA_URL/api/serviceaccounts/${SA_ID}/tokens" \
    -H "Content-Type: application/json" \
    -u "$GRAFANA_USER:$GRAFANA_PASS" \
    -d "{\"name\": \"${TEAM}-token\"}")
  GRAFANA_TOKEN=$(echo "$TOKEN_RESPONSE" | grep -o '"key":"[^"]*"' | cut -d'"' -f4)
  echo "   ✓ Grafana service account created (Editor on Team: ${TEAM} folder)"
  echo "   ✓ Grafana token: $GRAFANA_TOKEN  ← share with team, store in their Secret"
else
  echo "   ⚠ Grafana service account creation failed — check response: $SA_RESPONSE"
fi

# ----------------------------------------------------------------
# 5. Drop example alert rules ConfigMap into team namespace
# ----------------------------------------------------------------
echo "5. Creating example alert rules ConfigMap in namespace $NAMESPACE"
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${TEAM}-alert-rules
  namespace: ${NAMESPACE}
  labels:
    # This label triggers the rule-merger CronJob — rules go live in ~60s
    monitoring/rules: "true"
  annotations:
    monitoring/team: "${TEAM}"
data:
  rules.yaml: |
    groups:
      - name: ${TEAM}.example
        rules:
          - alert: ${TEAM^}ServiceDown
            # Replace 'my-service' with your actual service name
            expr: up{namespace="${NAMESPACE}", app="my-service"} == 0
            for: 1m
            labels:
              severity: warning
              team: ${TEAM}
            annotations:
              summary: "{{ \$labels.app }} in namespace ${NAMESPACE} is down"
              description: "Pod {{ \$labels.pod }} has been down for more than 1 minute."
EOF
echo "   ✓ Example alert rules ConfigMap created — edit and apply your own rules"

# ----------------------------------------------------------------
# 6. Print getting started summary
# ----------------------------------------------------------------
echo ""
echo "========================================================="
echo " Team $TEAM onboarded successfully!"
echo "========================================================="
echo ""
echo " METRICS (auto-discovered — no ticket needed):"
echo "   Add to your pod spec:"
echo "     annotations:"
echo "       prometheus.io/scrape: \"true\""
echo "       prometheus.io/port: \"8080\"   # your metrics port"
echo "   → Prometheus discovers your pod within 15 seconds"
echo ""
echo " CONSUL SERVICE MESH:"
echo "   Add to your pod spec:"
echo "     annotations:"
echo "       consul.hashicorp.com/connect-inject: \"true\""
echo "   → Envoy sidecar metrics auto-scraped on port 20100"
echo ""
echo " ALERT RULES (live in ~60s):"
echo "   Edit: kubectl edit configmap ${TEAM}-alert-rules -n ${NAMESPACE}"
echo "   The rule-merger CronJob syncs to Prometheus automatically"
echo ""
echo " GRAFANA:"
echo "   URL:    $GRAFANA_URL"
echo "   Folder: Team: ${TEAM}  (you have Editor access)"
if [[ -n "${GRAFANA_TOKEN:-}" ]]; then
echo "   Token:  $GRAFANA_TOKEN"
fi
echo ""
echo " LOGS (Loki — no setup needed):"
echo "   Query: {namespace=\"${NAMESPACE}\"}"
echo "========================================================="
