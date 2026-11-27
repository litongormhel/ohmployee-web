-- Fix notify_user parameter names and types in approve_new_store_request

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
        p_recipient_user_id => v_requester_auth,
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
        p_notification_type => 'approval',
        p_event_type     => CASE
                              WHEN COALESCE(v_req.request_type, 'new_store') = 'reactivation'
                                THEN 'store_reactivation_approved'
                              ELSE 'new_store_approved'
                            END,
        p_reference_type => 'new_store_request',
        p_reference_id   => p_request_id::text,
        p_deep_link_route => '/approvals?tab=new_stores'
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
        p_recipient_user_id => v_om_auth_id,
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
        p_notification_type => 'approval',
        p_event_type     => CASE
                              WHEN COALESCE(v_req.request_type, 'new_store') = 'reactivation'
                                THEN 'store_reactivation_approved'
                              ELSE 'new_store_approved'
                            END,
        p_reference_type => 'new_store_request',
        p_reference_id   => p_request_id::text,
        p_deep_link_route => '/approvals?tab=new_stores'
      );
    END IF;
  END IF;

  -- ── Audit Log ─────────────────────────────────────────────────
  PERFORM public.log_audit_event(
    p_module    => 'new_store_requests',
    p_action    => 'UPDATE',
    p_record_id => p_request_id,
    p_old_data  => jsonb_build_object('status', v_req.status),
    p_new_data  => jsonb_build_object(
      'status',         'approved',
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
