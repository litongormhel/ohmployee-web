-- ============================================================================
-- Migration: 20262606000085_fix_plantilla_separation_is_roving_and_nsr_data_team_workflow
-- Purpose:
--   1. Fix 42703 "column is_roving does not exist" on public.vacancies during
--      plantilla status updates (Resigned, AWOL, Terminated, Floating, Inactive)
--      by replacing vacancies.is_roving with employment_type = 'Roving'.
--   2. Implement Hybrid Two-Tier Workflow for New Store Requests (NSR):
--      - Expand nsr_status_chk constraint to include 'pending_super_admin'
--      - Update RLS policy nsr_select to grant SELECT to Data Team (role_level >= 30)
--      - Grant review/approval authority to Data Team (role_level >= 30)
--      - Add forward_new_store_request_to_super_admin RPC
--      - Update submit_new_store_request notification to route to Data Team (Encoder)
-- ============================================================================

BEGIN;

-- ── 1. Fix fn_plantilla_separation_to_vacancy Trigger Function ───────────────
CREATE OR REPLACE FUNCTION public.fn_plantilla_separation_to_vacancy()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_link        RECORD;
  v_vac         public.vacancies%ROWTYPE;
  v_esa         RECORD;
  v_new_link_id uuid;
  v_hc          numeric;
  v_resolved_requirement_id uuid;
  v_link_status text;
  v_link_vcode  text;
BEGIN
  -- Trigger filter logic
  IF OLD.status NOT IN ('Active', 'On Leave', 'For Deactivation')
    OR NEW.status NOT IN ('Resigned', 'AWOL', 'Endo', 'Terminated', 'Others',
                          'Inactive', 'Floating', 'For Deactivation')
    OR OLD.status = NEW.status THEN
    RETURN NEW;
  END IF;

  -- Dynamic resolution of position_id if null or invalid
  IF NEW.position_id IS NULL AND NEW.position IS NOT NULL AND btrim(NEW.position) <> '' THEN
    SELECT p.id INTO NEW.position_id
    FROM public.positions p
    WHERE lower(btrim(p.position_name)) = lower(btrim(NEW.position))
    LIMIT 1;
    IF NEW.position_id IS NOT NULL THEN
      UPDATE public.plantilla
         SET position_id = NEW.position_id
       WHERE id = NEW.id;
    END IF;
  END IF;

  IF NEW.position_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.positions WHERE id = NEW.position_id
  ) THEN
    SELECT p.id INTO NEW.position_id
    FROM public.positions p
    WHERE lower(btrim(p.position_name)) = lower(btrim(NEW.position))
    LIMIT 1;
    IF NEW.position_id IS NOT NULL THEN
      UPDATE public.plantilla
         SET position_id = NEW.position_id
       WHERE id = NEW.id;
    END IF;
  END IF;

  -- 1. Release the Coverage Group slot this employee occupied, if any.
  IF NEW.coverage_slot_id IS NOT NULL THEN
    UPDATE public.coverage_slots
       SET slot_status = 'open',
           current_occupant_plantilla_id = NULL,
           updated_at = NOW()
     WHERE id = NEW.coverage_slot_id
       AND current_occupant_plantilla_id = NEW.id;

    UPDATE public.hr_emploc
       SET deleted_at = NOW()
     WHERE coverage_slot_id = NEW.coverage_slot_id
       AND deleted_at IS NULL
       AND status = 'Moved to Plantilla';

  ELSIF NEW.coverage_group_id IS NOT NULL THEN
    UPDATE public.coverage_slots
       SET slot_status = 'open',
           current_occupant_plantilla_id = NULL,
           updated_at = NOW()
     WHERE coverage_group_id = NEW.coverage_group_id
       AND current_occupant_plantilla_id = NEW.id;

    UPDATE public.hr_emploc
       SET deleted_at = NOW()
     WHERE coverage_group_id = NEW.coverage_group_id
       AND deleted_at IS NULL
       AND status = 'Moved to Plantilla'
       AND coverage_slot_id IN (
         SELECT id FROM public.coverage_slots
          WHERE coverage_group_id = NEW.coverage_group_id
            AND current_occupant_plantilla_id IS NULL
       );
  END IF;

  -- ── Roving employee path ─────────────────────────────────────────────────
  IF COALESCE(NEW.deployment_type, '') = 'Roving' THEN

    v_link_status := CASE
      WHEN lower(COALESCE(NEW.separation_status, '')) IN ('awol','resigned','terminated','end of contract','endo','others')
        THEN 'Resigned'
      ELSE 'Backed Out'
    END;

    IF NEW.coverage_slot_id IS NOT NULL OR NEW.coverage_group_id IS NOT NULL THEN
      UPDATE public.plantilla_store_links
         SET status      = v_link_status,
             unlinked_at = NOW()
       WHERE plantilla_id = NEW.id
         AND status       = 'Active';

      UPDATE public.employee_store_allocations
         SET is_active     = false,
             effective_end = COALESCE(NEW.date_of_separation, CURRENT_DATE)
       WHERE plantilla_id = NEW.id
         AND is_active    = true;

      RETURN NEW;
    END IF;

    IF EXISTS (
      SELECT 1 FROM public.plantilla_store_links
       WHERE plantilla_id = NEW.id AND status = 'Active'
    ) THEN
      FOR v_link IN
        SELECT * FROM public.plantilla_store_links
         WHERE plantilla_id = NEW.id AND status = 'Active'
      LOOP
        SELECT COALESCE(esa.filled_hc, 1)::numeric INTO v_hc
          FROM public.employee_store_allocations esa
         WHERE esa.plantilla_id        = NEW.id
           AND esa.vcode               = v_link.vcode
           AND esa.is_active           = true
         LIMIT 1;

        v_hc := COALESCE(v_hc, 1);

        IF v_link.vacancy_id IS NOT NULL THEN
          SELECT * INTO v_vac FROM public.vacancies
           WHERE id = v_link.vacancy_id AND deleted_at IS NULL LIMIT 1;
        ELSE
          SELECT * INTO v_vac FROM public.vacancies
           WHERE vcode = v_link.vcode AND deleted_at IS NULL LIMIT 1;
        END IF;

        IF v_vac.id IS NOT NULL THEN
          IF v_vac.status IN ('Filled', 'Closed') THEN
            UPDATE public.vacancies
               SET status         = 'Open',
                   is_archived    = false,
                   archived_at    = NULL,
                   archived_by    = NULL,
                   required_headcount = GREATEST(
                                         COALESCE(required_headcount, 0) + v_hc,
                                         1
                                       ),
                   updated_at     = NOW()
             WHERE id = v_vac.id;
          ELSE
            UPDATE public.vacancies
               SET required_headcount = GREATEST(
                                         COALESCE(required_headcount, 0) + v_hc,
                                         1
                                       ),
                   updated_at = NOW()
             WHERE id = v_vac.id;
          END IF;
        ELSE
          INSERT INTO public.vacancies (
            vcode, account, account_id, store_id, store_name, position, position_id,
            status, vacancy_type, required_headcount, employment_type,
            source, created_at, updated_at
          )
          SELECT
            v_link.vcode,
            NEW.account,
            NEW.account_id,
            s.id,
            s.store_name,
            COALESCE(p.position_name, NEW.position, 'UNSPECIFIED'),
            p.id,
            'Open',
            'Backfill',
            GREATEST(v_hc, 1),
            'Roving',
            'plantilla',
            NOW(),
            NOW()
          FROM (SELECT 1) dummy
          LEFT JOIN public.positions p ON p.id = NEW.position_id
          LEFT JOIN public.stores s ON s.vcode = v_link.vcode
          RETURNING * INTO v_vac;

          UPDATE public.plantilla_store_links
             SET vacancy_id = v_vac.id
           WHERE id = v_link.id;
        END IF;

        UPDATE public.plantilla_store_links
           SET status      = v_link_status,
               unlinked_at = NOW()
         WHERE id = v_link.id;

      END LOOP;

    ELSE
      FOR v_esa IN
        SELECT * FROM public.employee_store_allocations
         WHERE plantilla_id = NEW.id AND is_active = true
      LOOP
        v_hc := COALESCE(v_esa.filled_hc, 1)::numeric;

        SELECT * INTO v_vac FROM public.vacancies
         WHERE store_id    = v_esa.store_id
           AND account_id  = NEW.account_id
           AND COALESCE(employment_type, '') = 'Roving'
           AND deleted_at  IS NULL
           AND status NOT IN ('Filled', 'Closed', 'Cancelled')
         LIMIT 1;

        IF NOT FOUND THEN
          INSERT INTO public.vacancies (
            vcode, account, account_id, store_id, position, position_id,
            status, vacancy_type, employment_type, required_headcount,
            source, created_at, updated_at
          )
          SELECT
            v_esa.store_id::text,
            NEW.account,
            NEW.account_id,
            v_esa.store_id,
            COALESCE(p.position_name, NEW.position, 'UNSPECIFIED'),
            p.id,
            'Open',
            'Backfill',
            'Roving',
            GREATEST(v_hc, 1),
            'plantilla',
            NOW(),
            NOW()
          FROM (SELECT 1) dummy
          LEFT JOIN public.positions p ON p.id = NEW.position_id
          RETURNING * INTO v_vac;
        ELSE
          UPDATE public.vacancies
             SET required_headcount = GREATEST(
                                       COALESCE(required_headcount, 0) + v_hc,
                                       1
                                     ),
                 status    = CASE
                               WHEN status IN ('Filled', 'Closed') THEN 'Open'
                               ELSE status
                             END,
                 is_archived = false,
                 archived_at = NULL,
                 archived_by = NULL,
                 updated_at  = NOW()
           WHERE id = v_vac.id
          RETURNING * INTO v_vac;
        END IF;

        v_link_vcode := COALESCE(v_vac.vcode, v_esa.vcode, v_esa.store_id::text);

        INSERT INTO public.plantilla_store_links (
          plantilla_id, account, vcode, store_name, vacancy_id, status
        )
        SELECT NEW.id, NEW.account, v_link_vcode, v_esa.store_name, v_vac.id, v_link_status
         WHERE NOT EXISTS (
           SELECT 1 FROM public.plantilla_store_links psl
            WHERE psl.plantilla_id = NEW.id
              AND psl.vcode        = v_link_vcode
         )
        RETURNING id INTO v_new_link_id;

        IF v_new_link_id IS NOT NULL THEN
          UPDATE public.plantilla_store_links
             SET unlinked_at = NOW()
           WHERE id = (
             SELECT id FROM public.plantilla_store_links
              WHERE plantilla_id = NEW.id
                AND vcode        = v_link_vcode
              ORDER BY created_at DESC
              LIMIT 1
           );
        END IF;
      END LOOP;
    END IF;

    UPDATE public.employee_store_allocations
       SET is_active     = false,
           effective_end = COALESCE(NEW.date_of_separation, CURRENT_DATE)
     WHERE plantilla_id = NEW.id
       AND is_active    = true;

    RETURN NEW;
  END IF;

  -- ── Stationary employee path ─────────────────────────────────────────────
  PERFORM public.reopen_or_create_vacancy_for_plantilla(
    NEW.id,
    NEW.date_of_separation,
    'Backfill'
  );

  UPDATE public.employee_store_allocations
     SET is_active     = false,
         effective_end = COALESCE(NEW.date_of_separation, CURRENT_DATE)
   WHERE plantilla_id = NEW.id
     AND is_active    = true;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_plantilla_separation_to_vacancy ON public.plantilla;
CREATE TRIGGER trg_plantilla_separation_to_vacancy
  AFTER UPDATE ON public.plantilla
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_plantilla_separation_to_vacancy();


-- ── 2. Update new_store_requests Table Constraints & RLS ─────────────────────

ALTER TABLE public.new_store_requests
  DROP CONSTRAINT IF EXISTS nsr_status_chk;

ALTER TABLE public.new_store_requests
  ADD CONSTRAINT nsr_status_chk
  CHECK (status = ANY (ARRAY['pending'::text, 'pending_super_admin'::text, 'approved'::text, 'rejected'::text]));

DROP POLICY IF EXISTS nsr_select ON public.new_store_requests;
CREATE POLICY nsr_select ON public.new_store_requests
  FOR SELECT TO authenticated
  USING (
    public.i_have_full_access()
    OR public.get_my_role_level() >= 30
    OR requested_by = public.get_current_profile_id()
  );


-- ── 3. Update approve_new_store_request RPC ─────────────────────────────────

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

  -- ── Insert active store into registry ─────────────────────────
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
        'NEW_STORE_REQUEST_APPROVED',
        'New Store Request Approved',
        'Your request to add store "' || v_req.store_name || '" has been approved and added to the store masterlist.',
        '/stores/' || v_new_store_id::text,
        'new_store_request',
        p_request_id::text
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'approve_new_store_request: notification failed: %', SQLERRM;
    END;
  END IF;

  RETURN jsonb_build_object(
    'success',  true,
    'store_id', v_new_store_id,
    'status',   'approved'
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.approve_new_store_request(uuid) TO authenticated;


-- ── 4. Update reject_new_store_request RPC ─────────────────────────────────

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
        'NEW_STORE_REQUEST_REJECTED',
        'New Store Request Rejected',
        'Your request to add store "' || v_req.store_name || '" was rejected. Reason: ' || TRIM(p_reason),
        '/approvals?category=new_stores',
        'new_store_request',
        p_request_id::text
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'reject_new_store_request: notification failed: %', SQLERRM;
    END;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'status',  'rejected'
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.reject_new_store_request(uuid, text) TO authenticated;


-- ── 5. New RPC: forward_new_store_request_to_super_admin ───────────────────

CREATE OR REPLACE FUNCTION public.forward_new_store_request_to_super_admin(
  p_request_id uuid,
  p_notes      text DEFAULT NULL
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
  v_notif_rec       record;
  v_formatted_note  text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;

  IF NOT (public.i_have_full_access() OR public.get_my_role_level() >= 30) THEN
    RAISE EXCEPTION 'Insufficient permissions — Data Team or Admin role required'
      USING ERRCODE = '42501';
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
    COALESCE(ro.role_name, 'Data Team')
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

  IF v_req.status <> 'pending' THEN
    RAISE EXCEPTION 'Request is not in pending status (current: %)', v_req.status
      USING ERRCODE = 'P0001';
  END IF;

  v_formatted_note := CASE
    WHEN p_notes IS NOT NULL AND btrim(p_notes) <> ''
    THEN '[Data Team Validated by ' || v_reviewer_name || ']: ' || btrim(p_notes)
    ELSE '[Data Team Validated by ' || v_reviewer_name || ']'
  END;

  UPDATE public.new_store_requests
  SET
    status           = 'pending_super_admin',
    reviewed_by      = v_reviewer_id,
    reviewed_by_name = v_reviewer_name,
    reviewed_at      = NOW(),
    review_reason    = v_formatted_note,
    updated_at       = NOW()
  WHERE id = p_request_id;

  -- ── Notify Super Admins / Head Admins for final sign-off ──────────────────
  FOR v_notif_rec IN
    SELECT DISTINCT ON (up.auth_user_id)
      up.auth_user_id,
      ro.role_name
    FROM public.users_profile up
    JOIN public.roles ro ON ro.id = up.role_id
    JOIN auth.users au   ON au.id = up.auth_user_id
    WHERE up.is_active = true
      AND up.auth_user_id IS NOT NULL
      AND ro.role_name IN ('Super Admin', 'Head Admin')
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
        'NEW_STORE_REQUEST_FORWARDED',
        'NSR Validated — Pending Final Sign-off',
        v_reviewer_name || ' (Data Team) validated new store request for "' || v_req.store_name || '" and forwarded for Super Admin approval.',
        '/approvals?category=new_stores',
        'new_store_request',
        p_request_id::text
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'forward_new_store_request_to_super_admin: notification failed: %', SQLERRM;
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'status',  'pending_super_admin'
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.forward_new_store_request_to_super_admin(uuid, text) TO authenticated;


-- ── 6. Update submit_new_store_request Notifications to include Data Team ───

CREATE OR REPLACE FUNCTION public.submit_new_store_request(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id           uuid;
  v_caller_name         text;
  v_store_name          text;
  v_province            text;
  v_city                text;
  v_account_id          uuid;
  v_account_name        text;
  v_group_id            uuid;
  v_position            text;
  v_requested_hc        integer;
  v_reason              text;
  v_new_req_id          uuid;
  v_dup_id              uuid;
  v_dup_status          text;
  v_notif_rec           record;
  v_notifications_sent  integer := 0;
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
    )
  INTO v_caller_name
  FROM public.users_profile up
  WHERE up.id = v_caller_id;

  v_store_name   := TRIM(p_input->>'store_name');
  v_province     := TRIM(p_input->>'province');
  v_city         := TRIM(p_input->>'city');
  v_account_id   := (p_input->>'account_id')::uuid;
  v_position     := NULLIF(TRIM(p_input->>'position'), '');
  v_requested_hc := (p_input->>'requested_hc')::integer;
  v_reason       := TRIM(p_input->>'reason');

  IF v_store_name IS NULL OR v_store_name = '' THEN
    RAISE EXCEPTION 'store_name is required' USING ERRCODE = '22023';
  END IF;
  IF v_province IS NULL OR v_province = '' THEN
    RAISE EXCEPTION 'province is required' USING ERRCODE = '22023';
  END IF;
  IF v_city IS NULL OR v_city = '' THEN
    RAISE EXCEPTION 'city is required' USING ERRCODE = '22023';
  END IF;
  IF v_account_id IS NULL THEN
    RAISE EXCEPTION 'account_id is required' USING ERRCODE = '22023';
  END IF;
  IF v_reason IS NULL OR v_reason = '' THEN
    RAISE EXCEPTION 'reason is required' USING ERRCODE = '22023';
  END IF;

  SELECT a.account_name, a.group_id
  INTO v_account_name, v_group_id
  FROM public.accounts a
  WHERE a.id = v_account_id AND a.is_active = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Account not found or inactive: %', v_account_id
      USING ERRCODE = 'P0002';
  END IF;

  IF p_input->>'group_id' IS NOT NULL AND TRIM(p_input->>'group_id') <> '' THEN
    v_group_id := (p_input->>'group_id')::uuid;
  END IF;

  SELECT id, status INTO v_dup_id, v_dup_status
  FROM public.new_store_requests
  WHERE LOWER(TRIM(store_name)) = LOWER(v_store_name)
    AND account_id = v_account_id
    AND is_archived = false
    AND status IN ('pending', 'pending_super_admin')
  LIMIT 1;

  IF FOUND THEN
    RAISE EXCEPTION 'DUPLICATE_PENDING_REQUEST: A request for this store under this account is already pending review (request ID: %)', v_dup_id
      USING ERRCODE = '23505';
  END IF;

  INSERT INTO public.new_store_requests (
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
    requested_by_name
  ) VALUES (
    v_store_name,
    v_province,
    v_city,
    v_account_id,
    v_account_name,
    v_group_id,
    v_position,
    v_requested_hc,
    v_reason,
    v_caller_id,
    v_caller_name
  )
  RETURNING id INTO v_new_req_id;

  -- ── Notify Data Team (Encoder), Head Admin, and Super Admin ───────────────
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
        'NEW_STORE_REQUEST_SUBMITTED',
        'New Store Request',
        v_caller_name || ' requested to add ' || v_store_name ||
          ' (' || v_city || ', ' || v_province || ') under ' || v_account_name || '.',
        '/approvals?category=new_stores',
        'new_store_request',
        v_new_req_id::text
      );
      v_notifications_sent := v_notifications_sent + 1;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'submit_new_store_request: skipped recipient %, role %, request_id %, error: %',
        v_notif_rec.auth_user_id, v_notif_rec.role_name, v_new_req_id, SQLERRM;
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'success',            true,
    'request_id',         v_new_req_id,
    'store_name',         v_store_name,
    'notifications_sent', v_notifications_sent
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.submit_new_store_request(jsonb) TO authenticated;

COMMIT;
