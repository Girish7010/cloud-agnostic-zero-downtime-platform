#!/usr/bin/env bash
# Samples autoscaling state every INTERVAL seconds until killed:
# time, API replicas/CPU (HPA), worker replicas, Redis stream lag and pending.
NS="${NS:-devops-platform}"; RELEASE="${RELEASE:-devops-platform}"; INTERVAL="${INTERVAL:-5}"
echo "time api_replicas api_cpu_vs_target worker_replicas queue_lag queue_pending"
while true; do
  hpa=$(kubectl get hpa "$RELEASE-api" -n "$NS" --no-headers 2>/dev/null | awk '{print $3"_"$4}')
  api=$(kubectl get deploy "$RELEASE-api" -n "$NS" -o jsonpath='{.status.readyReplicas}')
  wrk=$(kubectl get deploy "$RELEASE-worker" -n "$NS" -o jsonpath='{.status.readyReplicas}')
  q=$(kubectl exec -n "$NS" deploy/"$RELEASE"-redis -- redis-cli XINFO GROUPS jobs 2>/dev/null | awk 'p=="lag"{lag=$0} p=="pending"{pen=$0} {p=$0} END{print lag, pen}')
  echo "$(date +%T) ${api:-0} $hpa ${wrk:-0} $q"
  sleep "$INTERVAL"
done
