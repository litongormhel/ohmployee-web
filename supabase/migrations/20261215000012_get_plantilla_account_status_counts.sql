-- ============================================================
-- ohm#3m8z7q1v — Fix Plantilla Account Card HC Count Stuck at 1000
-- Migration: 20261215000012_get_plantilla_account_status_counts.sql
-- ============================================================
-- Root cause
-- ----------
-- fetchAccountCardsForScope queries v_plantilla_safe to build the folder
-- card activeCount. It calls:
--
--   .from('v_plantilla_safe')
--   .select('account, account_id, status, source_headcount_request_id')
--   .inFilter('account_id', accountIds)
--
-- This is an unbounded SETOF API call. PostgREST enforces max_rows = 1000,
-- silently truncating the response. With 1163 active employees for account
-- TWO, only 1000 rows are returned, so the folder card shows HC 1000/1000
-- while the detail screen (which paginates) correctly shows Active 1163.
--
-- Fix
-- ---
-- Add get_plantilla_account_status_counts(uuid[]) — a SECURITY DEFINER
-- aggregate RPC that returns one row per (account_id, status) combination.
-- The result set is tiny (accounts × statuses ≈ handful of rows) so it is
-- never truncated by PostgREST.  Flutter replaces the full row fetch with
-- this RPC and re-derives the same _AccountCounts buckets from the totals.
--
-- source_headcount_request_id IS NULL exclusion is preserved so vacancy-slot
-- placeholder rows (created from HC requests) are not counted as employees.
--
-- No table schema changes. No data changes.
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_plantilla_account_status_counts(
  p_account_ids uuid[]
)
RETURNS TABLE (
  account_id uuid,
  status     text,
  row_count  bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
  SELECT
    v.account_id::uuid   AS account_id,
    v.status             AS status,
    count(*)::bigint     AS row_count
  FROM public.v_plantilla_safe v
  WHERE v.account_id = ANY(p_account_ids)
    AND v.source_headcount_request_id IS NULL
  GROUP BY v.account_id, v.status;
$func$;

REVOKE ALL ON FUNCTION public.get_plantilla_account_status_counts(uuid[]) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_plantilla_account_status_counts(uuid[]) TO authenticated;

COMMENT ON FUNCTION public.get_plantilla_account_status_counts(uuid[]) IS
  'ohm#3m8z7q1v: aggregate employee counts by (account_id, status) for the '
  'Plantilla folder card. Returns tiny result set — immune to PostgREST '
  'max_rows cap that previously truncated unbounded v_plantilla_safe fetches.';
