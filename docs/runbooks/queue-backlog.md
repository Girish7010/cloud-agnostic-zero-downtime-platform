# Runbook: job backlog or worker failures (QueueBacklogGrowing / WorkerJobFailures)

1. **Inspect the queue.**
   - `kubectl exec -n <ns> deploy/<release>-redis -- redis-cli XINFO GROUPS jobs` shows lag (undelivered) and pending (delivered, not acknowledged).
   - In the cloud, use `redis-cli --tls` against Valkey.
2. **Check scaling.**
   - `kubectl get scaledobject,hpa -n <ns>`: is KEDA Ready and Active, and are replicas at max?
   - KEDA errors in `kubectl logs -n keda deploy/keda-operator`. This is how the local DNS bug was found: the scaler needs the FQDN Redis address.
3. **Large pending count but low lag** means workers are dying mid-job. Check:
   - OOMKilled / CrashLoop
   - jobs running longer than the 60 s maximum (the grace period is 75 s)
   Pending messages are reclaimed after 120 s by `XAUTOCLAIM`; idempotency markers prevent re-execution of finished jobs.
4. **Large lag** means insufficient throughput. Raise `worker.keda.maxReplicas`, check node capacity, and check downstream (DB) saturation before adding workers. Adding workers can make DB saturation worse.
5. **Poison messages** (the same message failing repeatedly):
   - Inspect with `XPENDING jobs job-workers - + 10`.
   - Move to a dead-letter stream with `XCLAIM` + `XADD jobs-dlq`, then `XACK` the original.
6. **Never** run `XTRIM`, `DEL` or `FLUSHALL` on the stream during an incident; that is job loss.
