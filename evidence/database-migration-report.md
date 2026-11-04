# PostgreSQL Expand-and-Contract Migration Test

## Environment
- Platform: Local Kubernetes (kind)
- Database: PostgreSQL
- Namespace: devops-platform
- Database: migration_demo
- Table: customers

## Migration stages

1. Legacy schema
   - Created customers table with name column.
   - Inserted two sample records.

2. Expand
   - Added nullable full_name column.
   - Retained the original name column.

3. Backfill
   - Copied name values into full_name.
   - Verified both customer records.

4. Contract
   - Set full_name to NOT NULL.
   - Removed the old name column.
   - Verified the final schema and preserved records.

## Final result
- Migration completed successfully.
- Both customer records were preserved.
- full_name is NOT NULL.
- Old name column was removed.

## Limitations
- Demonstration database only.
- Actual application compatibility was not tested.
- Production backup and rollback procedures must be validated.
