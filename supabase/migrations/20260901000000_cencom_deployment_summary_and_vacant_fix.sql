-- ============================================================================
-- OHM2026_0070 — CENCOM Deployment Summary + Vacant KPI Fix
-- ============================================================================
-- Deliverables:
--   §1  fn_cencom_deployment_summary()
--       Returns four current-month historical counters for the CENCOM Overview
--       Deployment Summary card.
--
--   §2  Documentation — Vacant KPI source-of-truth (comment only; the Dart fix
--       removing the +pipeline inflation is applied client-side in
--       cencom_service.dart).
--
-- Metric definitions
-- ─────────────────────────────────────────────────────────────────────────────
-- total_departures  COUNT of approved employee_deactivation_requests where
--                   processed_at is in the current calendar month.
--
-- additional_hc     COUNT of headcount_requests approved this month; uses
--                   COALESCE(head_admin_approved_at, reviewed_at) for the
--                   timestamp because encoder/OM-level approvals may not go
--                   through head_admin flow.  Status IN
--                   ('approved_pending_vcode', 'completed').
--
-- deleted_vcode     COUNT of vacancies archived OR soft-deleted in the current
--                   calendar month.  Uses COALESCE(archived_at, deleted_at).
--
-- deployment        COUNT of hr_emploc rows where hired_date is in the current
--                   calendar month and deleted_at IS NULL.
--
-- Scoping
-- ─────────────────────────────────────────────────────────────────────────────
-- SECURITY DEFINER; explicit scope guard mirrors other CENCOM RPCs.
-- Full-access users (superAdmin/headAdmin) see the global count.
-- Scoped users see counts restricted to their allowed accounts.
-- ============================================================================

BEGIN;

-- ── §1  fn_cencom_deployment_summary ─────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_cencom_deployment_summary()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
WITH
  period AS (
    SELECT
      date_trunc('month', now())::date                         AS month_start,
      (date_trunc('month', now()) + interval '1 month')::date AS month_end
  ),
  allowed AS (
    -- Full-access users: NULL sentinel means "no filter needed".
    -- Scoped users: array of permitted account UUIDs.
    SELECT CASE
      WHEN public.i_have_full_access() THEN NULL::uuid[]
      ELSE public.get_my_allowed_account_ids()
    END AS ids
  ),
  departures AS (
    SELECT count(*) AS cnt
    FROM public.employee_deactivation_requests d
    CROSS JOIN period p
    CROSS JOIN allowed sc
    WHERE d.status = 'Approved'
      AND d.processed_at::date >= p.month_start
      AND d.processed_at::date <  p.month_end
      AND d.is_archived = false
      AND (sc.ids IS NULL OR d.account_id = ANY(sc.ids))
  ),
  additional_hc AS (
    SELECT count(*) AS cnt
    FROM public.headcount_requests h
    CROSS JOIN period p
    CROSS JOIN allowed sc
    WHERE h.status IN ('approved_pending_vcode', 'completed')
      AND COALESCE(h.head_admin_approved_at, h.reviewed_at)::date >= p.month_start
      AND COALESCE(h.head_admin_approved_at, h.reviewed_at)::date <  p.month_end
      AND COALESCE(h.is_archived, false) = false
      AND (sc.ids IS NULL OR h.account_id = ANY(sc.ids))
  ),
  deleted_vcode AS (
    SELECT count(*) AS cnt
    FROM public.vacancies v
    CROSS JOIN period p
    CROSS JOIN allowed sc
    WHERE COALESCE(v.archived_at, v.deleted_at)::date >= p.month_start
      AND COALESCE(v.archived_at, v.deleted_at)::date <  p.month_end
      AND (sc.ids IS NULL OR v.account_id = ANY(sc.ids))
  ),
  deployment AS (
    SELECT count(*) AS cnt
    FROM public.hr_emploc he
    CROSS JOIN period p
    CROSS JOIN allowed sc
    WHERE he.hired_date >= p.month_start
      AND he.hired_date <  p.month_end
      AND he.deleted_at IS NULL
      AND (sc.ids IS NULL OR he.account_id = ANY(sc.ids))
  )
SELECT jsonb_build_object(
  'total_departures', COALESCE((SELECT cnt FROM departures),   0),
  'additional_hc',    COALESCE((SELECT cnt FROM additional_hc), 0),
  'deleted_vcode',    COALESCE((SELECT cnt FROM deleted_vcode), 0),
  'deployment',       COALESCE((SELECT cnt FROM deployment),    0)
);
$$;

COMMENT ON FUNCTION public.fn_cencom_deployment_summary() IS
  'OHM2026_0070: Returns four current-calendar-month operational counters for the '
  'CENCOM Overview Deployment Summary card. '
  'total_departures = approved employee_deactivation_requests this month. '
  'additional_hc    = approved_pending_vcode/completed headcount_requests this month. '
  'deleted_vcode    = vacancies archived or soft-deleted this month. '
  'deployment       = hr_emploc rows with hired_date this month. '
  'SECURITY DEFINER; scoped via i_have_full_access()/get_my_allowed_account_ids().';

GRANT EXECUTE ON FUNCTION public.fn_cencom_deployment_summary() TO authenticated;

-- ── §2  Vacant KPI — source-of-truth documentation ───────────────────────────
-- CENCOM Vacant KPI = v_cencom_allocation_kpi.open_hc
--   = COUNT of vacancies WHERE status='Open' AND deleted_at IS NULL
--     AND is_archived=false AND is_pool_vacancy=false
--     AND affects_required_hc=true
--   = slot_status='open' equivalent in the legacy vacancies table.
--
-- Pipeline count (hr_emploc rows in-process) is a SEPARATE metric and must NOT
-- be added to the Vacant KPI.  The previous OHM2026_0067 "Vacant = Open + Pipeline"
-- rule is superseded by the slot-first architecture (OHM2026_0070).
--
-- Expected values (as of 2026-06-04):
--   open_hc  (Vacant)  = 4
--   pipeline_count     = 10
--   CENCOM Vacant KPI  = 4   (was incorrectly shown as 14 = 4 + 10)
-- ─────────────────────────────────────────────────────────────────────────────

COMMIT;
