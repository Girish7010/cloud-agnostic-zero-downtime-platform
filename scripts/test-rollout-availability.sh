#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="devops-platform"
RELEASE="devops-platform"
CHECKER="traffic-checker"
CHART="./deploy/chart"
RESULTS="evidence/rollout-availability-$(date +%Y%m%d-%H%M%S).log"

mkdir -p evidence

echo "Starting Kubernetes rollout availability test..."
echo "Results file: $RESULTS"

kubectl exec -n "$NAMESPACE" "$CHECKER" -- sh -c '
i=0
success=0
failed=0

while [ "$i" -lt 60 ]; do
  i=$((i+1))

  if curl -fsS --max-time 3 \
    http://devops-platform-api:8080/healthz >/dev/null 2>&1; then
    success=$((success+1))
    echo "CHECK $i: SUCCESS"
  else
    failed=$((failed+1))
    echo "CHECK $i: FAILED"
  fi

  sleep 1
done

echo "===== FINAL RESULTS ====="
echo "Total: $i"
echo "Successful: $success"
echo "Failed: $failed"
echo "Success rate: $((success * 100 / i))%"
' > "$RESULTS" 2>&1 &

MONITOR_PID=$!

echo "Traffic monitoring started."
sleep 3

echo "Starting Helm rolling upgrade from v1 to v2..."

helm upgrade "$RELEASE" "$CHART" \
  -n "$NAMESPACE" \
  --set api.image.tag=v2 \
  --set api.appVersion=v2 \
  --wait \
  --timeout 120s

echo "Helm upgrade completed."

wait "$MONITOR_PID"

echo ""
echo "===== ROLLOUT TEST RESULTS ====="
cat "$RESULTS"
