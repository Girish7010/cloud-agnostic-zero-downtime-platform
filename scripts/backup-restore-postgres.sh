#!/usr/bin/env bash
# Evidence test: logical backup + restore into a NEW, separate database, then
# verify schema, row counts and a content checksum match. The source database
# is only read (pg_dump); nothing is overwritten or dropped.
# Cloud equivalent: RDS automated backups/PITR restored to a new instance (see
# docs/runbooks/database-recovery.md).
set -euo pipefail
NS="${NS:-devops-platform}"; DEPLOY="${DEPLOY:-migration-postgres}"
DB="${DB:-migration_demo}"; DBUSER="${DBUSER:-migration_user}"
TS=$(date +%Y%m%d%H%M%S); TARGET="${DB}_restore_${TS}"
BACKUP_DIR="${BACKUP_DIR:-backups}"; mkdir -p "$BACKUP_DIR"
pg() { kubectl exec -n "$NS" deploy/"$DEPLOY" -- "$@"; }
fingerprint() {  # schema + per-table row count + md5 of all rows (ordered)
  pg psql -U "$DBUSER" -d "$1" -At -c "
    SELECT 'table ' || table_name || ' columns=' || string_agg(column_name||':'||data_type||':'||is_nullable, ',' ORDER BY ordinal_position)
    FROM information_schema.columns WHERE table_schema='public' GROUP BY table_name ORDER BY table_name;" 
  pg psql -U "$DBUSER" -d "$1" -At -c "SELECT 'customers rows=' || count(*) || ' md5=' || md5(coalesce(string_agg(c::text, '|' ORDER BY id), '')) FROM customers c;"
}

echo "== backup/restore test started $(date '+%F %T %Z')"
pg postgres --version
echo "== source fingerprint ($DB)"; fingerprint "$DB" | tee /tmp/src.fp

echo "== pg_dump (custom format) inside pod -> local file"
pg sh -c "pg_dump -U $DBUSER -d $DB -Fc -f /tmp/backup-$TS.dump && ls -l /tmp/backup-$TS.dump"
kubectl exec -n "$NS" deploy/"$DEPLOY" -- cat "/tmp/backup-$TS.dump" > "$BACKUP_DIR/$DB-$TS.dump"
echo "local copy: $BACKUP_DIR/$DB-$TS.dump sha256=$(sha256sum "$BACKUP_DIR/$DB-$TS.dump" | cut -d' ' -f1) (backup files are gitignored)"
pg sh -c "pg_restore -l /tmp/backup-$TS.dump | grep -E 'TABLE|SEQUENCE' "

echo "== restore into NEW database $TARGET"
pg createdb -U "$DBUSER" "$TARGET"
pg pg_restore -U "$DBUSER" -d "$TARGET" --no-owner --exit-on-error "/tmp/backup-$TS.dump"
echo "== restored fingerprint ($TARGET)"; fingerprint "$TARGET" | tee /tmp/dst.fp

echo "== compare"
if diff /tmp/src.fp /tmp/dst.fp; then echo "RESULT: PASS (schema, row count and content checksum identical)"; else echo "RESULT: FAIL"; exit 1; fi
echo "Databases now present:"; pg psql -U "$DBUSER" -d postgres -At -c "SELECT datname FROM pg_database WHERE datname LIKE '${DB}%' ORDER BY 1;"
pg rm -f "/tmp/backup-$TS.dump"
echo "== finished $(date '+%F %T %Z')"
