-- ============================================================
-- Fix PROD Regression: Missing deleted_at & qa_archive_batch_id Columns
-- Migration: 20262606000010_fix_prod_regression_missing_deleted_at.sql
-- Purpose: Safe forward migration to restore schema parity for Moses HQ archival.
-- ============================================================

BEGIN;

-- 1. Add missing columns to workforce_assignments
ALTER TABLE public.workforce_assignments
  ADD COLUMN IF NOT EXISTS deleted_at timestamptz,
  ADD COLUMN IF NOT EXISTS qa_archive_batch_id uuid;

-- 2. Add missing columns to workforce_pool_request_items
ALTER TABLE public.workforce_pool_request_items
  ADD COLUMN IF NOT EXISTS deleted_at timestamptz,
  ADD COLUMN IF NOT EXISTS qa_archive_batch_id uuid;

-- 3. Add missing qa_archive_batch_id column to other Moses HQ tables
ALTER TABLE public.workforce_pool_slots
  ADD COLUMN IF NOT EXISTS qa_archive_batch_id uuid;

ALTER TABLE public.workforce_pool_requests
  ADD COLUMN IF NOT EXISTS qa_archive_batch_id uuid;

ALTER TABLE public.vacancy_coverage
  ADD COLUMN IF NOT EXISTS qa_archive_batch_id uuid;

ALTER TABLE public.workforce_slot_reviews
  ADD COLUMN IF NOT EXISTS qa_archive_batch_id uuid;

-- 4. Update check constraint on system_archive_batches
ALTER TABLE public.system_archive_batches
  DROP CONSTRAINT IF EXISTS chk_sab_action_type;

ALTER TABLE public.system_archive_batches
  ADD CONSTRAINT chk_sab_action_type CHECK (
    action_type IN ('qa_reset', 'plantilla', 'vacancy', 'hr_emploc', 'moses_hq')
  );

-- 5. Performance-safe indexing
CREATE INDEX IF NOT EXISTS idx_wa_qa_archive_batch_id
  ON public.workforce_assignments (qa_archive_batch_id)
  WHERE qa_archive_batch_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_wpri_qa_archive_batch_id
  ON public.workforce_pool_request_items (qa_archive_batch_id)
  WHERE qa_archive_batch_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_wps_qa_archive_batch_id
  ON public.workforce_pool_slots (qa_archive_batch_id)
  WHERE qa_archive_batch_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_wpr_qa_archive_batch_id
  ON public.workforce_pool_requests (qa_archive_batch_id)
  WHERE qa_archive_batch_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_vc_qa_archive_batch_id
  ON public.vacancy_coverage (qa_archive_batch_id)
  WHERE qa_archive_batch_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_wsr_qa_archive_batch_id
  ON public.workforce_slot_reviews (qa_archive_batch_id)
  WHERE qa_archive_batch_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_workforce_assignments_deleted_at
  ON public.workforce_assignments (deleted_at);

CREATE INDEX IF NOT EXISTS idx_workforce_pool_request_items_deleted_at
  ON public.workforce_pool_request_items (deleted_at);

-- 6. Backfill strategy (idempotent NULL-safety)
UPDATE public.workforce_assignments SET deleted_at = NULL WHERE deleted_at IS NULL;
UPDATE public.workforce_pool_request_items SET deleted_at = NULL WHERE deleted_at IS NULL;

UPDATE public.workforce_assignments SET qa_archive_batch_id = NULL WHERE qa_archive_batch_id IS NULL;
UPDATE public.workforce_pool_request_items SET qa_archive_batch_id = NULL WHERE qa_archive_batch_id IS NULL;
UPDATE public.workforce_pool_slots SET qa_archive_batch_id = NULL WHERE qa_archive_batch_id IS NULL;
UPDATE public.workforce_pool_requests SET qa_archive_batch_id = NULL WHERE qa_archive_batch_id IS NULL;
UPDATE public.vacancy_coverage SET qa_archive_batch_id = NULL WHERE qa_archive_batch_id IS NULL;
UPDATE public.workforce_slot_reviews SET qa_archive_batch_id = NULL WHERE qa_archive_batch_id IS NULL;

COMMIT;
