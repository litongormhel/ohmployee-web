-- Migration: 20260812000001_backfill_archived_vacancies_terminal_status
-- Created: 2026-08-12
-- Purpose: One-time backfill — align vacancies.status to 'Archived' for rows that
--          already have is_archived=true but were left at a non-terminal status
--          ('Open' / 'For Sourcing' / 'Pipeline') by an ad-hoc manual edit
--          (2026-05-21..05-28) and a since-removed Coverage Group merge code path
--          (Step 8b, live only 2026-07-02..2026-07-06, confirmed absent from the
--          current _execute_approved_coverage_request — no function change here).
--
-- Smoke Tests:
-- S1: SELECT count(*) FROM vacancies WHERE is_archived = true AND status IN
--     ('Open','For Sourcing','Pipeline') AND deleted_at IS NULL; → expect 0 after apply
-- S2: Spot-check a backfilled vcode (e.g. VCTG2_0002) shows status = 'Archived'
--     with is_archived still true and archived_at unchanged

UPDATE public.vacancies
SET status     = 'Archived',
    updated_at = now()
WHERE is_archived = true
  AND status IN ('Open', 'For Sourcing', 'Pipeline')
  AND deleted_at IS NULL;
