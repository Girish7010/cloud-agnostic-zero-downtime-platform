#!/usr/bin/env bash
# LEGACY (3 Nov 2026): polls through a host port-forward on localhost:8083. This
# method produced the 50/120 failures in evidence/raw/zero-downtime-traffic.txt
# (most likely because a port-forward pins to one pod; unproven). Superseded by scripts/test-deploy-under-load.sh
# (in-cluster k6 against the Service). Kept for traceability.

URL="http://localhost:8083/healthz"
VERSION_URL="http://localhost:8083/version"
LOG="evidence/rollback/zero-downtime-traffic.log"

TOTAL=120
SUCCESS=0
FAILED=0

mkdir -p evidence/rollback

echo "Zero-downtime traffic test started: $(date)" | tee "$LOG"
echo "Checking API every second for $TOTAL seconds."
echo "Deployment can be triggered from another terminal."
echo ""

for _ in $(seq 1 "$TOTAL"); do
    HTTP_CODE=$(curl -s --max-time 3 -o /dev/null -w "%{http_code}" "$URL")
    VERSION=$(curl -s --max-time 3 "$VERSION_URL")
    TIME=$(date '+%H:%M:%S')

    if [ "$HTTP_CODE" = "200" ]; then
        SUCCESS=$((SUCCESS + 1))
    else
        FAILED=$((FAILED + 1))
    fi

    echo "$TIME HTTP=$HTTP_CODE VERSION=$VERSION" | tee -a "$LOG"
    sleep 1
done

echo "" | tee -a "$LOG"
echo "Total requests: $TOTAL" | tee -a "$LOG"
echo "Successful requests: $SUCCESS" | tee -a "$LOG"
echo "Failed requests: $FAILED" | tee -a "$LOG"
echo "Test completed: $(date)" | tee -a "$LOG"
