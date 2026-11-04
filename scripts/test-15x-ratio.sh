#!/usr/bin/env bash
# Evidence test: 15x RATIO ramp on the local cluster (BASE_RATE -> 15x -> BASE)
# with API HPA + KEDA queue-depth worker scaling, then scale-in, then verify
# every accepted job was processed (no job dropped during scale-down).
# NOTE: BASE_RATE=10 gives 150 rps peak — 15x of a local baseline, NOT the
# assignment's 2,250 rps (needs cloud capacity; see docs/capacity-plan.md).
set -uo pipefail
NS="${NS:-devops-platform}"; RELEASE="${RELEASE:-devops-platform}"
BASE_RATE="${BASE_RATE:-10}"; JOB_EVERY="${JOB_EVERY:-30}"
OUT="${OUT_DIR:-evidence/submission-2026-11-04/load-15x-ratio}"; mkdir -p "$OUT"
PREFIX="ramp-$(date +%H%M%S)"
rcli() { kubectl exec -n "$NS" deploy/"$RELEASE"-redis -- redis-cli "$@"; }
echo "== 15x ratio test started $(date '+%F %T %Z') base=${BASE_RATE}rps peak=$((BASE_RATE*15))rps job_every=$JOB_EVERY prefix=$PREFIX"
free -h | sed -n 1,3p
scripts/observe-scaling.sh > "$OUT/scaling-timeline.txt" 2>&1 & OBS=$!
T0=$(date +%s)
scripts/k6-incluster.sh "k6-15x" "$OUT/k6.txt" PROFILE=ramp15x BASE_RATE="$BASE_RATE" JOB_EVERY="$JOB_EVERY" JOB_PREFIX="$PREFIX" > "$OUT/k6-summary.json"
echo "== load finished after $(( $(date +%s) - T0 ))s: $(cat "$OUT/k6-summary.json")"
accepted=$(jq .jobs_accepted "$OUT/k6-summary.json")
echo "== waiting for queue drain and scale-in (worker -> 1, api -> 2), max 12 min"
for _ in $(seq 1 144); do
  w=$(kubectl get deploy "$RELEASE-worker" -n "$NS" -o jsonpath='{.status.readyReplicas}')
  a=$(kubectl get deploy "$RELEASE-api" -n "$NS" -o jsonpath='{.status.replicas}')
  lag=$(rcli XINFO GROUPS jobs | awk 'p=="lag"{print; exit} {p=$0}')
  [ "$w" = 1 ] && [ "$a" = 2 ] && [ "$lag" = 0 ] && break; sleep 5
done
kill "$OBS" 2>/dev/null
done_count=$(rcli --scan --pattern "job:done:$PREFIX-*" | wc -l)
pending=$(rcli XPENDING jobs job-workers | head -1)
echo "== verification $(date +%T)"
echo "jobs accepted by API (k6 202s): $accepted"
echo "jobs with completion marker:    $done_count"
echo "stream lag: $lag   pending (unacked): $pending"
echo "peak api replicas: $(awk 'NR>1{print $2}' "$OUT/scaling-timeline.txt" | sort -n | tail -1)  peak worker replicas: $(awk 'NR>1{print $4}' "$OUT/scaling-timeline.txt" | sort -n | tail -1)"
echo "first sample api>2: $(awk 'NR>1 && $2>2{print $1; exit}' "$OUT/scaling-timeline.txt")  first sample worker>1: $(awk 'NR>1 && $4>1{print $1; exit}' "$OUT/scaling-timeline.txt")"
echo "final: api=$a worker=$w"
kubectl get hpa -n "$NS"
[ "$accepted" = "$done_count" ] && [ "$pending" = 0 ] && echo "RESULT: PASS (no accepted job lost across scale-up and scale-in)" || { echo "RESULT: FAIL"; exit 1; }
echo "== finished $(date '+%F %T %Z')"
