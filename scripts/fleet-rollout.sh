#!/usr/bin/env bash
# Ring-based fleet rollout with halt-on-failure.
# For each ring in gitops/fleet.yaml, each tenant is upgraded through
# scripts/gated-rollout.sh while light in-cluster traffic runs against it.
# The first failed gate (which itself rolls that tenant back) HALTS the fleet:
# later rings are never touched.
# Usage: scripts/fleet-rollout.sh <helm args for the new release...>
set -uo pipefail
IMAGE_VALUES="${IMAGE_VALUES:-deploy/environments/local.yaml}"
TENANT_RATE="${TENANT_RATE:-30}"
mapfile -t ORDER < <(python3 -c '
import yaml
for r in yaml.safe_load(open("gitops/fleet.yaml"))["rings"]:
    for t in r["tenants"]: print(r["ring"], t)')
echo "== fleet rollout started $(date '+%F %T %Z'); order: ${ORDER[*]}"
for entry in "${ORDER[@]}"; do
  read -r RING ID <<<"$entry"; FILE="gitops/tenants/$ID/values.yaml"
  read -r NS RELEASE < <(python3 -c "import yaml;p=yaml.safe_load(open('$FILE'))['platform'];print(p['namespace'],p['release'])")
  echo; echo "===== ring $RING tenant $ID ($NS/$RELEASE) $(date +%T)"
  NS=$NS scripts/k6-incluster.sh "k6-fleet-$ID" "/tmp/k6-fleet-$ID.txt" PROFILE=constant RATE="$TENANT_RATE" DURATION=150s \
    BASE_URL="http://$RELEASE-api:8080" MAX_FAIL_RATE=1 > "/tmp/k6-fleet-$ID.json" & K6=$!
  sleep 10
  if NS=$NS RELEASE=$RELEASE STEPS="${STEPS:-2}" MIN_REQUESTS="${MIN_REQUESTS:-100}" \
       scripts/gated-rollout.sh -f "$IMAGE_VALUES" -f "$FILE" "$@"; then
    echo "ring $RING tenant $ID: PASSED"
    kill "$K6" 2>/dev/null; kubectl delete pod -n "$NS" "k6-fleet-$ID" --wait=false >/dev/null 2>&1
  else
    echo "ring $RING tenant $ID: FAILED -> HALTING FLEET ROLLOUT; remaining rings untouched"
    kill "$K6" 2>/dev/null; kubectl delete pod -n "$NS" "k6-fleet-$ID" --wait=false >/dev/null 2>&1
    echo "== fleet rollout HALTED $(date '+%F %T %Z')"; exit 1
  fi
done
echo "== fleet rollout COMPLETED $(date '+%F %T %Z')"
