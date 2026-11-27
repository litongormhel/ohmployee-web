-- ============================================================================
-- Migration: 20262606000213_fix_new_store_approval_and_account_kpi_parity.sql
-- Description:
--   1. Fix duplicate key violation on uq_plantilla_slots_legacy_vcode_ordinal
--      in approve_new_store_request (fn_trg_auto_create_vacancy_slot already
--      creates slot_ordinal 1..N upon INSERT INTO public.vacancies).
--   2. Backfill missing active employee_store_allocations for Active stationary
--      plantilla rows (e.g. BACKYARD AS100002) and harden v_account_allocation_kpi
--      (preserving all 19 columns in exact order) so Active plantilla employees
--      without an allocation row are never dropped to HC 0/0.
-- ============================================================================

BEGIN;

-- ── 1. Fix approve_new_store_request slot creation idempotency ──────────────
CREATE OR REPLACE FUNCTION public.approve_new_store_request(p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_reviewer_id        uuid;
  v_reviewer_name      text;
  v_reviewer_role      text;
  v_req                public.new_store_requests;
  v_new_store_id       uuid;
  v_requester_auth     uuid;
  v_requester_role     text;
  v_vcode              text;
  v_vacancy_id         uuid;
  v_existing_vacancy_id uuid;
  v_existing_slot_id   uuid;
  v_account_name       text;
  v_group_id           uuid;
  v_group_name         text;
  v_position_id        uuid;
  v_position_name      text;
  v_hrco_user_id       uuid;
  v_hrco_name          text;
  v_requester_name     text;
  v_om_user_id         uuid;
  v_om_auth_id         uuid;
  v_om_role            text;
  v_next_ordinal       integer;
  v_ordinal            integer;
BEGIN
  -- ── Auth guard: Data Team (30+), Head Admin (90), Super Admin (100) ────────
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;

  IF NOT (public.i_have_full_access() OR public.get_my_role_level() >= 30) THEN
    RAISE EXCEPTION 'Insufficient permissions — Data Team, Head Admin, or Super Admin required'
      USING ERRCODE = '42501';
  END IF;

  v_reviewer_id := public.get_current_profile_id();
  IF v_reviewer_id IS NULL THEN
    RAISE EXCEPTION 'No active profile found for authenticated user'
      USING ERRCODE = '42501';
  END IF;

  -- ── Resolve reviewer display name ─────────────────────────────
  SELECT
    COALESCE(
      NULLIF(TRIM(COALESCE(up.last_name,'') || ', ' || COALESCE(up.first_name,'')), ', '),
      up.full_name,
      'Unknown'
    ),
    COALESCE(ro.role_name, 'admin')
  INTO v_reviewer_name, v_reviewer_role
  FROM public.users_profile up
  LEFT JOIN public.roles ro ON ro.id = up.role_id
  WHERE up.id = v_reviewer_id;

  -- ── Lock and load request row ─────────────────────────────────
  SELECT * INTO v_req
  FROM public.new_store_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'New store request not found: %', p_request_id
      USING ERRCODE = 'P0002';
  END IF;

  IF v_req.status NOT IN ('pending', 'pending_super_admin') THEN
    RAISE EXCEPTION 'Request is not in pending status (current: %)', v_req.status
      USING ERRCODE = 'P0001';
  END IF;

  -- ── RESOLVE ACCOUNT & ORG DATA ────────────────────────────────
  SELECT a.account_name, COALESCE(v_req.group_id, a.group_id), a.hrco_user_id, a.om_user_id
  INTO v_account_name, v_group_id, v_hrco_user_id, v_om_user_id
  FROM public.accounts a
  WHERE a.id = v_req.account_id;

  IF v_group_id IS NOT NULL THEN
    SELECT group_name INTO v_group_name
    FROM public.groups WHERE id = v_group_id;
  END IF;

  IF v_hrco_user_id IS NOT NULL THEN
    SELECT full_name INTO v_hrco_name
    FROM public.users_profile WHERE id = v_hrco_user_id;
  END IF;

  SELECT p.id, p.position_name
  INTO v_position_id, v_position_name
  FROM public.positions p
  WHERE lower(trim(p.position_name)) = lower(trim(COALESCE(v_req.position, 'Merchandiser')))
  ORDER BY p.created_at ASC
  LIMIT 1;

  SELECT COALESCE(NULLIF(TRIM(v_req.requested_by_name), ''), up.full_name, v_reviewer_name)
  INTO v_requester_name
  FROM public.users_profile up
  WHERE up.id = v_req.requested_by;

  -- ── BRANCH A: STORE REACTIVATION ──────────────────────────────
  IF COALESCE(v_req.request_type, 'new_store') = 'reactivation' THEN
    v_new_store_id := v_req.store_id;

    -- Fetch existing store to preserve old VCode
    SELECT vcode INTO v_vcode
    FROM public.stores
    WHERE id = v_new_store_id;

    -- Strict Old VCode Preservation: if store has existing VCode, keep it. If NULL/empty, mint one
    IF v_vcode IS NULL OR TRIM(v_vcode) = '' THEN
      v_vcode := public.generate_vcode_for_account(v_req.account_id);
    END IF;

    -- Reactivate store
    UPDATE public.stores
    SET
      is_active   = true,
      is_archived = false,
      status      = 'active',
      archived_at = NULL,
      vcode       = v_vcode,
      approved_by = v_reviewer_id,
      approved_at = NOW(),
      updated_at  = NOW()
    WHERE id = v_new_store_id;

    -- Check if vacancy already exists for this vcode (unconditional vacancies_vcode_key guard)
    SELECT id INTO v_existing_vacancy_id
    FROM public.vacancies
    WHERE vcode = v_vcode
    LIMIT 1;

    IF v_existing_vacancy_id IS NOT NULL THEN
      UPDATE public.vacancies
      SET
        status               = 'Open',
        is_archived          = false,
        required_headcount   = 1,
        vacant_date          = CURRENT_DATE,
        position             = COALESCE(v_position_name, trim(v_req.position), 'Merchandiser'),
        position_id          = v_position_id,
        store_id             = v_new_store_id,
        account_id           = v_req.account_id,
        group_id             = v_group_id,
        store_name           = v_req.store_name,
        area_name            = v_req.province,
        area_city            = v_req.city,
        province             = v_req.province,
        chain                = v_group_name,
        chain_id             = v_group_id,
        vacancy_type         = 'New',
        employment_type      = 'Stationary',
        urgency_level        = 'Medium',
        triggered_by_user_id = COALESCE(v_req.requested_by, v_reviewer_id),
        triggered_by_name    = COALESCE(v_requester_name, v_reviewer_name),
        hrco_user_id         = v_hrco_user_id,
        hrco_name            = v_hrco_name,
        source               = 'hc_request',
        updated_at           = NOW(),
        updated_by           = v_reviewer_id
      WHERE id = v_existing_vacancy_id
      RETURNING id INTO v_vacancy_id;
    ELSE
      -- Provision initial 1 HC Open Vacancy
      INSERT INTO public.vacancies (
        vcode, account, position, status,
        account_id, store_id, position_id, group_id,
        area_name, store_name, vacant_date,
        required_headcount, source_plantilla_id,
        vacancy_type, employment_type, urgency_level,
        triggered_by_user_id, triggered_by_name,
        hrco_user_id, hrco_name,
        source, area_city, province,
        chain, chain_id,
        created_by, updated_by
      ) VALUES (
        v_vcode,
        COALESCE(v_account_name, v_req.account_name),
        COALESCE(v_position_name, trim(v_req.position), 'Merchandiser'),
        'Open',
        v_req.account_id,
        v_new_store_id,
        v_position_id,
        v_group_id,
        v_req.province,
        v_req.store_name,
        CURRENT_DATE,
        1,
        NULL,
        'New',
        'Stationary',
        'Medium',
        COALESCE(v_req.requested_by, v_reviewer_id),
        COALESCE(v_requester_name, v_reviewer_name),
        v_hrco_user_id,
        v_hrco_name,
        'hc_request',
        v_req.city,
        v_req.province,
        v_group_name,
        v_group_id,
        v_reviewer_id,
        v_reviewer_id
      )
      RETURNING id INTO v_vacancy_id;
    END IF;

    -- Provision 1 open slot in plantilla_slots (ADR-002 Invariant 1 & 5) if none open
    -- (fn_trg_auto_create_vacancy_slot may have already created it on vacancy insert/update)
    SELECT id INTO v_existing_slot_id
    FROM public.plantilla_slots
    WHERE (store_id = v_new_store_id OR legacy_vcode = v_vcode)
      AND slot_status = 'open'
      AND closed_at IS NULL
    LIMIT 1;

    IF v_existing_slot_id IS NULL THEN
      SELECT COALESCE(MAX(slot_ordinal), 0) + 1 INTO v_next_ordinal
      FROM public.plantilla_slots
      WHERE store_id = v_new_store_id OR legacy_vcode = v_vcode;

      IF NOT EXISTS (
        SELECT 1 FROM public.plantilla_slots
        WHERE legacy_vcode = v_vcode
          AND slot_ordinal = v_next_ordinal::smallint
      ) THEN
        INSERT INTO public.plantilla_slots (
          store_id, account_id, group_id,
          position, employment_type, is_roving,
          slot_status, slot_ordinal, legacy_vcode,
          current_occupant_plantilla_id,
          created_at, updated_at, created_by, updated_by
        ) VALUES (
          v_new_store_id, v_req.account_id, v_group_id,
          COALESCE(v_position_name, trim(v_req.position), 'Merchandiser'),
          'stationary', false,
          'open', v_next_ordinal::smallint, v_vcode,
          NULL,
          NOW(), NOW(), v_reviewer_id, v_reviewer_id
        );
      END IF;
    END IF;

  -- ── BRANCH B: NEW STORE REGISTRATION ──────────────────────────
  ELSE
    INSERT INTO public.stores (
      account_id,
      group_id,
      store_name,
      area_city,
      province,
      is_active,
      status,
      created_by,
      approved_by,
      approved_at
    ) VALUES (
      v_req.account_id,
      v_req.group_id,
      v_req.store_name,
      v_req.city,
      v_req.province,
      true,
      'active',
      v_req.requested_by,
      v_reviewer_id,
      NOW()
    )
    RETURNING id INTO v_new_store_id;

    IF COALESCE(v_req.requested_hc, 0) >= 1
       AND NULLIF(TRIM(COALESCE(v_req.position, '')), '') IS NOT NULL
    THEN
      v_vcode := public.generate_vcode_for_account(v_req.account_id);

      UPDATE public.stores
      SET vcode = v_vcode
      WHERE id = v_new_store_id
        AND (vcode IS NULL OR trim(vcode) = '');

      INSERT INTO public.vacancies (
        vcode, account, position, status,
        account_id, store_id, position_id, group_id,
        area_name, store_name, vacant_date,
        required_headcount, source_plantilla_id,
        vacancy_type, employment_type, urgency_level,
        triggered_by_user_id, triggered_by_name,
        hrco_user_id, hrco_name,
        source, area_city, province,
        chain, chain_id,
        created_by, updated_by
      ) VALUES (
        v_vcode,
        COALESCE(v_account_name, v_req.account_name),
        COALESCE(v_position_name, trim(v_req.position)),
        'Open',
        v_req.account_id,
        v_new_store_id,
        v_position_id,
        v_group_id,
        v_req.province,
        v_req.store_name,
        CURRENT_DATE,
        v_req.requested_hc,
        NULL,
        'New',
        'Stationary',
        'Medium',
        COALESCE(v_req.requested_by, v_reviewer_id),
        COALESCE(v_requester_name, v_reviewer_name),
        v_hrco_user_id,
        v_hrco_name,
        'hc_request',
        v_req.city,
        v_req.province,
        v_group_name,
        v_group_id,
        v_reviewer_id,
        v_reviewer_id
      )
      RETURNING id INTO v_vacancy_id;

      -- Ensure open slot(s) exist in plantilla_slots without colliding with
      -- fn_trg_auto_create_vacancy_slot() (which fires on INSERT INTO vacancies)
      FOR v_ordinal IN 1 .. GREATEST(COALESCE(v_req.requested_hc, 1), 1) LOOP
        IF NOT EXISTS (
          SELECT 1 FROM public.plantilla_slots
          WHERE legacy_vcode = v_vcode
            AND slot_ordinal = v_ordinal::smallint
        ) THEN
          INSERT INTO public.plantilla_slots (
            store_id, account_id, group_id,
            position, employment_type, is_roving,
            slot_status, slot_ordinal, legacy_vcode,
            current_occupant_plantilla_id,
            created_at, updated_at, created_by, updated_by
          ) VALUES (
            v_new_store_id, v_req.account_id, v_group_id,
            COALESCE(v_position_name, trim(v_req.position)),
            'stationary', false,
            'open', v_ordinal::smallint, v_vcode,
            NULL,
            NOW(), NOW(), v_reviewer_id, v_reviewer_id
          );
        END IF;
      END LOOP;
    END IF;
  END IF;

  -- ── Mark request as approved ──────────────────────────────────
  UPDATE public.new_store_requests
  SET
    status           = 'approved',
    reviewed_by      = v_reviewer_id,
    reviewed_by_name = v_reviewer_name,
    reviewed_at      = NOW(),
    created_store_id = v_new_store_id,
    updated_at       = NOW()
  WHERE id = p_request_id;

  -- ── Notify requester ──────────────────────────────────────────
  IF v_req.requested_by IS NOT NULL THEN
    SELECT auth_user_id, role_id::text
    INTO v_requester_auth, v_requester_role
    FROM public.users_profile
    WHERE id = v_req.requested_by;

    SELECT COALESCE(r.role_name, 'requester')
    INTO v_requester_role
    FROM public.users_profile up
    LEFT JOIN public.roles r ON r.id = up.role_id
    WHERE up.id = v_req.requested_by;

    IF v_requester_auth IS NOT NULL THEN
      PERFORM public.notify_user(
        p_user_id        => v_requester_auth,
        p_recipient_role => COALESCE(v_requester_role, 'requester'),
        p_title          => CASE
                              WHEN COALESCE(v_req.request_type, 'new_store') = 'reactivation'
                                THEN 'Store Reactivation Approved'
                              ELSE 'New Store Request Approved'
                            END,
        p_message        => CASE
                              WHEN COALESCE(v_req.request_type, 'new_store') = 'reactivation'
                                THEN format(
                                  'Your reactivation request for %s (%s) under %s has been approved. Original VCode %s preserved with 1 Open Vacancy.',
                                  v_req.store_name, v_req.city, COALESCE(v_account_name, v_req.account_name), v_vcode
                                )
                              ELSE format(
                                'Your new store request for %s (%s, %s) under %s has been approved by %s.',
                                v_req.store_name, v_req.city, v_req.province, COALESCE(v_account_name, v_req.account_name), v_reviewer_name
                              )
                            END,
        p_event_type     => CASE
                              WHEN COALESCE(v_req.request_type, 'new_store') = 'reactivation'
                                THEN 'store_reactivation_approved'
                              ELSE 'new_store_approved'
                            END,
        p_reference_type => 'new_store_request',
        p_reference_id   => p_request_id
      );
    END IF;
  END IF;

  -- ── Notify Operations Manager (OM) if assigned & distinct ─────
  IF v_om_user_id IS NOT NULL AND v_om_user_id IS DISTINCT FROM v_req.requested_by THEN
    SELECT up.auth_user_id, COALESCE(r.role_name, 'OM')
    INTO v_om_auth_id, v_om_role
    FROM public.users_profile up
    LEFT JOIN public.roles r ON r.id = up.role_id
    WHERE up.id = v_om_user_id;

    IF v_om_auth_id IS NOT NULL THEN
      PERFORM public.notify_user(
        p_user_id        => v_om_auth_id,
        p_recipient_role => COALESCE(v_om_role, 'OM'),
        p_title          => CASE
                              WHEN COALESCE(v_req.request_type, 'new_store') = 'reactivation'
                                THEN 'Store Reactivated'
                              ELSE 'New Store Approved'
                            END,
        p_message        => CASE
                              WHEN COALESCE(v_req.request_type, 'new_store') = 'reactivation'
                                THEN format(
                                  'Store %s under %s has been reactivated (VCode: %s) with 1 Open Vacancy for %s.',
                                  v_req.store_name, COALESCE(v_account_name, v_req.account_name), v_vcode, COALESCE(v_position_name, trim(v_req.position), 'Merchandiser')
                                )
                              ELSE format(
                                'New store %s (%s, %s) under %s has been approved.',
                                v_req.store_name, v_req.city, v_req.province, COALESCE(v_account_name, v_req.account_name)
                              )
                            END,
        p_event_type     => CASE
                              WHEN COALESCE(v_req.request_type, 'new_store') = 'reactivation'
                                THEN 'store_reactivation_approved'
                              ELSE 'new_store_approved'
                            END,
        p_reference_type => 'new_store_request',
        p_reference_id   => p_request_id
      );
    END IF;
  END IF;

  -- ── Audit Log ─────────────────────────────────────────────────
  PERFORM public.log_audit_event(
    p_action      => 'UPDATE',
    p_module      => 'approvals',
    p_target_type => 'new_store_request',
    p_target_id   => p_request_id,
    p_details     => jsonb_build_object(
      'event',          CASE WHEN COALESCE(v_req.request_type, 'new_store') = 'reactivation' THEN 'STORE_REACTIVATION_APPROVED' ELSE 'NEW_STORE_APPROVED' END,
      'request_type',   COALESCE(v_req.request_type, 'new_store'),
      'store_id',       v_new_store_id,
      'store_name',     v_req.store_name,
      'account_id',     v_req.account_id,
      'vcode',          v_vcode,
      'vacancy_id',     v_vacancy_id,
      'requested_hc',   v_req.requested_hc,
      'reviewed_by',    v_reviewer_name
    )
  );

  RETURN jsonb_build_object(
    'ok',           true,
    'request_id',   p_request_id,
    'store_id',     v_new_store_id,
    'vcode',        v_vcode,
    'vacancy_id',   v_vacancy_id,
    'request_type', COALESCE(v_req.request_type, 'new_store')
  );
END;
$function$;


-- ── 2. Backfill missing active employee_store_allocations for Active stationary plantilla ──
INSERT INTO public.employee_store_allocations (
  plantilla_id,
  employee_no,
  account_id,
  group_id,
  store_id,
  vcode,
  store_name,
  filled_hc,
  active_store_count,
  effective_start,
  is_active
)
SELECT
  p.id,
  p.employee_no,
  p.account_id,
  a.group_id,
  COALESCE(
    p.store_id,
    (
      SELECT s.id FROM public.stores s
      WHERE s.account_id = p.account_id
        AND (
          (p.vcode IS NOT NULL AND upper(s.vcode) = upper(p.vcode))
          OR lower(trim(s.store_name)) = lower(trim(p.store_name))
        )
      ORDER BY s.is_active DESC, s.created_at ASC
      LIMIT 1
    )
  ),
  p.vcode,
  p.store_name,
  1.0000,
  1,
  COALESCE(p.date_hired, CURRENT_DATE),
  true
FROM public.plantilla p
LEFT JOIN public.accounts a ON a.id = p.account_id
WHERE p.status = 'Active'
  AND (p.date_of_separation IS NULL OR p.date_of_separation > CURRENT_DATE)
  AND COALESCE(p.is_deleted, false) = false
  AND COALESCE(p.is_archived, false) = false
  AND COALESCE(p.is_pool_employee, false) = false
  AND COALESCE(lower(p.deployment_type), 'stationary') <> 'roving'
  AND p.account_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM public.employee_store_allocations esa
    WHERE esa.plantilla_id = p.id
      AND esa.is_active = true
  )
  AND COALESCE(
    p.store_id,
    (
      SELECT s.id FROM public.stores s
      WHERE s.account_id = p.account_id
        AND (
          (p.vcode IS NOT NULL AND upper(s.vcode) = upper(p.vcode))
          OR lower(trim(s.store_name)) = lower(trim(p.store_name))
        )
      ORDER BY s.is_active DESC, s.created_at ASC
      LIMIT 1
    )
  ) IS NOT NULL;


-- ── 3. Harden v_account_allocation_kpi (preserve all 19 columns in exact order) ──
CREATE OR REPLACE VIEW public.v_account_allocation_kpi
  WITH (security_invoker = true)
AS
WITH active_unallocated_plantilla AS (
  SELECT p.account_id,
         count(*)::numeric AS filled_hc,
         count(DISTINCT COALESCE(NULLIF(trim(p.employee_no), ''), p.id::text)) AS actual_hc
  FROM public.plantilla p
  WHERE p.status = 'Active'
    AND (p.date_of_separation IS NULL OR p.date_of_separation > CURRENT_DATE)
    AND COALESCE(p.is_deleted, false) = false
    AND COALESCE(p.is_archived, false) = false
    AND COALESCE(p.is_pool_employee, false) = false
    AND p.account_id IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM public.employee_store_allocations esa
      WHERE esa.plantilla_id = p.id
        AND esa.is_active = true
    )
  GROUP BY p.account_id
),
filled AS (
  SELECT a.account_id,
         round(COALESCE(sum(a.filled_hc), 0), 4) AS filled_hc,
         count(DISTINCT a.employee_no)            AS actual_hc
  FROM public.employee_store_allocations a
  JOIN public.plantilla p ON p.id = a.plantilla_id
  WHERE a.is_active
    AND p.status = 'Active'
    AND (p.date_of_separation IS NULL OR p.date_of_separation > CURRENT_DATE)
    AND COALESCE(p.is_deleted, false) = false
    AND COALESCE(p.is_archived, false) = false
  GROUP BY a.account_id
),
leave AS (
  SELECT p.account_id,
         count(*) AS leave_count
  FROM public.plantilla p
  WHERE p.status IN ('On Leave', 'on_leave')
    AND (p.date_of_separation IS NULL OR p.date_of_separation > CURRENT_DATE)
    AND COALESCE(p.is_deleted, false) = false
    AND COALESCE(p.is_archived, false) = false
  GROUP BY p.account_id
),
active_pipeline_candidates AS (
  SELECT he.account_id,
         he.vcode,
         LOWER(TRIM(he.applicant_name)) AS cand_name,
         he.coverage_group_id,
         he.coverage_slot_id
  FROM public.hr_emploc he
  LEFT JOIN public.vacancies v ON v.id = he.vacancy_id
  WHERE he.status <> ALL (ARRAY['Moved to Plantilla'::text, 'Backout'::text])
    AND he.deleted_at IS NULL
    AND COALESCE(v.is_pool_vacancy, false) = false
  UNION
  SELECT v.account_id,
         a.vacancy_vcode AS vcode,
         LOWER(TRIM(a.full_name)) AS cand_name,
         a.coverage_group_id,
         a.coverage_slot_id
  FROM public.applicants a
  JOIN public.vacancies v ON v.vcode = a.vacancy_vcode
  WHERE a.status <> ALL (ARRAY['Backout'::text, 'Rejected'::text, 'Failed'::text, 'Did Not Report'::text, 'Rejected by Ops'::text, 'Withdrew'::text, 'Hired'::text, 'archived'::text])
    AND COALESCE(a.is_archived, false) = false
    AND COALESCE(v.is_pool_vacancy, false) = false
    AND NOT EXISTS (
      SELECT 1 FROM public.plantilla p_act
      WHERE p_act.account_id = v.account_id
        AND p_act.status IN ('Active', 'On Leave', 'on_leave')
        AND (p_act.date_of_separation IS NULL OR p_act.date_of_separation > CURRENT_DATE)
        AND COALESCE(p_act.is_deleted, false) = false
        AND COALESCE(p_act.is_archived, false) = false
        AND (
          (a.coverage_group_id IS NOT NULL AND p_act.coverage_group_id = a.coverage_group_id)
          OR LOWER(TRIM(p_act.employee_name)) = LOWER(TRIM(a.full_name))
        )
    )
),
pipeline AS (
  SELECT account_id,
         count(DISTINCT COALESCE(coverage_slot_id::text, coverage_group_id::text, cand_name)) AS pipeline_count
  FROM active_pipeline_candidates
  GROUP BY account_id
),
active_cg_with_pipeline AS (
  SELECT DISTINCT cgs.coverage_group_id
  FROM public.coverage_group_stores cgs
  JOIN public.coverage_groups cg ON cg.id = cgs.coverage_group_id
  JOIN public.stores s ON s.id = cgs.store_id
  WHERE cgs.archived_at IS NULL
    AND cg.archived_at IS NULL
    AND NOT EXISTS (
      SELECT 1 FROM public.coverage_slots cs_act
      WHERE cs_act.coverage_group_id = cg.id
        AND cs_act.slot_status = 'active'
        AND cs_act.current_occupant_plantilla_id IS NOT NULL
    )
    AND (
      cg.id IN (SELECT coverage_group_id FROM active_pipeline_candidates WHERE coverage_group_id IS NOT NULL)
      OR s.vcode IN (SELECT vcode FROM active_pipeline_candidates WHERE vcode IS NOT NULL)
      OR cgs.store_id IN (
        SELECT v.store_id FROM public.vacancies v
        WHERE v.vcode IN (SELECT vcode FROM active_pipeline_candidates WHERE vcode IS NOT NULL)
      )
    )
),
coverage_slot_kpi AS (
  SELECT
    cg.account_id,
    COUNT(*) FILTER (
      WHERE cs.slot_status = 'active'
        AND (
          cs.current_occupant_plantilla_id IS NULL
          OR NOT EXISTS (
            SELECT 1 FROM public.employee_store_allocations esa
            WHERE esa.plantilla_id = cs.current_occupant_plantilla_id
              AND esa.account_id = cg.account_id
              AND esa.is_active = true
          )
        )
    )::numeric AS filled_hc,
    COUNT(DISTINCT cs.current_occupant_plantilla_id) FILTER (
      WHERE cs.slot_status = 'active'
        AND cs.current_occupant_plantilla_id IS NOT NULL
        AND NOT EXISTS (
          SELECT 1 FROM public.employee_store_allocations esa
          WHERE esa.plantilla_id = cs.current_occupant_plantilla_id
            AND esa.account_id = cg.account_id
            AND esa.is_active = true
        )
    ) AS actual_hc,
    COUNT(*) FILTER (
      WHERE cs.slot_status IN ('pipeline', 'hr_processing')
        AND cg.id NOT IN (SELECT coverage_group_id FROM active_cg_with_pipeline)
    ) AS pipeline_count,
    COUNT(*) FILTER (
      WHERE cs.slot_status = 'open'
        AND cg.id NOT IN (SELECT coverage_group_id FROM active_cg_with_pipeline)
    )::numeric AS slot_vacant_hc
  FROM public.coverage_slots cs
  JOIN public.coverage_groups cg ON cg.id = cs.coverage_group_id
  LEFT JOIN public.plantilla cp ON cp.id = cs.current_occupant_plantilla_id
  WHERE cg.archived_at IS NULL
    AND (
      cp.id IS NULL
      OR (
        cp.status = 'Active'
        AND (cp.date_of_separation IS NULL OR cp.date_of_separation > CURRENT_DATE)
        AND COALESCE(cp.is_deleted, false) = false
        AND COALESCE(cp.is_archived, false) = false
      )
    )
  GROUP BY cg.account_id
),
slot_vacant_non_roving AS (
  SELECT
    ps.account_id,
    COUNT(*) FILTER (
      WHERE ps.slot_status = 'open'
        AND ps.legacy_vcode NOT IN (SELECT vcode FROM active_pipeline_candidates WHERE vcode IS NOT NULL)
    ) AS vacant_slots
  FROM public.plantilla_slots ps
  INNER JOIN public.vacancies v
    ON  v.vcode = ps.legacy_vcode
   AND  v.deleted_at IS NULL
   AND  COALESCE(v.is_archived, false)    = false
   AND  COALESCE(v.is_pool_vacancy, false) = false
  WHERE ps.is_roving    = false
    AND ps.legacy_vcode IS NOT NULL
    AND ps.account_id   IS NOT NULL
  GROUP BY ps.account_id
),
slot_vacant_roving AS (
  SELECT
    ps.account_id,
    SUM(
      CASE WHEN ps.slot_status = 'open'
            AND ps.legacy_vcode NOT IN (SELECT vcode FROM active_pipeline_candidates WHERE vcode IS NOT NULL)
            AND NOT EXISTS (
              SELECT 1 FROM public.coverage_group_stores cgs
              WHERE cgs.store_id = ps.store_id
                AND cgs.coverage_group_id IN (SELECT coverage_group_id FROM active_cg_with_pipeline)
            )
           THEN 1.0 / NULLIF(grp.total_slots::numeric, 0)
           ELSE 0.0
      END
    ) AS vacant_hc
  FROM public.plantilla_slots ps
  JOIN (
    SELECT source_hc_request_id,
           COUNT(*) AS total_slots
    FROM public.plantilla_slots
    WHERE is_roving = true
      AND source_hc_request_id IS NOT NULL
    GROUP BY source_hc_request_id
  ) grp ON grp.source_hc_request_id = ps.source_hc_request_id
  WHERE ps.is_roving            = true
    AND ps.source_hc_request_id IS NOT NULL
    AND ps.account_id           IS NOT NULL
  GROUP BY ps.account_id
),
vacant AS (
  SELECT vv.account_id, count(*) AS open_hc
  FROM public.vacancies vv
  WHERE vv.status = 'Open'
    AND vv.deleted_at IS NULL
    AND COALESCE(vv.is_archived, false)       = false
    AND COALESCE(vv.is_pool_vacancy, false)   = false
    AND COALESCE(vv.affects_required_hc, true) = true
    AND vv.vcode NOT IN (SELECT vcode FROM active_pipeline_candidates WHERE vcode IS NOT NULL)
    AND NOT EXISTS (
      SELECT 1 FROM public.coverage_group_stores cgs
      WHERE cgs.store_id = vv.store_id
        AND cgs.coverage_group_id IN (SELECT coverage_group_id FROM active_cg_with_pipeline)
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.plantilla_slots ps_chk
      WHERE ps_chk.legacy_vcode = vv.vcode
        AND ps_chk.closed_at IS NULL
        AND ps_chk.slot_status IN ('pipeline', 'hr_processing', 'occupied')
    )
  GROUP BY vv.account_id
),
base AS (
  SELECT
    a.id          AS account_id,
    a.account_name,
    a.account_code,
    a.group_id,
    g.group_name,
    g.group_code,
    round(
      COALESCE(f.filled_hc, 0)
    + COALESCE(aup.filled_hc, 0)
    + COALESCE(csk.filled_hc, 0)
    + COALESCE(l.leave_count, 0),
    4)::numeric(12,4)                                                                AS filled_hc,
    (
      COALESCE(f.actual_hc, 0)
    + COALESCE(aup.actual_hc, 0)
    + COALESCE(csk.actual_hc, 0)
    + COALESCE(l.leave_count, 0)
    )::bigint                                                                        AS actual_hc,
    (COALESCE(p.pipeline_count, 0) + COALESCE(csk.pipeline_count, 0))::bigint       AS pipeline_count,
    COALESCE(v.open_hc, 0)                                                           AS open_hc,
    round(
      COALESCE(svn.vacant_slots,   0)::numeric
    + COALESCE(svr.vacant_hc,      0)::numeric
    + COALESCE(csk.slot_vacant_hc, 0)::numeric,
    0)::numeric(12,4)                                                                AS slot_vacant_hc,
    round(
      COALESCE(f.filled_hc,          0)
    + COALESCE(aup.filled_hc,        0)
    + COALESCE(csk.filled_hc,        0)
    + COALESCE(l.leave_count,        0)
    + COALESCE(p.pipeline_count,     0)
    + COALESCE(csk.pipeline_count,   0)
    + COALESCE(svn.vacant_slots,     0)::numeric
    + COALESCE(svr.vacant_hc,        0)::numeric
    + COALESCE(csk.slot_vacant_hc,   0)::numeric,
    0)::numeric(12,4)                                                                AS required_hc,
    COALESCE(l.leave_count, 0)::bigint                                               AS leave_count
  FROM public.accounts a
  LEFT JOIN public.groups                      g    ON g.id           = a.group_id
  LEFT JOIN filled                             f    ON f.account_id   = a.id
  LEFT JOIN active_unallocated_plantilla       aup  ON aup.account_id = a.id
  LEFT JOIN leave                              l    ON l.account_id   = a.id
  LEFT JOIN pipeline                           p    ON p.account_id   = a.id
  LEFT JOIN coverage_slot_kpi                  csk  ON csk.account_id = a.id
  LEFT JOIN vacant                             v    ON v.account_id   = a.id
  LEFT JOIN slot_vacant_non_roving             svn  ON svn.account_id = a.id
  LEFT JOIN slot_vacant_roving                 svr  ON svr.account_id = a.id
  WHERE a.is_active = true
    AND COALESCE(a.is_pool_account, false) = false
    AND (
         public.i_have_full_access()
      OR a.id = ANY (public.get_my_allowed_account_ids())
    )
)
SELECT
  account_id, account_name, account_code, group_id, group_name, group_code,
  filled_hc,
  actual_hc,
  pipeline_count,
  open_hc,
  required_hc,
  CASE WHEN required_hc = 0 THEN 0.0
       ELSE round(LEAST(1.0, GREATEST(0.0, actual_hc::numeric / required_hc)), 4) END AS mfr,
  CASE WHEN required_hc = 0 THEN 0.0
       ELSE round(LEAST(1.0, GREATEST(0.0, (actual_hc::numeric + pipeline_count) / required_hc)), 4) END AS projected_mfr,
  CASE WHEN required_hc = 0 THEN 0.0
       ELSE round(slot_vacant_hc / required_hc, 4) END                     AS vacancy_rate,
  CASE WHEN required_hc = 0 THEN 0.0
       ELSE round(pipeline_count / required_hc, 4) END                     AS pipeline_coverage,
  CASE WHEN required_hc = 0              THEN 'healthy'::text
       WHEN actual_hc::numeric / required_hc >= 1.0 THEN 'healthy'::text
       WHEN actual_hc::numeric / required_hc >= 0.9 THEN 'at_risk'::text
       ELSE                                   'critical'::text
  END                                                                       AS health_status,
  slot_vacant_hc,
  leave_count
FROM base;

ALTER VIEW public.v_account_allocation_kpi OWNER TO postgres;
GRANT SELECT ON public.v_account_allocation_kpi TO authenticated, service_role;

COMMIT;
