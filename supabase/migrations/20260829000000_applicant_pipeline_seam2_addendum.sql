-- ============================================================
-- OHMployee — Applicant Pipeline SEAM 2 Addendum
-- Prompt ID : OHM2026_0099
-- Date      : 2026-06-01
-- Scope     :
--   §1  fn_get_applicant_pipeline_history — new read RPC
--       (SEAM 3 prerequisite; was deferred in 20260828000000)
--   §2  Drop 2-param fn_get_applicant_status_options overload
--   §3  fn_get_applicant_status_options — 3-param replacement
--       (adds p_applicant_id; excludes Sourcing for past-Sourcing applicants)
--   §4  Validation queries (commented — run in SQL Editor)
--
-- Dependencies (must be applied before this migration):
--   20260827000000_applicant_pipeline_status_seed_seam1.sql
--   20260828000000_applicant_pipeline_seam2_rpcs.sql
--
-- No Flutter changes.
-- No status seed changes.
-- No applicant table schema changes.
-- No fn_update_applicant_pipeline changes.
-- No CGCODE / slot / Plantilla changes.
-- ============================================================


-- ============================================================
-- §1  fn_get_applicant_pipeline_history
--
--     Returns the full audit history for one applicant from
--     applicant_status_history, ordered newest-first.
--
--     One history row per changed field (one-row-per-field model
--     from SEAM 2). changed_at_display is formatted server-side
--     in 12-hour Philippine Standard Time (Asia/Manila) with no
--     leading zeros, e.g. "June 1, 2026 3:30 PM".
--
--     Scope enforcement:
--       Full-access callers (SA/HA) may read any applicant.
--       All other roles are limited to applicants whose vacancy
--       belongs to one of their allowed accounts.
-- ============================================================
CREATE OR REPLACE FUNCTION public.fn_get_applicant_pipeline_history(
  p_applicant_id uuid,
  p_limit        int DEFAULT 50
)
RETURNS TABLE (
  id                 uuid,
  update_type        text,
  changed_field      text,
  old_value          text,
  new_value          text,
  changed_by         uuid,
  changed_by_name    text,
  changed_at         timestamptz,
  changed_at_display text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_level      int  := COALESCE(public.get_my_role_level(), 0);
  v_vcode      text;
BEGIN
  IF v_level = 0 THEN
    RAISE EXCEPTION 'forbidden: authenticated user with a recognized role required'
      USING ERRCODE = '42501';
  END IF;

  -- Resolve the applicant's vacancy vcode for scope check.
  SELECT a.vacancy_vcode
  INTO   v_vcode
  FROM   public.applicants a
  WHERE  a.id = p_applicant_id
    AND  COALESCE(a.is_archived, false) = false;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'applicant % not found or archived', p_applicant_id
      USING ERRCODE = 'P0002';
  END IF;

  -- Non-full-access callers must own the vacancy's account.
  IF NOT public.i_have_full_access() THEN
    IF NOT EXISTS (
      SELECT 1
      FROM   public.vacancies v
      WHERE  v.vcode      = v_vcode
        AND  v.account    = ANY(public.get_my_allowed_accounts())
        AND  v.deleted_at IS NULL
    ) THEN
      RAISE EXCEPTION 'forbidden: applicant is outside your account scope'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  RETURN QUERY
  SELECT
    h.id,
    h.update_type,
    h.changed_field,
    h.old_value,
    h.new_value,
    h.changed_by,
    h.changed_by_name,
    h.changed_at,
    TO_CHAR(
      h.changed_at AT TIME ZONE 'Asia/Manila',
      'FMMonth FMDD, YYYY FMHH12:MI AM'
    ) AS changed_at_display
  FROM   public.applicant_status_history h
  WHERE  h.applicant_id = p_applicant_id
  ORDER  BY h.changed_at DESC
  LIMIT  COALESCE(p_limit, 50);
END;
$$;

COMMENT ON FUNCTION public.fn_get_applicant_pipeline_history(uuid, int) IS
  'OHM2026_0099 SEAM 2 Addendum — Returns applicant pipeline audit history '
  'newest-first. One row per changed field (SEAM 2 one-row-per-field model). '
  'changed_at_display is 12-hour Philippine Standard Time, e.g. "June 1, 2026 3:30 PM". '
  'Scope-guarded: non-full-access callers limited to their allowed accounts.';

GRANT EXECUTE ON FUNCTION public.fn_get_applicant_pipeline_history(uuid, int)
  TO authenticated, service_role;


-- ============================================================
-- §2  DROP 2-PARAM fn_get_applicant_status_options OVERLOAD
--
--     PostgreSQL CREATE OR REPLACE cannot extend a function's
--     parameter list. The canonical 2-param signature must be
--     dropped before the 3-param replacement is created.
--
--     All existing callers passing 0–2 arguments are forward-
--     compatible with the 3-param function (p_applicant_id
--     defaults to NULL, which preserves old behavior exactly).
-- ============================================================
DROP FUNCTION IF EXISTS public.fn_get_applicant_status_options(boolean, boolean);


-- ============================================================
-- §3  fn_get_applicant_status_options — 3-PARAM REPLACEMENT
--
--     Adds p_applicant_id uuid DEFAULT NULL.
--
--     Sourcing exclusion rule:
--       When p_applicant_id is provided AND the applicant's
--       current status_code is NOT 'new' (i.e. the applicant
--       has moved past Sourcing), status_code='new' is removed
--       from the returned list.
--
--       When p_applicant_id is NULL (create/default flow),
--       status_code='new' is returned normally (allow_on_create
--       = true). No change to existing behavior.
--
--     System-only exclusion:
--       p_exclude_system_only=true continues to hide all 5
--       system-only codes (endorsed, confirmed_onboard,
--       transferred, did_not_report, rejected_by_ops).
--
--     Status resolution:
--       applicants.status stores the display label. The join
--       resolves the label to a status_code using the same
--       multi-form normalization as fn_update_applicant_pipeline
--       (exact code match → exact label match → normalized).
-- ============================================================
CREATE OR REPLACE FUNCTION public.fn_get_applicant_status_options(
  p_include_inactive    boolean DEFAULT false,
  p_exclude_system_only boolean DEFAULT false,
  p_applicant_id        uuid    DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_current_status_code text;
BEGIN
  -- Resolve the applicant's current status_code when filtering.
  IF p_applicant_id IS NOT NULL THEN
    SELECT opt.status_code
    INTO   v_current_status_code
    FROM   public.applicants a
    JOIN   public.applicant_status_options opt
           ON  opt.status_code = a.status
            OR opt.label       = a.status
            OR lower(regexp_replace(opt.label, '[^a-zA-Z0-9]+', '_', 'g'))
               = lower(regexp_replace(COALESCE(a.status, ''), '[^a-zA-Z0-9]+', '_', 'g'))
    WHERE  a.id = p_applicant_id
    ORDER  BY CASE WHEN opt.status_code = a.status THEN 0 ELSE 1 END
    LIMIT  1;
    -- If the applicant is not found, v_current_status_code remains NULL
    -- and the Sourcing exclusion is skipped (safe default).
  END IF;

  RETURN (
    SELECT COALESCE(jsonb_agg(
      jsonb_build_object(
        'status_code',     s.status_code,
        'label',           s.label,
        'is_terminal',     s.is_terminal,
        'allow_on_create', s.allow_on_create,
        'is_system_only',  s.is_system_only,
        'color_key',       s.color_key,
        'sort_order',      s.sort_order,
        'is_active',       s.is_active
      ) ORDER BY s.sort_order
    ), '[]'::jsonb)
    FROM public.applicant_status_options s
    WHERE (p_include_inactive OR s.is_active = true)
      AND (NOT p_exclude_system_only OR s.is_system_only = false)
      -- Exclude Sourcing (status_code='new') when the applicant is past it.
      -- NULL v_current_status_code means no applicant filter → keep 'new'.
      -- v_current_status_code='new' means still at Sourcing → keep 'new'.
      -- Any other value means past Sourcing → hide 'new'.
      AND (
        v_current_status_code IS NULL
        OR v_current_status_code = 'new'
        OR s.status_code <> 'new'
      )
  );
END;
$$;

COMMENT ON FUNCTION public.fn_get_applicant_status_options(boolean, boolean, uuid) IS
  'OHM2026_0099 SEAM 2 Addendum — Returns available applicant status options as jsonb. '
  'p_include_inactive: include inactive rows (default false). '
  'p_exclude_system_only: hide system-only statuses from manual dropdowns (default false). '
  'p_applicant_id: when provided, hides status_code=''new'' (Sourcing) if the applicant '
  'is already past Sourcing — prevents manual return to initial state for non-SA callers. '
  'SA transition enforcement remains in fn_update_applicant_pipeline. '
  'Old 2-param callers are fully backward-compatible (p_applicant_id defaults to NULL).';

GRANT EXECUTE ON FUNCTION public.fn_get_applicant_status_options(boolean, boolean, uuid)
  TO authenticated, service_role;


-- ============================================================
-- §4  VALIDATION QUERIES
--     Run in Supabase SQL Editor after applying this migration.
-- ============================================================

-- V1: fn_get_applicant_pipeline_history exists with correct signature
-- SELECT proname, pg_get_function_arguments(oid) AS args
-- FROM   pg_proc
-- WHERE  proname      = 'fn_get_applicant_pipeline_history'
--   AND  pronamespace = 'public'::regnamespace;
-- Expected: 1 row
--   args = "p_applicant_id uuid, p_limit integer DEFAULT 50"

-- V2: fn_get_applicant_status_options has exactly ONE 3-param signature
-- SELECT proname, pronargs, pg_get_function_arguments(oid) AS args
-- FROM   pg_proc
-- WHERE  proname      = 'fn_get_applicant_status_options'
--   AND  pronamespace = 'public'::regnamespace;
-- Expected: exactly 1 row
--   pronargs = 3
--   args = "p_include_inactive boolean DEFAULT false,
--            p_exclude_system_only boolean DEFAULT false,
--            p_applicant_id uuid DEFAULT NULL"

-- V3: No-arg backward-compat call resolves without ambiguity
-- SELECT jsonb_array_length(public.fn_get_applicant_status_options()) AS count;
-- Expected: 24 (all active statuses, system-only included)

-- V4: 2-param backward-compat call (exclude system-only, no applicant)
-- SELECT jsonb_array_length(public.fn_get_applicant_status_options(false, true)) AS manual_count;
-- Expected: 19 (24 minus 5 system-only; 'new'/Sourcing still present)

-- V5: changed_at_display format is 12-hour (verify structure)
-- SELECT TO_CHAR(now() AT TIME ZONE 'Asia/Manila', 'FMMonth FMDD, YYYY FMHH12:MI AM')
--        AS sample_display;
-- Expected: e.g. "June 1, 2026 3:30 PM" — no leading zeros on day or hour,
--           AM/PM suffix, no military time.

-- V6: History rows return newest-first (requires live data)
-- SELECT id, changed_field, old_value, new_value, changed_at, changed_at_display
-- FROM   public.fn_get_applicant_pipeline_history('<applicant_uuid>')
-- LIMIT  5;
-- Expected: rows ordered by changed_at DESC; changed_at_display in 12-hour PH format.

-- V7: fn_get_applicant_status_options hides Sourcing for a past-Sourcing applicant
-- -- (requires an applicant whose status is not 'Sourcing'/'new')
-- SELECT jsonb_array_elements(
--   public.fn_get_applicant_status_options(false, true, '<past_sourcing_applicant_uuid>')
-- ) ->> 'status_code' AS code;
-- Expected: 'new' does NOT appear in the result set.

-- V8: fn_get_applicant_status_options shows Sourcing for a Sourcing applicant
-- -- (requires an applicant whose status is 'Sourcing')
-- SELECT jsonb_array_elements(
--   public.fn_get_applicant_status_options(false, true, '<sourcing_applicant_uuid>')
-- ) ->> 'status_code' AS code;
-- Expected: 'new' DOES appear in the result set.

-- V9: fn_get_applicant_status_options shows Sourcing for create/default flow (no applicant)
-- SELECT jsonb_array_elements(
--   public.fn_get_applicant_status_options(false, true, NULL)
-- ) ->> 'status_code' AS code;
-- Expected: 'new' DOES appear in the result set.

-- V10: System-only statuses still hidden when p_exclude_system_only=true
-- SELECT jsonb_array_elements(
--   public.fn_get_applicant_status_options(false, true)
-- ) ->> 'status_code' AS code;
-- Must NOT appear: endorsed, confirmed_onboard, transferred,
--                  did_not_report, rejected_by_ops

-- V11: History RPC respects scope — call outside allowed account raises 42501
-- (requires two different user sessions; verify SQLSTATE 42501 returned
--  when an authenticated non-full-access user reads an out-of-scope applicant)
