#!/usr/bin/env bash
# Evidence test: worker graceful drain during a rolling restart.
# Submits a JOB_SECONDS job, restarts the worker Deployment mid-job, captures
# the OLD pod's logs live, then verifies completion, ACK, no duplicates and an
# empty pending list in Redis.
set -uo pipefail
NS="${NS:-devops-platform}"; RELEASE="${RELEASE:-devops-platform}"
JOB_SECONDS="${JOB_SECONDS:-45}"
OUT="${OUT_DIR:-evidence/submission-2026-11-04/worker-drain}"; mkdir -p "$OUT"
JOB="drain-$(date +%Y%m%d%H%M%S)"; JOB2="${JOB}-after-sigterm"
rcli() { kubectl exec -n "$NS" deploy/"$RELEASE"-redis -- redis-cli "$@"; }
submit() { kubectl exec -n "$NS" deploy/"$RELEASE"-api -c api -- python -c "
import json,urllib.request as u
r=u.Request('http://127.0.0.1:8080/jobs',data=json.dumps({'job_id':'$1','duration_seconds':$2}).encode(),headers={'Content-Type':'application/json'})
print(u.urlopen(r).read().decode())"; }

echo "== worker drain test started $(date '+%F %T %Z') job=$JOB duration=${JOB_SECONDS}s"
kubectl get deploy "$RELEASE-worker" -n "$NS" -o jsonpath='terminationGracePeriodSeconds={.spec.template.spec.terminationGracePeriodSeconds}{"\n"}'
OLD=$(kubectl get pods -n "$NS" -l app="$RELEASE-worker" -o jsonpath='{.items[0].metadata.name}')
echo "old worker pod: $OLD"
kubectl logs -n "$NS" -f "$OLD" --since=1s > "$OUT/old-worker.log" 2>&1 & LOGPID=$!

echo "$(date +%T) submit: $(submit "$JOB" "$JOB_SECONDS")"
until grep -q "Processing job_id=$JOB " "$OUT/old-worker.log"; do sleep 1; done
echo "$(date +%T) old worker started processing $JOB"
sleep 5
T0=$(date +%s); echo "$(date +%T) kubectl rollout restart deploy/$RELEASE-worker (old pod will get SIGTERM mid-job)"
kubectl rollout restart deploy/"$RELEASE-worker" -n "$NS"
until grep -q "Shutdown signal received" "$OUT/old-worker.log"; do sleep 1; done
echo "$(date +%T) SIGTERM observed in old worker; submitting second job $JOB2"
echo "$(date +%T) submit: $(submit "$JOB2" 2)"
kubectl wait --for=delete pod/"$OLD" -n "$NS" --timeout=120s
T1=$(date +%s); echo "$(date +%T) old pod terminated after $((T1-T0))s from restart"
wait "$LOGPID" 2>/dev/null
kubectl rollout status deploy/"$RELEASE-worker" -n "$NS" --timeout=120s
NEW=$(kubectl get pods -n "$NS" -l app="$RELEASE-worker" -o jsonpath='{.items[0].metadata.name}')
sleep 8; kubectl logs -n "$NS" "$NEW" > "$OUT/new-worker.log" 2>&1

echo "== old worker log ($OLD)"; cat "$OUT/old-worker.log"
echo "== new worker log ($NEW, job lines)"; grep -E "job_id=$JOB|started" "$OUT/new-worker.log"
echo "== verification"
p_old=$(grep -c "Processing job_id=$JOB " "$OUT/old-worker.log"); p_new=$(grep -c "Processing job_id=$JOB " "$OUT/new-worker.log")
a_old=$(grep -c "Acknowledged job_id=$JOB " "$OUT/old-worker.log")
j2_old=$(grep -c "job_id=$JOB2" "$OUT/old-worker.log"); j2_new=$(grep -c "Acknowledged job_id=$JOB2" "$OUT/new-worker.log")
echo "job1 processed by old=$p_old new=$p_new (expect 1/0); acknowledged by old=$a_old (expect 1)"
echo "job2 seen by old=$j2_old (expect 0); acknowledged by new=$j2_new (expect 1)"
echo "redis done-marker job1: $(rcli EXISTS "job:done:$JOB")  job2: $(rcli EXISTS "job:done:$JOB2")"
echo "redis XPENDING summary:"; rcli XPENDING jobs job-workers
echo "redis XINFO GROUPS:"; rcli XINFO GROUPS jobs
pend=$(rcli XPENDING jobs job-workers | head -1)
if [ "$p_old" = 1 ] && [ "$p_new" = 0 ] && [ "$a_old" = 1 ] && [ "$j2_old" = 0 ] && [ "$j2_new" = 1 ] && [ "$pend" = 0 ] && [ $((T1-T0)) -lt 75 ]; then
  echo "RESULT: PASS"; else echo "RESULT: FAIL"; exit 1; fi
echo "== finished $(date '+%F %T %Z')"
