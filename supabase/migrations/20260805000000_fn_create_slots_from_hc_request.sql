-- ============================================================
-- OHM2026_0003 — Slot Creation RPC: fn_create_slots_from_hc_request
-- Migration: 20260805000000_fn_create_slots_from_hc_request.sql
-- Depends on:
--   20260804000000_plantilla_slot_foundation_v1.sql
--     (plantilla_slots, slot_history, slot_reason_codes)
--   Pre-existing: headcount_requests, accounts, groups, stores,
--     positions, users_profile
--   Pre-existing helpers: get_my_role(), get_current_profile_id(),
--     i_have_full_access()
-- ============================================================
-- Scope: BACKEND RPC ONLY — slot creation foundation.
--   Creates plantilla_slots + slot_history rows from an approved
--   HC Request. One slot row and one history row per approved HC unit.
--
--   This migration deliberately does NOT:
--     • call, modify, or replace create_plantilla_slot_from_request,
--     • call, modify, or replace approve_headcount_request,
--     • update headcount_requests.status (not wired into approval yet),
--     • create Vacancy derivation from slots (deferred per architecture),
--     • alter Vacancy / Plantilla / Transfer / Import behavior,
--     • touch MFR / CENCOM,
--     • migrate or backfill existing data.
--   No existing table or RPC is modified. No existing behavior changes.
--
-- VACANCY DERIVATION NOT IMPLEMENTED YET.
--   Per the locked architecture (plantilla_slot_architecture.md v1.0),
--   vacancies will eventually be derived from slots. That derivation is
--   out of scope for this phase. The existing create_plantilla_slot_from_request
--   continues to own Vacancy creation from HC requests until the
--   architecture migration is formally wired.
--
-- ROVING MULTI-STORE COVERAGE NOT IMPLEMENTED HERE.
--   Roving slots are created with is_roving=true and store_id=NULL
--   (no fixed home store). Per-store coverage linkage for roving slots
--   is deferred to a later phase per the locked architecture.
--   Stationary slots are fully supported.
--
-- HC APPROVAL HOOK CANDIDATES (for future integration — NOT wired yet):
--   1. create_plantilla_slot_from_request (20260712000000_enforce_recruitment_freeze.sql)
--      — currently creates vacancies + pool plantilla rows for a request
--        in status='approved_pending_vcode', then sets it to 'completed'.
--      — Natural integration point: call fn_create_slots_from_hc_request
--        inside create_plantilla_slot_from_request so that slots are
--        created atomically alongside the existing vacancy creation.
--      — Requires confirming idempotency and status-guard alignment.
--   2. approve_headcount_request (20260520012857_remote_schema.sql)
--      — sets status to 'approved_pending_vcode'.
--      — Earlier hook: creates slots at approval time, before vacancies.
--      — Requires deciding whether slots should pre-exist vacancies or
--        be co-created; more architectural impact.
--
-- Validation Queries (run manually after applying):
--   V1 – Function exists
--     SELECT proname, prosecdef FROM pg_proc
--       JOIN pg_namespace ON pg_namespace.oid = pg_proc.pronamespace
--       WHERE pg_namespace.nspname = 'public'
--         AND proname = 'fn_create_slots_from_hc_request';
--   V2 – SECURITY DEFINER
--     SELECT prosecdef FROM pg_proc p
--       JOIN pg_namespace n ON n.oid = p.pronamespace
--       WHERE n.nspname = 'public'
--         AND p.proname = 'fn_create_slots_from_hc_request';
--     -- expect: true
--   V3 – Dry test with a known approved request (replace UUID):
--     SELECT fn_create_slots_from_hc_request('<approved_request_id>'::uuid);
--     -- expect: {"ok": true, "slots_created": N, ...}
--     -- then rollback to leave test data clean.
-- ============================================================


-- ============================================================
-- fn_create_slots_from_hc_request
-- ============================================================
-- Creates one plantilla_slots row + one slot_history row per
-- approved HC unit for a given headcount_requests record.
--
-- Parameters:
--   p_request_id  — the headcount_requests.id to source from.
--   p_quantity    — optional override for how many slots to create.
--                   Defaults to headcount_requests.headcount_needed.
--                   Must be > 0 when supplied.
--
-- Returns: jsonb
--   ok=true  → { ok, request_id, slots_created, slot_ids }
--   ok=false → { ok, error, [field|current|expected|hint] }
--
-- RBAC: Encoder | Head Admin | Super Admin
--   (Data Team + full-access roles, matching create_plantilla_slot_from_request)
--
-- Guards:
--   • HC request must exist.
--   • HC request status must be 'approved_pending_vcode'.
--   • Resolved quantity must be > 0.
--   • account_id must be present and reference a valid account.
--   • store_id, if present on the request, must reference a valid store.
--   • group_id (from request or account fallback), if resolvable, must
--     reference a valid group.
--   • position must be resolvable (via position_id or position_name_snapshot).
--
-- No direct table mutation from client — all writes are SECURITY DEFINER only.
-- plantilla_slots and slot_history are INSERT/UPDATE/DELETE-revoked from
-- authenticated/anon (enforced by the foundation migration RLS policies).

CREATE OR REPLACE FUNCTION public.fn_create_slots_from_hc_request(
  p_request_id uuid,
  p_quantity   integer DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_role            text    := public.get_my_role();
  v_caller_id       uuid    := public.get_current_profile_id();
  v_req             public.headcount_requests%ROWTYPE;
  v_account         public.accounts%ROWTYPE;
  v_store           public.stores%ROWTYPE;
  v_group           public.groups%ROWTYPE;
  v_position        public.positions%ROWTYPE;
  v_qty             integer;
  v_slot_id         uuid;
  v_slot_ids        uuid[]  := ARRAY[]::uuid[];
  v_is_roving       boolean;
  v_employment_type text;
  v_position_name   text;
  v_group_id        uuid;
  i                 integer;
BEGIN
  -- ── RBAC: Data Team (Encoder) and full-access roles ───────────────────────
  -- Mirrors the RBAC guard in create_plantilla_slot_from_request.
  IF v_role NOT IN ('Encoder', 'Head Admin', 'Super Admin') THEN
    RETURN jsonb_build_object(
      'ok',    false,
      'error', 'forbidden',
      'hint',  'requires Encoder, Head Admin, or Super Admin'
    );
  END IF;

  -- ── Fetch and pessimistically lock the HC request ─────────────────────────
  SELECT * INTO v_req
  FROM public.headcount_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF v_req.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'request_not_found');
  END IF;

  -- ── Guard: only approved requests are eligible for slot creation ──────────
  -- Status 'approved_pending_vcode' is set by approve_headcount_request().
  -- Slot creation for any other status is blocked to prevent orphaned slots.
  IF v_req.status <> 'approved_pending_vcode' THEN
    RETURN jsonb_build_object(
      'ok',      false,
      'error',   'request_not_in_approved_state',
      'current', v_req.status,
      'expected','approved_pending_vcode'
    );
  END IF;

  -- ── Resolve quantity ──────────────────────────────────────────────────────
  -- Caller override takes precedence; falls back to request headcount_needed.
  v_qty := COALESCE(p_quantity, v_req.headcount_needed, 1);

  IF v_qty < 1 THEN
    RETURN jsonb_build_object(
      'ok',    false,
      'error', 'invalid_quantity',
      'hint',  'quantity must be greater than 0'
    );
  END IF;

  -- ── Validate account (required) ───────────────────────────────────────────
  IF v_req.account_id IS NULL THEN
    RETURN jsonb_build_object(
      'ok',    false,
      'error', 'missing_account_id',
      'hint',  'headcount_requests.account_id is required for slot creation'
    );
  END IF;

  SELECT * INTO v_account FROM public.accounts WHERE id = v_req.account_id;
  IF v_account.id IS NULL THEN
    RETURN jsonb_build_object(
      'ok',    false,
      'error', 'invalid_reference',
      'field', 'account_id'
    );
  END IF;

  -- ── Validate store (when present on the request) ──────────────────────────
  -- Roving slots may have no fixed home store (store_id = NULL is allowed).
  IF v_req.store_id IS NOT NULL THEN
    SELECT * INTO v_store FROM public.stores WHERE id = v_req.store_id;
    IF v_store.id IS NULL THEN
      RETURN jsonb_build_object(
        'ok',    false,
        'error', 'invalid_reference',
        'field', 'store_id'
      );
    END IF;
  END IF;

  -- ── Resolve and validate group_id ─────────────────────────────────────────
  v_group_id := COALESCE(v_req.group_id, v_account.group_id);
  IF v_group_id IS NOT NULL THEN
    SELECT * INTO v_group FROM public.groups WHERE id = v_group_id;
    IF v_group.id IS NULL THEN
      RETURN jsonb_build_object(
        'ok',    false,
        'error', 'invalid_reference',
        'field', 'group_id'
      );
    END IF;
  END IF;

  -- ── Resolve position name ─────────────────────────────────────────────────
  -- Prefer live lookup via position_id; fall back to snapshot text.
  IF v_req.position_id IS NOT NULL THEN
    SELECT * INTO v_position FROM public.positions WHERE id = v_req.position_id;
    IF v_position.id IS NULL THEN
      RETURN jsonb_build_object(
        'ok',    false,
        'error', 'invalid_reference',
        'field', 'position_id'
      );
    END IF;
    v_position_name := v_position.position_name;
  ELSE
    v_position_name := v_req.position_name_snapshot;
  END IF;

  IF v_position_name IS NULL OR TRIM(v_position_name) = '' THEN
    RETURN jsonb_build_object(
      'ok',    false,
      'error', 'missing_position',
      'hint',  'no resolvable position on HC request'
    );
  END IF;

  -- ── Resolve employment_type and roving flag ───────────────────────────────
  v_employment_type := v_req.employment_type;
  -- Roving multi-store coverage linkage is deferred. Roving slots are created
  -- with is_roving=true and store_id=NULL; coverage is a future-phase attribute.
  v_is_roving := (v_employment_type = 'Roving');

  -- ── Create one slot + one history row per HC unit ─────────────────────────
  FOR i IN 1..v_qty LOOP

    INSERT INTO public.plantilla_slots (
      store_id,
      account_id,
      group_id,
      position,
      employment_type,
      is_roving,
      slot_status,
      created_by,
      updated_by
    ) VALUES (
      v_store.id,       -- NULL when store_id was absent on the HC request
      v_account.id,
      v_group_id,
      v_position_name,
      v_employment_type,
      v_is_roving,
      'open',
      v_caller_id,
      v_caller_id
    )
    RETURNING id INTO v_slot_id;

    v_slot_ids := array_append(v_slot_ids, v_slot_id);

    -- One history row per slot: records the creation event with reason HC_ADD.
    INSERT INTO public.slot_history (
      slot_id,
      account_id,
      action_type,
      new_value,
      reason_code,
      performed_by,
      remarks
    ) VALUES (
      v_slot_id,
      v_account.id,
      'created',
      'open',
      'HC_ADD',
      v_caller_id,
      format(
        'Slot %s of %s created from HC request %s — %s %s',
        i, v_qty,
        p_request_id::text,
        v_employment_type,
        v_position_name
      )
    );

  END LOOP;

  RETURN jsonb_build_object(
    'ok',            true,
    'request_id',    p_request_id,
    'slots_created', v_qty,
    'slot_ids',      v_slot_ids
  );

END;
$$;

COMMENT ON FUNCTION public.fn_create_slots_from_hc_request(uuid, integer) IS
  'Creates one plantilla_slots row + one slot_history row (reason HC_ADD) per '
  'approved HC unit. Reads position/employment_type/store/account/group from the '
  'headcount_requests row. HC request status must be approved_pending_vcode. '
  'Does not update HC request status; not wired into the approval flow yet. '
  'Vacancy derivation from slots is deferred (see plantilla_slot_architecture.md). '
  'RBAC: Encoder | Head Admin | Super Admin.';
