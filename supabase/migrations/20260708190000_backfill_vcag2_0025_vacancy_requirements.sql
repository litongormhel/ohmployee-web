-- Migration: 20260708190000_backfill_vcag2_0025_vacancy_requirements
-- Created: 2026-07-08
-- Purpose: Sub-task B (ohm#8xk3vpc9) — historical backfill for VCAG2_0025, the
--          one live gap identified in ohm#9nx4wtc7/ohm#5rz2mkp8. Both source
--          HC requests are already status='completed', so the new sync path
--          added in 20260708180000 cannot be re-invoked (its idempotency
--          guard intentionally blocks re-running completed requests). This
--          migration applies the identical merge logic (one row per
--          vacancy_id + position_id, tagged with source_headcount_request_id)
--          directly, as a one-time historical repair — confirmed with Ohm
--          before writing since the RPC path could not be reused as-is.
--
--          Reconciliation: legacy vacancies.required_headcount = 3 for
--          VCAG2_0025 = Sales Promoter (hc=2, HC-8DD33E63) + Merchandiser
--          (hc=1, second HC request) — verified equal before writing.
--
--          The 3 existing applicants on VCAG2_0025 are left with
--          vacancy_requirement_id = NULL — confirmed with Ohm. No column
--          on `applicants` ever recorded per-applicant position at the time
--          these 3 rows were created (they predate both vacancy_requirements
--          and the intake-time position picker), so there is no data to
--          attribute them to either position without guessing. All 3 are
--          placeholder/test rows (never onboarded — one Backout, two still
--          'new') rendering as "Unassigned/Legacy" in the UI, which is
--          accurate.
--
-- Smoke Tests:
-- S1: SELECT confirms VCAG2_0025 now has exactly 2 vacancy_requirements rows:
--     Sales Promoter hc_needed=2, Merchandiser hc_needed=1 (sum = 3, matches
--     legacy vacancies.required_headcount).
-- S2: SELECT confirms both rows carry the correct source_headcount_request_id.
-- S3: SELECT confirms all 3 applicants on VCAG2_0025 still have
--     vacancy_requirement_id IS NULL (unchanged, by decision above).
-- S4: Re-running this migration is a no-op (guarded by NOT EXISTS on
--     vacancy_id + position_id) — no duplicate rows created.

BEGIN;

INSERT INTO public.vacancy_requirements (
  vacancy_id, position_id, employment_type, hc_needed, hc_filled,
  source_headcount_request_id
)
SELECT
  'f0690db0-825a-443d-9688-fb94106ad268'::uuid, -- VCAG2_0025
  'cc000001-0000-0000-0000-000000000001'::uuid, -- Sales Promoter
  'Stationary', 2, 0,
  '8dd33e63-743a-4904-82c8-3365dbf2403d'::uuid   -- HC-8DD33E63
WHERE NOT EXISTS (
  SELECT 1 FROM public.vacancy_requirements
  WHERE vacancy_id = 'f0690db0-825a-443d-9688-fb94106ad268'::uuid
    AND position_id = 'cc000001-0000-0000-0000-000000000001'::uuid
);

INSERT INTO public.vacancy_requirements (
  vacancy_id, position_id, employment_type, hc_needed, hc_filled,
  source_headcount_request_id
)
SELECT
  'f0690db0-825a-443d-9688-fb94106ad268'::uuid, -- VCAG2_0025
  'e23a9bfb-db0c-4921-a3b4-75c6e0981f53'::uuid, -- Merchandiser
  'Stationary', 1, 0,
  '4cfda206-dcdf-4cb7-bab6-47a1a5db86b6'::uuid   -- second HC request
WHERE NOT EXISTS (
  SELECT 1 FROM public.vacancy_requirements
  WHERE vacancy_id = 'f0690db0-825a-443d-9688-fb94106ad268'::uuid
    AND position_id = 'e23a9bfb-db0c-4921-a3b4-75c6e0981f53'::uuid
);

COMMIT;
