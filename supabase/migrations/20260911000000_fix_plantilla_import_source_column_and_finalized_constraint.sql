-- ============================================================
-- OHM2026_0072 / OHM2026_0073 — Fix stores.source_import_id column reference,
--                                ESA a.updated_at column reference, and
--                                pib_status_check finalized constraint
-- Migration: 20260911000000_fix_plantilla_import_source_column_and_finalized_constraint.sql
-- Depends on: 20260909000000_import_rollback_governance_72_business_hours.sql
-- ============================================================
-- Problems fixed:
--   1. _import_records_modified_after_approval referenced s.source_import_batch_id
--      on the stores table. The stores table column is source_import_id (not
--      source_import_batch_id — that column lives on employee_store_allocations).
--   2. _import_records_modified_after_approval referenced a.updated_at on
--      employee_store_allocations. ESA has no updated_at column — it is append-only;
--      rows are superseded (is_active=false + effective_end set) not edited.
--      Replaced with a.created_at, which is the correct timestamp column on ESA.
--   3. pib_status_check did not include 'finalized', causing constraint violations
--      when finalize_expired_import_rollback_windows() updated batch status.
-- ============================================================

-- §1  Fix pib_status_check to include 'finalized'
-- ============================================================
-- Idempotent: drops by name before re-adding.
DO $$
BEGIN
  ALTER TABLE public.plantilla_import_batches DROP CONSTRAINT IF EXISTS pib_status_check;
  ALTER TABLE public.plantilla_import_batches DROP CONSTRAINT IF EXISTS plantilla_import_batches_status_check;
  ALTER TABLE public.plantilla_import_batches
    ADD CONSTRAINT pib_status_check CHECK (
      status IN (
        'uploaded','validated','approved','observation_period',
        'rollback_requested','rolled_back','finalized',
        'draft_uploaded','validation_failed','pending_approval','rejected',
        'commit_failed','rollback_pending','rollback_failed','failed_after_processing',
        'expired'
      )
    );
END$$;

-- §2  Fix _import_records_modified_after_approval
-- ============================================================
-- Two column fixes vs the original in 20260909000000:
--   a) stores branch: s.source_import_batch_id → s.source_import_id
--      (stores uses source_import_id; source_import_batch_id lives on ESA)
--   b) ESA branch: a.updated_at → a.created_at
--      (employee_store_allocations is append-only; it has no updated_at column.
--       Superseded rows have is_active set to false but no update timestamp.
--       created_at is the only available timestamp on ESA rows.)
CREATE OR REPLACE FUNCTION public._import_records_modified_after_approval(
  p_module text,
  p_batch_id uuid,
  p_approved_at timestamptz
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
BEGIN
  IF p_approved_at IS NULL THEN
    RETURN false;
  END IF;

  IF p_module = 'plantilla' THEN
    RETURN EXISTS (
      SELECT 1 FROM public.plantilla p
       WHERE p.source_baseline_import_batch_id = p_batch_id
         AND p.updated_at > p_approved_at
    ) OR EXISTS (
      SELECT 1 FROM public.stores s
       WHERE s.source_import_id = p_batch_id
         AND s.updated_at > p_approved_at
    ) OR EXISTS (
      SELECT 1 FROM public.employee_store_allocations a
       WHERE a.source_import_batch_id = p_batch_id
         AND a.created_at > p_approved_at
    );
  END IF;

  IF p_module = 'vacancy' THEN
    RETURN EXISTS (
      SELECT 1 FROM public.vacancies v
       WHERE v.source_vacancy_import_batch_id = p_batch_id
         AND v.updated_at > p_approved_at
    );
  END IF;

  RETURN false;
END;
$func$;

COMMENT ON FUNCTION public._import_records_modified_after_approval(text, uuid, timestamptz) IS
  'Returns true when any record committed by the given import batch was modified after approval. '
  'Plantilla: checks plantilla.updated_at (source_baseline_import_batch_id), '
  'stores.updated_at (source_import_id), and employee_store_allocations.created_at '
  '(source_import_batch_id; ESA is append-only, no updated_at column). '
  'Vacancy: checks vacancies.updated_at (source_vacancy_import_batch_id). '
  'Rollback is blocked after post-import edits to prevent clobbering approved operational changes.';
