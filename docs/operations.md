# Operations and SLO plan

## SLOs
- Shared availability: 99.9% monthly.
- Dedicated availability: 99.95% monthly.
- API p95 latency: <400 ms.
- Error budget: derive from the monthly SLO; alert on burn rate, not a single transient failure.

## Alerts
- API 5xx rate and p95 latency.
- Readiness failures / unavailable replicas.
- Worker queue age and depth; failed/retried jobs.
- PostgreSQL connections, CPU, storage, locks and replication lag.
- Redis memory, evictions, persistence/replication health.
- Pod restarts, pending pods, node capacity and autoscaler errors.
- Backup age and failed restore drills.

## Runbooks to complete
- `runbooks/api-outage.md`
- `runbooks/queue-backlog.md`
- `runbooks/database-recovery.md`
- `runbooks/failed-rollout.md`

## Backup/restore
Configure managed database backups and point-in-time recovery in the tenant's residency region. A backup is not proven until a restore to an isolated target succeeds and the application-level validation is recorded.
