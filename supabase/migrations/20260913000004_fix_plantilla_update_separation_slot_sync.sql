-- ============================================================
-- OHM2026_0072 — Fix plantilla_update_separation: add Phase 6.4 slot sync hook
-- Migration: 20260913000004_fix_plantilla_update_separation_slot_sync.sql
-- Depends on:
--   20260813000004_wire_occupied_open_slot_transition.sql
--     (fn_sync_slot_to_open — Phase 6.4 non-blocking helper)
--   20260913000000_fix_import_inactive_reconcile_and_slot_occupancy.sql
--     (slot occupancy backfill — ensures imported employees have a wired slot)
-- ============================================================
-- Root Cause
-- ----------
-- Phase 6.4 (OHM2026_0022, 20260813000004) wired the occupied→open slot
-- transition into TWO separation paths:
--
--   _apply_separation      — called by resign_employee, endo_employee (DB-level),
--                            separate_employee RPCs.
--   approve_deactivation_requests_batch — deactivation finalization.
--
-- However the Flutter client does NOT call resign_employee/endo_employee/
-- separate_employee for Endo, AWOL, Terminated, End of Contract, or Others
-- separation types. Instead, all non-Resigned separations call:
--
--   plantilla_update_separation(p_plantilla_id, p_separation_status, p_effective_date)
--
-- via PlantillaService.updateEmploymentStatus() → endoEmployee() / separateEmployee().
--
-- plantilla_update_separation sets status = 'Inactive' and writes separation
-- fields — but NEVER calls fn_sync_slot_to_open. The slot remains 'occupied'
-- after the status change, so the vacancy never reopens in the Vacancy Module
-- or vw_slot_derived_vacancy_shadow for these separation types.
--
-- (Resigned path IS correctly wired: Flutter calls resignEmployee() →
-- resign_employee RPC → _apply_separation → fn_sync_slot_to_open.)
--
-- Fix
-- ---
-- Patch plantilla_update_separation with the same non-blocking Phase 6.4
-- hook that _apply_separation carries:
--   1. DECLARE v_sep_reason_code text
--   2. After the UPDATE RETURNING, call fn_sync_slot_to_open (non-blocking)
--      with reason code ENDO (for Endo / End of Contract) or RESIGNED (all others).
--   3. Guard: roving employees skipped (deployment_type = 'Roving'),
--      same carve-out as OHM2026_0022.
-- All other function behavior is preserved IDENTICALLY from
-- 20260521062543_remote_schema.sql (the latest applied version).
--
-- Effect on the lifecycle
-- -----------------------
-- After this fix, when Ops tags an employee Inactive via any separation type
-- (Endo, AWOL, Terminated, End of Contract, Others), fn_sync_slot_to_open:
--   1. Locates the slot by current_occupant_plantilla_id (authoritative, set
--      by the OHM2026_0071 import slot wire) OR legacy_vcode bridge fallback.
--   2. Transitions slot_status: occupied → open.
--   3. Clears current_occupant_plantilla_id = NULL.
--   4. Appends slot_history row (reason ENDO or RESIGNED).
--   5. The vacancy VCODE now appears in vw_slot_derived_vacancy_shadow as
--      vacancy_tab = 'Open', open_count >= 1 → visible in Vacancy Open tab.
-- fn_sync_slot_to_open NEVER raises; errors are RAISE NOTICE only.
--
-- Non-goals
-- ---------
-- • Does NOT change Flutter or Dart code.
-- • Does NOT alter _apply_separation, approve_deactivation_requests_batch,
--   fn_sync_slot_to_open, or the shadow view.
-- • Does NOT affect roving employees (Phase 6.4 carve-out maintained).
-- • Does NOT change import, MIKA, or HR Emploc flows.
--
-- Replay safety
-- -------------
-- CREATE OR REPLACE — idempotent on re-apply.
-- No DDL changes to tables, indexes, or constraints.
--
-- Smoke Tests (run after supabase db push)
-- -----------------------------------------
-- T1 — Function body includes fn_sync_slot_to_open call
--   SELECT prosrc FROM pg_proc WHERE proname = 'plantilla_update_separation';
--   -- Expected: body contains 'fn_sync_slot_to_open'
--
-- T2 — Slot releases when employee is tagged Inactive (Endo)
--   -- Pre-condition: employee has status='Active', slot_status='occupied'
--   SELECT ps.slot_status, ps.current_occupant_plantilla_id
--   FROM plantilla_slots ps
--   INNER JOIN plantilla p ON p.id = ps.current_occupant_plantilla_id
--   WHERE p.employee_no = '2023-09515';
--   -- Expected before: occupied, plantilla_id set
--   -- Call: SELECT plantilla_update_separation('<id>', 'Endo', CURRENT_DATE);
--   -- Expected after: slot_status = 'open', current_occupant_plantilla_id = NULL
--
-- T3 — Released slot appears in shadow view
--   SELECT legacy_vcode, vacancy_tab, open_count
--   FROM vw_slot_derived_vacancy_shadow
--   WHERE legacy_vcode = (
--     SELECT vcode FROM plantilla WHERE employee_no = '2023-09515' LIMIT 1
--   );
--   -- Expected: 1 row, vacancy_tab = 'Open', open_count >= 1
--
-- T4 — Roving employees: fn_sync_slot_to_open NOT called (carve-out)
--   SELECT prosrc FROM pg_proc WHERE proname = 'plantilla_update_separation';
--   -- Body includes the deployment_type Roving guard — verified structurally.
-- ============================================================


CREATE OR REPLACE FUNCTION public.plantilla_update_separation(
  p_plantilla_id    uuid,
  p_separation_status text,
  p_effective_date  date,
  p_remarks         text DEFAULT NULL::text
)
RETURNS public.plantilla
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_row              public.plantilla;
  v_sep_reason_code  text;  -- Phase 6.4 slot reason code (OHM2026_0072)
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

  -- ── Phase 6.4: non-blocking slot occupied→open sync (OHM2026_0072) ──────
  -- Mirrors the hook added to _apply_separation by 20260813000004 (OHM2026_0022).
  -- When the employee's slot is 'occupied' (wired by OHM2026_0071 import backfill
  -- or by the Phase 6.3 hr_processing→occupied transition), fn_sync_slot_to_open
  -- transitions it to 'open', clears current_occupant_plantilla_id, and appends
  -- slot_history — making the vacancy visible again in the Vacancy Open tab.
  --
  -- Reason code: Endo / End of Contract → ENDO; everything else → RESIGNED.
  -- Roving carve-out: deployment_type = 'Roving' → skip (OHM2026_0017 Q6).
  -- fn_sync_slot_to_open NEVER raises; errors are RAISE NOTICE only.
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
      p_source_fn    => 'plantilla_update_separation'
    );
  END IF;

  RETURN v_row;
END;
$function$;

COMMENT ON FUNCTION public.plantilla_update_separation(uuid, text, date, text) IS
  'OHM2026_0072: Sets plantilla.status = ''Inactive'' for non-Resigned separations '
  '(Endo, AWOL, Terminated, End of Contract, Others). '
  'Phase 6.4 slot sync: after the UPDATE, calls fn_sync_slot_to_open '
  '(non-blocking) to transition the employee''s slot occupied→open, '
  'clearing current_occupant_plantilla_id and appending slot_history. '
  'Reason codes: Endo/End of Contract → ENDO; all others → RESIGNED. '
  'Roving employees excluded (OHM2026_0017 Q6 carve-out). '
  'All other behavior (RBAC, scope check, field writes) unchanged from '
  '20260521062543_remote_schema.sql.';
