#!/usr/bin/env bash
# Onboard a dedicated tenant from its single reviewed file:
#   gitops/tenants/<id>/values.yaml
# Steps: policy checks (residency/region, mode) -> namespace with isolation
# labels, ResourceQuota, LimitRange -> helm install from the shared template ->
# smoke test. Prints total elapsed time (target: < 30 minutes).
# Usage: scripts/onboard-tenant.sh <tenant-id>    (IMAGE_VALUES=deploy/environments/local.yaml)
set -euo pipefail
ID="$1"; FILE="gitops/tenants/$ID/values.yaml"
IMAGE_VALUES="${IMAGE_VALUES:-deploy/environments/local.yaml}"
T0=$(date +%s); echo "== onboarding $ID started $(date '+%F %T %Z')"
[ -f "$FILE" ] || { echo "missing $FILE"; exit 1; }

read -r NS RELEASE MODE RES REGION < <(python3 - "$FILE" <<'PY'
import sys,yaml
d=yaml.safe_load(open(sys.argv[1])); t=d["tenant"]; p=d["platform"]
print(p["namespace"], p["release"], t["mode"], t["residency"], t["region"])
PY
)
echo "namespace=$NS release=$RELEASE mode=$MODE residency=$RES region=$REGION"

# Policy gate (same rule as the Terraform residency validation).
case "$MODE" in shared|dedicated) ;; *) echo "POLICY FAIL: mode must be shared|dedicated"; exit 1;; esac
case "$RES:$REGION" in
  eu:eu-*|us:us-*) echo "POLICY PASS: residency $RES allows region $REGION";;
  *) echo "POLICY FAIL: residency $RES does not allow region $REGION"; exit 1;;
esac

kubectl apply -f - <<YAML
apiVersion: v1
kind: Namespace
metadata:
  name: $NS
  labels:
    platform.io/tenant: "$ID"
    platform.io/deployment-mode: "$MODE"
    platform.io/data-residency: "$RES"
    pod-security.kubernetes.io/enforce: baseline
    pod-security.kubernetes.io/warn: restricted
---
apiVersion: v1
kind: ResourceQuota
metadata: { name: tenant-quota, namespace: $NS }
spec:
  hard: { requests.cpu: "2", requests.memory: 2Gi, limits.cpu: "4", limits.memory: 4Gi, pods: "20" }
---
apiVersion: v1
kind: LimitRange
metadata: { name: tenant-defaults, namespace: $NS }
spec:
  limits:
    - type: Container
      default: { cpu: 300m, memory: 256Mi }
      defaultRequest: { cpu: 50m, memory: 64Mi }
YAML

helm upgrade --install "$RELEASE" ./deploy/chart -n "$NS" -f "$IMAGE_VALUES" -f "$FILE" --wait --timeout 180s
kubectl exec -n "$NS" deploy/"$RELEASE"-api -c api -- python -c "
import urllib.request as u
for p in ('/healthz','/readyz','/version'): print(p, u.urlopen('http://127.0.0.1:8080'+p).read().decode())"
kubectl get pods -n "$NS" -L platform.io/tenant,platform.io/data-residency
T1=$(date +%s); echo "== onboarding $ID finished $(date '+%F %T %Z') elapsed=$((T1-T0))s"
