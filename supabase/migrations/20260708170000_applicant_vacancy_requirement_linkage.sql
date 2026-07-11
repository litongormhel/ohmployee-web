-- Migration: 20260708170000_applicant_vacancy_requirement_linkage
-- Created: 2026-07-08
-- Purpose: Add a nullable vacancy_requirement_id FK on applicants so the
--   pipeline UI can group applicants by position/requirement (Phase 3,
--   ohm#7a1d3f44 — reduced scope, vacancy detail screen only, approved by Ohm).
--
-- SCOPE NOTE: This column is display/grouping metadata only. It is populated
-- client-side (optional, skippable picker at applicant-creation time) and is
-- NEVER read or written by confirm_applicant_onboard, move_to_plantilla, or
-- fn_plantilla_separation_to_vacancy — those RPCs/triggers remain the sole
-- authority over vacancy_requirements.hc_filled (per ohm#3bd81e6a/ohm#c7a9f2d1/
-- ohm#9f3d2a7c). No RPC signature, RLS policy, or trigger is touched here.
-- Mirrors the exact ADD COLUMN / FK pattern used for hr_emploc/plantilla in
-- 20260708150000_vacancy_requirement_hardening_phase1.sql. No backfill —
-- all existing applicant rows start NULL (Unassigned/Legacy in the UI).
--
-- Smoke Tests:
-- S1: SELECT column_name FROM information_schema.columns
--       WHERE table_name = 'applicants' AND column_name = 'vacancy_requirement_id';
--     -- Expected: 1 row
-- S2: INSERT INTO applicants (vacancy_vcode, full_name, status) VALUES ('SMOKE_TEST_VCODE', 'Smoke Test', 'New')
--       RETURNING vacancy_requirement_id;
--     -- Expected: NULL, insert succeeds unchanged (roll back after)
-- S3: UPDATE applicants SET vacancy_requirement_id = (SELECT id FROM vacancy_requirements LIMIT 1)
--       WHERE id = '<smoke row id>';
--     -- Expected: succeeds when the id exists; FK violation when it doesn't

BEGIN;

ALTER TABLE public.applicants
  ADD COLUMN IF NOT EXISTS vacancy_requirement_id uuid;

ALTER TABLE public.applicants
  DROP CONSTRAINT IF EXISTS fk_applicants_vacancy_requirement;

ALTER TABLE public.applicants
  ADD CONSTRAINT fk_applicants_vacancy_requirement
  FOREIGN KEY (vacancy_requirement_id)
  REFERENCES public.vacancy_requirements(id)
  ON DELETE SET NULL;

COMMENT ON COLUMN public.applicants.vacancy_requirement_id IS
  'ohm#7a1d3f44 — Optional grouping key for per-position pipeline UI. '
  'Non-authoritative for hc_filled (owned exclusively by confirm_applicant_onboard). '
  'NULL for legacy applicants and all pool/roving/coverage-group applicants (ADR-001).';

COMMIT;
