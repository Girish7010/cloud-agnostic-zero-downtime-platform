#!/usr/bin/env bash
# Metric-gated rolling deployment with automatic rollback (local implementation
# of the canary-analysis idea; in the cloud design Argo Rollouts does this
# against Prometheus — see gitops/rollouts/).
#
#   1. helm upgrade --wait --rollback-on-failure  -> gate 1: pods must become Ready
#      (readiness/startup probes). Failure => Helm restores previous revision.
#   2. Analysis: every INTERVAL s for STEPS steps, scrape /metrics of every new
#      API pod (real traffic counters), compute over the interval:
#        error rate  = 5xx / all non-probe requests      must be <= MAX_ERROR_RATE
#        slow ratio  = requests slower than 400 ms / all must be <= MAX_SLOW_RATIO
#      (slow ratio <= 5% <=> p95 < 400 ms). Too little traffic = inconclusive = FAIL.
#   3. Any failed step => helm rollback to the previous revision, exit 1.
#
# Usage: scripts/gated-rollout.sh [helm upgrade args...]
#   e.g. scripts/gated-rollout.sh -f deploy/environments/local.yaml --set api.appVersion=v4.1
set -euo pipefail

NS="${NS:-devops-platform}"
RELEASE="${RELEASE:-devops-platform}"
CHART="${CHART:-./deploy/chart}"
STEPS="${STEPS:-4}"
INTERVAL="${INTERVAL:-15}"
MIN_REQUESTS="${MIN_REQUESTS:-50}"
MAX_ERROR_RATE="${MAX_ERROR_RATE:-0.01}"
MAX_SLOW_RATIO="${MAX_SLOW_RATIO:-0.05}"
TIMEOUT="${TIMEOUT:-180s}"

ts() { date '+%F %T'; }
log() { echo "[$(ts)] $*"; }

prev=$(helm history "$RELEASE" -n "$NS" -o json | jq '[.[] | select(.status=="deployed")] | last | .revision')
log "Current deployed revision: $prev"

log "Gate 1 (readiness): helm upgrade --wait --rollback-on-failure --timeout $TIMEOUT"
if ! helm upgrade "$RELEASE" "$CHART" -n "$NS" --wait --rollback-on-failure --timeout "$TIMEOUT" "$@"; then
  log "GATE 1 FAILED: new pods never became Ready; Helm rolled back automatically."
  helm history "$RELEASE" -n "$NS" | tail -3
  exit 1
fi
new=$(helm history "$RELEASE" -n "$NS" -o json | jq 'last | .revision')
log "Gate 1 passed: revision $new rolled out and Ready."

# Per-pod counter snapshot as JSON {pod: [requests, errors, fast(<=0.4s), count]}.
# Deltas are computed PER POD so HPA scale-up/down during analysis (pods
# appearing/disappearing) and counter resets cannot distort the result.
sample() {
  local pods p line out="{"
  pods=$(kubectl get pods -n "$NS" -l app="$RELEASE-api" --field-selector=status.phase=Running -o name)
  for p in $pods; do
    line=$(kubectl exec -n "$NS" "$p" -c api -- python -c '
import urllib.request,re
t=e=f=c=0
for l in urllib.request.urlopen("http://127.0.0.1:8080/metrics",timeout=5).read().decode().splitlines():
    if l.startswith("#") or re.search(r"path=\"/(healthz|readyz|metrics)\"",l): continue
    v=float(l.rsplit(" ",1)[1])
    if l.startswith("http_requests_total{"):
        t+=v; e+=v if re.search(r"status=\"5\d\d\"",l) else 0
    elif l.startswith("http_request_duration_seconds_bucket{") and "le=\"0.4\"" in l: f+=v
    elif l.startswith("http_request_duration_seconds_count{"): c+=v
print(int(t),int(e),int(f),int(c))' 2>/dev/null) || continue
    out+="\"${p#pod/}\": [${line// /,}],"
  done
  echo "${out%,}}"
}

before=$(sample)
for step in $(seq 1 "$STEPS"); do
  sleep "$INTERVAL"
  after=$(sample)
  verdict=$(python3 - "$before" "$after" "$MIN_REQUESTS" "$MAX_ERROR_RATE" "$MAX_SLOW_RATIO" <<'PY'
import json,sys
b,a=json.loads(sys.argv[1]),json.loads(sys.argv[2]); mn=int(sys.argv[3]); maxe,maxs=map(float,sys.argv[4:6])
d=[0,0,0,0]
for pod,cur in a.items():
    prev=b.get(pod,[0,0,0,0])
    if cur[0] < prev[0]: prev=[0,0,0,0]   # counter reset (container restart)
    d=[x+(c-p) for x,c,p in zip(d,cur,prev)]
dt,de,df,dc=d
if dt < mn: print(f"FAIL inconclusive: only {dt} requests (< {mn}) across {len(a)} pods"); sys.exit()
er=de/dt; slow=(dc-df)/dc if dc else 0
ok = er<=maxe and slow<=maxs
print(f"{'PASS' if ok else 'FAIL'} pods={len(a)} requests={dt} errors={de} error_rate={er:.4f} (max {maxe}) slow_ratio={slow:.4f} (max {maxs})")
PY
)
  log "Analysis step $step/$STEPS: $verdict"
  if [[ "$verdict" == FAIL* ]]; then
    log "GATE 2 FAILED: rolling back revision $new -> $prev"
    helm rollback "$RELEASE" "$prev" -n "$NS" --wait --timeout "$TIMEOUT"
    log "Rollback complete."
    helm history "$RELEASE" -n "$NS" | tail -3
    exit 1
  fi
  before=$after
done
log "ALL GATES PASSED: revision $new promoted."
