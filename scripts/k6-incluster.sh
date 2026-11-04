#!/usr/bin/env bash
# Run a k6 script as a Pod inside the cluster (traffic goes through the
# ClusterIP Service exactly like real in-cluster clients; no port-forward).
# Usage: scripts/k6-incluster.sh <pod-name> <log-file> [ENV=VALUE ...]
set -euo pipefail
NS="${NS:-devops-platform}"
SCRIPT="${SCRIPT:-tests/load/platform.js}"
K6_IMAGE="${K6_IMAGE:-localhost:5001/k6:2.3.0}"
POD="$1"; LOG="$2"; shift 2

kubectl -n "$NS" create configmap k6-script --from-file=script.js="$SCRIPT" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null

env_json="[]"
for kv in "$@"; do
  env_json=$(jq -c --arg k "${kv%%=*}" --arg v "${kv#*=}" '. + [{name:$k,value:$v}]' <<<"$env_json")
done

kubectl -n "$NS" delete pod "$POD" --ignore-not-found --wait=true >/dev/null
kubectl -n "$NS" apply -f - >/dev/null <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: $POD
  labels: { app: k6-load }
spec:
  restartPolicy: Never
  containers:
    - name: k6
      image: $K6_IMAGE
      args: ["run", "--no-color", "/scripts/script.js"]
      env: $env_json
      resources:
        requests: { cpu: 200m, memory: 64Mi }
        limits: { cpu: "1", memory: 384Mi }
      volumeMounts: [{ name: s, mountPath: /scripts }]
  volumes: [{ name: s, configMap: { name: k6-script } }]
YAML
kubectl -n "$NS" wait --for=condition=Ready pod/"$POD" --timeout=60s >/dev/null || true
kubectl -n "$NS" logs -f "$POD" > "$LOG" 2>&1 || true
# Wait until the pod has terminated and record its exit code.
for _ in $(seq 1 30); do
  phase=$(kubectl -n "$NS" get pod "$POD" -o jsonpath='{.status.phase}')
  [ "$phase" = Succeeded ] || [ "$phase" = Failed ] && break
  sleep 2
done
code=$(kubectl -n "$NS" get pod "$POD" -o jsonpath='{.status.containerStatuses[0].state.terminated.exitCode}')
echo "k6 pod $POD phase=$phase exitCode=$code" >> "$LOG"
grep '^K6_SUMMARY_JSON' "$LOG" | sed 's/^K6_SUMMARY_JSON //' || true
