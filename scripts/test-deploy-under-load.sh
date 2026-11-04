#!/usr/bin/env bash
# Evidence test: run in-cluster k6 load while a metric-gated rollout happens.
# Usage: scripts/test-deploy-under-load.sh <name> <k6-env...> -- <gated-rollout args...>
#   OUT_DIR (default evidence/submission-2026-11-04/<name>)
#   ROLLOUT_DELAY seconds of load before the rollout starts (default 25)
set -uo pipefail
NS="${NS:-devops-platform}"; RELEASE="${RELEASE:-devops-platform}"
NAME="$1"; shift
K6ENV=(); while [ $# -gt 0 ] && [ "$1" != "--" ]; do K6ENV+=("$1"); shift; done; shift || true
OUT="${OUT_DIR:-evidence/submission-2026-11-04/$NAME}"; mkdir -p "$OUT"
echo "== $NAME started $(date '+%F %T %Z')"; echo "k6 env: ${K6ENV[*]}"; echo "rollout args: $*"
echo "memory before:"; free -h | sed -n 1,3p
helm history "$RELEASE" -n "$NS" | tail -2

# Background observers: pod lifecycle and ready-endpoint count each second.
kubectl get pods -n "$NS" -l "app=$RELEASE-api" -w --output-watch-events > "$OUT/pod-watch.txt" 2>&1 & W1=$!
( while true; do printf '%s ready_endpoints=%s\n' "$(date +%T)" \
    "$(kubectl get endpointslices -n "$NS" -l kubernetes.io/service-name="$RELEASE-api" -o json | jq '[.items[].endpoints[]? | select(.conditions.ready)] | length')"; sleep 1; done ) > "$OUT/endpoints.txt" 2>&1 & W2=$!

scripts/k6-incluster.sh "k6-$NAME" "$OUT/k6.txt" "${K6ENV[@]}" > "$OUT/k6-summary.json" & K6=$!
sleep "${ROLLOUT_DELAY:-25}"
echo "== rollout starting $(date +%T)"
scripts/gated-rollout.sh "$@" 2>&1 | tee "$OUT/rollout.txt"; RC=${PIPESTATUS[0]}
echo "== rollout finished $(date +%T) exit=$RC"
wait "$K6"; kill "$W1" "$W2" 2>/dev/null
echo "== k6 summary:"; cat "$OUT/k6-summary.json"
echo "== k6 checks:"; grep -E '✓|✗|checks|http_req_failed|http_reqs|thresholds' "$OUT/k6.txt" | head -20
echo "== min ready endpoints during test: $(awk -F= '{print $2}' "$OUT/endpoints.txt" | sort -n | head -1)"
helm history "$RELEASE" -n "$NS" | tail -3
kubectl get deploy -n "$NS" -o custom-columns=NAME:.metadata.name,IMAGE:.spec.template.spec.containers[0].image,READY:.status.readyReplicas
echo "memory after:"; free -h | sed -n 2,3p
echo "== $NAME finished $(date '+%F %T %Z')"
exit "$RC"
