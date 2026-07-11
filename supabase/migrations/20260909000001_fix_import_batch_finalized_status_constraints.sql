-- ============================================================
-- OHM2026_0071 — Fix Shared Import Batch Status Constraint for Plantilla and Vacancy
-- Migration: 20260909000001_fix_import_batch_finalized_status_constraints.sql
-- ============================================================
-- Purpose:
--   Ensures that both plantilla_import_batches and vacancy_import_batches
--   have check constraints allowing the 'finalized' status. This prevents
--   constraint violations during the finalization sweep triggered by
--   either module.
-- ============================================================

DO $$
BEGIN
  -- Plantilla Import Batches constraints
  ALTER TABLE public.plantilla_import_batches DROP CONSTRAINT IF EXISTS pib_status_check;
  ALTER TABLE public.plantilla_import_batches DROP CONSTRAINT IF EXISTS plantilla_import_batches_status_check;
  ALTER TABLE public.plantilla_import_batches
    ADD CONSTRAINT pib_status_check CHECK (
      status IN (
        'uploaded','validated','approved','observation_period',
        'rollback_requested','rolled_back','finalized',
        'draft_uploaded','validation_failed','pending_approval','rejected',
        'commit_failed','rollback_pending','rollback_failed','failed_after_processing'
      )
    );

  -- Vacancy Import Batches constraints
  ALTER TABLE public.vacancy_import_batches DROP CONSTRAINT IF EXISTS vib_status_check;
  ALTER TABLE public.vacancy_import_batches DROP CONSTRAINT IF EXISTS vacancy_import_batches_status_check;
  ALTER TABLE public.vacancy_import_batches
    ADD CONSTRAINT vib_status_check CHECK (
      status IN (
        'uploaded','validated','approved','observation_period',
        'rollback_requested','rolled_back','finalized',
        'draft_uploaded','validation_failed','pending_approval','rejected',
        'commit_failed'
      )
    );
END$$;
