# Operations: SLOs, alerts, tenant visibility, backups

**Status:** SLO definitions and alert rules are **[IMPLEMENTED as config]** in `gitops/observability/prometheus-rules.yaml`, but **not deployed**, because kube-prometheus-stack wasn't run on the laptop. Backup/restore and runbook procedures were **[TESTED-LOCAL]** where noted.

## SLOs and error budgets
| Stack | Availability SLO | Monthly error budget | Latency SLO |
|---|---|---|---|
| Shared | 99.9% | 43.8 min (0.1% of requests) | p95 < 400 ms |
| Dedicated | 99.95% | 21.9 min (0.05% of requests) | p95 < 400 ms |

- **Availability SLI** = non-5xx responses ÷ all responses, excluding probe paths (`/healthz`, `/readyz`, `/metrics`), measured per `tenant` at the API.
- **Latency SLI** = share of requests faster than 400 ms. This uses the histogram bucket `le="0.4"`, the same series the rollout gate reads.
- **Worker SLI** = jobs completed ÷ jobs accepted, plus queue age under 5 minutes.

## Alerting (multi-window burn rate)
| Alert | Condition | Severity | Runbook |
|---|---|---|---|
| SLOFastBurn | error ratio > 14.4 × budget over 1 h **and** 5 m | page | `runbooks/api-outage.md` |
| SLOSlowBurn | error ratio > 6 × budget over 6 h | page | `runbooks/api-outage.md` |
| APILatencyP95High | p95 > 400 ms for 10 m | ticket | `runbooks/api-outage.md` |
| QueueBacklogGrowing | stream lag > 500 for 10 m | page | `runbooks/queue-backlog.md` |
| WorkerJobFailures | failures > 0.05/s | ticket | `runbooks/queue-backlog.md` |
| DeploymentReplicasUnavailable | unavailable > 0 for 10 m | ticket | `runbooks/failed-rollout.md` |
| PostgresConnectionsHigh | > 80% of `max_connections` | page | `runbooks/database-recovery.md` |
| BackupTooOld | no successful restore drill in 8 days | ticket | `runbooks/database-recovery.md` |

Paging uses burn rate rather than single errors, which avoids noise from one bad request while still catching a 2%-of-budget-per-hour burn within about 5 minutes.

## Per-tenant visibility
Every object carries `platform.io/tenant`, `platform.io/deployment-mode` and `platform.io/data-residency` labels. Prometheus relabels the pod label into `tenant`, so every SLI, dashboard and alert is per tenant. Dedicated stacks run their own Prometheus in-region (EU data stays in the EU) and federate only aggregate, non-personal SLI series. The local evidence for these labels is `evidence/submission-2026-11-04/isolation-residency/run.txt` §4.

## Backups and restore
- **Cloud [DESIGN]:**
  - RDS automated backups with 14 days PITR (shared) and 7–14 days (dedicated), stored in the stack's own region and KMS key. No cross-region copy for EU.
  - A weekly restore drill restores PITR to a **new** instance, runs validation queries, and records the result as a metric (`platform_last_successful_restore_test_timestamp_seconds`).
  - Valkey: daily snapshot. The queue is transient, so the database is the system of record.
- **Local [TESTED-LOCAL]:**
  - `scripts/backup-restore-postgres.sh` ran `pg_dump` to a custom-format file, then `pg_restore` into a new database.
  - Schema, row count and content MD5 were identical. Evidence: `evidence/submission-2026-11-04/backup-restore/`.
  - The dataset was tiny (2 rows), so this proves the procedure, not the RTO at size.

## Ownership
| Area | Owner |
|---|---|
| Provider/platform layers, pipeline, SLO tooling | Platform team |
| Application behaviour (migrations, idempotency) | Application team |
| Tenant onboarding approvals, ring promotion | Tenant operations |
| On-call | Platform team primary; application team secondary for app-level incidents |

## Runbooks
- `runbooks/api-outage.md`: API errors or latency
- `runbooks/queue-backlog.md`: job backlog or worker failures
- `runbooks/database-recovery.md`: PITR, bad migration, connection exhaustion
- `runbooks/failed-rollout.md`: gate failure, ring halt
- `runbooks/tenant-onboarding.md`: one-PR onboarding
