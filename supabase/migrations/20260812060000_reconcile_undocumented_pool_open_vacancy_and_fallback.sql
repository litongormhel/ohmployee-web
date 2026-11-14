-- ============================================================
-- ohm#f8k3n7wq — Reconciliation: capture undocumented live changes to
-- _apply_separation / fn_sync_slot_to_open / plantilla_update_separation
-- Migration: 20260812060000_reconcile_undocumented_pool_open_vacancy_and_fallback.sql
-- ============================================================
-- Root Cause
-- ----------
-- These three functions were found live on staging carrying a
-- `p_open_vacancy boolean DEFAULT false` param with no corresponding
-- migration file and no docs/state or .ai/handoff entry — an undocumented
-- change, discovered while investigating ohm#f8k3n7wq (wiring the
-- p_open_vacancy toggle into the Workforce Pool separation UI).
--
-- Widening the investigation found `fn_sync_slot_to_open` also carries a
-- SECOND, earlier undocumented addition predating p_open_vacancy — a
-- "pool fallback" branch (comment-tagged `ohm#7n4k9wpx` in the live body)
-- that lets the function act on `workforce_pool_slots` when no
-- `plantilla_slots` row matches. That change also has no migration file
-- or state-file entry anywhere in this repo.
--
-- Per AI.md's Migration Recovery Policy, this migration reconciles the
-- repository to match live staging exactly — it is NOT a new behavior
-- change. Every statement below is CREATE OR REPLACE with the body
-- captured verbatim from live `pg_get_functiondef()` output on staging
-- (qqiiznmqxfoamqytjica), captured 2026-08-12 during ohm#f8k3n7wq.
--
-- Behavior captured (already live, not introduced here)
-- -------------------------------------------------------
-- `fn_sync_slot_to_open`:
--   1. Non-pool path (plantilla_slots): byte-identical to pre-existing
--      ohm#7n4k9wpx behavior — p_open_vacancy is never read on this branch.
--   2. Pool path (workforce_pool_slots, matched via occupant_employee_id):
--      - p_open_vacancy = true  → slot released to 'open',
--        occupant_employee_id cleared. Linked vacancy untouched.
--      - p_open_vacancy = false (default) → seat eliminated: slot set to
--        'hc_reduced', occupant_employee_id cleared, deleted_at stamped;
--        any linked vacancies row (status='Open', deleted_at IS NULL)
--        soft-deleted (deleted_at = NOW()). No minimum-HC floor on this
--        path — pool "stores" are reliever/HQ seats, not real stores.
--
-- `_apply_separation` / `plantilla_update_separation`: both now accept
-- `p_open_vacancy boolean DEFAULT false` and pass it straight through to
-- fn_sync_slot_to_open. No other behavior changed in either function —
-- confirmed by diffing against the last known-documented bodies
-- (20260913000004 for plantilla_update_separation; the pg_get_functiondef
-- snapshot in docs/audit/adr001_before_snapshots_2026-08-03/ for
-- _apply_separation) outside of this one additive param + pass-through.
--
-- Scope-critical: this param and the pool branch are reached ONLY for
-- employees whose slot resolves via workforce_pool_slots.occupant_employee_id
-- (i.e. Workforce Pool employees). Regular Plantilla employees (resolved via
-- plantilla_slots) are completely unaffected — the non-pool branch never
-- reads p_open_vacancy.
--
-- Non-goals
-- ---------
-- • No schema/table/RLS/grant change — functions only.
-- • No data mutation.
-- • No change to any Flutter/Dart call site — this migration only makes
--   the repository match what staging already runs. Flutter wiring of the
--   p_open_vacancy toggle is a separate, separately-approved task.
--
-- Verification (run after supabase db push)
-- -------------------------------------------
-- SELECT proname, pg_get_function_identity_arguments(oid) AS args
--   FROM pg_proc
--  WHERE proname IN ('_apply_separation','plantilla_update_separation','fn_sync_slot_to_open');
-- -- Expected: all three list p_open_vacancy boolean as their final arg,
-- -- identical to the pre-migration live signatures (this migration is a
-- -- byte-identical re-apply, not a behavior change).
-- ============================================================

CREATE OR REPLACE FUNCTION public._apply_separation(
  p_plantilla_id uuid,
  p_separation_type text,
  p_separation_date date,
  p_remarks text,
  p_capability text,
  p_open_vacancy boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_old            plantilla%ROWTYPE;
  v_sep_status     text;
  v_sep_reason_code text;
BEGIN
  IF NOT public._can_act_on_plantilla(p_plantilla_id, p_capability) THEN
    RETURN jsonb_build_object('ok',false,'error','forbidden');
  END IF;

  SELECT * INTO v_old FROM public.plantilla WHERE id = p_plantilla_id FOR UPDATE;
  IF v_old.id IS NULL THEN
    RETURN jsonb_build_object('ok',false,'error','plantilla_not_found');
  END IF;
  IF v_old.status <> 'Active' THEN
    RETURN jsonb_build_object('ok',false,'error','only_active_can_be_separated','current_status',v_old.status);
  END IF;

  v_sep_status := CASE p_separation_type
    WHEN 'Resigned'   THEN 'Resigned'
    WHEN 'Endo'       THEN 'Endo'
    WHEN 'AWOL'       THEN 'AWOL'
    WHEN 'Separated'  THEN 'Others'
    WHEN 'Terminated' THEN 'Others'
    ELSE 'Others'
  END;

  UPDATE public.plantilla
  SET status              = 'Inactive',
      inactive_at         = NOW(),
      inactive_by         = public.get_current_profile_id(),
      date_of_separation  = p_separation_date,
      resignation_date    = p_separation_date,
      separation_status   = v_sep_status,
      remarks             = COALESCE(p_remarks, remarks),
      updated_at          = NOW(),
      updated_by          = public.get_current_profile_id()
  WHERE id = p_plantilla_id;

  -- Existing trigger trg_plantilla_separation_to_vacancy fires here
  -- and creates the backfill vacancy reusing the same vcode (plantilla_slots path only).

  PERFORM public._log_employee_action(
    p_plantilla_id,
    'SEPARATION_'||UPPER(p_separation_type),
    format('Employee marked %s effective %s', p_separation_type, p_separation_date),
    to_jsonb(v_old),
    jsonb_build_object('separation_type',p_separation_type,'date',p_separation_date,'remarks',p_remarks)
  );

  v_sep_reason_code := CASE p_separation_type
    WHEN 'Endo' THEN 'ENDO'
    ELSE 'RESIGNED'
  END;

  IF COALESCE(v_old.deployment_type, '') <> 'Roving' THEN
    PERFORM public.fn_sync_slot_to_open(
      p_plantilla_id => p_plantilla_id,
      p_reason_code  => v_sep_reason_code,
      p_performed_by => public.get_current_profile_id(),
      p_source_fn    => '_apply_separation',
      p_open_vacancy => p_open_vacancy
    );
  END IF;

  RETURN jsonb_build_object('ok',true,'plantilla_id',p_plantilla_id,'new_status','Inactive',
                            'separation_status',v_sep_status,'vcode',v_old.vcode);
END
$function$;

CREATE OR REPLACE FUNCTION public.fn_sync_slot_to_open(
  p_plantilla_id uuid,
  p_reason_code text DEFAULT 'RESIGNED'::text,
  p_performed_by uuid DEFAULT NULL::uuid,
  p_source_fn text DEFAULT NULL::text,
  p_open_vacancy boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
/*
  Phase 6.4 — non-blocking occupied→open slot sync (OHM2026_0022).

  Locates the slot by current_occupant_plantilla_id first (authoritative),
  falling back to legacy_vcode (1:1 bridge, non-roving only).
  Delegates to fn_set_slot_status with:
    p_new_status            = 'open'
    p_occupant_plantilla_id = NULL  (cleared automatically by fn_set_slot_status)

  Blocked or no_op results from fn_set_slot_status are logged via
  RAISE NOTICE and returned as-is — they never raise into the host RPC.

  ohm#7n4k9wpx: added pool fallback — when no plantilla_slots row matches
  (Workforce Pool employee), act on the corresponding workforce_pool_slots
  row instead. Purely additive for the plantilla_slots path above: only
  reached when that lookup already returned null, so non-pool separations
  are byte-identical to pre-change behavior.

  Workforce-Pool-scope follow-up (this migration): the pool branch is now
  conditional on p_open_vacancy, per explicit instruction that this
  default-flip applies ONLY to Workforce-Pool-linked separations, never to
  regular plantilla_slots employees:
    p_open_vacancy = true  → same as ohm#7n4k9wpx: release slot to 'open'
    p_open_vacancy = false (default) → eliminate the seat: slot goes
      straight to 'hc_reduced' (mirrors execute_pool_hc_reduction's write
      pattern, minus its formal request/approval scaffolding — separation
      is already RBAC-gated via _can_act_on_plantilla) and any linked
      vacancy is soft-deleted. No minimum-HC floor on this path — pool
      stores are reliever/HQ seats, not real stores, per instruction.
*/
DECLARE
  v_plantilla_row   record;
  v_slot_id         uuid;
  v_pool_slot_id    uuid;
  v_pool_vacancy_id uuid;
  v_result          jsonb;
BEGIN
  IF p_plantilla_id IS NULL THEN
    RAISE NOTICE
      'fn_sync_slot_to_open: skipped — p_plantilla_id is null (source=%)',
      COALESCE(p_source_fn, 'unknown');
    RETURN NULL;
  END IF;

  SELECT id, vcode, deployment_type, employee_no
    INTO v_plantilla_row
    FROM public.plantilla
   WHERE id = p_plantilla_id
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE NOTICE
      'fn_sync_slot_to_open: plantilla % not found, skipped (source=%)',
      p_plantilla_id, COALESCE(p_source_fn, 'unknown');
    RETURN NULL;
  END IF;

  IF COALESCE(v_plantilla_row.deployment_type, '') = 'Roving' THEN
    RAISE NOTICE
      'fn_sync_slot_to_open: skipped — roving plantilla % not in Phase 6.4 scope (source=%)',
      p_plantilla_id, COALESCE(p_source_fn, 'unknown');
    RETURN NULL;
  END IF;

  SELECT id INTO v_slot_id
    FROM public.plantilla_slots
   WHERE current_occupant_plantilla_id = p_plantilla_id
     AND is_roving = false
  LIMIT 1;

  IF v_slot_id IS NULL AND v_plantilla_row.vcode IS NOT NULL THEN
    SELECT id INTO v_slot_id
      FROM public.plantilla_slots
     WHERE legacy_vcode = v_plantilla_row.vcode
       AND is_roving    = false
    LIMIT 1;
  END IF;

  IF v_slot_id IS NULL THEN
    -- Pool fallback. Direct occupant FK (workforce_pool_slots.occupant_employee_id → plantilla.id).
    SELECT id, vacancy_id INTO v_pool_slot_id, v_pool_vacancy_id
      FROM public.workforce_pool_slots
     WHERE occupant_employee_id = p_plantilla_id
       AND status = 'filled'
       AND deleted_at IS NULL
    LIMIT 1;

    IF v_pool_slot_id IS NULL THEN
      -- No slot anywhere for this plantilla (pre-slot-era, roving, or genuinely unslotted).
      RETURN NULL;
    END IF;

    IF p_open_vacancy THEN
      UPDATE public.workforce_pool_slots
         SET status = 'open',
             occupant_employee_id = NULL,
             updated_at = NOW(),
             updated_by = COALESCE(p_performed_by::text, 'fn_sync_slot_to_open')
       WHERE id = v_pool_slot_id
         AND occupant_employee_id = p_plantilla_id
         AND status = 'filled';

      IF FOUND THEN
        RETURN jsonb_build_object(
          'status', 'ok', 'pool', true, 'action', 'opened',
          'slot_id', v_pool_slot_id, 'plantilla_id', p_plantilla_id,
          'reason_code', p_reason_code
        );
      ELSE
        RAISE NOTICE
          'fn_sync_slot_to_open: pool slot % no longer filled/occupant mismatch at write time, skipped (source=%)',
          v_pool_slot_id, COALESCE(p_source_fn, 'unknown');
        RETURN NULL;
      END IF;
    ELSE
      -- Default: eliminate the seat (no minimum-HC floor for pool per instruction).
      UPDATE public.workforce_pool_slots
         SET status = 'hc_reduced',
             occupant_employee_id = NULL,
             deleted_at = NOW(),
             updated_at = NOW(),
             updated_by = COALESCE(p_performed_by::text, 'fn_sync_slot_to_open')
       WHERE id = v_pool_slot_id
         AND occupant_employee_id = p_plantilla_id
         AND status = 'filled';

      IF FOUND THEN
        IF v_pool_vacancy_id IS NOT NULL THEN
          UPDATE public.vacancies
             SET deleted_at = NOW(),
                 updated_by = p_performed_by,
                 updated_at = NOW()
           WHERE id = v_pool_vacancy_id
             AND status = 'Open'
             AND deleted_at IS NULL;
        END IF;

        RETURN jsonb_build_object(
          'status', 'ok', 'pool', true, 'action', 'hc_reduced',
          'slot_id', v_pool_slot_id, 'plantilla_id', p_plantilla_id,
          'reason_code', p_reason_code
        );
      ELSE
        RAISE NOTICE
          'fn_sync_slot_to_open: pool slot % no longer filled/occupant mismatch at write time, skipped (source=%)',
          v_pool_slot_id, COALESCE(p_source_fn, 'unknown');
        RETURN NULL;
      END IF;
    END IF;
  END IF;

  -- ── Non-pool path — completely unchanged from ohm#7n4k9wpx ──────────────
  SELECT public.fn_set_slot_status(
    p_slot_id               => v_slot_id,
    p_new_status            => 'open',
    p_reason_code           => p_reason_code,
    p_performed_by          => p_performed_by,
    p_remarks               => format(
                                 'Phase 6.4 / %s / plantilla_id=%s / employee_no=%s / reason=%s',
                                 COALESCE(p_source_fn, 'unknown'),
                                 p_plantilla_id::text,
                                 COALESCE(v_plantilla_row.employee_no, 'null'),
                                 COALESCE(p_reason_code, 'null')
                               ),
    p_occupant_plantilla_id => NULL
  ) INTO v_result;

  IF (v_result->>'status') IN ('blocked', 'no_op') THEN
    RAISE NOTICE
      'fn_sync_slot_to_open: % for slot_id=% plantilla_id=% source=% — %',
      v_result->>'status', v_slot_id, p_plantilla_id,
      COALESCE(p_source_fn, 'unknown'),
      COALESCE(v_result->>'blocked_reason', 'same-state no_op');
  END IF;

  RETURN v_result;

EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE
    'fn_sync_slot_to_open: error for plantilla_id=% source=% — % (sqlstate=%)',
    p_plantilla_id, COALESCE(p_source_fn, 'unknown'), SQLERRM, SQLSTATE;
  RETURN NULL;
END;
$function$;

CREATE OR REPLACE FUNCTION public.plantilla_update_separation(
  p_plantilla_id uuid,
  p_separation_status text,
  p_effective_date date,
  p_remarks text DEFAULT NULL::text,
  p_open_vacancy boolean DEFAULT false
)
RETURNS plantilla
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_row              public.plantilla;
  v_sep_reason_code  text;
BEGIN
  IF NOT public._can_act_on_plantilla(p_plantilla_id, 'separate') THEN
    RAISE EXCEPTION 'forbidden: Ops role required for plantilla status update'
      USING ERRCODE = '42501';
  END IF;

  IF p_effective_date IS NULL THEN
    RAISE EXCEPTION 'effective_date is required';
  END IF;

  IF p_separation_status NOT IN ('Resigned','AWOL','Terminated','End of Contract','Endo','Others') THEN
    RAISE EXCEPTION 'invalid separation_status: %', p_separation_status;
  END IF;

  SELECT * INTO v_row
  FROM public.plantilla
  WHERE id = p_plantilla_id
    AND COALESCE(is_deleted, false) = false
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'plantilla not found: %', p_plantilla_id;
  END IF;

  IF NOT public.i_have_full_access()
     AND NOT (v_row.account = ANY(public.get_my_allowed_accounts())) THEN
    RAISE EXCEPTION 'forbidden: account out of scope'
      USING ERRCODE = '42501';
  END IF;

  UPDATE public.plantilla
     SET separation_status  = p_separation_status,
         date_of_separation = p_effective_date,
         status             = 'Inactive',
         remarks            = COALESCE(p_remarks, remarks),
         updated_by         = auth.uid(),
         updated_at         = NOW()
   WHERE id = p_plantilla_id
   RETURNING * INTO v_row;

  IF COALESCE(v_row.deployment_type, '') <> 'Roving' THEN
    v_sep_reason_code := CASE p_separation_status
      WHEN 'Endo'            THEN 'ENDO'
      WHEN 'End of Contract' THEN 'ENDO'
      ELSE 'RESIGNED'
    END;

    PERFORM public.fn_sync_slot_to_open(
      p_plantilla_id => p_plantilla_id,
      p_reason_code  => v_sep_reason_code,
      p_performed_by => public.get_current_profile_id(),
      p_source_fn    => 'plantilla_update_separation',
      p_open_vacancy => p_open_vacancy
    );
  END IF;

  RETURN v_row;
END;
$function$;

COMMENT ON FUNCTION public.plantilla_update_separation(uuid, text, date, text, boolean) IS
  'OHM2026_0072 + ohm#f8k3n7wq reconciliation: sets plantilla.status = ''Inactive'' for '
  'non-Resigned separations (Endo, AWOL, Terminated, End of Contract, Others). '
  'Phase 6.4 slot sync via fn_sync_slot_to_open, forwarding p_open_vacancy '
  '(default false) — has effect only for Workforce-Pool-linked employees; '
  'regular plantilla_slots employees are unaffected (param never read on that branch). '
  'Roving employees excluded (OHM2026_0017 Q6 carve-out).';
