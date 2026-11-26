-- Migration: Store Reactivation Workflow & Old VCode Preservation
-- Enforces:
-- 1. Updates to public.new_store_requests (request_type, store_id, existing_vcode, status constraint)
-- 2. submit_store_reactivation_request RPC (Ops only, justification required, OM notified)
-- 3. withdraw_store_reactivation_request RPC (Ops/requester can withdraw ongoing request)
-- 4. approve_new_store_request surgical extension for reactivation (preserves old VCode, sets is_active=true, creates 1 open vacancy + 1 open slot)
-- 5. reject_new_store_request notification update for reactivation

BEGIN;

-- ── 1. Update new_store_requests Table Structure & Constraints ────────────────
ALTER TABLE public.new_store_requests
  ADD COLUMN IF NOT EXISTS request_type text NOT NULL DEFAULT 'new_store',
  ADD COLUMN IF NOT EXISTS store_id uuid REFERENCES public.stores(id),
  ADD COLUMN IF NOT EXISTS existing_vcode text;

-- Add check constraint for request_type if not exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'nsr_request_type_chk'
  ) THEN
    ALTER TABLE public.new_store_requests
      ADD CONSTRAINT nsr_request_type_chk CHECK (request_type IN ('new_store', 'reactivation'));
  END IF;
END $$;

-- Update status check constraint to include 'withdrawn'
ALTER TABLE public.new_store_requests DROP CONSTRAINT IF EXISTS nsr_status_chk;
ALTER TABLE public.new_store_requests
  ADD CONSTRAINT nsr_status_chk CHECK (status IN ('pending', 'pending_super_admin', 'approved', 'rejected', 'withdrawn'));

-- Duplicate protection index: only 1 pending reactivation per store
CREATE UNIQUE INDEX IF NOT EXISTS uq_nsr_pending_reactivation_per_store
  ON public.new_store_requests (store_id)
  WHERE status IN ('pending', 'pending_super_admin') AND is_archived = false AND request_type = 'reactivation';

-- ── 2. submit_store_reactivation_request RPC ─────────────────────────────────
CREATE OR REPLACE FUNCTION public.submit_store_reactivation_request(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id           uuid;
  v_caller_name         text;
  v_caller_role         text;
  v_store_id            uuid;
  v_store_rec           record;
  v_position            text;
  v_reason              text;
  v_new_req_id          uuid;
  v_dup_id              uuid;
  v_notif_rec           record;
  v_om_auth_id          uuid;
  v_om_role             text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;

  v_caller_id := public.get_current_profile_id();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'No active profile found for authenticated user'
      USING ERRCODE = '42501';
  END IF;

  -- Role check: Ops = OM, TL, ATL, HRCO, or role level >= 90 (HA, SA), or full access
  SELECT
    COALESCE(
      NULLIF(TRIM(COALESCE(up.last_name,'') || ', ' || COALESCE(up.first_name,'')), ', '),
      up.full_name,
      'Unknown'
    ),
    COALESCE(ro.role_name, 'admin')
  INTO v_caller_name, v_caller_role
  FROM public.users_profile up
  LEFT JOIN public.roles ro ON ro.id = up.role_id
  WHERE up.id = v_caller_id;

  IF NOT (
    public.i_have_full_access()
    OR public.get_my_role_level() >= 90
    OR v_caller_role IN ('Operations Manager', 'TL', 'ATL', 'HRCO', 'Super Admin', 'Head Admin')
  ) THEN
    RAISE EXCEPTION 'Insufficient permissions — Only Operations (OM, TL, ATL, HRCO) can request store reactivation'
      USING ERRCODE = '42501';
  END IF;

  v_store_id := (p_input->>'store_id')::uuid;
  v_position := TRIM(COALESCE(p_input->>'position', ''));
  v_reason   := TRIM(COALESCE(p_input->>'reason', ''));

  IF v_store_id IS NULL THEN
    RAISE EXCEPTION 'store_id is required' USING ERRCODE = '22023';
  END IF;
  IF v_position IS NULL OR v_position = '' THEN
    RAISE EXCEPTION 'Target position is required for initial 1 HC vacancy' USING ERRCODE = '22023';
  END IF;
  IF v_reason IS NULL OR v_reason = '' THEN
    RAISE EXCEPTION 'Operational justification (reason) is required' USING ERRCODE = '22023';
  END IF;

  SELECT s.id, s.store_name, s.area_city, s.province, s.account_id, s.group_id, s.vcode, s.is_active, s.is_archived, s.status, a.account_name, a.om_user_id
  INTO v_store_rec
  FROM public.stores s
  JOIN public.accounts a ON a.id = s.account_id
  WHERE s.id = v_store_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Store not found: %', v_store_id USING ERRCODE = 'P0002';
  END IF;

  -- Ensure store is actually archived/inactive
  IF v_store_rec.is_active = true AND v_store_rec.is_archived = false AND COALESCE(v_store_rec.status, '') <> 'archived' THEN
    RAISE EXCEPTION 'Store is already active. Reactivation applies only to archived stores.' USING ERRCODE = 'P0001';
  END IF;

  -- Check duplicate pending reactivation
  SELECT id INTO v_dup_id
  FROM public.new_store_requests
  WHERE store_id = v_store_id
    AND is_archived = false
    AND status IN ('pending', 'pending_super_admin')
  LIMIT 1;

  IF FOUND THEN
    RAISE EXCEPTION 'A reactivation request for this store is already pending review (request ID: %)', v_dup_id
      USING ERRCODE = '23505';
  END IF;

  INSERT INTO public.new_store_requests (
    request_type,
    store_id,
    existing_vcode,
    store_name,
    province,
    city,
    account_id,
    account_name,
    group_id,
    position,
    requested_hc,
    reason,
    requested_by,
    requested_by_name,
    status
  ) VALUES (
    'reactivation',
    v_store_id,
    v_store_rec.vcode,
    v_store_rec.store_name,
    v_store_rec.province,
    v_store_rec.area_city,
    v_store_rec.account_id,
    v_store_rec.account_name,
    v_store_rec.group_id,
    v_position,
    1,
    v_reason,
    v_caller_id,
    v_caller_name,
    'pending'
  )
  RETURNING id INTO v_new_req_id;

  -- Notify Data Team (Encoder, Head Admin, Super Admin)
  FOR v_notif_rec IN
    SELECT DISTINCT ON (up.auth_user_id)
      up.auth_user_id,
      ro.role_name
    FROM public.users_profile up
    JOIN public.roles ro ON ro.id = up.role_id
    JOIN auth.users au   ON au.id = up.auth_user_id
    WHERE up.is_active = true
      AND up.auth_user_id IS NOT NULL
      AND ro.role_name IN ('Super Admin', 'Head Admin', 'Encoder')
    ORDER BY up.auth_user_id
  LOOP
    BEGIN
      INSERT INTO public.notifications (
        recipient_role,
        recipient_user_id,
        notification_type,
        event_type,
        title,
        message,
        deep_link_route,
        reference_type,
        reference_id
      ) VALUES (
        v_notif_rec.role_name,
        v_notif_rec.auth_user_id,
        'new_store_request',
        'STORE_REACTIVATION_REQUEST_SUBMITTED',
        'Store Reactivation Request',
        v_caller_name || ' requested reactivation of store "' || v_store_rec.store_name || '" under ' || v_store_rec.account_name || '.',
        '/approvals?category=new_stores',
        'new_store_request',
        v_new_req_id::text
      );
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END LOOP;

  -- Notify OM of the account
  IF v_store_rec.om_user_id IS NOT NULL THEN
    SELECT up.auth_user_id, ro.role_name
    INTO v_om_auth_id, v_om_role
    FROM public.users_profile up
    JOIN public.roles ro ON ro.id = up.role_id
    WHERE up.id = v_store_rec.om_user_id;

    IF v_om_auth_id IS NOT NULL AND v_om_auth_id <> auth.uid() THEN
      BEGIN
        INSERT INTO public.notifications (
          recipient_role,
          recipient_user_id,
          notification_type,
          event_type,
          title,
          message,
          deep_link_route,
          reference_type,
          reference_id
        ) VALUES (
          v_om_role,
          v_om_auth_id,
          'new_store_request',
          'STORE_REACTIVATION_REQUEST_SUBMITTED',
          'Store Reactivation Requested',
          v_caller_name || ' submitted a reactivation request for store "' || v_store_rec.store_name || '".',
          '/approvals?category=new_stores',
          'new_store_request',
          v_new_req_id::text
        );
      EXCEPTION WHEN OTHERS THEN
        NULL;
      END;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'success',    true,
    'request_id', v_new_req_id,
    'store_id',   v_store_id,
    'status',     'pending'
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.submit_store_reactivation_request(jsonb) TO authenticated;

-- ── 3. withdraw_store_reactivation_request RPC ───────────────────────────────
CREATE OR REPLACE FUNCTION public.withdraw_store_reactivation_request(
  p_request_id uuid,
  p_reason     text DEFAULT NULL
)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id       uuid;
  v_caller_name     text;
  v_caller_role     text;
  v_req             public.new_store_requests;
  v_om_user_id      uuid;
  v_om_auth_id      uuid;
  v_om_role         text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;

  v_caller_id := public.get_current_profile_id();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'No active profile found for authenticated user'
      USING ERRCODE = '42501';
  END IF;

  SELECT
    COALESCE(
      NULLIF(TRIM(COALESCE(up.last_name,'') || ', ' || COALESCE(up.first_name,'')), ', '),
      up.full_name,
      'Unknown'
    ),
    COALESCE(ro.role_name, 'admin')
  INTO v_caller_name, v_caller_role
  FROM public.users_profile up
  LEFT JOIN public.roles ro ON ro.id = up.role_id
  WHERE up.id = v_caller_id;

  SELECT * INTO v_req
  FROM public.new_store_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Request not found: %', p_request_id USING ERRCODE = 'P0002';
  END IF;

  IF v_req.status NOT IN ('pending', 'pending_super_admin') THEN
    RAISE EXCEPTION 'Only pending requests can be withdrawn (current status: %)', v_req.status
      USING ERRCODE = 'P0001';
  END IF;

  -- Caller must be requester or Ops leadership (OM, TL, ATL, HRCO) or Super Admin
  IF NOT (
    v_req.requested_by = v_caller_id
    OR public.i_have_full_access()
    OR public.get_my_role_level() >= 90
    OR v_caller_role IN ('Operations Manager', 'TL', 'ATL', 'HRCO')
  ) THEN
    RAISE EXCEPTION 'Permission denied — Only the requester or Ops leadership can withdraw this request'
      USING ERRCODE = '42501';
  END IF;

  UPDATE public.new_store_requests
  SET
    status           = 'withdrawn',
    review_reason    = COALESCE(NULLIF(TRIM(p_reason), ''), 'Withdrawn by requester / Ops'),
    reviewed_by      = v_caller_id,
    reviewed_by_name = v_caller_name,
    reviewed_at      = NOW(),
    updated_at       = NOW()
  WHERE id = p_request_id;

  -- Notify OM of withdrawal if caller is not OM
  SELECT a.om_user_id INTO v_om_user_id
  FROM public.accounts a
  WHERE a.id = v_req.account_id;

  IF v_om_user_id IS NOT NULL THEN
    SELECT up.auth_user_id, ro.role_name
    INTO v_om_auth_id, v_om_role
    FROM public.users_profile up
    JOIN public.roles ro ON ro.id = up.role_id
    WHERE up.id = v_om_user_id;

    IF v_om_auth_id IS NOT NULL AND v_om_auth_id <> auth.uid() THEN
      BEGIN
        INSERT INTO public.notifications (
          recipient_role,
          recipient_user_id,
          notification_type,
          event_type,
          title,
          message,
          deep_link_route,
          reference_type,
          reference_id
        ) VALUES (
          v_om_role,
          v_om_auth_id,
          'new_store_request',
          'STORE_REACTIVATION_REQUEST_WITHDRAWN',
          'Store Reactivation Withdrawn',
          v_caller_name || ' withdrew the reactivation request for store "' || v_req.store_name || '".',
          '/plantilla',
          'new_store_request',
          p_request_id::text
        );
      EXCEPTION WHEN OTHERS THEN
        NULL;
      END;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'success',    true,
    'request_id', p_request_id,
    'status',     'withdrawn'
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.withdraw_store_reactivation_request(uuid, text) TO authenticated;

-- ── 4. approve_new_store_request (Surgical Support for Reactivation) ───────────
CREATE OR REPLACE FUNCTION public.approve_new_store_request(p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_reviewer_id     uuid;
  v_reviewer_name   text;
  v_reviewer_role   text;
  v_req             public.new_store_requests;
  v_new_store_id    uuid;
  v_requester_auth  uuid;
  v_requester_role  text;
  v_vcode           text;
  v_vacancy_id      uuid;
  v_account_name    text;
  v_group_id        uuid;
  v_group_name      text;
  v_position_id     uuid;
  v_position_name   text;
  v_hrco_user_id    uuid;
  v_hrco_name       text;
  v_requester_name  text;
  v_om_user_id      uuid;
  v_om_auth_id      uuid;
  v_om_role         text;
  v_next_ordinal    integer;
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
      'Reactivation',
      'Stationary',
      'Medium',
      COALESCE(v_req.requested_by, v_reviewer_id),
      COALESCE(v_requester_name, v_reviewer_name),
      v_hrco_user_id,
      v_hrco_name,
      'store_reactivation',
      v_req.city,
      v_req.province,
      v_group_name,
      v_group_id,
      v_reviewer_id,
      v_reviewer_id
    )
    RETURNING id INTO v_vacancy_id;

    -- Provision 1 open slot in plantilla_slots (ADR-002 Invariant 1 & 5)
    SELECT COALESCE(MAX(slot_ordinal), 0) + 1 INTO v_next_ordinal
    FROM public.plantilla_slots
    WHERE store_id = v_new_store_id;

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

      -- Provision open slot(s) in plantilla_slots
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
        'open', 1::smallint, v_vcode,
        NULL,
        NOW(), NOW(), v_reviewer_id, v_reviewer_id
      );
    END IF;
  END IF;

  -- ── Mark request as approved ──────────────────────────────────
  UPDATE public.new_store_requests
  SET
    status           = 'approved',
    created_store_id = v_new_store_id,
    reviewed_by      = v_reviewer_id,
    reviewed_by_name = v_reviewer_name,
    reviewed_at      = NOW(),
    updated_at       = NOW()
  WHERE id = p_request_id;

  -- ── Notify requester ──────────────────────────────────────────
  SELECT up.auth_user_id, ro.role_name
  INTO v_requester_auth, v_requester_role
  FROM public.users_profile up
  JOIN public.roles ro ON ro.id = up.role_id
  WHERE up.id = v_req.requested_by;

  IF v_requester_auth IS NOT NULL THEN
    BEGIN
      INSERT INTO public.notifications (
        recipient_role,
        recipient_user_id,
        notification_type,
        event_type,
        title,
        message,
        deep_link_route,
        reference_type,
        reference_id
      ) VALUES (
        v_requester_role,
        v_requester_auth,
        'new_store_request',
        CASE WHEN v_req.request_type = 'reactivation' THEN 'STORE_REACTIVATION_REQUEST_APPROVED' ELSE 'NEW_STORE_REQUEST_APPROVED' END,
        CASE WHEN v_req.request_type = 'reactivation' THEN 'Store Reactivation Approved' ELSE 'New Store Request Approved' END,
        CASE WHEN v_req.request_type = 'reactivation'
          THEN 'Your request to reactivate store "' || v_req.store_name || '" has been approved. The store is now active with 1 open vacancy.'
          ELSE 'Your request to add store "' || v_req.store_name || '" has been approved and added to the store masterlist.'
        END,
        '/plantilla',
        'new_store_request',
        p_request_id::text
      );
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END IF;

  -- ── Notify OM of the account ───────────────────────────────────
  IF v_om_user_id IS NOT NULL THEN
    SELECT up.auth_user_id, ro.role_name
    INTO v_om_auth_id, v_om_role
    FROM public.users_profile up
    JOIN public.roles ro ON ro.id = up.role_id
    WHERE up.id = v_om_user_id;

    IF v_om_auth_id IS NOT NULL AND (v_requester_auth IS NULL OR v_om_auth_id <> v_requester_auth) THEN
      BEGIN
        INSERT INTO public.notifications (
          recipient_role,
          recipient_user_id,
          notification_type,
          event_type,
          title,
          message,
          deep_link_route,
          reference_type,
          reference_id
        ) VALUES (
          v_om_role,
          v_om_auth_id,
          'new_store_request',
          CASE WHEN v_req.request_type = 'reactivation' THEN 'STORE_REACTIVATION_REQUEST_APPROVED' ELSE 'NEW_STORE_REQUEST_APPROVED' END,
          CASE WHEN v_req.request_type = 'reactivation' THEN 'Store Reactivation Approved' ELSE 'New Store Request Approved' END,
          CASE WHEN v_req.request_type = 'reactivation'
            THEN 'Store "' || v_req.store_name || '" has been reactivated with 1 open vacancy.'
            ELSE 'New store "' || v_req.store_name || '" has been approved and registered.'
          END,
          '/plantilla',
          'new_store_request',
          p_request_id::text
        );
      EXCEPTION WHEN OTHERS THEN
        NULL;
      END;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'success',    true,
    'store_id',   v_new_store_id,
    'status',     'approved',
    'vcode',      v_vcode,
    'vacancy_id', v_vacancy_id
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.approve_new_store_request(uuid) TO authenticated;

-- ── 5. reject_new_store_request (Surgical Support for Reactivation) ────────────
CREATE OR REPLACE FUNCTION public.reject_new_store_request(
  p_request_id uuid,
  p_reason     text
)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_reviewer_id     uuid;
  v_reviewer_name   text;
  v_reviewer_role   text;
  v_req             public.new_store_requests;
  v_requester_auth  uuid;
  v_requester_role  text;
  v_om_user_id      uuid;
  v_om_auth_id      uuid;
  v_om_role         text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;

  IF NOT (public.i_have_full_access() OR public.get_my_role_level() >= 30) THEN
    RAISE EXCEPTION 'Insufficient permissions — Data Team, Head Admin, or Super Admin required'
      USING ERRCODE = '42501';
  END IF;

  IF p_reason IS NULL OR TRIM(p_reason) = '' THEN
    RAISE EXCEPTION 'A rejection reason is required' USING ERRCODE = '22023';
  END IF;

  v_reviewer_id := public.get_current_profile_id();
  IF v_reviewer_id IS NULL THEN
    RAISE EXCEPTION 'No active profile found for authenticated user'
      USING ERRCODE = '42501';
  END IF;

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

  UPDATE public.new_store_requests
  SET
    status           = 'rejected',
    reviewed_by      = v_reviewer_id,
    reviewed_by_name = v_reviewer_name,
    reviewed_at      = NOW(),
    review_reason    = TRIM(p_reason),
    updated_at       = NOW()
  WHERE id = p_request_id;

  SELECT up.auth_user_id, ro.role_name
  INTO v_requester_auth, v_requester_role
  FROM public.users_profile up
  JOIN public.roles ro ON ro.id = up.role_id
  WHERE up.id = v_req.requested_by;

  IF v_requester_auth IS NOT NULL THEN
    BEGIN
      INSERT INTO public.notifications (
        recipient_role,
        recipient_user_id,
        notification_type,
        event_type,
        title,
        message,
        deep_link_route,
        reference_type,
        reference_id
      ) VALUES (
        v_requester_role,
        v_requester_auth,
        'new_store_request',
        CASE WHEN v_req.request_type = 'reactivation' THEN 'STORE_REACTIVATION_REQUEST_REJECTED' ELSE 'NEW_STORE_REQUEST_REJECTED' END,
        CASE WHEN v_req.request_type = 'reactivation' THEN 'Store Reactivation Rejected' ELSE 'New Store Request Rejected' END,
        CASE WHEN v_req.request_type = 'reactivation'
          THEN 'Your request to reactivate store "' || v_req.store_name || '" was rejected. Reason: ' || TRIM(p_reason)
          ELSE 'Your request to add store "' || v_req.store_name || '" was rejected. Reason: ' || TRIM(p_reason)
        END,
        '/plantilla',
        'new_store_request',
        p_request_id::text
      );
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END IF;

  -- Notify OM of account
  SELECT a.om_user_id INTO v_om_user_id
  FROM public.accounts a
  WHERE a.id = v_req.account_id;

  IF v_om_user_id IS NOT NULL THEN
    SELECT up.auth_user_id, ro.role_name
    INTO v_om_auth_id, v_om_role
    FROM public.users_profile up
    JOIN public.roles ro ON ro.id = up.role_id
    WHERE up.id = v_om_user_id;

    IF v_om_auth_id IS NOT NULL AND (v_requester_auth IS NULL OR v_om_auth_id <> v_requester_auth) THEN
      BEGIN
        INSERT INTO public.notifications (
          recipient_role,
          recipient_user_id,
          notification_type,
          event_type,
          title,
          message,
          deep_link_route,
          reference_type,
          reference_id
        ) VALUES (
          v_om_role,
          v_om_auth_id,
          'new_store_request',
          CASE WHEN v_req.request_type = 'reactivation' THEN 'STORE_REACTIVATION_REQUEST_REJECTED' ELSE 'NEW_STORE_REQUEST_REJECTED' END,
          CASE WHEN v_req.request_type = 'reactivation' THEN 'Store Reactivation Rejected' ELSE 'New Store Request Rejected' END,
          'Reactivation request for store "' || v_req.store_name || '" was rejected. Reason: ' || TRIM(p_reason),
          '/plantilla',
          'new_store_request',
          p_request_id::text
        );
      EXCEPTION WHEN OTHERS THEN
        NULL;
      END;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'status',  'rejected'
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.reject_new_store_request(uuid, text) TO authenticated;

COMMIT;
