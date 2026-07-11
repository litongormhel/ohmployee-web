-- Migration: 20262406000003_staging_prod_parity_missing_objects
-- Created: 2026-06-24
-- Updated: 2026-06-24 (ohm#x7q2m9v4) — add coverage_group_stores.hc_share prerequisite
-- Purpose: Restore 10 objects confirmed missing from staging (2 columns, view, 7 functions, 3 triggers) — verbatim PROD definitions, no grants or RLS changes.
--
-- Smoke Tests:
-- S0: SELECT hc_share FROM coverage_group_stores LIMIT 1; -- must not error (column exists)
-- S1: SELECT source_vacancy_import_batch_id FROM plantilla_slots LIMIT 1; -- must not error
-- S2: SELECT * FROM v_coverage_applicant_store_footprint LIMIT 1; -- must not error
-- S3: SELECT fn_resolve_user_names(ARRAY[]::uuid[]); -- must return empty set, not 42883
-- S4: SELECT get_web_freeze_mode_status(); -- must return JSON with is_read_only_emergency_active key
-- S5: SELECT get_amr_target_vacancies('TRANSFER', 'FAKE-V001'); -- must raise invalid_parameter_value or return rows, not 42883
-- S6: UPDATE roles SET role_name = role_name WHERE false; -- trigger trg_guard_role_level must exist (pg_trigger check)
-- S7: SELECT tgname FROM pg_trigger WHERE tgname IN ('trg_applicants_read_only_check','trg_sync_applicant_name_snapshot','trg_guard_role_level'); -- must return 3 rows
-- S8: SELECT fn_recompute_cg_hc_shares(gen_random_uuid()); -- must not error (function exists, no-op on unknown uuid)

BEGIN;

-- ── Fix 1: Missing column on plantilla_slots ─────────────────────────────────

ALTER TABLE public.plantilla_slots
  ADD COLUMN IF NOT EXISTS source_vacancy_import_batch_id uuid
    REFERENCES public.vacancy_import_batches(id);

-- ── Fix 2: Missing view ───────────────────────────────────────────────────────

CREATE OR REPLACE VIEW public.v_coverage_applicant_store_footprint AS
SELECT
  a.id AS applicant_id,
  a.coverage_group_id,
  a.coverage_slot_id,
  cg.coverage_code,
  cgs.store_id,
  s.store_name,
  s.store_branch,
  cgs.is_anchor,
  cgs.added_at,
  cs.slot_status,
  CASE
    WHEN cs.slot_status = 'active'        THEN 'Onboarded'
    WHEN cs.slot_status = 'hr_processing' THEN 'HR Processing'
    WHEN cs.slot_status = 'pipeline'      THEN 'Pipeline'
    ELSE 'Pending'
  END AS onboarding_status
FROM applicants a
JOIN coverage_groups cg
  ON cg.id = a.coverage_group_id AND cg.archived_at IS NULL
JOIN coverage_group_stores cgs
  ON cgs.coverage_group_id = cg.id AND cgs.archived_at IS NULL
JOIN stores s ON s.id = cgs.store_id
LEFT JOIN coverage_slots cs ON cs.id = a.coverage_slot_id
WHERE a.coverage_group_id IS NOT NULL;

-- ── Fix 2b: coverage_group_stores.hc_share (prerequisite for Fix 3a) ─────────
-- Matches PROD schema (numeric, nullable, no default). Added to PROD outside
-- the migration chain; this restores staging parity. IF NOT EXISTS is safe.

ALTER TABLE public.coverage_group_stores
  ADD COLUMN IF NOT EXISTS hc_share numeric;

-- ── Fix 3a: fn_recompute_cg_hc_shares ────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_recompute_cg_hc_shares(p_coverage_group_id uuid)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  UPDATE public.coverage_group_stores
  SET hc_share = (
    SELECT ROUND(1.0 / NULLIF(COUNT(*), 0), 4)
    FROM public.coverage_group_stores cgs2
    WHERE cgs2.coverage_group_id = p_coverage_group_id
      AND cgs2.archived_at IS NULL
  )
  WHERE coverage_group_id = p_coverage_group_id
    AND archived_at IS NULL;
$function$;

-- ── Fix 3b: fn_resolve_user_names ────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_resolve_user_names(p_user_ids uuid[])
 RETURNS TABLE(id uuid, auth_user_id uuid, full_name text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  RETURN QUERY
  SELECT up.id, up.auth_user_id, up.full_name
  FROM public.users_profile up
  WHERE up.id = ANY(p_user_ids)
     OR up.auth_user_id = ANY(p_user_ids);
END;
$function$;

-- ── Fix 3c: get_amr_target_vacancies ─────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.get_amr_target_vacancies(
  p_movement_type text,
  p_source_vcode  text
)
 RETURNS TABLE(
   vcode              text,
   account            text,
   vacancy_position   text,
   top_applicant_name text,
   top_applicant_id   uuid
 )
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_me_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'get_amr_target_vacancies: authentication required'
      USING ERRCODE = '42501';
  END IF;

  SELECT id INTO v_me_id
  FROM public.users_profile
  WHERE auth_user_id = auth.uid() AND is_active = true;

  IF v_me_id IS NULL THEN
    RAISE EXCEPTION 'get_amr_target_vacancies: user profile not found'
      USING ERRCODE = '42501';
  END IF;

  IF p_movement_type NOT IN ('TRANSFER', 'SWAP') THEN
    RAISE EXCEPTION 'get_amr_target_vacancies: movement_type must be TRANSFER or SWAP'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  IF nullif(trim(coalesce(p_source_vcode, '')), '') IS NULL THEN
    RAISE EXCEPTION 'get_amr_target_vacancies: p_source_vcode is required'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  IF p_movement_type = 'TRANSFER' THEN
    RETURN QUERY
    SELECT
      v.vcode,
      v.account,
      COALESCE(v.position, '')  AS vacancy_position,
      NULL::text                AS top_applicant_name,
      NULL::uuid                AS top_applicant_id
    FROM  public.vacancies v
    JOIN  public.accounts  ac
            ON  ac.account_name = v.account
            AND ac.is_active     = true
            AND ac.status        = 'Active'
    JOIN  public.stores    st
            ON  st.id        = v.store_id
            AND st.is_active = true
            AND st.status    = 'active'
    WHERE v.vcode                                 <> p_source_vcode
      AND v.deleted_at                            IS NULL
      AND COALESCE(v.is_archived,       false)    = false
      AND v.status                                = 'Open'
      AND COALESCE(v.has_pending_closure, false)  = false
      AND COALESCE(v.is_pool_vacancy,   false)    = false
      AND NOT EXISTS (
            SELECT 1
            FROM   public.applicant_movement_reservations res
            JOIN   public.applicant_movement_requests     r2
                     ON r2.id = res.request_id
            WHERE  res.reserved_vcode = v.vcode
              AND  res.released_at    IS NULL
              AND  r2.status          = 'pending'
          )
      AND (
        public.i_have_full_access()
        OR ac.id IN (
          SELECT us.account_id
          FROM   public.user_scopes us
          WHERE  us.user_id    = v_me_id
            AND  us.account_id IS NOT NULL
          UNION ALL
          SELECT a2.id
          FROM   public.user_scopes us2
          JOIN   public.accounts    a2 ON a2.group_id = us2.group_id
          WHERE  us2.user_id     = v_me_id
            AND  us2.group_id    IS NOT NULL
            AND  us2.account_id  IS NULL
        )
      )
    ORDER BY v.vcode
    LIMIT 100;

  ELSE
    RETURN QUERY
    SELECT DISTINCT ON (v.vcode)
      v.vcode,
      v.account,
      COALESCE(v.position, '')  AS vacancy_position,
      (
        a_top.last_name  || ', ' || a_top.first_name
        || CASE WHEN COALESCE(a_top.middle_name, '') <> ''
                THEN ' ' || a_top.middle_name
                ELSE '' END
      )                         AS top_applicant_name,
      a_top.id                  AS top_applicant_id
    FROM  public.vacancies  v
    JOIN  public.accounts   ac
            ON  ac.account_name = v.account
            AND ac.is_active     = true
            AND ac.status        = 'Active'
    JOIN  public.stores     st
            ON  st.id        = v.store_id
            AND st.is_active = true
            AND st.status    = 'active'
    JOIN  public.applicants a_top
            ON  a_top.vacancy_vcode                  = v.vcode
            AND COALESCE(a_top.is_archived, false)   = false
            AND public.fn_is_active_vacancy_applicant_status(a_top.status)
            AND COALESCE(a_top.applicant_source, '') <> 'plantilla'
            AND a_top.linked_plantilla_id            IS NULL
            AND a_top.coverage_group_id              IS NULL
            AND a_top.coverage_slot_id               IS NULL
    WHERE v.vcode                                  <> p_source_vcode
      AND v.deleted_at                             IS NULL
      AND COALESCE(v.is_archived,       false)     = false
      AND v.status NOT IN ('Filled', 'Closed', 'Archived')
      AND COALESCE(v.has_pending_closure, false)   = false
      AND COALESCE(v.is_pool_vacancy,   false)     = false
      AND NOT EXISTS (
            SELECT 1
            FROM   public.applicant_movement_reservations res
            JOIN   public.applicant_movement_requests     r2
                     ON r2.id = res.request_id
            WHERE  res.reserved_vcode = v.vcode
              AND  res.released_at    IS NULL
              AND  r2.status          = 'pending'
          )
      AND (
        public.i_have_full_access()
        OR ac.id IN (
          SELECT us.account_id
          FROM   public.user_scopes us
          WHERE  us.user_id    = v_me_id
            AND  us.account_id IS NOT NULL
          UNION ALL
          SELECT a2.id
          FROM   public.user_scopes us2
          JOIN   public.accounts    a2 ON a2.group_id = us2.group_id
          WHERE  us2.user_id     = v_me_id
            AND  us2.group_id    IS NOT NULL
            AND  us2.account_id  IS NULL
        )
      )
    ORDER BY v.vcode, a_top.created_at ASC
    LIMIT 100;
  END IF;
END;
$function$;

-- ── Fix 3d: get_web_freeze_mode_status ───────────────────────────────────────

CREATE OR REPLACE FUNCTION public.get_web_freeze_mode_status()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id  uuid := auth.uid();
  v_enabled    boolean;
  v_updated_at timestamptz;
  v_reason     text;
  v_updated_by uuid;
  v_actor_name text;
BEGIN
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Unauthenticated' USING ERRCODE = '42501';
  END IF;

  SELECT gc.enabled, gc.updated_at, gc.reason, gc.updated_by
  INTO v_enabled, v_updated_at, v_reason, v_updated_by
  FROM public.governance_controls gc
  WHERE gc.control_key = 'read_only_emergency';

  IF NOT FOUND OR NOT COALESCE(v_enabled, false) THEN
    RETURN jsonb_build_object(
      'is_read_only_emergency_active', false,
      'activated_at',      NULL,
      'activated_by_name', NULL,
      'reason',            NULL
    );
  END IF;

  SELECT up.full_name INTO v_actor_name
  FROM public.users_profile up
  WHERE up.id = v_updated_by;

  RETURN jsonb_build_object(
    'is_read_only_emergency_active', true,
    'activated_at',      v_updated_at,
    'activated_by_name', v_actor_name,
    'reason',            v_reason
  );
END;
$function$;

-- ── Fix 3e: sync_applicant_name_snapshot (trigger function) ──────────────────

CREATE OR REPLACE FUNCTION public.sync_applicant_name_snapshot()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  new.full_name_snapshot := coalesce(new.full_name, new.full_name_snapshot);
  return new;
end;
$function$;

-- ── Fix 3f: trg_fn_applicants_read_only_check (trigger function) ─────────────

CREATE OR REPLACE FUNCTION public.trg_fn_applicants_read_only_check()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF public.fn_check_freeze_active('read_only_emergency') THEN
    RAISE EXCEPTION 'Read-Only Emergency Mode is active. Write actions are temporarily disabled.'
      USING ERRCODE = 'P0001';
  END IF;
  RETURN NEW;
END;
$function$;

-- ── Fix 3g: trg_fn_guard_role_level (trigger function) ───────────────────────

CREATE OR REPLACE FUNCTION public.trg_fn_guard_role_level()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF OLD.canonical_key IS NOT NULL THEN
    IF NEW.role_level < OLD.role_level THEN
      RAISE EXCEPTION
        'ROLE_LEVEL_REDUCTION_BLOCKED: cannot lower role_level for system role "%" (canonical_key=%). '
        'Current level: %. Attempted level: %.',
        OLD.role_name, OLD.canonical_key, OLD.role_level, NEW.role_level
        USING ERRCODE = '23514';
    END IF;
    IF NEW.canonical_key IS DISTINCT FROM OLD.canonical_key THEN
      RAISE EXCEPTION
        'CANONICAL_KEY_IMMUTABLE: canonical_key cannot be changed for system role "%" (was: %).',
        OLD.role_name, OLD.canonical_key
        USING ERRCODE = '23514';
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

-- ── Fix 4: Missing triggers ───────────────────────────────────────────────────

-- trg_sync_applicant_name_snapshot
DROP TRIGGER IF EXISTS trg_sync_applicant_name_snapshot ON public.applicants;
CREATE TRIGGER trg_sync_applicant_name_snapshot
  BEFORE INSERT OR UPDATE ON public.applicants
  FOR EACH ROW EXECUTE FUNCTION public.sync_applicant_name_snapshot();

-- trg_applicants_read_only_check
DROP TRIGGER IF EXISTS trg_applicants_read_only_check ON public.applicants;
CREATE TRIGGER trg_applicants_read_only_check
  BEFORE INSERT OR UPDATE ON public.applicants
  FOR EACH ROW EXECUTE FUNCTION public.trg_fn_applicants_read_only_check();

-- trg_guard_role_level
DROP TRIGGER IF EXISTS trg_guard_role_level ON public.roles;
CREATE TRIGGER trg_guard_role_level
  BEFORE UPDATE ON public.roles
  FOR EACH ROW EXECUTE FUNCTION public.trg_fn_guard_role_level();

COMMIT;
