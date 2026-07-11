-- ============================================================
-- OHM2026_2063 — Fix create_deactivation_request partial-index conflict
-- Migration:  20260524115000_fix_deactivation_request_rpc_conflict.sql
-- Depends on: 20260524110000_deactivation_v2_rpcs.sql
-- ============================================================
-- Root cause:
--   create_deactivation_request used:
--     ON CONFLICT ON CONSTRAINT uq_deact_req_pending_per_employee
--   uq_deact_req_pending_per_employee is a PARTIAL UNIQUE INDEX
--   defined in 20260524100000, not a named table constraint.
--   PostgreSQL only accepts named constraints (PRIMARY KEY, UNIQUE,
--   EXCLUSION created via CREATE TABLE / ALTER TABLE ... ADD CONSTRAINT)
--   in ON CONFLICT ON CONSTRAINT clauses.  Partial indexes must use
--   ON CONFLICT (cols) WHERE predicate OR an explicit pre-insert check.
--
-- Fix:
--   Replace ON CONFLICT ON CONSTRAINT with an explicit pre-insert
--   SELECT that detects a Pending duplicate before the INSERT.
--   The partial index uq_deact_req_pending_per_employee is PRESERVED
--   as a DB-level race-condition safety net; the EXCEPTION WHEN
--   unique_violation block also remains.
--
-- Idempotent behavior preserved:
--   - If Pending request already exists → return { idempotent: true }
--   - If new request created            → return { idempotent: false }
--   - Audit log written only for newly created requests
--
-- Validation Queries (run manually after applying):
--   V1 – RPC replaces successfully
--     SELECT proname FROM pg_proc
--     WHERE pronamespace = 'public'::regnamespace
--       AND proname = 'create_deactivation_request';
--   V2 – First call creates row (idempotent: false)
--     SELECT create_deactivation_request('<inactive_plantilla_id>');
--   V3 – Second call returns existing row (idempotent: true)
--     SELECT create_deactivation_request('<same_plantilla_id>');
--   V4 – Row appears in employee_deactivation_requests
--     SELECT * FROM employee_deactivation_requests
--     WHERE plantilla_id = '<plantilla_id>' AND status = 'Pending';
--   V5 – Audit log written once (not on duplicate call)
--     SELECT COUNT(*) FROM employee_deactivation_audit_log
--     WHERE plantilla_id = '<plantilla_id>' AND action = 'REQUEST_CREATED';
-- ============================================================


CREATE OR REPLACE FUNCTION public.create_deactivation_request(
  p_plantilla_id  uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_caller_id         uuid;
  v_row               public.plantilla;
  v_existing_req_id   uuid;
  v_new_req_id        uuid;
  v_group_id          uuid;
BEGIN
  -- ── Auth guard ───────────────────────────────────────────────
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;

  IF NOT (public.i_am_ops() OR public.i_have_full_access()) THEN
    RAISE EXCEPTION 'Insufficient permissions — Ops role required'
      USING ERRCODE = '42501';
  END IF;

  v_caller_id := public.get_current_profile_id();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'No active profile found for authenticated user'
      USING ERRCODE = '42501';
  END IF;

  -- ── Lock and load plantilla row ──────────────────────────────
  SELECT * INTO v_row
    FROM public.plantilla
   WHERE id = p_plantilla_id
     AND COALESCE(is_deleted, false) = false
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Plantilla row not found or already deleted: %', p_plantilla_id
      USING ERRCODE = 'P0002';
  END IF;

  -- ── Scope check ──────────────────────────────────────────────
  IF NOT public.i_have_full_access() THEN
    IF NOT (v_row.account_id::text = ANY(public.get_my_allowed_accounts())) THEN
      RAISE EXCEPTION 'Account not in caller scope'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  -- ── Status check ─────────────────────────────────────────────
  IF v_row.status <> 'Inactive' THEN
    -- Idempotent: if already Pending Deactivation, return existing request
    IF v_row.status = 'Pending Deactivation' THEN
      SELECT id INTO v_existing_req_id
        FROM public.employee_deactivation_requests
       WHERE plantilla_id = p_plantilla_id
         AND status = 'Pending'
         AND is_archived = false
       LIMIT 1;

      RETURN jsonb_build_object(
        'request_id',  v_existing_req_id,
        'plantilla_id', p_plantilla_id,
        'status', 'Pending',
        'idempotent', true
      );
    END IF;

    -- Handle legacy 'For Deactivation' gracefully before data migration
    IF v_row.status = 'For Deactivation' THEN
      RETURN jsonb_build_object(
        'request_id',  NULL,
        'plantilla_id', p_plantilla_id,
        'status', 'Pending',
        'idempotent', true,
        'note', 'Legacy For Deactivation row — awaiting data migration'
      );
    END IF;

    RAISE EXCEPTION 'Employee must be Inactive to request deactivation. Current status: %',
      v_row.status
      USING ERRCODE = 'P0001';
  END IF;

  -- ── Idempotent check: abort early if a Pending request exists ─
  -- uq_deact_req_pending_per_employee is a partial unique INDEX, not a
  -- named table constraint, so ON CONFLICT ON CONSTRAINT cannot reference
  -- it. Use an explicit pre-insert SELECT instead; the partial index
  -- remains as a race-condition safety net (caught by EXCEPTION WHEN
  -- unique_violation below).
  SELECT id INTO v_existing_req_id
    FROM public.employee_deactivation_requests
   WHERE plantilla_id = p_plantilla_id
     AND status = 'Pending'
     AND is_archived = false
   LIMIT 1;

  IF v_existing_req_id IS NOT NULL THEN
    RETURN jsonb_build_object(
      'request_id',   v_existing_req_id,
      'plantilla_id', p_plantilla_id,
      'status',       'Pending',
      'idempotent',   true
    );
  END IF;

  -- ── Resolve group_id ─────────────────────────────────────────
  SELECT group_id INTO v_group_id
    FROM public.user_scopes
   WHERE user_id = v_caller_id
   LIMIT 1;

  -- ── Create request ───────────────────────────────────────────
  INSERT INTO public.employee_deactivation_requests (
    plantilla_id,
    requestor_profile_id,
    group_id,
    account_id,
    employee_name,
    employee_no,
    account_name,
    status
  ) VALUES (
    p_plantilla_id,
    v_caller_id,
    v_group_id,
    v_row.account_id,
    v_row.employee_name,
    v_row.employee_no,
    v_row.account,
    'Pending'
  )
  RETURNING id INTO v_new_req_id;

  -- ── Update plantilla status ──────────────────────────────────
  UPDATE public.plantilla SET
    status                = 'Pending Deactivation',
    inactive_visible_until = NOW() + INTERVAL '30 days',
    updated_at            = NOW()
  WHERE id = p_plantilla_id;

  -- ── Audit log ────────────────────────────────────────────────
  INSERT INTO public.employee_deactivation_audit_log (
    request_id,
    plantilla_id,
    action,
    performed_by_profile_id,
    metadata
  ) VALUES (
    v_new_req_id,
    p_plantilla_id,
    'REQUEST_CREATED',
    v_caller_id,
    jsonb_build_object('employee_name', v_row.employee_name)
  );

  RETURN jsonb_build_object(
    'request_id',  v_new_req_id,
    'plantilla_id', p_plantilla_id,
    'status', 'Pending',
    'idempotent', false
  );

EXCEPTION
  WHEN unique_violation THEN
    -- Race condition safety net: partial index blocked the insert
    SELECT id INTO v_existing_req_id
      FROM public.employee_deactivation_requests
     WHERE plantilla_id = p_plantilla_id
       AND status = 'Pending'
       AND is_archived = false
     LIMIT 1;

    RETURN jsonb_build_object(
      'request_id',  v_existing_req_id,
      'plantilla_id', p_plantilla_id,
      'status', 'Pending',
      'idempotent', true
    );
END;
$$;


-- Re-assert grants (SECURITY DEFINER functions always need explicit grants)
REVOKE ALL ON FUNCTION public.create_deactivation_request(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_deactivation_request(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.create_deactivation_request(uuid) TO authenticated;

COMMENT ON FUNCTION public.create_deactivation_request(uuid) IS
  'Creates a v2 deactivation request for an Inactive employee. '
  'Idempotent — returns existing Pending row if duplicate. '
  'Caller must be Ops or full-access and within account scope. '
  'OHM2026_2063: replaced ON CONFLICT ON CONSTRAINT with explicit pre-insert '
  'duplicate check; uq_deact_req_pending_per_employee is a partial index, not a constraint.';
