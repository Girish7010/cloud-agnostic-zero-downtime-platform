# Runbook: database recovery (bad migration, data loss, connection exhaustion)

## A. Destructive or bad migration already applied
Redeploying the old image does **not** restore dropped columns or data.
1. Freeze deploys and halt the fleet.
2. Decide between:
   - **Forward-fix:** a new release that works with the new schema, if the data is intact. Preferred.
   - **PITR:** if data was lost.
3. **PITR, cloud:** restore the RDS instance to a point just before the migration, into a **new** instance (`aws rds restore-db-instance-to-point-in-time ... --target-db-instance-identifier <new>`). Validate row counts and checksums against expectations. Then switch the application secret (ESO) to the new endpoint and redeploy N-1 by digest. Writes made after the restore point must be reconciled from application logs or the outbox.
4. **Drill locally:** `scripts/backup-restore-postgres.sh`. It restores into a new database and verifies schema, row count and an MD5 of the content; it never overwrites the source.

## B. Connection exhaustion
1. Check per-pod pool size × replicas against `max_connections` (capacity plan: about 354 at peak against a 400 cap).
2. Cap HPA/KEDA maximums temporarily, or move to RDS Proxy / PgBouncer (transaction pooling).
3. Kill idle-in-transaction sessions (`pg_terminate_backend`) only after identifying their owner.

## C. Primary failure
Multi-AZ RDS fails over automatically (about 60–120 s). The application reconnects; readiness stays green because `/readyz` checks only Redis. Watch the 5xx burn rate. If it's sustained beyond 5 minutes, page the database owner.
