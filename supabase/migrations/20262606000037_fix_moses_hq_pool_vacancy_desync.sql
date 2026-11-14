-- Migration: 20262606000037_fix_moses_hq_pool_vacancy_desync
-- Created: 2026-08-10
-- Purpose: Reconcile Moses HQ pool vacancies with their true capacity ledger
--          (workforce_pool_slots). Two classes of desync found live during
--          ohm#4x8k2wpn investigation, both pre-dating today's session:
--          (1) 6 vcodes have an open workforce_pool_slots row but NO
--              vacancies row at all (orphan slots, never backfilled), and
--          (2) 7 vcodes have a vacancies row stuck Archived/Closed/Filled
--              while workforce_pool_slots still shows open capacity for
--              that vcode. This is why the Vacancy module's Open tab
--              (reads vacancies) and the Workforce Pool overview (reads
--              workforce_pool_slots directly) disagreed — 0 vs 66 Vacant HC.
--          Not caused by ohm#8m4w1q6n or ohm#7q4n2wkx (both verified
--          uninvolved — see ohm#4x8k2wpn investigation report).
--
-- Smoke Tests:
-- S1: SELECT vcode, status, is_archived, required_headcount FROM vacancies
--       WHERE vcode IN ('COM-GHQ-00001','REL-GHQ-00001','REL-GHQ-00002',
--       'REL-GHQ-00003','SEA-GHQ-00001','SEA-GHQ-00002');
--     -- Expect: 6 rows, all status='Open', is_archived=false,
--        required_headcount=1
-- S2: SELECT vcode, status, is_archived FROM vacancies WHERE vcode = 'REL-00007';
--     -- Expect: status='Open', is_archived=false, archived_at IS NULL
-- S3: Vacancy Open tab (VacancyService.fetchVacancies) for a Data Team /
--     Encoder session scoped to Moses HQ should now return 7 open pool
--     vacancies (6 backfilled + REL-00007) instead of 0.
-- S4: Workforce Pool overview Vacant HC count for Moses HQ is unchanged by
--     this migration (workforce_pool_slots rows are not modified).
-- S5: No vcode uniqueness violation — all 6 backfilled vcodes verified to
--     have zero existing vacancies rows (by id and by vcode) immediately
--     before this migration was authored.
--
-- SCOPE NOTE (ohm#9v3k7wmq): the other 6 desynced vcodes identified in the
-- ohm#4x8k2wpn investigation (BUN-GHQ-00011/12/13, SEA-00004, SEA-GHQ-00003,
-- COM-GHQ-00003) are INTENTIONALLY EXCLUDED from this migration. Their
-- current vacancies.status is 'Closed' or 'Archived', and
-- fn_is_valid_vacancy_transition() does not permit Closed->Open or
-- Archived->Open at all (confirmed live: attempting it raises "Invalid
-- vacancy status transition"). The sanctioned restore_vacancy_record() RPC
-- goes through the same trigger and would hit the identical block for these
-- rows. Reopening them requires either extending the transition matrix or
-- another sanctioned path — a business-rule decision out of scope for a
-- data-only reconciliation migration. Left open pending follow-up.

BEGIN;

-- ============================================================
-- §1  Backfill missing vacancies rows for orphaned open pool slots
-- ============================================================
-- Each of these 6 vcodes has exactly one open, active, non-deleted
-- workforce_pool_slots row and zero required_headcount is safe at 1.
-- position/position_id follow the established convention for -GHQ-
-- suffixed pool vcodes at this account (see sibling rows COM-GHQ-00003,
-- REL-GHQ-00004/5, SEA-GHQ-00003 — all use position_id
-- e23a9bfb-db0c-4921-a3b4-75c6e0981f53 / 'Merchandiser').
-- pool_request_id intentionally left NULL: no matching
-- workforce_pool_requests row exists for these vcodes.

INSERT INTO public.vacancies (
  vcode, account, account_id, home_account_id, group_id,
  position, position_id,
  status, required_headcount,
  is_pool_vacancy, pool_type_id, source,
  is_archived, has_pending_closure, has_penalty, has_reliever,
  affects_required_hc, affects_mfr, is_ops_request,
  closure_request_status
)
SELECT
  x.vcode, 'Moses HQ', '3946ffdd-d826-4fc7-bb9e-356a32dcd152'::uuid,
  '3946ffdd-d826-4fc7-bb9e-356a32dcd152'::uuid,
  '93a714e2-8c87-485a-b0ad-446187ff959e'::uuid,
  'Merchandiser', 'e23a9bfb-db0c-4921-a3b4-75c6e0981f53'::uuid,
  'Open', 1,
  true, x.pool_type_id, 'pool',
  false, false, false, false,
  false, false, false,
  'None'
FROM (VALUES
  ('COM-GHQ-00001', '393cbe3a-dd65-40e0-aea2-ca31db8cb7d7'::uuid),
  ('REL-GHQ-00001', 'b58f1cec-d4b5-4212-9b02-d10cd087b517'::uuid),
  ('REL-GHQ-00002', 'b58f1cec-d4b5-4212-9b02-d10cd087b517'::uuid),
  ('REL-GHQ-00003', 'b58f1cec-d4b5-4212-9b02-d10cd087b517'::uuid),
  ('SEA-GHQ-00001', '5460928f-35eb-43db-b62a-f4888cc3e17d'::uuid),
  ('SEA-GHQ-00002', '5460928f-35eb-43db-b62a-f4888cc3e17d'::uuid)
) AS x(vcode, pool_type_id)
WHERE NOT EXISTS (
  SELECT 1 FROM public.vacancies v WHERE v.vcode = x.vcode
);

-- ============================================================
-- §2  Re-open the one stuck-terminal vcode whose transition IS valid
-- ============================================================
-- REL-00007 is currently 'Filled' (not 'Closed'/'Archived'), and
-- Filled->Open IS a permitted transition per fn_is_valid_vacancy_transition.
-- The other 6 desynced vcodes are excluded — see SCOPE NOTE above.

UPDATE public.vacancies
   SET status      = 'Open',
       is_archived = false,
       archived_at = NULL,
       archived_by = NULL,
       archived_by_id = NULL,
       archive_reason = NULL,
       updated_at  = NOW()
 WHERE vcode = 'REL-00007'
 AND account_id = '3946ffdd-d826-4fc7-bb9e-356a32dcd152'::uuid;

COMMIT;
