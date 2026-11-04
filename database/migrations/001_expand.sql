-- EXPAND: Add a nullable column.
-- Old application versions can continue using name.

ALTER TABLE customers
ADD COLUMN IF NOT EXISTS full_name VARCHAR(150);
