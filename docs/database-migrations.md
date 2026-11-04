# Database migration safety

The black-box application runs its migrations **on startup**, and some aren't backward-compatible. During a rolling or canary deployment, old (N-1) and new (N) pods run against the **same** schema at the same time. So the rule is:

> **Every release must be schema-compatible with the previous release.** A breaking change is split across releases: expand → backfill → contract.

## Expand / backfill / contract (demonstrated locally)
| Step | Release | SQL (demo in `database/migrations/`) | Old code still works? |
|---|---|---|---|
| 0 Legacy | N-1 | `000_legacy_schema.sql`: `customers(name)` | yes |
| 1 **Expand** | N | `001_expand.sql`: add nullable `full_name` | yes (column ignored) |
| 2 **Backfill** | N (job) | `002_backfill.sql`: copy `name` → `full_name` (batched in production, for example 5,000 rows per transaction with a pause, watching locks and replication lag) | yes |
| — | N | the app writes **both** columns, reads `full_name` | yes |
| 3 **Contract** | N+1 or later, after the rollback window | `003_contract.sql`: `SET NOT NULL`, `DROP COLUMN name` | **no**, which is why it ships separately |

This was run on PostgreSQL 16 in kind (`evidence/database-migration-report.md`). It is **not** integrated with the real app's startup migrations, because the app wasn't supplied.

## Controls
1. **Migration ordering.** Where the black box supports a "migrate only" mode, run it as a pre-sync Job (Argo CD hook) holding `pg_advisory_lock`. That way exactly one migrator runs, before any N pod. Otherwise the first canary pod performs it, which is only acceptable for expand-type migrations.
2. **Startup probe budget.** `startupProbe` allows 60 s, so a slow migration isn't killed by liveness.
3. **Contract releases** are labelled in the PR, need a manual approval, and are preceded by a verified snapshot. They're never combined with other changes.
4. **Backfill** runs as an idempotent, resumable batch job, never in a single transaction on large tables.

## Rollback after a migration
| Situation | Action |
|---|---|
| Failure before or after an **expand** | Roll back the image to N-1 by digest (automatic via the gates). The extra nullable column is harmless. |
| Failure after **contract** (column dropped) | Redeploying N-1 **fails**, because the code expects a column that no longer exists. Options: forward-fix release, or **PITR restore to a new instance** and cut over, reconciling writes made since. See `runbooks/database-recovery.md`. |
| Data corrupted by a bad backfill | Stop the job, PITR to a new instance or repair from the still-present old column (possible only because contract hasn't run yet). |

## Backup and restore evidence
`scripts/backup-restore-postgres.sh` does a logical `pg_dump`, then restores into a **new** database and compares schema, row count and an MD5 of all rows. It passed locally on 4 Nov 2026 (`evidence/submission-2026-11-04/backup-restore/`). In the cloud, RDS PITR is the primary mechanism, and the weekly drill restores into a new instance.
