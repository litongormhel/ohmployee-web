-- ============================================================================
-- ohm#c92f4d1e — Fix Merge Coverage Group Residual Vacancy Cleanup (PROD Backfill)
-- Migration: 20260702000002_fix_merge_coverage_group_vacancy_cleanup.sql
-- Created: 2026-07-02
-- ============================================================================
--
-- Problem:
--   merge_coverage_groups execution (20260701000002) did NOT archive existing
--   per-store vacancies for stores absorbed into a Coverage Group. After merge,
--   those legacy Open/For Sourcing/Pipeline vacancies remained visible, causing
--   duplicate vacancy cards alongside the correct CG card.
--
-- Root Fix:
--   20260701000002_fix_merge_coverage_group_execution.sql has been patched with
--   Step 8b — all future merges will archive these vacancies atomically.
--
-- This Migration:
--   Backfill-only: archives the residual vacancies that pre-existed the patch.
--   Safe to run on both staging and production.
--   Idempotent (already-archived rows are excluded by the WHERE clause).
--
-- NOTE on schema:
--   vacancies has NO coverage_group_id column. The correct discriminator is
--   store_id IN (active coverage_group_stores). A vacancy is "CG-absorbed" if
--   its store_id is covered by an active CG membership row.
--
-- Scope:
--   Vacancies where:
--     - status IN ('Open', 'For Sourcing', 'Pipeline')
--     - NOT already archived (is_archived = false / NULL)
--     - NOT deleted
--     - store_id appears in an active coverage_group_stores row
--
-- Smoke Tests (run after applying):
--   S1 — TASK 3 validation query returns ZERO rows (see below)
--   S2 — Merged CG shows exactly ONE vacancy card in UI
--   S3 — HC totals unchanged (archived vacancies excluded from open count)
--   S4 — Applicants unaffected (applicants table not touched)
--   S5 — remove_store unaffected (removed stores exit active CGS with archived_at
--         IS NOT NULL — excluded from this query)
--   S6 — dissolve_coverage_group unaffected (dissolved stores exit CGS;
--         post-dissolve per-store vacancies are intentionally kept open)
--
-- TASK 3 — Validation query (should return ZERO after applying):
--   SELECT v.id, v.store_id, v.account_id, v.status
--   FROM public.vacancies v
--   WHERE v.status IN ('Open', 'For Sourcing', 'Pipeline')
--     AND COALESCE(v.is_archived, false) = false
--     AND v.deleted_at IS NULL
--     AND EXISTS (
--       SELECT 1
--       FROM public.coverage_group_stores cgs
--       WHERE cgs.store_id = v.store_id
--         AND cgs.archived_at IS NULL
--     );
-- ============================================================================

BEGIN;

-- ============================================================================
-- §1  PREVIEW — Safe read-only diagnostic (informational only — not applied)
-- ============================================================================
--
-- Run this SELECT before applying to see which vacancies will be archived:
--
-- SELECT v.id, v.store_id, v.account_id, v.status
-- FROM public.vacancies v
-- WHERE v.status IN ('Open', 'For Sourcing', 'Pipeline')
--   AND COALESCE(v.is_archived, false) = false
--   AND v.deleted_at IS NULL
--   AND EXISTS (
--     SELECT 1
--     FROM public.coverage_group_stores cgs
--     WHERE cgs.store_id = v.store_id
--       AND cgs.archived_at IS NULL
--   );

-- ============================================================================
-- §2  FIX — Archive residual per-store vacancies absorbed by Coverage Groups
-- ============================================================================

UPDATE public.vacancies v
SET is_archived = true,
    archived_at = now(),
    updated_at  = now()
WHERE v.status IN ('Open', 'For Sourcing', 'Pipeline')
  AND COALESCE(v.is_archived, false) = false
  AND v.deleted_at IS NULL
  AND EXISTS (
    SELECT 1
    FROM public.coverage_group_stores cgs
    WHERE cgs.store_id = v.store_id
      AND cgs.archived_at IS NULL
  );

-- ============================================================================
-- §3  POST-APPLY VALIDATION
-- ============================================================================
--
-- After applying, run the TASK 3 validation query (see header above).
-- Expected result: 0 rows.

COMMIT;

-- ============================================================================
-- Regression Notes:
--   - remove_store: removed stores exit coverage_group_stores with
--     archived_at IS NOT NULL — excluded from EXISTS subquery. Safe.
--   - dissolve_coverage_group: all CGS rows archived on dissolve — excluded.
--     Post-dissolve per-store vacancies are intentionally kept open. Safe.
--   - No vacancy queries modified. No UI changes. No architecture changes.
--   - No new vacancies created. No applicant rows touched.
-- ============================================================================
