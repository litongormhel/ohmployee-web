-- ============================================================
-- ohm#5j8qn3wr — Return-type-safe rewrite of fn_get_archive_batch_history
-- ============================================================
-- CONTEXT:
--   The archived migration 20262606000008_reassert_function_bodies.sql
--   failed on production at statement #48/226 (SQLSTATE 42P13,
--   "cannot change return type of existing function") while trying to
--   add moses_hq_count to fn_get_archive_batch_history() via
--   CREATE OR REPLACE FUNCTION. Postgres blocks in-place RETURNS TABLE
--   column changes on existing functions — the statement must DROP the
--   function first. That migration rolled back in full; production was
--   left at the pre-change, 13-column return type
--   (verified live 2026-07-03, ohm#4kx9p2wv). This migration is a
--   narrowly-scoped, standalone fix for that one statement only.
--
-- ROOT CAUSE CONFIRMED (read-only inspection, production
--   rwxelulyapjgaarlwkus + staging qqiiznmqxfoamqytjica):
--   - production `system_archive_batches` has NO moses_hq_count column.
--   - production `fn_get_archive_batch_history()` still returns the
--     original 13 columns.
--   - `20260630091756_moses_hq_archive_extension.sql` is tracked as
--     "applied" on production's migration history, but its effects
--     (moses_hq_count column + Moses HQ archive functions) never took
--     live effect there — consistent with the known migration-tracking
--     drift pattern already documented in
--     docs/audit/migration_drift_root_cause_2026-07-03.md (history rows
--     present without matching bodies applied).
--   - On staging, the same column + 14-column function ARE live and
--     working (moses_hq_count driven by fn_archive_moses_hq_data,
--     fn_archive_plantilla_data's Moses HQ cascade, and
--     fn_archive_all_operational_data's QA Reset). This migration brings
--     production's fn_get_archive_batch_history() return shape back to
--     parity with staging's already-validated 14-column contract, which
--     the Flutter client (data_archival_center_service.dart,
--     ArchiveBatchHistory.mosesHqCount) already expects with a
--     null-safe `?? 0` fallback.
--
-- OUT OF SCOPE (explicitly not touched by this migration):
--   - fn_archive_moses_hq_data, fn_archive_plantilla_data's Moses HQ
--     cascade, fn_archive_all_operational_data's Moses HQ module, and
--     fn_get_archive_impact_preview's Moses HQ breakdown are NOT
--     restored here. On production these currently do not reference
--     moses_hq_count at all (their live bodies were overwritten by
--     20260907000000_enterprise_data_archival_center.sql's simpler
--     3-count design), so moses_hq_count will read 0 for every row
--     until/unless those functions are separately reviewed and
--     reintroduced in a future, individually-scoped migration.
--   - i_am_head_admin / i_am_hrco / i_am_om search_path — pre-existing,
--     unrelated, left alone per instruction.
--
-- FIX SEQUENCE (matches the required sequence exactly):
--   1. ALTER TABLE system_archive_batches ADD COLUMN moses_hq_count
--      (idempotent; matches the column already live on staging).
--   2. DROP FUNCTION + CREATE FUNCTION (not CREATE OR REPLACE) for the
--      14-column return type — avoids the 42P13 error.
--   3. Re-grant EXECUTE to the exact grantee set confirmed live on
--      production before this migration: service_role, authenticated,
--      anon, postgres. (anon having EXECUTE here is a pre-existing
--      condition, not something this migration widens or narrows.)
-- ============================================================


-- ── §1. Add moses_hq_count backing column ──────────────────────────────────

ALTER TABLE public.system_archive_batches
  ADD COLUMN IF NOT EXISTS moses_hq_count integer NOT NULL DEFAULT 0;


-- ── §2. DROP + CREATE fn_get_archive_batch_history (return-type change) ────

DROP FUNCTION IF EXISTS public.fn_get_archive_batch_history();

CREATE FUNCTION public.fn_get_archive_batch_history()
RETURNS TABLE(
  id                  uuid,
  archive_batch_id    uuid,
  action_type         text,
  reason              text,
  executed_by_name    text,
  executed_at         timestamptz,
  rollback_deadline   timestamptz,
  plantilla_count     integer,
  vacancy_count       integer,
  hr_emploc_count     integer,
  moses_hq_count      integer,
  total_count         integer,
  status              text,
  rolled_back_by_name text,
  rolled_back_at      timestamptz
)
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT
    b.id,
    b.archive_batch_id,
    b.action_type,
    b.reason,
    COALESCE(up.full_name, 'Unknown') AS executed_by_name,
    b.executed_at,
    b.rollback_deadline,
    b.plantilla_count,
    b.vacancy_count,
    b.hr_emploc_count,
    b.moses_hq_count,
    b.plantilla_count + b.vacancy_count + b.hr_emploc_count + b.moses_hq_count AS total_count,
    CASE
      WHEN b.status = 'ACTIVE' AND now() > b.rollback_deadline THEN 'EXPIRED'
      ELSE b.status
    END AS status,
    rb.full_name AS rolled_back_by_name,
    b.rolled_back_at
  FROM public.system_archive_batches b
  LEFT JOIN public.users_profile up ON up.id = b.executed_by
  LEFT JOIN public.users_profile rb ON rb.id = b.rolled_back_by
  ORDER BY b.executed_at DESC;
$function$;

COMMENT ON FUNCTION public.fn_get_archive_batch_history() IS
  'Returns all system_archive_batches rows with resolved actor display names, '
  'EXPIRED status computed lazily, and moses_hq_count for Moses HQ batches. '
  'total_count now includes moses_hq_count. moses_hq_count reads 0 for all '
  'rows until the Moses HQ archive functions (fn_archive_moses_hq_data, '
  'fn_archive_plantilla_data cascade, fn_archive_all_operational_data) are '
  'separately reviewed and reintroduced on this environment.';


-- ── §3. Re-grant EXECUTE to the exact grantee set live pre-migration ───────
-- Confirmed via information_schema.routine_privileges before this migration:
-- service_role, authenticated, anon, postgres. Not widened, not narrowed.

REVOKE ALL ON FUNCTION public.fn_get_archive_batch_history() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_get_archive_batch_history() TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_get_archive_batch_history() TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_get_archive_batch_history() TO anon;
GRANT EXECUTE ON FUNCTION public.fn_get_archive_batch_history() TO postgres;
