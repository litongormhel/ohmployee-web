-- Migration: 20260528000000_vacancy_applicant_account_scope.sql
-- Ticket: OHM2026_3002 - Enforce Vacancy applicant account scope in Supabase
--
-- Purpose:
--   Harden the applicant-account scoping at the Supabase level.
--   This migration:
--     1. Creates fn_search_applicants_scoped — a SECURITY DEFINER RPC that
--        enforces account-scoped applicant search based on a target vacancy vcode.
--        Client-side PostgREST filters (from OHM2026_3001) are replaced by this
--        backend-authoritative path.
--     2. Documents confirmed backend enforcement in confirm_applicant_onboard.
--     3. Documents that vw_vacancy_detail already exposes active_applicant_count.
--
-- Compatibility — Import Vacancy:
--   Imported vacancies (created by approve_vacancy_import / restore path) always
--   carry vacancies.account = v_acct_name and vacancies.vcode = the imported vcode.
--   This RPC resolves account via deleted_at IS NULL only (not is_archived) so
--   it works for Open, Pipeline, Filled, Closed, and Archived imported vacancies.
--   Rolled-back import vacancies have deleted_at IS NOT NULL and are correctly
--   excluded (they must be re-imported via a new batch before becoming usable).
--   The Import Vacancy workflow itself (submit/approve/reject/rollback RPCs) is
--   NOT touched by this migration.
--
-- Architecture notes:
--   - applicants has no account column; account is derived via applicants → vacancies.account.
--   - The existing applicants_read_scoped RLS uses get_my_scoped_vcodes(), which
--     returns all vcodes from all accounts the caller can access. A multi-account
--     user sees applicants from ALL their accounts — not just the target vacancy's
--     account. This is the gap this migration closes.
--   - The existing applicants_insert_ops_only RLS already prevents inserting
--     applicants for vacancies outside the caller's allowed accounts. No change needed.
--   - confirm_applicant_onboard already derives account from vacancies.account via
--     the applicant's vacancy_vcode JOIN, and has an explicit scope check
--     (v_vac.account = ANY(get_my_allowed_accounts())). No change needed.
--   - vw_vacancy_detail already exposes active_applicant_count (confirmed in
--     remote schema and in the import_vacancy_migration_v1 recreation). The
--     Flutter topApplicant fallback in OHM2026_3001 is unnecessary but harmless.
--
-- Acceptance validation (run after apply):
--   -- 1. Function exists:
--   SELECT proname FROM pg_proc
--   WHERE proname = 'fn_search_applicants_scoped'
--     AND pronamespace = 'public'::regnamespace;
--
--   -- 2. vw_vacancy_detail exposes active_applicant_count:
--   SELECT column_name FROM information_schema.columns
--   WHERE table_schema = 'public'
--     AND table_name = 'vw_vacancy_detail'
--     AND column_name = 'active_applicant_count';
--
--   -- 3. Confirm insert policy scopes by account:
--   SELECT polname FROM pg_policies
--   WHERE tablename = 'applicants'
--     AND polname = 'applicants_insert_ops_only';
--
--   -- 4. Spot-check: imported vacancy vcode resolves an account (replace 'ABC-001'):
--   SELECT account FROM public.vacancies
--   WHERE vcode = 'ABC-001' AND deleted_at IS NULL LIMIT 1;

-- ── §1  fn_search_applicants_scoped ────────────────────────────────────────
--
-- Replaces the client-side PostgREST embedded-join filter added in OHM2026_3001.
-- When p_vacancy_vcode is provided, the function:
--   a. Resolves the target vacancy's account — filters deleted_at IS NULL only
--      so both manually created and imported vacancies at any lifecycle status
--      (Open, Pipeline, Filled, Closed, Archived) are resolved correctly.
--      Rolled-back import vacancies (deleted_at IS NOT NULL) return P0002.
--   b. Verifies the caller is in scope for that account.
--   c. Returns ONLY applicants whose linked vacancy belongs to that account.
--      The result JOIN also uses deleted_at IS NULL so applicants from
--      rolled-back import vacancies are excluded, but applicants from
--      Archived/Closed/Filled vacancies in the same account ARE included
--      (valid candidates for pre-filling the Add Applicant form).
-- This blocks cross-account search results even for users with multi-account scope.
--
-- When p_vacancy_vcode is NULL, falls back to all accounts in the caller's scope
-- (matches the previous behaviour via applicants_read_scoped RLS).

DROP FUNCTION IF EXISTS public.fn_search_applicants_scoped(text, text, text, text, int);

CREATE OR REPLACE FUNCTION public.fn_search_applicants_scoped(
  p_last_name      text,
  p_first_name     text,
  p_middle_name    text DEFAULT NULL,
  p_vacancy_vcode  text DEFAULT NULL,
  p_limit          int  DEFAULT 20
)
RETURNS SETOF public.applicants
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_target_account   text;
  v_allowed_accounts text[];
BEGIN
  -- Require authenticated session
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'unauthenticated'
      USING ERRCODE = '42501';
  END IF;

  v_allowed_accounts := public.get_my_allowed_accounts();

  IF p_vacancy_vcode IS NOT NULL AND btrim(p_vacancy_vcode) <> '' THEN
    -- Resolve the target vacancy's account.
    -- Filter: deleted_at IS NULL only.
    --   • Includes: Open, Pipeline, Filled, Closed, Archived vacancies
    --     (both manually created and imported — all have valid account data).
    --   • Excludes: rolled-back import vacancies (deleted_at IS NOT NULL).
    --   • is_archived is intentionally NOT filtered here: an archived vacancy
    --     still carries the correct account and vcode for scope resolution.
    SELECT v.account INTO v_target_account
    FROM public.vacancies v
    WHERE v.vcode = p_vacancy_vcode
      AND v.deleted_at IS NULL
    LIMIT 1;

    IF v_target_account IS NULL THEN
      RAISE EXCEPTION 'vacancy % not found or has been deleted', p_vacancy_vcode
        USING ERRCODE = 'P0002';
    END IF;

    -- Enforce: caller must have access to this account
    IF NOT public.i_have_full_access()
       AND NOT (v_target_account = ANY(v_allowed_accounts)) THEN
      RAISE EXCEPTION 'forbidden: vacancy % is outside caller account scope', p_vacancy_vcode
        USING ERRCODE = '42501';
    END IF;

    -- Return applicants scoped strictly to the target vacancy's account.
    -- Result JOIN: deleted_at IS NULL on vacancies so rolled-back import rows
    -- are excluded; is_archived is NOT filtered so applicants from
    -- Archived/Closed vacancies in the same account remain findable.
    -- Applicant-level: is_archived = false excludes withdrawn/archived applicants.
    RETURN QUERY
    SELECT DISTINCT ON (a.last_name, a.first_name, a.contact_number) a.*
    FROM public.applicants a
    JOIN public.vacancies v
      ON v.vcode = a.vacancy_vcode
     AND v.account = v_target_account
     AND v.deleted_at IS NULL
    WHERE COALESCE(a.is_archived, false) = false
      AND a.last_name  ILIKE '%' || btrim(p_last_name)  || '%'
      AND a.first_name ILIKE '%' || btrim(p_first_name) || '%'
      AND (
        p_middle_name IS NULL
        OR btrim(p_middle_name) = ''
        OR a.middle_name ILIKE '%' || btrim(p_middle_name) || '%'
      )
    ORDER BY a.last_name, a.first_name, a.contact_number, a.created_at DESC
    LIMIT p_limit;

  ELSE
    -- No vacancy context: fall back to all accounts in caller's scope.
    -- Behaves identically to the previous applicants_read_scoped RLS path.
    RETURN QUERY
    SELECT DISTINCT ON (a.last_name, a.first_name, a.contact_number) a.*
    FROM public.applicants a
    JOIN public.vacancies v
      ON v.vcode = a.vacancy_vcode
     AND (
       public.i_have_full_access()
       OR v.account = ANY(v_allowed_accounts)
     )
     AND v.deleted_at IS NULL
    WHERE COALESCE(a.is_archived, false) = false
      AND a.last_name  ILIKE '%' || btrim(p_last_name)  || '%'
      AND a.first_name ILIKE '%' || btrim(p_first_name) || '%'
      AND (
        p_middle_name IS NULL
        OR btrim(p_middle_name) = ''
        OR a.middle_name ILIKE '%' || btrim(p_middle_name) || '%'
      )
    ORDER BY a.last_name, a.first_name, a.contact_number, a.created_at DESC
    LIMIT p_limit;
  END IF;
END;
$function$;

COMMENT ON FUNCTION public.fn_search_applicants_scoped(text, text, text, text, int) IS
  'OHM2026_3002 — Account-scoped applicant search. '
  'When p_vacancy_vcode is provided, restricts results to applicants whose vacancy '
  'belongs to the same account as the target vacancy. '
  'Caller must have access to that account. '
  'Falls back to all scoped accounts when p_vacancy_vcode is NULL. '
  'SECURITY DEFINER: RLS bypassed; scope enforced internally via vacancies JOIN.';

REVOKE ALL ON FUNCTION public.fn_search_applicants_scoped(text, text, text, text, int) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_search_applicants_scoped(text, text, text, text, int) FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_search_applicants_scoped(text, text, text, text, int) TO authenticated;

-- ── §2  Verify confirm_applicant_onboard account preservation ───────────────
--
-- confirm_applicant_onboard already enforces account scope correctly:
--   1. Loads vacancy via: SELECT * FROM vacancies WHERE vcode = v_app.vacancy_vcode
--   2. Scope check: IF NOT i_have_full_access() AND NOT (v_vac.account = ANY(get_my_allowed_accounts()))
--      THEN RAISE EXCEPTION 'forbidden: vacancy is outside caller scope'
--   3. HR Emploc INSERT uses: account = v_vac.account, account_id = v_vac.account_id
--      (derived from the vacancy, not from any Flutter parameter)
--   4. Plantilla fast-track path uses: account = v_vac.account consistently
--
-- The destination account in Vacancy → HR Emploc → Plantilla is always sourced
-- from vacancies.account. No Flutter-side account parameter exists or is needed.
-- No SQL change required for this item.

-- ── §3  vw_vacancy_detail active_applicant_count — already present ──────────
--
-- vw_vacancy_detail already exposes active_applicant_count in production
-- (confirmed in the remote_schema migration and in import_vacancy_migration_v1
-- recreation at §11). The Flutter topApplicant fallback added by OHM2026_3001
-- is redundant but harmless. No migration needed.
--
-- active_applicant_count definition (already live):
--   COALESCE(s.active_applicant_count, 0) AS active_applicant_count
-- where s.active_applicant_count counts applicants with canonical active statuses
-- (not Failed/Backout/Did Not Report/Rejected by Ops/Confirmed Onboard).
