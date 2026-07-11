-- ============================================================
-- OHM2026_2058 — Fix Approval Queue RPC Missing Scope ID Columns
-- ============================================================
-- Corrective migration for OHM2026_2057.
-- Root cause: 20260523000000_approval_queue_scope_hydration.sql was
-- not applied, leaving the live v_approval_queue and get_approval_queue()
-- in the state produced by 20260522200000, which returns only
-- requested_group_names / requested_account_names but NOT the
-- three new columns required for form pre-population.
--
-- This migration is idempotent regardless of whether
-- 20260523000000 was applied or not. It fully supersedes it.
--
-- Columns added / corrected:
--   requested_scope_type   TEXT   → 'scoped' | assigned_scope_type | 'global'
--   requested_group_ids    UUID[] → aggregated from account_request_group_scopes
--   requested_account_ids  UUID[] → aggregated from account_request_account_scopes
--
-- Existing columns preserved:
--   requested_group_names, requested_account_names, all prior fields.
--
-- No schema changes. No new tables. No RLS changes.
-- No changes to approve_account_request_v2 or signup flow.
-- Safe to apply after: 20260522200000_account_request_identity_v1_1.sql
-- ============================================================

-- Drop view (CASCADE removes the dependent get_approval_queue RPC)
DROP VIEW IF EXISTS public.v_approval_queue CASCADE;

-- ── Recreate view with full scope hydration ─────────────────────────────────
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

    -- ── Requested group IDs ── for approval form pre-population ─────────────
    COALESCE(
      (
        SELECT ARRAY_AGG(rgs.group_id ORDER BY g.group_name)
        FROM   public.account_request_group_scopes rgs
        JOIN   public.groups g ON g.id = rgs.group_id
        WHERE  rgs.account_request_id = ar.id
      ),
      ARRAY[]::UUID[]
    ) AS requested_group_ids,

    -- ── Requested group names ── display only ────────────────────────────────
    COALESCE(
      (
        SELECT ARRAY_AGG(g.group_name ORDER BY g.group_name)
        FROM   public.account_request_group_scopes rgs
        JOIN   public.groups g ON g.id = rgs.group_id
        WHERE  rgs.account_request_id = ar.id
      ),
      ARRAY[]::TEXT[]
    ) AS requested_group_names,

    -- ── Requested account IDs ── for approval form pre-population ───────────
    COALESCE(
      (
        SELECT ARRAY_AGG(ras.account_id ORDER BY a.account_name)
        FROM   public.account_request_account_scopes ras
        JOIN   public.accounts a ON a.id = ras.account_id
        WHERE  ras.account_request_id = ar.id
      ),
      ARRAY[]::UUID[]
    ) AS requested_account_ids,

    -- ── Requested account names ── display only ──────────────────────────────
    COALESCE(
      (
        SELECT ARRAY_AGG(a.account_name ORDER BY a.account_name)
        FROM   public.account_request_account_scopes ras
        JOIN   public.accounts a ON a.id = ras.account_id
        WHERE  ras.account_request_id = ar.id
      ),
      ARRAY[]::TEXT[]
    ) AS requested_account_names,

    -- ── Derived requested scope type ─────────────────────────────────────────
    -- Priority:
    --   1. 'scoped'              → group scope rows exist for this request
    --   2. ar.assigned_scope_type → already-resolved scope on the request row
    --   3. 'global'              → fallback
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM   public.account_request_group_scopes rgs
        WHERE  rgs.account_request_id = ar.id
      ) THEN 'scoped'
      WHEN ar.assigned_scope_type IS NOT NULL THEN ar.assigned_scope_type
      ELSE 'global'
    END AS requested_scope_type,

    ((EXTRACT(EPOCH FROM (NOW() - ar.created_at))::INT) / 86400) AS days_pending

  FROM      public.account_requests ar
  LEFT JOIN public.roles req_r
              ON req_r.id  = ar.requested_role_id
  LEFT JOIN public.roles asgn_r
              ON asgn_r.id = ar.assigned_role_id
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

-- ── Recreate RPC (dropped by CASCADE above) ──────────────────────────────────
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

REVOKE ALL  ON FUNCTION public.get_approval_queue(public.account_request_status) FROM PUBLIC;
REVOKE ALL  ON FUNCTION public.get_approval_queue(public.account_request_status) FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_approval_queue(public.account_request_status) TO authenticated;

-- ──────────────────────────────────────────────────────────────────────────────
-- VALIDATION QUERIES (read-only — run manually in Supabase SQL Editor)
-- ──────────────────────────────────────────────────────────────────────────────
/*
-- V1: Confirm new columns exist in the view definition
SELECT column_name, data_type
FROM   information_schema.columns
WHERE  table_schema = 'public'
  AND  table_name   = 'v_approval_queue'
  AND  column_name  IN (
         'requested_scope_type',
         'requested_group_ids',
         'requested_account_ids',
         'requested_group_names',
         'requested_account_names'
       )
ORDER BY column_name;
-- Expected: 5 rows

-- V2: Confirm RPC exists with correct signature
SELECT proname, pg_get_function_identity_arguments(oid)
FROM   pg_proc
WHERE  proname = 'get_approval_queue'
  AND  pronamespace = 'public'::regnamespace;
-- Expected: 1 row — get_approval_queue(p_status account_request_status)

-- V3: Target request — must return scope data
SELECT
  id,
  requested_scope_type,
  requested_group_ids,
  requested_group_names,
  requested_account_ids,
  requested_account_names
FROM get_approval_queue()
WHERE id = '23ab341b-7a6f-4206-9a72-7e1bab48de86';
-- Expected:
--   requested_scope_type  = 'scoped'
--   requested_group_ids   = [<Group 5 UUID>]
--   requested_account_ids = [<ACTISERVE UUID>, <ALL DAY G5 UUID>]
--   names still display correctly

-- V4: Requests with no group scope rows → scope type = 'global' or assigned_scope_type
SELECT id, requested_scope_type, requested_group_ids, requested_account_ids
FROM   public.v_approval_queue
WHERE  requested_scope_type != 'scoped'
LIMIT  5;

-- V5: Requests with group scope rows → 'scoped' + populated arrays
SELECT id, requested_scope_type, requested_group_ids, requested_account_ids
FROM   public.v_approval_queue
WHERE  requested_scope_type = 'scoped'
LIMIT  5;

-- V6: RPC smoke test (all pending)
SELECT id, requested_scope_type, requested_group_ids, requested_account_ids
FROM   get_approval_queue('pending'::public.account_request_status)
LIMIT  10;
*/
