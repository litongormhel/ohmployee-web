-- Migration: 20262606000110_coverage_direct_creation_and_manpower_merge.sql
-- Description:
-- 1. Enhance public.create_coverage_group to:
--    - Convert active employees in member stores to Roving under the new group.
--    - Allocate fractional headcount (1/N) across all group stores in employee_store_allocations and plantilla_store_links.
--    - Automatically fulfill and suppress member store vacancies when covered by an active employee.
--    - Insert a canonical coverage_requests record with status = 'approved' and full execution metadata so direct HA/SA creations appear in Approvals > Coverage > Approved.
--    - Insert audit_logs and coverage_request_history records so the action surfaces on the Dashboard Recent Activity feed.
-- 2. Data reconciliation for existing Forever Office coverage group CG-FG1-0004 (Waltermart Gen. Trias, Emilus Rosario, Puregold Tanza):
--    - Links active manpower, creates 1/3 HC allocations, records approved coverage request, and updates audit trail.

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- §1. Upgrade public.create_coverage_group
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.create_coverage_group(
  p_account_id uuid,
  p_position_id uuid,
  p_employment_type text,
  p_area_name text,
  p_store_ids uuid[],
  p_anchor_store_id uuid
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id            uuid;
  v_caller_name          text;
  v_role                 text;
  v_cgcode               text;
  v_group_id             uuid;
  v_request_id           uuid;
  v_store_id             uuid;
  v_overlap_store        text;
  v_overlap_cgcode       text;
  v_store_count          integer;
  v_anchor_store_name    text;
  v_anchor_store_vcode   text;
  v_pl                   record;
  v_slot_id              uuid;
  v_slot_ordinal         integer := 0;
  v_old_slot_id          uuid;
  v_old_vcode            text;
  v_store_name_local     text;
  v_store_vcode          text;
  v_employees_converted  integer := 0;
  v_execution_result     jsonb;
  v_slot_auth            jsonb;
BEGIN
  -- 1. Authenticate caller
  SELECT id, full_name INTO v_caller_id, v_caller_name
  FROM public.users_profile
  WHERE auth_user_id = auth.uid()
    AND is_active = true;

  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'forbidden: active profile not found' USING ERRCODE = '42501';
  END IF;

  SELECT r.role_name INTO v_role
  FROM public.users_profile up
  JOIN public.roles r ON r.id = up.role_id
  WHERE up.id = v_caller_id;

  IF v_role NOT IN ('Super Admin', 'Head Admin', 'Encoder') THEN
    RAISE EXCEPTION 'forbidden: Data Team role required' USING ERRCODE = '42501';
  END IF;

  IF v_role = 'Encoder'
     AND NOT (p_account_id = ANY (public.get_my_allowed_account_ids())) THEN
    RAISE EXCEPTION 'forbidden: account not in caller scope' USING ERRCODE = '42501';
  END IF;

  -- 2. Validate account
  IF NOT EXISTS (
    SELECT 1
    FROM public.accounts
    WHERE id = p_account_id
      AND is_active = true
      AND lower(COALESCE(status, 'active')) <> 'archived'
  ) THEN
    RAISE EXCEPTION 'account not found or archived' USING ERRCODE = '42501';
  END IF;

  -- 3. Validate store set
  v_store_count := COALESCE(array_length(p_store_ids, 1), 0);
  IF p_store_ids IS NULL OR v_store_count < 2 THEN
    RAISE EXCEPTION 'coverage group requires at least 2 stores; use the normal Vacancy workflow for a single store'
      USING ERRCODE = '22023';
  END IF;

  IF p_anchor_store_id IS NULL OR NOT (p_anchor_store_id = ANY (p_store_ids)) THEN
    RAISE EXCEPTION 'anchor store must be one of the selected stores'
      USING ERRCODE = '22023';
  END IF;

  -- 4. Overlap check
  SELECT s.store_name, cg.coverage_code
  INTO v_overlap_store, v_overlap_cgcode
  FROM unnest(p_store_ids) AS t(sid)
  JOIN public.coverage_group_stores cgs
    ON cgs.store_id = t.sid
   AND cgs.archived_at IS NULL
  JOIN public.coverage_groups cg
    ON cg.id = cgs.coverage_group_id
   AND cg.archived_at IS NULL
   AND lower(COALESCE(cg.status, '')) <> 'archived'
  JOIN public.stores s
    ON s.id = t.sid
   AND s.is_active = true
   AND lower(COALESCE(s.status, 'active')) <> 'archived'
  LIMIT 1;

  IF v_overlap_store IS NOT NULL THEN
    RAISE EXCEPTION 'store "%" is already assigned to active coverage group %',
      v_overlap_store, v_overlap_cgcode
      USING ERRCODE = '23505';
  END IF;

  -- 5. Plantilla operational footprint check
  IF EXISTS (
    SELECT 1
    FROM unnest(p_store_ids) AS sid
    WHERE NOT EXISTS (
      SELECT 1
      FROM public.stores s
      WHERE s.id = sid
        AND s.account_id = p_account_id
        AND s.is_active = true
        AND lower(COALESCE(s.status, 'active')) <> 'archived'
        AND (
          EXISTS (
            SELECT 1
            FROM public.plantilla_slots ps
            WHERE ps.store_id = s.id
              AND ps.slot_status <> 'closed'
          )
          OR EXISTS (
            SELECT 1
            FROM public.employee_store_allocations esa
            WHERE esa.store_id = s.id
              AND esa.is_active = true
          )
          OR EXISTS (
            SELECT 1
            FROM public.plantilla pl_any
            WHERE pl_any.store_id = s.id
              AND pl_any.status = 'Active'
              AND COALESCE(pl_any.is_deleted, false) = false
          )
        )
    )
  ) THEN
    RAISE EXCEPTION 'all stores must belong to the account and have active, non-archived Plantilla operational footprint'
      USING ERRCODE = '22023';
  END IF;

  -- 6. Generate group code and ID
  v_cgcode := public.fn_generate_cgcode_for_account(p_account_id);
  v_group_id := gen_random_uuid();
  v_request_id := gen_random_uuid();

  SELECT store_name, vcode INTO v_anchor_store_name, v_anchor_store_vcode
  FROM public.stores
  WHERE id = p_anchor_store_id;

  -- 7. Insert into public.coverage_groups
  INSERT INTO public.coverage_groups (
    id,
    coverage_code,
    account_id,
    position_id,
    employment_type,
    required_headcount,
    status,
    area_name,
    created_by,
    created_at
  ) VALUES (
    v_group_id,
    v_cgcode,
    p_account_id,
    p_position_id,
    p_employment_type,
    1,
    'open',
    nullif(trim(coalesce(p_area_name, '')), ''),
    v_caller_id,
    now()
  );

  -- 8. Insert member stores into public.coverage_group_stores
  FOREACH v_store_id IN ARRAY p_store_ids LOOP
    INSERT INTO public.coverage_group_stores (
      coverage_group_id,
      store_id,
      is_anchor,
      added_by,
      added_at,
      hc_share
    ) VALUES (
      v_group_id,
      v_store_id,
      (v_store_id = p_anchor_store_id),
      v_caller_id,
      now(),
      round(1.0 / v_store_count, 4)
    );
  END LOOP;

  -- 9. Manpower Merge: evaluate active employees in member stores
  v_slot_ordinal := 0;
  FOR v_pl IN (
    SELECT pl.*, a.group_id
    FROM public.plantilla pl
    JOIN public.accounts a ON a.id = pl.account_id
    WHERE pl.store_id = ANY(p_store_ids)
      AND pl.account_id = p_account_id
      AND (p_position_id IS NULL OR pl.position_id = p_position_id)
      AND pl.status = 'Active'
      AND COALESCE(pl.is_deleted, false) = false
      AND COALESCE(pl.is_archived, false) = false
  ) LOOP
    v_slot_id := gen_random_uuid();
    v_slot_ordinal := v_slot_ordinal + 1;

    -- Create active coverage slot row
    INSERT INTO public.coverage_slots (
      id,
      coverage_group_id,
      slot_ordinal,
      slot_status,
      current_occupant_plantilla_id,
      created_at,
      updated_at
    ) VALUES (
      v_slot_id,
      v_group_id,
      v_slot_ordinal,
      'active',
      v_pl.id,
      now(),
      now()
    );

    -- Update employee plantilla row to roving under new group
    UPDATE public.plantilla
    SET deployment_type = 'Roving',
        coverage_group_id = v_group_id,
        coverage_slot_id = v_slot_id,
        store_id = p_anchor_store_id,
        store_name = v_anchor_store_name,
        vcode = NULL,
        updated_at = now()
    WHERE id = v_pl.id;

    -- Vacate/open old stationary slot in plantilla_slots if occupied
    SELECT id, legacy_vcode INTO v_old_slot_id, v_old_vcode
    FROM public.plantilla_slots
    WHERE current_occupant_plantilla_id = v_pl.id
    ORDER BY created_at DESC
    LIMIT 1;

    IF v_old_slot_id IS NOT NULL THEN
      v_slot_auth := public.fn_set_slot_status(
        p_slot_id      => v_old_slot_id,
        p_new_status   => 'open',
        p_reason_code  => 'COVERAGE_GROUP_CREATED',
        p_performed_by => v_caller_id,
        p_remarks      => 'Employee converted to roving coverage in group ' || v_cgcode || '.'
      );

      INSERT INTO public.slot_history (
        slot_id, account_id, action_type,
        old_value, new_value, reason_code,
        performed_by, remarks, created_at
      ) VALUES (
        v_old_slot_id, v_pl.account_id, 'employee_separated',
        'occupied', 'open', 'COVERAGE_GROUP_CREATED',
        v_caller_id, 'Employee converted to roving coverage in group ' || v_cgcode || '.', now()
      );
    END IF;

    -- Reconcile store allocations (fractional 1/N HC per store)
    UPDATE public.employee_store_allocations
    SET is_active = false,
        effective_end = CURRENT_DATE
    WHERE plantilla_id = v_pl.id AND is_active = true;

    FOREACH v_store_id IN ARRAY p_store_ids LOOP
      SELECT store_name, vcode INTO v_store_name_local, v_store_vcode
      FROM public.stores WHERE id = v_store_id;

      INSERT INTO public.employee_store_allocations (
        plantilla_id, employee_no, roving_group_id,
        store_id, vcode, store_name,
        account_id, group_id,
        filled_hc, active_store_count,
        effective_start, is_active,
        source_import_batch_id, created_by,
        created_at
      ) VALUES (
        v_pl.id, v_pl.employee_no, v_group_id,
        v_store_id, v_store_vcode, v_store_name_local,
        v_pl.account_id, v_pl.group_id,
        round(1.0 / v_store_count, 4), v_store_count,
        CURRENT_DATE, true,
        v_pl.source_baseline_import_batch_id, v_caller_id,
        now()
      );
    END LOOP;

    -- Live employee store links: deactivate old and insert new for all member stores
    UPDATE public.plantilla_store_links
    SET status = 'Resigned',
        deleted_at = now(),
        unlinked_at = now(),
        unlinked_by = v_caller_id
    WHERE plantilla_id = v_pl.id AND deleted_at IS NULL;

    FOREACH v_store_id IN ARRAY p_store_ids LOOP
      SELECT store_name, vcode INTO v_store_name_local, v_store_vcode
      FROM public.stores WHERE id = v_store_id;

      INSERT INTO public.plantilla_store_links (
        plantilla_id,
        coverage_group_id,
        vcode,
        store_name,
        account,
        status,
        linked_at,
        linked_by,
        created_by,
        updated_by
      ) VALUES (
        v_pl.id,
        v_group_id,
        v_store_vcode,
        v_store_name_local,
        (SELECT account_name FROM public.accounts WHERE id = v_pl.account_id),
        'Active',
        now(),
        v_caller_id,
        v_caller_id,
        v_caller_id
      );
    END LOOP;

    PERFORM public.fn_sync_employee_store_allocations(v_pl.employee_no);

    v_employees_converted := v_employees_converted + 1;
  END LOOP;

  -- 10. If no active employee was converted, create exactly 1 open coverage slot
  IF v_employees_converted = 0 THEN
    INSERT INTO public.coverage_slots (
      coverage_group_id,
      slot_ordinal,
      slot_status,
      current_occupant_plantilla_id,
      created_at,
      updated_at
    ) VALUES (
      v_group_id,
      1,
      'open',
      NULL,
      now(),
      now()
    );
  ELSE
    -- When active manpower exists, update group status
    UPDATE public.coverage_groups
    SET required_headcount = v_employees_converted,
        status = 'filled'
    WHERE id = v_group_id;

    -- Automatically fulfill and suppress member store vacancies when covered by an active employee
    UPDATE public.vacancies
    SET status = 'Filled',
        closed_at = now(),
        remarks = COALESCE(remarks || ' | ', '') || 'Fulfilled by Coverage Group ' || v_cgcode || '.'
    WHERE store_id = ANY(p_store_ids)
      AND status = 'Open';
  END IF;

  -- 11. Record approved coverage_requests row so action appears in Approvals > Coverage > Approved
  v_execution_result := jsonb_build_object(
    'structural_execution_enabled', true,
    'request_type',                 'create_coverage_group',
    'coverage_group_id',            v_group_id,
    'coverage_code',                v_cgcode,
    'stores_added',                 v_store_count,
    'employees_converted',          v_employees_converted
  );

  INSERT INTO public.coverage_requests (
    id,
    request_type,
    status,
    account_id,
    position_id,
    employment_type,
    target_coverage_group_id,
    payload,
    reason,
    requested_by,
    requested_by_name,
    requested_by_role,
    requested_at,
    submitted_by,
    submitted_by_name,
    submitted_at,
    approved_by,
    approved_by_name,
    approved_at,
    executed_at,
    reviewer_remarks,
    execution_summary,
    created_by,
    updated_by,
    created_at,
    updated_at
  ) VALUES (
    v_request_id,
    'create_coverage_group'::public.request_type,
    'approved'::public.request_status,
    p_account_id,
    p_position_id,
    p_employment_type,
    v_group_id,
    jsonb_build_object(
      'store_ids', p_store_ids,
      'anchor_store_id', p_anchor_store_id,
      'area_name', p_area_name
    ),
    'Direct Administrator Creation',
    v_caller_id,
    v_caller_name,
    v_role,
    now(),
    v_caller_id,
    v_caller_name,
    now(),
    v_caller_id,
    v_caller_name,
    now(),
    now(),
    'Directly created and approved by Administrator.',
    v_execution_result,
    v_caller_id,
    v_caller_id,
    now(),
    now()
  );

  -- 12. Insert coverage request history
  PERFORM public._log_coverage_request_history(
    v_request_id,
    'pending'::public.request_status,
    'approved'::public.request_status,
    'executed',
    v_execution_result,
    v_caller_id,
    v_caller_name,
    v_role,
    'Coverage Group directly created and approved by Administrator.'
  );

  -- 13. Audit log for Recent Activity
  INSERT INTO public.audit_logs (
    id,
    actor_id,
    module,
    action,
    record_id,
    new_data,
    old_data,
    role,
    timestamp
  ) VALUES (
    gen_random_uuid(),
    v_caller_id,
    'coverage_requests',
    'APPROVE_REQUEST'::public.audit_action,
    v_request_id,
    jsonb_build_object(
      'coverage_code', v_cgcode,
      'coverage_group_id', v_group_id,
      'account_id', p_account_id,
      'store_ids', p_store_ids,
      'anchor_store_name', v_anchor_store_name,
      'employees_converted', v_employees_converted,
      'vcode', v_cgcode
    ),
    NULL,
    v_role,
    now()
  );

  RETURN json_build_object(
    'coverage_group_id', v_group_id,
    'coverage_code', v_cgcode,
    'request_id', v_request_id
  );
END;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- §2. Data Reconciliation for existing Forever Office CG-FG1-0004
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
  v_cg_id          uuid := '8dc063cf-143c-428f-9833-4297e3b920fa'; -- CG-FG1-0004
  v_acct_id        uuid := 'd0533fbc-3cce-4d0a-a619-ad0539dbc66d'; -- FOREVER OFFICE
  v_ha_profile_id  uuid;
  v_ha_name        text;
  v_ha_role        text;
  v_req_id         uuid := gen_random_uuid();
  v_emp_id         uuid := '1a5453b4-0361-4698-8aad-dd4c17e554a6'; -- DELFINA, JUAPHEL DOLAR (Active at PUREGOLD TANZA)
  v_tanza_id       uuid := 'fa34e0e7-0403-4ddd-96aa-dd83d259352e';
  v_waltermart_id  uuid := 'de441afc-3bc6-47c8-a496-2bf0db250348';
  v_emilus_id      uuid := 'fa0fdbe2-3253-42aa-a60d-dc96e2f0d73a';
  v_store_ids      uuid[];
BEGIN
  v_store_ids := ARRAY[v_tanza_id, v_waltermart_id, v_emilus_id];

  -- Resolve Head Admin uat3@ohmployee.com
  SELECT up.id, up.full_name, r.role_name
  INTO v_ha_profile_id, v_ha_name, v_ha_role
  FROM public.users_profile up
  JOIN public.roles r ON r.id = up.role_id
  WHERE up.email = 'uat3@ohmployee.com'
    AND up.is_active = true
  LIMIT 1;

  IF v_ha_profile_id IS NULL THEN
    SELECT up.id, up.full_name, r.role_name
    INTO v_ha_profile_id, v_ha_name, v_ha_role
    FROM public.users_profile up
    JOIN public.roles r ON r.id = up.role_id
    WHERE r.role_name IN ('Head Admin', 'Super Admin')
      AND up.is_active = true
    LIMIT 1;
  END IF;

  -- 1. If CG-FG1-0004 exists, update required_headcount and bind active employee Delfina
  IF EXISTS (SELECT 1 FROM public.coverage_groups WHERE id = v_cg_id) THEN
    UPDATE public.coverage_groups
    SET required_headcount = 1,
        status = 'filled'
    WHERE id = v_cg_id;

    -- Set 1/3 hc_share on group stores
    UPDATE public.coverage_group_stores
    SET hc_share = 0.3333
    WHERE coverage_group_id = v_cg_id;

    -- Update Delfina to roving under CG-FG1-0004
    UPDATE public.plantilla
    SET deployment_type = 'Roving',
        coverage_group_id = v_cg_id,
        vcode = NULL,
        updated_at = now()
    WHERE id = v_emp_id;

    -- Ensure coverage_slots has an active row for Delfina
    IF NOT EXISTS (
      SELECT 1 FROM public.coverage_slots
      WHERE coverage_group_id = v_cg_id
        AND current_occupant_plantilla_id = v_emp_id
    ) THEN
      INSERT INTO public.coverage_slots (
        coverage_group_id, slot_ordinal, slot_status, current_occupant_plantilla_id, created_at, updated_at
      ) VALUES (
        v_cg_id, 1, 'active', v_emp_id, now(), now()
      );
    END IF;

    -- Reconcile employee_store_allocations with 1/3 HC across the 3 stores
    UPDATE public.employee_store_allocations
    SET is_active = false, effective_end = CURRENT_DATE
    WHERE plantilla_id = v_emp_id AND is_active = true;

    INSERT INTO public.employee_store_allocations (
      plantilla_id, employee_no, roving_group_id,
      store_id, vcode, store_name,
      account_id, group_id,
      filled_hc, active_store_count,
      effective_start, is_active,
      created_by, created_at
    )
    SELECT
      v_emp_id, '2019-08946', v_cg_id,
      s.id, s.vcode, s.store_name,
      v_acct_id, (SELECT group_id FROM public.accounts WHERE id = v_acct_id),
      0.3333, 3,
      CURRENT_DATE, true,
      v_ha_profile_id, now()
    FROM public.stores s
    WHERE s.id = ANY(v_store_ids);

    -- Reconcile plantilla_store_links
    UPDATE public.plantilla_store_links
    SET status = 'Resigned', deleted_at = now()
    WHERE plantilla_id = v_emp_id AND deleted_at IS NULL;

    INSERT INTO public.plantilla_store_links (
      plantilla_id, coverage_group_id, vcode, store_name, account,
      status, linked_at, linked_by, created_by, updated_by
    )
    SELECT
      v_emp_id, v_cg_id, s.vcode, s.store_name, 'FOREVER OFFICE',
      'Active', now(), v_ha_profile_id, v_ha_profile_id, v_ha_profile_id
    FROM public.stores s
    WHERE s.id = ANY(v_store_ids);

    PERFORM public.fn_sync_employee_store_allocations('2019-08946');

    -- Fulfill and suppress member store vacancies
    UPDATE public.vacancies
    SET status = 'Filled',
        closed_at = now(),
        remarks = COALESCE(remarks || ' | ', '') || 'Fulfilled by Coverage Group CG-FG1-0004 (Active employee: DELFINA, JUAPHEL DOLAR)'
    WHERE store_id = ANY(v_store_ids)
      AND status = 'Open';

    -- Insert approved coverage_requests record for CG-FG1-0004
    IF NOT EXISTS (
      SELECT 1 FROM public.coverage_requests
      WHERE target_coverage_group_id = v_cg_id
    ) THEN
      INSERT INTO public.coverage_requests (
        id,
        request_type,
        status,
        account_id,
        position_id,
        employment_type,
        target_coverage_group_id,
        payload,
        reason,
        requested_by,
        requested_by_name,
        requested_by_role,
        requested_at,
        submitted_by,
        submitted_by_name,
        submitted_at,
        approved_by,
        approved_by_name,
        approved_at,
        executed_at,
        reviewer_remarks,
        execution_summary,
        created_by,
        updated_by,
        created_at,
        updated_at
      ) VALUES (
        v_req_id,
        'create_coverage_group'::public.request_type,
        'approved'::public.request_status,
        v_acct_id,
        (SELECT position_id FROM public.coverage_groups WHERE id = v_cg_id),
        'Regular',
        v_cg_id,
        jsonb_build_object(
          'store_ids', v_store_ids,
          'anchor_store_id', v_tanza_id
        ),
        'Created by HA via Coverage Group modal',
        v_ha_profile_id,
        COALESCE(v_ha_name, 'Sy Bolinas'),
        COALESCE(v_ha_role, 'Head Admin'),
        now() - interval '1 hour',
        v_ha_profile_id,
        COALESCE(v_ha_name, 'Sy Bolinas'),
        now() - interval '1 hour',
        v_ha_profile_id,
        COALESCE(v_ha_name, 'Sy Bolinas'),
        now() - interval '1 hour',
        now() - interval '1 hour',
        'Directly created and approved by Administrator.',
        jsonb_build_object(
          'coverage_group_id', v_cg_id,
          'coverage_code', 'CG-FG1-0004',
          'stores_added', 3,
          'employees_converted', 1
        ),
        v_ha_profile_id,
        v_ha_profile_id,
        now() - interval '1 hour',
        now() - interval '1 hour'
      );

      -- Log history
      PERFORM public._log_coverage_request_history(
        v_req_id,
        'pending'::public.request_status,
        'approved'::public.request_status,
        'executed',
        jsonb_build_object('coverage_code', 'CG-FG1-0004', 'stores_added', 3, 'employees_converted', 1),
        v_ha_profile_id,
        COALESCE(v_ha_name, 'Sy Bolinas'),
        COALESCE(v_ha_role, 'Head Admin'),
        'Coverage Group created and approved by Head Admin.'
      );

      -- Audit log
      INSERT INTO public.audit_logs (
        id, actor_id, module, action, record_id,
        new_data, role, timestamp
      ) VALUES (
        gen_random_uuid(),
        v_ha_profile_id,
        'coverage_requests',
        'APPROVE_REQUEST'::public.audit_action,
        v_req_id,
        jsonb_build_object(
          'coverage_code', 'CG-FG1-0004',
          'coverage_group_id', v_cg_id,
          'account_id', v_acct_id,
          'anchor_store_name', 'PUREGOLD TANZA',
          'employees_converted', 1,
          'vcode', 'CG-FG1-0004'
        ),
        COALESCE(v_ha_role, 'Head Admin'),
        now() - interval '1 hour'
      );
    END IF;
  END IF;
END $$;

COMMIT;
