-- CONTRACT: Run only after all old application versions
-- have stopped using the legacy name column.

ALTER TABLE customers
ALTER COLUMN full_name SET NOT NULL;

ALTER TABLE customers
DROP COLUMN name;
