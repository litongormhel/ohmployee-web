-- ============================================================
-- OHM2026_0074 — Fix ESA branch a.updated_at → a.created_at
-- Migration: 20260911000001_fix_esa_branch_created_at.sql
-- Depends on: 20260911000000_fix_plantilla_import_source_column_and_finalized_constraint.sql
-- ============================================================
-- Root cause:
--   20260911000000 was applied to Supabase before the a.updated_at → a.created_at
--   fix was saved into the local migration file. The constraint §1 applied correctly
--   (includes 'finalized' and 'expired'), and stores §2 used the correct
--   s.source_import_id, but the ESA branch still referenced a.updated_at because
--   that was the function body at apply time.
--
--   employee_store_allocations is append-only and has no updated_at column.
--   Superseded rows have is_active set to false and effective_end set, but are
--   never updated in place. The only available timestamp on ESA rows is created_at.
-- ============================================================

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
