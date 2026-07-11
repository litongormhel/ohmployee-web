-- OHM2026_0088: Reapply Plantilla additional-store approval RBAC guard
--
-- The original 20261014000000 migration may already be recorded in live
-- migration history, leaving the applied function with the older permission
-- guard. This follow-up replaces only fn_approve_plantilla_additional_store
-- so eligible Vacancy pipeline approvers are allowed without changing ESA,
-- HR Emploc, Plantilla duplication, or Store A / Store B behavior.
CREATE OR REPLACE FUNCTION public.fn_approve_plantilla_additional_store(
  p_applicant_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
/*
  OHM2026_0080 — Plantilla Additional Store Assignment (Option A)

  Called when an applicant whose applicant_source = 'plantilla' is confirmed
  onboard. Instead of the normal flow (HR Emploc → Plantilla), this function:
    1. Validates the applicant is plantilla-sourced with a valid linked employee
    2. Inserts a new employee_store_allocations row under the EXISTING plantilla record
       — NO new plantilla row is created; employee identity is preserved
    3. Calls fn_sync_slot_to_occupied with the existing plantilla.id (non-blocking)
    4. Closes the vacancy if all slots are now occupied (slot-aware guard)
    5. Updates the applicant status to 'Confirmed Onboard'
    6. Writes an audit log entry

  The existing Plantilla record and all its current store assignments are preserved.
  No assignment is removed. No vacancy is opened in the originating store.
  This is NOT a transfer workflow.

  RBAC: Vacancy pipeline approval authority: full-access admins, Encoder,
  Head Admin, Super Admin, or Ops Team (OM, HRCO, ATL, TL).

  Idempotent: returns true when applicant is already 'Confirmed Onboard'.
*/
DECLARE
  v_role         text  := public.get_my_role();
  v_role_level   int   := COALESCE(public.get_my_role_level(), 0);
  v_profile_id   uuid  := public.get_my_profile_id();

  v_app          public.applicants%ROWTYPE;
  v_linked_plt   public.plantilla%ROWTYPE;
  v_vac          public.vacancies%ROWTYPE;
  v_new_esa_id   uuid;
  v_target_vcode text;
BEGIN
  -- ── RBAC ─────────────────────────────────────────────────────────────────
  IF NOT (
    public.i_have_full_access()
    OR v_role_level IN (30, 90, 100)                 -- Encoder, Head Admin, Super Admin
    OR public.i_am_ops()
    OR v_role IN ('OM', 'HRCO', 'ATL', 'TL', 'Operations Manager')
  ) THEN
    RAISE EXCEPTION 'forbidden: Ops Team or Data Team required'
      USING ERRCODE = '42501';
  END IF;

  -- ── Fetch & lock applicant ───────────────────────────────────────────────
  SELECT * INTO v_app
    FROM public.applicants
   WHERE id = p_applicant_id
  FOR UPDATE;

  IF NOT FOUND OR COALESCE(v_app.is_archived, false) THEN
    RAISE EXCEPTION 'applicant % not found or archived', p_applicant_id
      USING ERRCODE = 'P0002';
  END IF;

  -- ── Source validation ────────────────────────────────────────────────────
  IF COALESCE(v_app.applicant_source, 'manual') <> 'plantilla' THEN
    RAISE EXCEPTION
      'applicant % is not a plantilla-sourced applicant (source=%)',
      p_applicant_id, COALESCE(v_app.applicant_source, 'manual')
      USING ERRCODE = '22023';
  END IF;

  IF v_app.linked_plantilla_id IS NULL THEN
    RAISE EXCEPTION
      'applicant % has applicant_source=plantilla but no linked_plantilla_id',
      p_applicant_id
      USING ERRCODE = '22023';
  END IF;

  -- ── Idempotent guard ─────────────────────────────────────────────────────
  IF v_app.status = 'Confirmed Onboard' THEN
    RETURN jsonb_build_object(
      'ok',             true,
      'applicant_id',   v_app.id,
      'applicant_status', v_app.status,
      'vcode',          v_app.vacancy_vcode,
      'idempotent',     true
    );
  END IF;

  -- ── Fetch linked plantilla employee (must be active) ─────────────────────
  -- Lock the row to prevent concurrent duplicate assignments
  SELECT * INTO v_linked_plt
    FROM public.plantilla
   WHERE id = v_app.linked_plantilla_id
     AND COALESCE(is_deleted, false)   = false
     AND COALESCE(is_archived, false)  = false
     AND status IN ('Active', 'For Deactivation', 'On Leave')
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION
      'linked plantilla employee % not found or not active',
      v_app.linked_plantilla_id USING ERRCODE = 'P0002';
  END IF;

  IF v_linked_plt.employee_no IS NULL OR btrim(v_linked_plt.employee_no) = '' THEN
    RAISE EXCEPTION 'linked plantilla employee has no employee_no'
      USING ERRCODE = '22023';
  END IF;

  v_target_vcode := v_app.vacancy_vcode;

  -- ── Fetch & lock target vacancy ──────────────────────────────────────────
  SELECT * INTO v_vac
    FROM public.vacancies
   WHERE vcode       = v_target_vcode
     AND COALESCE(is_archived, false) = false
     AND deleted_at  IS NULL
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'active vacancy not found for vcode %', v_target_vcode
      USING ERRCODE = 'P0002';
  END IF;

  IF COALESCE(v_vac.has_pending_closure, false) = true THEN
    RAISE EXCEPTION
      'onboarding blocked: vacancy % has a pending closure request',
      v_target_vcode USING ERRCODE = '55000';
  END IF;

  -- ── Scope check ──────────────────────────────────────────────────────────
  IF NOT public.i_have_full_access()
     AND NOT (v_vac.account = ANY(public.get_my_allowed_accounts())) THEN
    RAISE EXCEPTION 'forbidden: vacancy is outside caller scope'
      USING ERRCODE = '42501';
  END IF;

  -- ── Duplicate guard ───────────────────────────────────────────────────────
  -- Block: employee already has an active ESA row for this VCODE
  IF EXISTS (
    SELECT 1
      FROM public.employee_store_allocations
     WHERE plantilla_id = v_linked_plt.id
       AND vcode        = v_target_vcode
       AND is_active    = true
       AND effective_end IS NULL
  ) THEN
    RAISE EXCEPTION
      'employee % already has an active store allocation for VCODE %',
      v_linked_plt.employee_no, v_target_vcode
      USING ERRCODE = '23505';
  END IF;

  -- ── INSERT new ESA row under the existing Plantilla record ───────────────
  -- Identity: plantilla_id + employee_no come from the existing Plantilla row
  -- Store context: store_id, store_name, account_id, vcode from the target vacancy
  -- filled_hc=1.0 for a non-roving additional store assignment (single-slot HC contribution)
  INSERT INTO public.employee_store_allocations (
    plantilla_id,
    employee_no,
    store_id,
    store_name,
    vcode,
    account_id,
    group_id,
    filled_hc,
    active_store_count,
    effective_start,
    effective_end,
    is_active,
    created_by,
    created_at
  )
  VALUES (
    v_linked_plt.id,
    v_linked_plt.employee_no,
    v_vac.store_id,
    v_vac.store_name,
    v_target_vcode,
    v_vac.account_id,
    v_vac.chain_id,              -- chain_id maps to group_id in ESA
    1.0,                         -- non-roving additional store: full HC contribution
    1,                           -- active_store_count for this allocation row
    CURRENT_DATE,
    NULL,                        -- NULL effective_end = currently active
    true,
    v_profile_id,
    NOW()
  )
  RETURNING id INTO v_new_esa_id;

  -- ── Sync slot to occupied using the EXISTING plantilla record (non-blocking)
  PERFORM public.fn_sync_slot_to_occupied(
    p_vcode        => v_target_vcode,
    p_hr_emploc_id => NULL,
    p_plantilla_id => v_linked_plt.id,
    p_performed_by => v_profile_id,
    p_source_fn    => 'fn_approve_plantilla_additional_store'
  );

  -- ── Close vacancy if all slots now occupied ───────────────────────────────
  -- Uses the same NOT EXISTS slot guard as move_to_plantilla (OHM2026_0081)
  -- so multi-slot vacancies only close when every slot is occupied.
  IF v_vac.id IS NOT NULL THEN
    UPDATE public.vacancies
       SET status     = 'Filled',
           updated_at = NOW(),
           updated_by = v_profile_id
     WHERE id = v_vac.id
       AND NOT EXISTS (
         SELECT 1 FROM public.plantilla_slots ps
          WHERE ps.legacy_vcode = v_target_vcode
            AND ps.is_roving    = false
            AND ps.slot_status  IN ('open', 'pipeline', 'hr_processing')
       );
  END IF;

  -- VCODE fallback: close remaining Open vacancy for this VCODE
  UPDATE public.vacancies
     SET status     = 'Filled',
         updated_at = NOW(),
         updated_by = v_profile_id
   WHERE vcode      = v_target_vcode
     AND status     IN ('Open', 'For Sourcing')
     AND COALESCE(is_archived, false) = false
     AND deleted_at IS NULL
     AND NOT EXISTS (
       SELECT 1 FROM public.plantilla_slots ps
        WHERE ps.legacy_vcode = v_target_vcode
          AND ps.is_roving    = false
          AND ps.slot_status  IN ('open', 'pipeline', 'hr_processing')
     );

  -- ── Update applicant → Confirmed Onboard (terminal for this path) ─────────
  UPDATE public.applicants
     SET status     = 'Confirmed Onboard',
         hired_date = COALESCE(hired_date, CURRENT_DATE),
         updated_at = NOW(),
         updated_by = v_profile_id
   WHERE id = p_applicant_id;

  -- ── Audit log ─────────────────────────────────────────────────────────────
  INSERT INTO public.audit_logs (
    actor_id, module, action, record_id, new_data, role
  ) VALUES (
    v_profile_id,
    'Plantilla',
    'INSERT',
    v_new_esa_id,
    jsonb_build_object(
      'business_action',      'PLANTILLA_ADDITIONAL_STORE_ESA',
      'employee_no',          v_linked_plt.employee_no,
      'target_vcode',         v_target_vcode,
      'source_plantilla_id',  v_app.linked_plantilla_id,
      'applicant_id',         p_applicant_id,
      'new_esa_id',           v_new_esa_id,
      'target_store_id',      v_vac.store_id,
      'target_store_name',    v_vac.store_name,
      'label',                'Additional store assignment created'
    ),
    v_role
  );

  RETURN jsonb_build_object(
    'ok',               true,
    'applicant_id',     p_applicant_id,
    'applicant_status', 'Confirmed Onboard',
    'new_esa_id',       v_new_esa_id,
    'source_plantilla_id', v_linked_plt.id,
    'vcode',            v_target_vcode,
    'employee_no',      v_linked_plt.employee_no,
    'idempotent',       false
  );
END;
$$;

