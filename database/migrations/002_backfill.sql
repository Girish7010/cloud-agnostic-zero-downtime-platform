-- BACKFILL: Copy existing values in batches in production.
-- This small demonstration uses one SQL update.

UPDATE customers
SET full_name = name
WHERE full_name IS NULL;
