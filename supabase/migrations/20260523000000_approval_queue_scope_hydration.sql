-- ============================================================
-- OHM2026_2057 — Approval Queue Scope Hydration
-- ============================================================
-- Extends v_approval_queue + get_approval_queue to return:
--   requested_group_ids    UUID[]  — for form pre-population
--   requested_account_ids  UUID[]  — for form pre-population
--   requested_scope_type   TEXT    — derived: 'scoped' | 'global'
--
-- Fixes: Approval queue UI showed empty groups/accounts even
-- when the user selected them during signup. The existing view
-- returned requested_group_names/requested_account_names (display
-- only) but not the IDs needed to pre-select form widgets.
--
-- Safe to apply after: 20260522200000_account_request_identity_v1_1.sql
-- No schema changes. No new tables. No RLS changes.
-- No changes to approve_account_request_v2 or any approval flow.
-- ============================================================

-- Drop view (CASCADE removes the dependent get_approval_queue RPC)
DROP VIEW IF EXISTS public.v_approval_queue CASCADE;

-- Recreate view with scope hydration fields added
CREATE VIEW public.v_approval_queue AS
  SELECT
    ar.id,
    ar.auth_user_id,
    ar.email,
    ar.full_name,
    ar.last_name,
    ar.first_name,
    ar.middle_name,
    ar.mobile_number,
    ar.full_name_search,
    ar.status,
    ar.notes,
    ar.requested_role_id,
    req_r.role_name  AS requested_role_name,
    req_r.role_level AS requested_role_level,
    ar.assigned_role_id,
    asgn_r.role_name  AS assigned_role_name,
    asgn_r.role_level AS assigned_role_level,
    ar.assigned_scope_type,
    ar.assigned_groups_snapshot,
    ar.assigned_accounts_snapshot,
    ar.reviewed_by,
    ar.reviewed_at,
    ar.rejection_reason,
    ar.rejected_at,
    ar.created_at,
    ar.updated_at,
    reviewer_up.full_name AS reviewer_display_name,

    -- ── Requested group IDs (for approval form pre-population) ───────────
    COALESCE(
      (
        SELECT ARRAY_AGG(rgs.group_id ORDER BY g.group_name)
        FROM public.account_request_group_scopes rgs
        JOIN public.groups g ON g.id = rgs.group_id
        WHERE rgs.account_request_id = ar.id
      ),
      ARRAY[]::UUID[]
    ) AS requested_group_ids,

    -- ── Requested group names (for display) ──────────────────────────────
    COALESCE(
      (
        SELECT ARRAY_AGG(g.group_name ORDER BY g.group_name)
        FROM public.account_request_group_scopes rgs
        JOIN public.groups g ON g.id = rgs.group_id
        WHERE rgs.account_request_id = ar.id
      ),
      ARRAY[]::TEXT[]
    ) AS requested_group_names,

    -- ── Requested account IDs (for approval form pre-population) ─────────
    COALESCE(
      (
        SELECT ARRAY_AGG(ras.account_id ORDER BY a.account_name)
        FROM public.account_request_account_scopes ras
        JOIN public.accounts a ON a.id = ras.account_id
        WHERE ras.account_request_id = ar.id
      ),
      ARRAY[]::UUID[]
    ) AS requested_account_ids,

    -- ── Requested account names (for display) ────────────────────────────
    COALESCE(
      (
        SELECT ARRAY_AGG(a.account_name ORDER BY a.account_name)
        FROM public.account_request_account_scopes ras
        JOIN public.accounts a ON a.id = ras.account_id
        WHERE ras.account_request_id = ar.id
      ),
      ARRAY[]::TEXT[]
    ) AS requested_account_names,

    -- ── Derived requested scope type ─────────────────────────────────────
    -- 'scoped'  → user selected one or more groups during signup
    -- 'global'  → no groups selected (will default to global approval)
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM public.account_request_group_scopes rgs
        WHERE rgs.account_request_id = ar.id
      ) THEN 'scoped'
      ELSE 'global'
    END AS requested_scope_type,

    ((EXTRACT(EPOCH FROM (NOW() - ar.created_at))::INT) / 86400) AS days_pending

  FROM public.account_requests ar
  LEFT JOIN public.roles req_r        ON req_r.id  = ar.requested_role_id
  LEFT JOIN public.roles asgn_r       ON asgn_r.id = ar.assigned_role_id
  LEFT JOIN public.users_profile reviewer_up
                                      ON reviewer_up.auth_user_id = ar.reviewed_by
  ORDER BY
    CASE ar.status
      WHEN 'pending'  THEN 1
      WHEN 'rejected' THEN 2
      WHEN 'approved' THEN 3
      ELSE NULL
    END,
    ar.created_at DESC;

-- Recreate RPC (was dropped by CASCADE above)
CREATE OR REPLACE FUNCTION public.get_approval_queue(
  p_status public.account_request_status DEFAULT 'pending'::public.account_request_status
)
  RETURNS SETOF public.v_approval_queue
  LANGUAGE sql
  STABLE
  SET search_path TO 'public', 'pg_temp'
AS $$
  SELECT * FROM public.v_approval_queue WHERE status = p_status;
$$;

GRANT EXECUTE ON FUNCTION public.get_approval_queue(public.account_request_status)
  TO authenticated;

-- ──────────────────────────────────────────────────────────────
-- VALIDATION QUERIES (read-only, run manually to verify)
-- ──────────────────────────────────────────────────────────────
/*
-- V1: New columns present in the view
SELECT
  id,
  requested_scope_type,
  requested_group_ids,
  requested_group_names,
  requested_account_ids,
  requested_account_names
FROM public.v_approval_queue
LIMIT 10;

-- V2: Pending requests correctly return scope data
SELECT
  id,
  full_name,
  requested_role_name,
  requested_scope_type,
  requested_group_ids,
  requested_account_ids
FROM public.v_approval_queue
WHERE status = 'pending'
LIMIT 10;

-- V3: RPC returns same shape
SELECT * FROM public.get_approval_queue('pending'::public.account_request_status) LIMIT 5;

-- V4: Requests with no groups return 'global' and empty arrays
SELECT id, requested_scope_type, requested_group_ids, requested_account_ids
FROM public.v_approval_queue
WHERE requested_scope_type = 'global'
LIMIT 5;

-- V5: Requests with groups return 'scoped' and populated arrays
SELECT id, requested_scope_type, requested_group_ids, requested_account_ids
FROM public.v_approval_queue
WHERE requested_scope_type = 'scoped'
LIMIT 5;
*/
