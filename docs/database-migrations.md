# Database migration safety

The API and worker are a black box; confirm actual migration behavior before rollout.

1. Expand: add nullable columns/tables/indexes in a backward-compatible migration.
2. Deploy code that can read old and new schema; write compatibly.
3. Backfill in bounded batches and monitor locks, replication lag and latency.
4. Switch reads/writes to the new representation.
5. Contract only after all old application versions are gone and the rollback window has expired.

If migrations execute automatically at application startup, do not run old and new versions concurrently until compatibility is proven. Prefer a separately controlled migration job if the application supports it; otherwise document and test the startup migration behavior.

A destructive/non-backward-compatible migration cannot generally be rolled back by simply redeploying the old image. Recovery may require a forward-fix, point-in-time restore, or a tested data transformation. Take a verified backup before the migration.
