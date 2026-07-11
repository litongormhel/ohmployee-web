-- ═════════════════════════════════════════════════════════════════════════════
-- OHM2026_0051 — Safespace Risk Controls Phase 1
-- Migration: 20260714000000_safespace_risk_controls.sql
--
-- Depends on:
--   20260707000000_governance_controls_foundation.sql  (governance_controls table, fn_check_governance_control)
--   20260711000000_safespace_freeze_modes.sql          (fn_assert_freeze_inactive, freeze keys)
--   20260712000000_enforce_recruitment_freeze.sql      (generate_vcodes_for_request, generate_vcodes_from_request)
--   20260713000000_enforce_audit_freeze.sql            (rollback_plantilla_import_batch, fn_request_emploc_deletion, plantilla_request_deletion)
--   20260523100000_fix_user_management_backend.sql     (upsert_user_profile_and_scopes)
--
-- Purpose:
--   Implements Risk Controls as centralized operational capability restrictions
--   inside OHM's Safespace. Risk Controls are INDEPENDENT of Freeze Modes:
--     - Freeze Modes suspend operations during active audit/payroll periods.
--     - Risk Controls gate specific high-risk capabilities permanently until
--       a Super Admin explicitly restricts or allows them.
--
--   Risk Controls default to enabled (allowed). When a Super Admin disables a
--   control, the affected RPC raises:
--     "This capability is currently restricted by System Administration."
--     SQLSTATE P0001
--
-- Sections:
--   §1  Seed — 7 Phase 1 risk control keys (enabled = true by default)
--   §2  fn_assert_risk_control_enabled — shared raise helper
--   §3  Gate bulk_move_ready_to_plantilla          → risk_bulk_actions
--   §4  Gate upsert_user_profile_and_scopes        → risk_role_editing
--   §5  Gate generate_vcodes_for_request           → risk_vcode_creation
--   §6  Gate generate_vcodes_from_request          → risk_vcode_creation
--   §7  Gate plantilla_get_atm                     → risk_export_sensitive_data
--   §8  Gate fn_request_emploc_deletion            → risk_manual_deletion_actions
--   §9  Gate plantilla_request_deletion            → risk_manual_deletion_actions
--   §10 Gate rollback_plantilla_import_batch       → risk_import_rollback_actions
--
-- What is NOT changed:
--   - governance_controls / governance_audit_log schema and RLS
--   - fn_get_governance_controls / fn_update_governance_control / fn_check_governance_control
--   - Any Freeze Mode keys or fn_assert_freeze_inactive
--   - Payroll Freeze, Audit Freeze, Recruitment Freeze, Read-Only Emergency
--   - CENCOM, deactivation, applicant, vacancy approval flows
--   - session invalidation / unrelated workforce workflows
--
-- Replay safety:
--   All functions use CREATE OR REPLACE. Idempotent.
--   Seed uses ON CONFLICT DO NOTHING.
--   No table or column DDL beyond INSERT.
-- ═════════════════════════════════════════════════════════════════════════════

BEGIN;

-- ═════════════════════════════════════════════════════════════════════════════
-- §1  Seed Phase 1 Risk Control keys
-- ═════════════════════════════════════════════════════════════════════════════
-- Risk controls are ENABLED (allowed) by default.
-- A Super Admin must explicitly disable a control to restrict the capability.

INSERT INTO public.governance_controls (control_key, enabled)
VALUES
  ('risk_bulk_actions',           true),
  ('risk_role_editing',           true),
  ('risk_vcode_creation',         true),
  ('risk_export_sensitive_data',  true),
  ('risk_manual_deletion_actions',true),
  ('risk_import_rollback_actions',true),
  ('risk_cross_group_operations', true)
ON CONFLICT (control_key) DO NOTHING;


-- ═════════════════════════════════════════════════════════════════════════════
-- §2  fn_assert_risk_control_enabled
-- ═════════════════════════════════════════════════════════════════════════════
-- Called at the top of each risk-gated RPC.
-- If the control is disabled (enabled = false), raises P0001 with the canonical
-- user-facing message. SECURITY DEFINER so it bypasses RLS for the check.
-- NOTE: Risk Controls are distinct from Freeze Modes. A control being "enabled"
-- means the capability is ALLOWED. "disabled" means RESTRICTED.

CREATE OR REPLACE FUNCTION public.fn_assert_risk_control_enabled(p_control_key text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.fn_check_governance_control(p_control_key) THEN
    RAISE EXCEPTION 'This capability is currently restricted by System Administration.'
      USING ERRCODE = 'P0001';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_assert_risk_control_enabled(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_assert_risk_control_enabled(text) TO authenticated;

COMMENT ON FUNCTION public.fn_assert_risk_control_enabled(text) IS
  'OHM2026_0051: Raises P0001 with canonical user-facing message when the named '
  'risk control is disabled/restricted. Called at the top of each risk-gated RPC. '
  'Risk controls are independent of freeze modes.';


-- ═════════════════════════════════════════════════════════════════════════════
-- §3  Gate bulk_move_ready_to_plantilla → risk_bulk_actions
-- ═════════════════════════════════════════════════════════════════════════════
-- Carries forward the original function body (remote_schema 20260520012857)
-- with the risk control gate added immediately after the role guard.

CREATE OR REPLACE FUNCTION public.bulk_move_ready_to_plantilla()
RETURNS TABLE(hr_emploc_id uuid, plantilla_id uuid, result text, error text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  r    record;
  v_pl public.plantilla;
BEGIN
  IF NOT (i_have_full_access() OR get_my_role() = 'Encoder') THEN
    RAISE EXCEPTION 'forbidden: Data Team role required' USING ERRCODE = '42501';
  END IF;

  -- ── Risk Control Gate (Phase 1) ────────────────────────────────────────────
  PERFORM public.fn_assert_risk_control_enabled('risk_bulk_actions');

  FOR r IN
    SELECT id FROM hr_emploc
     WHERE status = 'Ready for Plantilla'
       AND employee_no IS NOT NULL
       AND deleted_at IS NULL
     ORDER BY hr_reviewed_at ASC NULLS LAST
  LOOP
    BEGIN
      v_pl := move_to_plantilla(r.id);
      hr_emploc_id := r.id; plantilla_id := v_pl.id; result := 'moved'; error := NULL;
      RETURN NEXT;
    EXCEPTION WHEN OTHERS THEN
      hr_emploc_id := r.id; plantilla_id := NULL; result := 'skipped'; error := SQLERRM;
      RETURN NEXT;
    END;
  END LOOP;
  RETURN;
END
$function$;

REVOKE ALL ON FUNCTION public.bulk_move_ready_to_plantilla() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.bulk_move_ready_to_plantilla() TO authenticated;

COMMENT ON FUNCTION public.bulk_move_ready_to_plantilla() IS
  'OHM2026_0051: Gated with risk_bulk_actions. Bulk moves hr_emploc records in '
  'Ready for Plantilla status into the Plantilla table. Blocked when risk_bulk_actions is disabled.';


-- ═════════════════════════════════════════════════════════════════════════════
-- §4  Gate upsert_user_profile_and_scopes → risk_role_editing
-- ═════════════════════════════════════════════════════════════════════════════
-- Carries forward OHM2026_2010 / fix_user_management_backend
-- (20260523100000) with the risk control gate added after the caller auth check.

CREATE OR REPLACE FUNCTION public.upsert_user_profile_and_scopes(
  p_full_name   TEXT,
  p_email       TEXT,
  p_role_id     UUID,
  p_group_ids   UUID[],
  p_profile_id  UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_caller_level  INT;
  v_caller_role   TEXT;
  v_target_level  INT;
  v_target_role   TEXT;
  v_profile_id    UUID := p_profile_id;
  v_gid           UUID;
  v_old_data      jsonb;
BEGIN
  -- ── Auth ──────────────────────────────────────────────────────────────────
  SELECT r.role_level, r.role_name
    INTO v_caller_level, v_caller_role
    FROM public.users_profile up
    JOIN public.roles r ON r.id = up.role_id
   WHERE up.auth_user_id = auth.uid();

  IF COALESCE(v_caller_level, 0) < 90 THEN
    RAISE EXCEPTION 'unauthorized: requires Head Admin or higher'
      USING ERRCODE = '42501';
  END IF;

  -- ── Guard (a): Head Admin cannot create new users ─────────────────────────
  IF p_profile_id IS NULL AND v_caller_level < 100 THEN
    RAISE EXCEPTION 'only Super Admin can create new user accounts'
      USING ERRCODE = '42501';
  END IF;

  -- ── Risk Control Gate (Phase 1) ────────────────────────────────────────────
  PERFORM public.fn_assert_risk_control_enabled('risk_role_editing');

  -- ── Resolve target role ───────────────────────────────────────────────────
  SELECT role_name, role_level
    INTO v_target_role, v_target_level
    FROM public.roles
   WHERE id = p_role_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'role not found: %', p_role_id
      USING ERRCODE = 'P0002';
  END IF;

  -- ── Guard (b): cannot assign a role at or above own level ─────────────────
  IF COALESCE(v_target_level, 0) >= COALESCE(v_caller_level, 0)
     AND v_caller_level < 100 THEN
    RAISE EXCEPTION 'cannot assign a role at or above your own level (your level: %, role level: %)',
      v_caller_level, v_target_level
      USING ERRCODE = '42501';
  END IF;

  -- ── Update or insert users_profile ────────────────────────────────────────
  IF v_profile_id IS NOT NULL THEN
    SELECT to_jsonb(up.*)
      INTO v_old_data
      FROM public.users_profile up
     WHERE up.id = v_profile_id;

    UPDATE public.users_profile
       SET full_name  = p_full_name,
           email      = p_email,
           role_id    = p_role_id,
           updated_at = NOW()
     WHERE id = v_profile_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'user profile not found: %', v_profile_id
        USING ERRCODE = 'P0002';
    END IF;
  ELSE
    -- Only reachable by Super Admin (guard (a) above)
    INSERT INTO public.users_profile (full_name, email, role_id, is_active)
    VALUES (p_full_name, p_email, p_role_id, TRUE)
    RETURNING id INTO v_profile_id;
  END IF;

  -- ── Replace scopes ────────────────────────────────────────────────────────
  DELETE FROM public.user_scopes WHERE user_id = v_profile_id;

  FOREACH v_gid IN ARRAY p_group_ids LOOP
    INSERT INTO public.user_scopes (user_id, group_id)
    VALUES (v_profile_id, v_gid)
    ON CONFLICT DO NOTHING;
  END LOOP;

  -- ── Audit — explicit ::audit_action cast ──────────────────────────────────
  INSERT INTO public.audit_logs (actor_id, module, action, record_id, old_data, new_data)
  VALUES (
    auth.uid(),
    'User Management',
    (CASE WHEN p_profile_id IS NULL THEN 'CREATE_USER' ELSE 'UPDATE_USER_ROLE' END)::audit_action,
    v_profile_id,
    v_old_data,
    jsonb_build_object(
      'full_name', p_full_name,
      'email',     p_email,
      'role_id',   p_role_id,
      'role_name', v_target_role,
      'group_ids', p_group_ids
    )
  );

  RETURN v_profile_id;
END;
$$;

REVOKE ALL ON FUNCTION public.upsert_user_profile_and_scopes(text, text, uuid, uuid[], uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.upsert_user_profile_and_scopes(text, text, uuid, uuid[], uuid) TO authenticated;

COMMENT ON FUNCTION public.upsert_user_profile_and_scopes(text, text, uuid, uuid[], uuid) IS
  'OHM2026_0051: Gated with risk_role_editing. Creates or updates a user profile and '
  'replaces group scopes. Blocked when risk_role_editing is disabled.';


-- ═════════════════════════════════════════════════════════════════════════════
-- §5  Gate generate_vcodes_for_request → risk_vcode_creation
-- ═════════════════════════════════════════════════════════════════════════════
-- Carries forward OHM2026_0049 (20260712000000) which already gates for
-- recruitment_freeze. Adds risk control gate for risk_vcode_creation.

CREATE OR REPLACE FUNCTION public.generate_vcodes_for_request(
  p_vacancy_request_id uuid,
  p_account_code       text,
  p_group_code         text,
  p_slots              integer
)
RETURNS TABLE(vcode_id uuid, vcode text, sequence_num integer)
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_prefix        TEXT;
  v_seq           INT;
  v_vcode         TEXT;
  v_id            UUID;
  v_lock_key      BIGINT;
  v_generated     INT := 0;
  v_already       INT;
BEGIN
  -- ── Freeze Gate (Phase 2A) ─────────────────────────────────────────────────
  PERFORM public.fn_assert_freeze_inactive('recruitment_freeze');

  -- ── Risk Control Gate (Phase 1) ────────────────────────────────────────────
  PERFORM public.fn_assert_risk_control_enabled('risk_vcode_creation');

  -- Validate group_code
  IF p_group_code NOT IN ('G1','G2','G3','G4','G5') THEN
    RAISE EXCEPTION 'Invalid group_code: %. Must be G1–G5.', p_group_code;
  END IF;

  -- Validate slots
  IF p_slots < 1 OR p_slots > 100 THEN
    RAISE EXCEPTION 'slots must be between 1 and 100.';
  END IF;

  -- Guard: already fully generated
  SELECT COUNT(*) INTO v_already
  FROM vcodes
  WHERE vacancy_request_id = p_vacancy_request_id;

  IF v_already >= p_slots THEN
    RAISE EXCEPTION 'VCodes already fully generated for this request (% / %).', v_already, p_slots;
  END IF;

  -- Advisory lock — prevents race condition per scope
  v_lock_key := hashtext(p_account_code || '::' || p_group_code);
  PERFORM pg_advisory_xact_lock(v_lock_key);

  v_prefix := p_account_code || '-' || p_group_code;

  LOOP
    EXIT WHEN v_generated >= p_slots;

    -- Atomic increment via vcode_sequences
    INSERT INTO vcode_sequences (prefix, last_seq, updated_at)
    VALUES (v_prefix, 1, NOW())
    ON CONFLICT (prefix) DO UPDATE
      SET last_seq   = vcode_sequences.last_seq + 1,
          updated_at = NOW()
    RETURNING last_seq INTO v_seq;

    v_vcode := v_prefix || '-' || LPAD(v_seq::TEXT, 4, '0');
    v_id    := gen_random_uuid();

    INSERT INTO vcodes (
      id, vacancy_request_id, account_code,
      group_code, sequence_number, vcode, status
    ) VALUES (
      v_id, p_vacancy_request_id, p_account_code,
      p_group_code, v_seq, v_vcode, 'available'
    );

    vcode_id     := v_id;
    vcode        := v_vcode;
    sequence_num := v_seq;
    RETURN NEXT;

    v_generated := v_generated + 1;
  END LOOP;
END;
$function$;

REVOKE ALL ON FUNCTION public.generate_vcodes_for_request(uuid, text, text, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.generate_vcodes_for_request(uuid, text, text, integer) TO authenticated;

COMMENT ON FUNCTION public.generate_vcodes_for_request(uuid, text, text, integer) IS
  'OHM2026_0051: Gated with recruitment_freeze (Phase 2A) and risk_vcode_creation (Phase 1). '
  'Generates VCodes for a vacancy request. Blocked when either control is active/disabled.';


-- ═════════════════════════════════════════════════════════════════════════════
-- §6  Gate generate_vcodes_from_request → risk_vcode_creation
-- ═════════════════════════════════════════════════════════════════════════════
-- Carries forward OHM2026_0049 (20260712000000). Adds risk_vcode_creation gate.
-- Note: generate_vcodes_from_request delegates to generate_vcodes_for_request
-- which already checks the risk control, but we gate here defensively for
-- belt-and-suspenders completeness at the entry point.

CREATE OR REPLACE FUNCTION public.generate_vcodes_from_request(p_vacancy_request_id uuid)
RETURNS TABLE(vcode_id uuid, vcode text, sequence_num integer)
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_account_code  TEXT;
  v_group_code    TEXT;
  v_slots         INT;
  v_account_name  TEXT;
BEGIN
  -- ── Freeze Gate (Phase 2A) ─────────────────────────────────────────────────
  PERFORM public.fn_assert_freeze_inactive('recruitment_freeze');

  -- ── Risk Control Gate (Phase 1) ────────────────────────────────────────────
  PERFORM public.fn_assert_risk_control_enabled('risk_vcode_creation');

  -- Pull slots + account name from vacancy_request
  SELECT no_of_slots, account
  INTO v_slots, v_account_name
  FROM vacancy_requests
  WHERE id = p_vacancy_request_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Vacancy request not found: %', p_vacancy_request_id;
  END IF;

  IF v_slots IS NULL OR v_slots < 1 THEN
    RAISE EXCEPTION 'no_of_slots is null or invalid on this request.';
  END IF;

  -- Resolve account_code + group_code from account name
  SELECT a.account_code, g.group_code
  INTO v_account_code, v_group_code
  FROM accounts a
  JOIN groups g ON a.group_id = g.id
  WHERE LOWER(TRIM(a.account_name)) = LOWER(TRIM(v_account_name))
  LIMIT 1;

  IF v_account_code IS NULL THEN
    RAISE EXCEPTION 'Cannot resolve account_code for account: "%". Check accounts table.', v_account_name;
  END IF;

  -- Delegate to core generator
  RETURN QUERY
  SELECT r.vcode_id, r.vcode, r.sequence_num
  FROM generate_vcodes_for_request(
    p_vacancy_request_id,
    v_account_code,
    v_group_code,
    v_slots
  ) r;
END;
$function$;

REVOKE ALL ON FUNCTION public.generate_vcodes_from_request(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.generate_vcodes_from_request(uuid) TO authenticated;

COMMENT ON FUNCTION public.generate_vcodes_from_request(uuid) IS
  'OHM2026_0051: Gated with recruitment_freeze (Phase 2A) and risk_vcode_creation (Phase 1). '
  'Auto-resolves account/group codes and delegates to generate_vcodes_for_request.';


-- ═════════════════════════════════════════════════════════════════════════════
-- §7  Gate plantilla_get_atm → risk_export_sensitive_data
-- ═════════════════════════════════════════════════════════════════════════════
-- Carries forward original function body (remote_schema 20260520012857)
-- with risk control gate added after role check.

CREATE OR REPLACE FUNCTION public.plantilla_get_atm(p_plantilla_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_atm     text;
  v_account text;
  v_role    text := public.get_my_role();
BEGIN
  IF v_role = 'Viewer' THEN
    RAISE EXCEPTION 'forbidden: viewer cannot reveal ATM information' USING ERRCODE = '42501';
  END IF;

  -- ── Risk Control Gate (Phase 1) ────────────────────────────────────────────
  PERFORM public.fn_assert_risk_control_enabled('risk_export_sensitive_data');

  SELECT atm_no, account
  INTO v_atm, v_account
  FROM public.plantilla
  WHERE id = p_plantilla_id
    AND COALESCE(is_deleted, false) = false;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'plantilla not found';
  END IF;

  IF NOT public.i_have_full_access()
     AND NOT (v_account = ANY(public.get_my_allowed_accounts())) THEN
    RAISE EXCEPTION 'forbidden: account out of scope' USING ERRCODE = '42501';
  END IF;

  PERFORM public._log_employee_action(
    p_plantilla_id,
    'ATM_REVEAL',
    format('%s revealed ATM info', public.get_my_full_name()),
    null,
    jsonb_build_object(
      'revealed_by_role', v_role,
      'revealed_at', now()
    )
  );

  RETURN v_atm;
END;
$function$;

REVOKE ALL ON FUNCTION public.plantilla_get_atm(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.plantilla_get_atm(uuid) TO authenticated;

COMMENT ON FUNCTION public.plantilla_get_atm(uuid) IS
  'OHM2026_0051: Gated with risk_export_sensitive_data. Reveals ATM number for a Plantilla slot. '
  'Blocked when risk_export_sensitive_data is disabled.';


-- ═════════════════════════════════════════════════════════════════════════════
-- §8  Gate fn_request_emploc_deletion → risk_manual_deletion_actions
-- ═════════════════════════════════════════════════════════════════════════════
-- Carries forward OHM2026_0050 (20260713000000) which already gates for
-- audit_freeze. Adds risk_manual_deletion_actions gate.

CREATE OR REPLACE FUNCTION public.fn_request_emploc_deletion(
  p_hr_emploc_id       uuid,
  p_reason             text,
  p_deletion_type      text DEFAULT 'Backout',
  p_original_emploc_id uuid DEFAULT NULL
)
RETURNS public.hr_emploc_deletion_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_emp         public.hr_emploc;
  v_profile     public.users_profile;
  v_req         public.hr_emploc_deletion_requests;
  v_full_name   text;
  v_last_name   text;
  v_first_name  text;
  v_store       text;
  v_name        text;
  v_parts       text[];
BEGIN
  -- RBAC: Ops roles or full access
  IF NOT (public.i_am_ops() OR public.i_have_full_access()) THEN
    RAISE EXCEPTION 'forbidden: Ops or Admin role required'
      USING ERRCODE = '42501';
  END IF;

  -- ── Audit Freeze Gate (Phase 2A) ──────────────────────────────────────────
  PERFORM public.fn_assert_freeze_inactive('audit_freeze');

  -- ── Risk Control Gate (Phase 1) ────────────────────────────────────────────
  PERFORM public.fn_assert_risk_control_enabled('risk_manual_deletion_actions');

  IF p_deletion_type NOT IN ('Backout', 'Duplicate Record') THEN
    RAISE EXCEPTION 'invalid deletion_type: %. Must be Backout or Duplicate Record', p_deletion_type
      USING ERRCODE = '22023';
  END IF;

  IF p_deletion_type = 'Duplicate Record' AND p_original_emploc_id IS NULL THEN
    RAISE EXCEPTION 'original_emploc_id is required for Duplicate Record deletion type'
      USING ERRCODE = '22023';
  END IF;

  IF p_original_emploc_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.hr_emploc
      WHERE id = p_original_emploc_id AND deleted_at IS NULL
    ) THEN
      RAISE EXCEPTION 'original_emploc_id % not found or archived', p_original_emploc_id
        USING ERRCODE = 'P0002';
    END IF;
  END IF;

  IF NULLIF(BTRIM(COALESCE(p_reason, '')), '') IS NULL THEN
    RAISE EXCEPTION 'reason is required' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_emp FROM public.hr_emploc WHERE id = p_hr_emploc_id FOR UPDATE;
  IF NOT FOUND OR v_emp.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'hr_emploc % not found or already archived', p_hr_emploc_id
      USING ERRCODE = 'P0002';
  END IF;

  IF v_emp.moved_to_plantilla_at IS NOT NULL THEN
    RAISE EXCEPTION 'cannot request deletion: employee is already in Plantilla'
      USING ERRCODE = 'P0001';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.plantilla
    WHERE hr_emploc_id = p_hr_emploc_id
      AND COALESCE(is_deleted, false) = false
  ) THEN
    RAISE EXCEPTION 'cannot request deletion: active Plantilla record exists'
      USING ERRCODE = 'P0001';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.hr_emploc_deletion_requests
    WHERE hr_emploc_id = p_hr_emploc_id AND status = 'Pending'
  ) THEN
    RAISE EXCEPTION 'a pending deletion request already exists for this record'
      USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_profile FROM public.users_profile WHERE id = public.get_my_profile_id();
  v_full_name := COALESCE(v_profile.full_name, public.get_my_full_name());

  -- Immutable name snapshot (Last, First or First Last)
  v_name := COALESCE(v_emp.applicant_name_snapshot, v_emp.applicant_name);
  IF v_name LIKE '%, %' THEN
    v_last_name  := BTRIM(split_part(v_name, ', ', 1));
    v_first_name := BTRIM(split_part(v_name, ', ', 2));
  ELSE
    v_parts      := regexp_split_to_array(BTRIM(v_name), '\s+');
    v_last_name  := v_parts[array_length(v_parts, 1)];
    v_first_name := BTRIM(array_to_string(v_parts[1:array_length(v_parts,1)-1], ' '));
  END IF;

  v_store := COALESCE(NULLIF(BTRIM(COALESCE(v_emp.store_name, '')), ''), v_emp.account);

  INSERT INTO public.hr_emploc_deletion_requests (
    hr_emploc_id,
    applicant_name,
    vcode,
    account,
    reason,
    requested_by,
    requested_by_role,
    requested_by_user_id,
    deletion_type,
    original_emploc_id,
    reopen_vacancy,
    original_hr_status,
    snapshot_last_name,
    snapshot_first_name,
    snapshot_position,
    snapshot_store,
    status
  ) VALUES (
    p_hr_emploc_id,
    COALESCE(v_emp.applicant_name_snapshot, v_emp.applicant_name),
    v_emp.vcode,
    v_emp.account,
    BTRIM(p_reason),
    v_full_name,
    COALESCE(v_profile.role, public.get_my_role()),
    public.get_my_profile_id(),
    p_deletion_type,
    p_original_emploc_id,
    (p_deletion_type = 'Backout'),
    v_emp.hr_status,
    v_last_name,
    v_first_name,
    v_emp.position,
    v_store,
    'Pending'
  )
  RETURNING * INTO v_req;

  RETURN v_req;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_request_emploc_deletion(uuid, text, text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_request_emploc_deletion(uuid, text, text, uuid) TO authenticated;

COMMENT ON FUNCTION public.fn_request_emploc_deletion(uuid, text, text, uuid) IS
  'OHM2026_0051: Gated with audit_freeze (Phase 2A) and risk_manual_deletion_actions (Phase 1). '
  'Submits a deletion request for an HR Emploc record.';


-- ═════════════════════════════════════════════════════════════════════════════
-- §9  Gate plantilla_request_deletion → risk_manual_deletion_actions
-- ═════════════════════════════════════════════════════════════════════════════
-- Carries forward OHM2026_0050 (20260713000000) which already gates for
-- audit_freeze. Adds risk_manual_deletion_actions gate.

CREATE OR REPLACE FUNCTION public.plantilla_request_deletion(
  p_plantilla_id uuid,
  p_reason       text,
  p_remarks      text DEFAULT NULL
)
RETURNS public.plantilla
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_row public.plantilla;
BEGIN
  IF NOT public.i_can_act_on_plantilla() THEN
    RAISE EXCEPTION 'forbidden: insufficient role for deletion request';
  END IF;

  -- ── Audit Freeze Gate (Phase 2A) ──────────────────────────────────────────
  PERFORM public.fn_assert_freeze_inactive('audit_freeze');

  -- ── Risk Control Gate (Phase 1) ────────────────────────────────────────────
  PERFORM public.fn_assert_risk_control_enabled('risk_manual_deletion_actions');

  IF p_reason NOT IN ('Store Closed','Position No Longer Needed','Duplicate','Wrong Entry') THEN
    RAISE EXCEPTION 'invalid deletion_reason: %', p_reason;
  END IF;

  SELECT * INTO v_row FROM public.plantilla
  WHERE id = p_plantilla_id AND COALESCE(is_deleted, FALSE) = FALSE
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'plantilla not found'; END IF;

  IF v_row.status = 'Active' THEN
    RAISE EXCEPTION 'cannot delete an Active employee';
  END IF;

  IF NOT public.i_have_full_access()
     AND NOT (v_row.account = ANY(public.get_my_allowed_accounts())) THEN
    RAISE EXCEPTION 'forbidden: account out of scope';
  END IF;

  UPDATE public.plantilla
  SET deletion_requested_at = NOW(),
      deletion_requested_by = auth.uid(),
      deletion_reason       = p_reason,
      deletion_remarks      = p_remarks,
      updated_by            = auth.uid(),
      updated_at            = NOW()
  WHERE id = p_plantilla_id
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$function$;

REVOKE ALL ON FUNCTION public.plantilla_request_deletion(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.plantilla_request_deletion(uuid, text, text) TO authenticated;

COMMENT ON FUNCTION public.plantilla_request_deletion(uuid, text, text) IS
  'OHM2026_0051: Gated with audit_freeze (Phase 2A) and risk_manual_deletion_actions (Phase 1). '
  'Marks a Plantilla slot as deletion-requested.';


-- ═════════════════════════════════════════════════════════════════════════════
-- §10  Gate rollback_plantilla_import_batch → risk_import_rollback_actions
-- ═════════════════════════════════════════════════════════════════════════════
-- Carries forward OHM2026_0050 (20260713000000) which already gates for
-- audit_freeze. Adds risk_import_rollback_actions gate immediately after
-- the audit freeze check.

CREATE OR REPLACE FUNCTION public.rollback_plantilla_import_batch(
  p_batch_id uuid,
  p_reason   text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
DECLARE
  v_uid   uuid := auth.uid();
  v_actor uuid := public.get_current_profile_id();
  v_batch public.plantilla_import_batches%ROWTYPE;
  v_reason text := NULLIF(trim(COALESCE(p_reason, '')), '');
  v_archive_reason text;
  v_caller_role text;

  v_plantilla_restored      int := 0;
  v_plantilla_archived      int := 0;
  v_stores_restored         int := 0;
  v_stores_deactivated      int := 0;
  v_allocations_restored    int := 0;
  v_allocations_deactivated int := 0;
  v_roving_groups_archived  int := 0;
BEGIN
  -- ── Auth ─────────────────────────────────────────────────────────────────
  IF NOT public.fn_can_approve_plantilla_import() THEN
    RAISE EXCEPTION 'forbidden: Head Admin or Super Admin required'
      USING ERRCODE = '42501';
  END IF;

  -- ── Audit Freeze Gate (Phase 2A) ─────────────────────────────────────────
  PERFORM public.fn_assert_freeze_inactive('audit_freeze');

  -- ── Risk Control Gate (Phase 1) ────────────────────────────────────────────
  PERFORM public.fn_assert_risk_control_enabled('risk_import_rollback_actions');

  -- ── Caller role (for audit enrichment) ───────────────────────────────────
  v_caller_role := public.get_my_role();

  -- ── Advisory lock: serialise concurrent rollback/approval for this batch ──
  PERFORM pg_advisory_xact_lock(4207900, hashtext(p_batch_id::text));

  -- ── Lock + state check ───────────────────────────────────────────────────
  SELECT * INTO v_batch
    FROM public.plantilla_import_batches
   WHERE id = p_batch_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'BATCH_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  -- Idempotency guard: already rolled back
  IF v_batch.status = 'rolled_back' THEN
    RAISE EXCEPTION 'Batch already processed.'
      USING ERRCODE = 'P0001';
  END IF;

  IF v_batch.status <> 'approved' THEN
    RAISE EXCEPTION 'INVALID_STATE: only approved batches can be rolled back (current=%)',
      v_batch.status USING ERRCODE = '22023';
  END IF;

  IF NOT COALESCE(v_batch.rollback_ready, false) THEN
    RAISE EXCEPTION 'ROLLBACK_NOT_READY: batch has no completed rollback lineage'
      USING ERRCODE = '22023';
  END IF;

  IF NOT EXISTS (
    SELECT 1
      FROM public.plantilla_import_commit_snapshots s
     WHERE s.batch_id = p_batch_id
  ) THEN
    RAISE EXCEPTION 'ROLLBACK_NOT_READY: no commit snapshots found for batch'
      USING ERRCODE = '22023';
  END IF;

  v_archive_reason := 'Import batch rollback'
    || CASE WHEN v_reason IS NULL THEN '' ELSE ': ' || v_reason END;

  UPDATE public.plantilla_import_batches
     SET status = 'rollback_pending',
         rollback_error_detail = NULL,
         rollback_reason = v_reason,
         updated_at = now()
   WHERE id = p_batch_id;

  -- ── Entity rollback block ─────────────────────────────────────────────────
  BEGIN

    -- ── Batch-level superseded scope check ──────────────────────────────────
    IF EXISTS (
      SELECT 1
        FROM public.plantilla_import_batches newer
       WHERE newer.selected_group_id   = v_batch.selected_group_id
         AND newer.selected_account_id = v_batch.selected_account_id
         AND newer.status IN ('approved', 'rollback_pending')
         AND newer.approved_at > v_batch.approved_at
         AND newer.id <> p_batch_id
    ) THEN
      RAISE EXCEPTION 'ROLLBACK_UNSAFE: a newer approved import batch exists for this scope. Rolling back would corrupt newer batch state.'
        USING ERRCODE = '40001';
    END IF;

    -- ── Entity-level superseded checks ──────────────────────────────────────
    IF EXISTS (
      SELECT 1
        FROM public.plantilla_import_commit_snapshots s
        JOIN public.plantilla p ON p.id = s.entity_id
       WHERE s.batch_id = p_batch_id
         AND s.entity_type = 'plantilla'
         AND s.action = 'update'
         AND p.updated_at > v_batch.approved_at
         AND p.updated_by <> v_uid
    ) THEN
      RAISE EXCEPTION 'ROLLBACK_UNSAFE: one or more plantilla records have been modified since batch approval.'
        USING ERRCODE = '40001';
    END IF;

    -- ── 1. Restore plantilla rows from commit snapshots ──────────────────────
    WITH restored AS (
      UPDATE public.plantilla p
         SET status            = (s.before_state->>'status'),
             is_deleted        = COALESCE((s.before_state->>'is_deleted')::boolean, false),
             deleted_at        = (s.before_state->>'deleted_at')::timestamptz,
             updated_at        = now(),
             updated_by        = v_uid
        FROM public.plantilla_import_commit_snapshots s
       WHERE s.batch_id    = p_batch_id
         AND s.entity_type = 'plantilla'
         AND s.action IN ('create', 'update')
         AND p.id          = s.entity_id
      RETURNING p.id
    )
    SELECT count(*) INTO v_plantilla_restored FROM restored;

    -- ── 2. Archive newly-created plantilla rows ──────────────────────────────
    WITH archived AS (
      UPDATE public.plantilla p
         SET is_deleted  = true,
             deleted_at  = now(),
             updated_at  = now(),
             updated_by  = v_uid
        FROM public.plantilla_import_commit_snapshots s
       WHERE s.batch_id    = p_batch_id
         AND s.entity_type = 'plantilla'
         AND s.action      = 'create'
         AND p.id          = s.entity_id
         AND COALESCE(p.is_deleted, false) = false
      RETURNING p.id
    )
    SELECT count(*) INTO v_plantilla_archived FROM archived;

    -- ── 3. Restore stores ────────────────────────────────────────────────────
    WITH r AS (
      UPDATE public.stores st
         SET is_active  = COALESCE((s.before_state->>'is_active')::boolean, true),
             updated_at = now()
        FROM public.plantilla_import_commit_snapshots s
       WHERE s.batch_id    = p_batch_id
         AND s.entity_type = 'store'
         AND s.action      = 'update'
         AND st.id         = s.entity_id
      RETURNING st.id
    )
    SELECT count(*) INTO v_stores_restored FROM r;

    -- ── 4. Deactivate newly-created stores ──────────────────────────────────
    WITH d AS (
      UPDATE public.stores st
         SET is_active  = false,
             updated_at = now()
        FROM public.plantilla_import_commit_snapshots s
       WHERE s.batch_id    = p_batch_id
         AND s.entity_type = 'store'
         AND s.action      = 'create'
         AND st.id         = s.entity_id
         AND COALESCE(st.is_active, true) = true
      RETURNING st.id
    )
    SELECT count(*) INTO v_stores_deactivated FROM d;

    -- ── 5. Restore allocations ───────────────────────────────────────────────
    WITH r AS (
      UPDATE public.plantilla_allocations al
         SET allocated_hc = (s.before_state->>'allocated_hc')::int,
             updated_at   = now()
        FROM public.plantilla_import_commit_snapshots s
       WHERE s.batch_id    = p_batch_id
         AND s.entity_type = 'allocation'
         AND s.action      = 'update'
         AND al.id         = s.entity_id
      RETURNING al.id
    )
    SELECT count(*) INTO v_allocations_restored FROM r;

    -- ── 6. Deactivate newly-created allocations ──────────────────────────────
    WITH d AS (
      UPDATE public.plantilla_allocations al
         SET allocated_hc = 0,
             updated_at   = now()
        FROM public.plantilla_import_commit_snapshots s
       WHERE s.batch_id    = p_batch_id
         AND s.entity_type = 'allocation'
         AND s.action      = 'create'
         AND al.id         = s.entity_id
      RETURNING al.id
    )
    SELECT count(*) INTO v_allocations_deactivated FROM d;

    -- ── 7. Archive roving group assignments ──────────────────────────────────
    WITH r AS (
      UPDATE public.plantilla_roving_groups rg
         SET archived_at = now()
        FROM public.plantilla_import_commit_snapshots s
       WHERE s.batch_id    = p_batch_id
         AND s.entity_type = 'roving_group'
         AND s.action      = 'create'
         AND rg.id         = s.entity_id
         AND rg.archived_at IS NULL
      RETURNING rg.id
    )
    SELECT count(*) INTO v_roving_groups_archived FROM r;

    -- ── 8. Finalize batch ────────────────────────────────────────────────────
    UPDATE public.plantilla_import_batches
       SET status      = 'rolled_back',
           rolled_back_at = now(),
           rolled_back_by = v_actor,
           updated_at  = now()
     WHERE id = p_batch_id;

  EXCEPTION WHEN OTHERS THEN
    UPDATE public.plantilla_import_batches
       SET status             = 'rollback_failed',
           rollback_error_detail = SQLERRM,
           updated_at         = now()
     WHERE id = p_batch_id;

    RAISE;
  END;

  RETURN jsonb_build_object(
    'batch_id',                 p_batch_id,
    'status',                   'rolled_back',
    'plantilla_restored',       v_plantilla_restored,
    'plantilla_archived',       v_plantilla_archived,
    'stores_restored',          v_stores_restored,
    'stores_deactivated',       v_stores_deactivated,
    'allocations_restored',     v_allocations_restored,
    'allocations_deactivated',  v_allocations_deactivated,
    'roving_groups_archived',   v_roving_groups_archived
  );
END
$func$;

REVOKE ALL ON FUNCTION public.rollback_plantilla_import_batch(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rollback_plantilla_import_batch(uuid, text) TO authenticated;

COMMENT ON FUNCTION public.rollback_plantilla_import_batch(uuid, text) IS
  'OHM2026_0051: Gated with audit_freeze (Phase 2A) and risk_import_rollback_actions (Phase 1). '
  'Rolls back an approved Plantilla import batch to its pre-import state.';


-- ═════════════════════════════════════════════════════════════════════════════
-- §11  fn_get_risk_controls — Super Admin RPC to read Phase 1 risk controls
-- ═════════════════════════════════════════════════════════════════════════════
-- Returns all risk_* keys with their metadata for the Flutter UI.
-- Caller must be Super Admin (role_level >= 100).

CREATE OR REPLACE FUNCTION public.fn_get_risk_controls()
RETURNS TABLE(
  control_key     text,
  enabled         boolean,
  updated_at      timestamptz,
  reason          text,
  updated_by_name text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_level int;
BEGIN
  SELECT r.role_level INTO v_level
  FROM public.users_profile up
  JOIN public.roles r ON r.id = up.role_id
  WHERE up.auth_user_id = auth.uid();

  IF v_level IS NULL OR v_level < 100 THEN
    RAISE EXCEPTION 'Access denied: fn_get_risk_controls requires superAdmin.';
  END IF;

  RETURN QUERY
  SELECT
    gc.control_key,
    gc.enabled,
    gc.updated_at,
    gc.reason,
    up.full_name AS updated_by_name
  FROM public.governance_controls gc
  LEFT JOIN public.users_profile up ON up.id = gc.updated_by
  WHERE gc.control_key LIKE 'risk_%'
  ORDER BY gc.control_key;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_get_risk_controls() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_get_risk_controls() TO authenticated;

COMMENT ON FUNCTION public.fn_get_risk_controls() IS
  'OHM2026_0051: Fetches all Phase 1 risk controls (risk_* keys) with metadata. '
  'Restricted to Super Admin.';


COMMIT;
