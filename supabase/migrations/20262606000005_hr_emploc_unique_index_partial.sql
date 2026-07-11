-- Migration: 20262606000005_hr_emploc_unique_index_partial
-- Created: 2026-06-26
-- Prompt ID: ohm#6t9v3a1k (continuation — UAT regression fix)
-- Purpose: Replace global unique index on hr_emploc(applicant_name, vcode) with a
--          partial index scoped to active (non-deleted) rows only.
--
-- Root cause:
--   hr_emploc_applicant_vcode_unique had no WHERE clause, so soft-deleted rows
--   from rolled-back imports permanently occupied the unique slot and blocked
--   re-upload of the same employee + VCode after rollback.
--
-- Business rule:
--   - Active HR Emploc records must remain unique by (applicant_name, vcode).
--   - Soft-deleted records (rollback, deletion requests) must not block re-import.
--   - Audit trail must be preserved — no applicant_name/vcode cleared on rollback.
--
-- Changes:
--   1. DROP existing global unique index hr_emploc_applicant_vcode_unique.
--   2. CREATE partial unique index (applicant_name, vcode) WHERE deleted_at IS NULL.
--
-- No function changes. No data mutation. No Flutter changes.
-- Consistent with submit_hr_emploc_import STEP E which already filters deleted_at IS NULL.
--
-- Smoke Tests:
-- S1: Rolled-back row (deleted_at IS NOT NULL) no longer blocks re-upload of same applicant+VCode
-- S2: Two active rows with same (applicant_name, vcode) still blocked by index
-- S3: Audit history rows (deleted_at IS NOT NULL) remain intact and queryable
-- S4: Vacancy and slot are reusable after rollback

BEGIN;

-- The index backs a named table constraint; must drop the constraint, not the index directly.
ALTER TABLE public.hr_emploc
  DROP CONSTRAINT IF EXISTS hr_emploc_applicant_vcode_unique;

-- Recreate as a partial unique index covering active rows only.
-- Rolled-back / soft-deleted rows (deleted_at IS NOT NULL) are excluded.
CREATE UNIQUE INDEX hr_emploc_applicant_vcode_unique
  ON public.hr_emploc (applicant_name, vcode)
  WHERE deleted_at IS NULL;

COMMIT;
