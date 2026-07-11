-- Migration: 20261215000005_moses_hq_workforce_request_approval.sql
-- Goal: Implement MOSES HQ Workforce Request approval and visibility architecture

-- 1. Add metadata columns to workforce_pool_requests and vacancies
ALTER TABLE public.workforce_pool_requests
ADD COLUMN IF NOT EXISTS is_ops_request boolean DEFAULT false NOT NULL,
ADD COLUMN IF NOT EXISTS position_id uuid REFERENCES public.positions(id) ON DELETE SET NULL,
ADD COLUMN IF NOT EXISTS position_name text,
ADD COLUMN IF NOT EXISTS created_by_name text;

ALTER TABLE public.vacancies
ADD COLUMN IF NOT EXISTS is_ops_request boolean DEFAULT false NOT NULL;

-- 2. Update create_pool_vacancy to handle Ops requests (pending) and Data Team requests (auto-approved)
CREATE OR REPLACE FUNCTION public.create_pool_vacancy(
  p_pool_type_code        text,
  p_position_id           uuid,
  p_requesting_account_id uuid,
  p_requesting_store_id   uuid    DEFAULT NULL::uuid,
  p_headcount_needed      integer DEFAULT 1,
  p_priority              text    DEFAULT 'normal'::text,
  p_reason                text    DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_role_level            int;
  v_caller_id             uuid;   -- auth.uid() for created_by (uuid) columns
  v_caller_name           text;   -- full name for display / approved_by columns
  v_pool_type_id          uuid;
  v_moses_hq_id           uuid;
  v_requesting_acct_name  text;
  v_requesting_store_name text;
  v_position_name         text;
  v_req_group_id          uuid;
  v_pool_request_id       uuid;
  v_vcode                 text;
  v_vacancy_id            uuid;
  v_created_vcodes        text[] := '{}';
  v_created_ids           uuid[] := '{}';
  i                       int;
  v_is_ops_request        boolean;
BEGIN
  v_role_level := public.get_my_role_level();
  IF v_role_level IS NULL OR v_role_level NOT IN (100, 90, 70, 45, 42, 41, 40, 30) THEN
    RAISE EXCEPTION 'Unauthorized: create_pool_vacancy requires Data Team or Ops access';
  END IF;

  v_is_ops_request := (v_role_level BETWEEN 40 AND 70);
  v_caller_id   := auth.uid();
  v_caller_name := public.get_my_full_name();

  IF p_headcount_needed < 1 OR p_headcount_needed > 50 THEN
    RAISE EXCEPTION 'headcount_needed must be 1–50, got %', p_headcount_needed;
  END IF;

  IF p_priority NOT IN ('normal', 'urgent', 'critical') THEN
    RAISE EXCEPTION 'Invalid priority: %', p_priority;
  END IF;

  SELECT id INTO v_pool_type_id
  FROM public.workforce_pool_types
  WHERE code = p_pool_type_code AND is_active = true;
  IF v_pool_type_id IS NULL THEN
    RAISE EXCEPTION 'Invalid pool type code: %', p_pool_type_code;
  END IF;

  SELECT id INTO v_moses_hq_id
  FROM public.accounts
  WHERE is_pool_account = true AND is_active = true
  LIMIT 1;
  IF v_moses_hq_id IS NULL THEN
    RAISE EXCEPTION 'Moses HQ pool account not found';
  END IF;

  SELECT account_name, group_id
  INTO v_requesting_acct_name, v_req_group_id
  FROM public.accounts
  WHERE id = p_requesting_account_id AND is_active = true;
  IF v_requesting_acct_name IS NULL THEN
    RAISE EXCEPTION 'Requesting account not found or inactive';
  END IF;

  IF p_requesting_store_id IS NOT NULL THEN
    SELECT store_name INTO v_requesting_store_name
    FROM public.stores
    WHERE id = p_requesting_store_id AND is_active = true;
  END IF;

  SELECT position_name INTO v_position_name
  FROM public.positions
  WHERE id = p_position_id AND is_active = true;
  IF v_position_name IS NULL THEN
    RAISE EXCEPTION 'Position not found or inactive';
  END IF;

  IF v_is_ops_request THEN
    INSERT INTO public.workforce_pool_requests (
      pool_type_id, requesting_account_id, requesting_account,
      requesting_store_id, requesting_store,
      headcount_needed, priority, reason,
      status, created_by, created_by_name, position_id, position_name, is_ops_request
    ) VALUES (
      v_pool_type_id, p_requesting_account_id, v_requesting_acct_name,
      p_requesting_store_id, v_requesting_store_name,
      p_headcount_needed, p_priority, p_reason,
      'pending', v_caller_id::text, v_caller_name, p_position_id, v_position_name, true
    ) RETURNING id INTO v_pool_request_id;

    RETURN jsonb_build_object(
      'success',           true,
      'pool_request_id',   v_pool_request_id,
      'pool_type',         p_pool_type_code,
      'headcount_created', p_headcount_needed,
      'vacancy_created',   false,
      'vcodes',            v_created_vcodes,
      'vacancy_ids',       v_created_ids
    );
  ELSE
    INSERT INTO public.workforce_pool_requests (
      pool_type_id, requesting_account_id, requesting_account,
      requesting_store_id, requesting_store,
      headcount_needed, priority, reason,
      status, approved_by, approved_at, created_by, created_by_name,
      position_id, position_name, is_ops_request
    ) VALUES (
      v_pool_type_id, p_requesting_account_id, v_requesting_acct_name,
      p_requesting_store_id, v_requesting_store_name,
      p_headcount_needed, p_priority, p_reason,
      'approved', v_caller_name, now(), v_caller_id::text, v_caller_name,
      p_position_id, v_position_name, false
    ) RETURNING id INTO v_pool_request_id;

    FOR i IN 1..p_headcount_needed LOOP
      v_vcode := public.generate_pool_vcode(p_pool_type_code);

      INSERT INTO public.vacancies (
        vcode, account, account_id, group_id,
        position, position_id, store_id,
        status, vacant_date, required_headcount, source,
        is_pool_vacancy, pool_type_id, home_account_id,
        affects_required_hc, affects_mfr, pool_request_id,
        created_by, is_ops_request
      ) VALUES (
        v_vcode, v_requesting_acct_name, p_requesting_account_id, v_req_group_id,
        v_position_name, p_position_id, p_requesting_store_id,
        'Open', now(), 1, 'pool',
        true, v_pool_type_id, v_moses_hq_id,
        false, false, v_pool_request_id,
        v_caller_id, false
      ) RETURNING id INTO v_vacancy_id;

      INSERT INTO public.workforce_pool_slots (
        vcode, pool_type_id, vacancy_id,
        status, account, account_id, group_id, created_by
      ) VALUES (
        v_vcode, v_pool_type_id, v_vacancy_id,
        'open', v_requesting_acct_name, p_requesting_account_id,
        v_req_group_id, v_caller_id
      );

      INSERT INTO public.workforce_pool_request_items (
        request_id, vacancy_id, vcode, position_id, status
      ) VALUES (
        v_pool_request_id, v_vacancy_id, v_vcode, p_position_id, 'open'
      );

      v_created_vcodes := v_created_vcodes || v_vcode;
      v_created_ids    := v_created_ids    || v_vacancy_id;
    END LOOP;

    RETURN jsonb_build_object(
      'success',           true,
      'pool_request_id',   v_pool_request_id,
      'pool_type',         p_pool_type_code,
      'headcount_created', p_headcount_needed,
      'vacancy_created',   true,
      'vcodes',            v_created_vcodes,
      'vacancy_ids',       v_created_ids
    );
  END IF;
END;
$function$;

-- 3. Define new approve and reject functions
CREATE OR REPLACE FUNCTION public.approve_pool_vacancy_request(p_request_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_role_level            int;
  v_caller_id             uuid;
  v_caller_name           text;
  v_req                   public.workforce_pool_requests%ROWTYPE;
  v_vcode                 text;
  v_vacancy_id            uuid;
  v_created_vcodes        text[] := '{}';
  v_created_ids           uuid[] := '{}';
  i                       int;
  v_req_group_id          uuid;
BEGIN
  v_role_level := public.get_my_role_level();
  IF v_role_level IS NULL OR v_role_level NOT IN (100, 90, 30) THEN
    RAISE EXCEPTION 'Unauthorized: approve_pool_vacancy_request requires Data Team/Admin access (SA/HA/Encoder)';
  END IF;

  v_caller_id   := auth.uid();
  v_caller_name := public.get_my_full_name();

  SELECT * INTO v_req
  FROM public.workforce_pool_requests
  WHERE id = p_request_id AND deleted_at IS NULL
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Request not found';
  END IF;

  IF v_req.status <> 'pending' THEN
    RAISE EXCEPTION 'Request is already processed: status is %', v_req.status;
  END IF;

  SELECT group_id INTO v_req_group_id
  FROM public.accounts
  WHERE id = v_req.requesting_account_id AND is_active = true;

  FOR i IN 1..v_req.headcount_needed LOOP
    DECLARE
      v_pool_type_code text;
      v_moses_hq_id uuid;
    BEGIN
      SELECT code INTO v_pool_type_code
      FROM public.workforce_pool_types
      WHERE id = v_req.pool_type_id;

      SELECT id INTO v_moses_hq_id
      FROM public.accounts
      WHERE is_pool_account = true AND is_active = true
      LIMIT 1;

      v_vcode := public.generate_pool_vcode(v_pool_type_code);

      INSERT INTO public.vacancies (
        vcode, account, account_id, group_id,
        position, position_id, store_id,
        status, vacant_date, required_headcount, source,
        is_pool_vacancy, pool_type_id, home_account_id,
        affects_required_hc, affects_mfr, pool_request_id,
        created_by, is_ops_request
      ) VALUES (
        v_vcode, v_req.requesting_account, v_req.requesting_account_id, v_req_group_id,
        v_req.position_name, v_req.position_id, v_req.requesting_store_id,
        'Open', now(), 1, 'pool',
        true, v_req.pool_type_id, v_moses_hq_id,
        false, false, v_req.id,
        v_req.created_by::uuid, true
      ) RETURNING id INTO v_vacancy_id;

      INSERT INTO public.workforce_pool_slots (
        vcode, pool_type_id, vacancy_id,
        status, account, account_id, group_id, created_by
      ) VALUES (
        v_vcode, v_req.pool_type_id, v_vacancy_id,
        'open', v_req.requesting_account, v_req.requesting_account_id,
        v_req_group_id, v_req.created_by::uuid
      );

      INSERT INTO public.workforce_pool_request_items (
        request_id, vacancy_id, vcode, position_id, status
      ) VALUES (
        v_req.id, v_vacancy_id, v_vcode, v_req.position_id, 'open'
      );

      v_created_vcodes := v_created_vcodes || v_vcode;
      v_created_ids    := v_created_ids    || v_vacancy_id;
    END;
  END LOOP;

  UPDATE public.workforce_pool_requests
  SET status = 'approved',
      approved_by = v_caller_name,
      approved_at = now(),
      updated_by = v_caller_id::text,
      updated_at = now()
  WHERE id = p_request_id;

  RETURN jsonb_build_object(
    'success',           true,
    'pool_request_id',   p_request_id,
    'headcount_created', v_req.headcount_needed,
    'vcodes',            v_created_vcodes,
    'vacancy_ids',       v_created_ids
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.reject_pool_vacancy_request(p_request_id uuid, p_reason text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_role_level            int;
  v_caller_id             uuid;
  v_caller_name           text;
  v_status                text;
BEGIN
  v_role_level := public.get_my_role_level();
  IF v_role_level IS NULL OR v_role_level NOT IN (100, 90, 30) THEN
    RAISE EXCEPTION 'Unauthorized: reject_pool_vacancy_request requires Data Team/Admin access (SA/HA/Encoder)';
  END IF;

  v_caller_id   := auth.uid();
  v_caller_name := public.get_my_full_name();

  SELECT status INTO v_status
  FROM public.workforce_pool_requests
  WHERE id = p_request_id AND deleted_at IS NULL
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Request not found';
  END IF;

  IF v_status <> 'pending' THEN
    RAISE EXCEPTION 'Request is already processed: status is %', v_status;
  END IF;

  UPDATE public.workforce_pool_requests
  SET status = 'rejected',
      rejected_by = v_caller_name,
      rejected_at = now(),
      rejection_reason = p_reason,
      updated_by = v_caller_id::text,
      updated_at = now()
  WHERE id = p_request_id;

  RETURN jsonb_build_object(
    'success', true,
    'pool_request_id', p_request_id
  );
END;
$function$;

-- 4. Grant access to new RPCs
GRANT EXECUTE ON FUNCTION public.approve_pool_vacancy_request(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reject_pool_vacancy_request(uuid, text) TO authenticated;

-- 5. Update RLS policies for public.vacancies
DROP POLICY IF EXISTS "vacancies_read_scoped" ON public.vacancies;
CREATE POLICY "vacancies_read_scoped" ON "public"."vacancies"
FOR SELECT TO public
USING (
  public.i_have_full_access()
  OR (
    (account = ANY (public.get_my_allowed_accounts()))
    AND (status <> ALL (ARRAY['Filled'::text, 'Closed'::text, 'Archived'::text]))
    AND (COALESCE(is_archived, false) = false)
    AND (
      NOT COALESCE(is_pool_vacancy, false)
      OR COALESCE(is_ops_request, false) = true
    )
  )
  OR (
    COALESCE(is_pool_vacancy, false) = true
    AND (
      public.get_my_role_level() = 20
      OR public.get_my_role_level() = 30
      OR public.get_my_role_level() >= 90
    )
  )
);

-- 6. Update RLS policies for public.applicants
DROP POLICY IF EXISTS "applicants_insert_ops_only" ON public.applicants;
CREATE POLICY "applicants_insert_ops_only" ON "public"."applicants"
FOR INSERT TO public
WITH CHECK (
  (
    public.i_have_full_access()
    OR (
      public.i_am_recruitment()
      AND EXISTS (
        SELECT 1 FROM public.vacancies v
        WHERE v.vcode = applicants.vacancy_vcode
          AND v.is_pool_vacancy = true
          AND v.deleted_at IS NULL
      )
    )
    OR (
      (public.i_am_ops() OR public.i_am_recruitment())
      AND vacancy_vcode IN (
        SELECT v.vcode
        FROM public.vacancies v
        WHERE v.account = ANY (public.get_my_allowed_accounts())
          AND v.deleted_at IS NULL
          AND NOT COALESCE(v.is_pool_vacancy, false)
      )
    )
  )
  AND NOT EXISTS (
    SELECT 1 FROM public.vacancies v
    WHERE v.vcode = applicants.vacancy_vcode
      AND v.has_pending_closure = true
      AND v.deleted_at IS NULL
  )
);

DROP POLICY IF EXISTS "applicants_update_ops_recruitment" ON public.applicants;
CREATE POLICY "applicants_update_ops_recruitment" ON "public"."applicants"
FOR UPDATE TO public
USING (
  public.i_have_full_access()
  OR (
    public.i_am_recruitment()
    AND EXISTS (
      SELECT 1 FROM public.vacancies v
      WHERE v.vcode = applicants.vacancy_vcode
        AND v.is_pool_vacancy = true
        AND v.deleted_at IS NULL
    )
  )
  OR (
    (public.i_am_ops() OR public.i_am_recruitment())
    AND vacancy_vcode IN (
      SELECT v.vcode
      FROM public.vacancies v
      WHERE v.account = ANY (public.get_my_allowed_accounts())
        AND v.deleted_at IS NULL
        AND NOT COALESCE(v.is_pool_vacancy, false)
    )
  )
);

DROP POLICY IF EXISTS "applicants_read_scoped" ON public.applicants;
CREATE POLICY "applicants_read_scoped" ON "public"."applicants"
FOR SELECT TO public
USING (
  public.i_have_full_access()
  OR (vacancy_vcode = ANY (public.get_my_scoped_vcodes()))
  OR (
    EXISTS (
      SELECT 1 FROM public.vacancies v
      WHERE v.vcode = applicants.vacancy_vcode
        AND v.is_pool_vacancy = true
        AND v.deleted_at IS NULL
    )
    AND (
      public.get_my_role_level() = 20
      OR public.get_my_role_level() = 30
      OR public.get_my_role_level() >= 90
    )
  )
);

-- 7. Update RBAC within confirm_applicant_onboard
CREATE OR REPLACE FUNCTION public.confirm_applicant_onboard(
  p_applicant_id uuid,
  p_last_name text DEFAULT NULL::text,
  p_first_name text DEFAULT NULL::text,
  p_middle_name text DEFAULT NULL::text,
  p_full_name text DEFAULT NULL::text,
  p_contact_number text DEFAULT NULL::text,
  p_remarks text DEFAULT NULL::text,
  p_roving_assignment_id uuid DEFAULT NULL::uuid,
  p_hired_by_user_id uuid DEFAULT NULL::uuid,
  p_endorsed_by_deployer_id uuid DEFAULT NULL::uuid,
  p_endorsed_by_name text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_role        text    := public.get_my_role();
  v_role_level  int     := COALESCE(public.get_my_role_level(), 0);
  v_profile_id  uuid    := public.get_my_profile_id();
  v_actor_name  text    := public.get_my_full_name();
  v_app         public.applicants%ROWTYPE;
  v_vac         public.vacancies%ROWTYPE;
  v_hr          public.hr_emploc%ROWTYPE;
  v_full_name   text;
  v_hired_by_id uuid;
  v_is_roving   boolean;
  v_store_link_id uuid;
  v_late_result   jsonb;
  -- fast-track vars
  v_existing_plt      public.plantilla%ROWTYPE;
  v_roving_id         uuid;
  v_new_roving        boolean := false;
  v_plt_store_link_id uuid;
  v_existing_employee_no text;
  v_roving_hr_found   boolean := false;
BEGIN
  SELECT * INTO v_app
    FROM public.applicants
   WHERE id = p_applicant_id
  FOR UPDATE;

  IF NOT FOUND OR COALESCE(v_app.is_archived, false) THEN
    RAISE EXCEPTION 'applicant % not found or archived', p_applicant_id
      USING ERRCODE = 'P0002';
  END IF;

  SELECT * INTO v_vac
    FROM public.vacancies
   WHERE vcode = v_app.vacancy_vcode
     AND COALESCE(is_archived, false) = false
     AND deleted_at IS NULL
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'active vacancy not found for vcode %', v_app.vacancy_vcode
      USING ERRCODE = 'P0002';
  END IF;

  -- RBAC guard updated for pool vacancies
  IF COALESCE(v_vac.is_pool_vacancy, false) = true THEN
    IF NOT (v_role_level = 100 OR public.i_am_recruitment()) THEN
      RAISE EXCEPTION 'forbidden: only Recruitment or Super Admin can onboard applicants for MOSES HQ pool vacancies'
        USING ERRCODE = '42501';
    END IF;
  ELSE
    IF NOT (
      public.i_have_full_access()
      OR v_role_level = 30
      OR v_role IN ('OM', 'HRCO', 'ATL', 'TL', 'Operations Manager')
    ) THEN
      RAISE EXCEPTION 'forbidden: Ops Team, Data Team, or Super Admin required'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  IF COALESCE(v_app.status, 'New') IN (
    'Failed', 'Backout', 'Did Not Report', 'Rejected by Ops'
  ) THEN
    RAISE EXCEPTION
      'cannot confirm onboarding: applicant is in terminal status %', v_app.status
      USING ERRCODE = '22023';
  END IF;

  v_is_roving := COALESCE(p_roving_assignment_id, v_app.roving_assignment_id) IS NOT NULL;

  IF v_app.status = 'Confirmed Onboard' THEN
    IF v_is_roving THEN
      SELECT * INTO v_hr
        FROM public.hr_emploc
       WHERE roving_assignment_id = COALESCE(p_roving_assignment_id, v_app.roving_assignment_id)
          AND assignment_type = 'Roving'
          AND deleted_at IS NULL
       ORDER BY created_at ASC LIMIT 1;
    ELSE
      SELECT * INTO v_hr
        FROM public.hr_emploc
       WHERE deleted_at IS NULL
          AND (
            applicant_id = v_app.id
            OR (applicant_name = v_app.full_name AND vcode = v_app.vacancy_vcode)
          )
       ORDER BY created_at DESC LIMIT 1;
    END IF;

    RETURN jsonb_build_object(
      'ok', true,
      'applicant_id', v_app.id,
      'applicant_status', v_app.status,
      'hr_emploc_id', v_hr.id,
      'vcode', v_app.vacancy_vcode,
      'idempotent', true
    );
  END IF;

  IF COALESCE(v_vac.has_pending_closure, false) = true THEN
    RAISE EXCEPTION
      'onboarding blocked: vacancy % has a pending closure request. Withdraw the closure request first.',
      v_vac.vcode
      USING ERRCODE = '55000';
  END IF;

  IF NOT public.i_have_full_access()
     AND NOT (v_vac.account = ANY(public.get_my_allowed_accounts()))
     AND NOT (COALESCE(v_vac.is_pool_vacancy, false) = true AND public.i_am_recruitment()) THEN
    RAISE EXCEPTION 'forbidden: vacancy is outside caller scope'
      USING ERRCODE = '42501';
  END IF;

  IF p_contact_number IS NOT NULL AND btrim(p_contact_number) <> '' THEN
    PERFORM public.fn_validate_ph_contact_number(p_contact_number);
  END IF;

  v_full_name := COALESCE(
    NULLIF(btrim(p_full_name), ''),
    NULLIF(btrim(concat_ws(' ',
      NULLIF(p_first_name, ''),
      NULLIF(p_middle_name, ''),
      NULLIF(p_last_name, '')
    )), ''),
    v_app.full_name
  );

  v_hired_by_id := COALESCE(p_hired_by_user_id, v_profile_id);

  UPDATE public.applicants
  SET
    last_name                = COALESCE(NULLIF(p_last_name, ''), last_name),
    first_name               = COALESCE(NULLIF(p_first_name, ''), first_name),
    middle_name              = p_middle_name,
    full_name                = v_full_name,
    full_name_snapshot       = v_full_name,
    contact_number           = COALESCE(NULLIF(p_contact_number, ''), contact_number),
    remarks                  = p_remarks,
    roving_assignment_id     = COALESCE(p_roving_assignment_id, roving_assignment_id),
    status                   = 'Confirmed Onboard',
    hired_date               = COALESCE(hired_date, CURRENT_DATE),
    hired_at                 = COALESCE(hired_at, NOW()),
    hired_by                 = v_actor_name,
    hired_by_team            = v_role,
    hired_by_user_id         = v_hired_by_id,
    endorsed_by_deployer_id  = p_endorsed_by_deployer_id,
    endorsed_by_name         = p_endorsed_by_name,
    deployed_by_user_id      = v_profile_id,
    is_archived              = false,
    updated_at               = NOW(),
    updated_by               = v_profile_id
  WHERE id = p_applicant_id
  RETURNING * INTO v_app;

  SELECT * INTO v_existing_plt
    FROM public.plantilla
   WHERE account = v_vac.account
     AND status = 'Active'
     AND is_deleted = false
     AND employee_no IS NOT NULL
     AND (
       (
         COALESCE(p_roving_assignment_id, v_app.roving_assignment_id) IS NOT NULL
         AND roving_assignment_id = COALESCE(p_roving_assignment_id, v_app.roving_assignment_id)
       )
       OR LOWER(TRIM(employee_name)) = LOWER(TRIM(v_full_name))
     )
   ORDER BY
     CASE
       WHEN roving_assignment_id = COALESCE(p_roving_assignment_id, v_app.roving_assignment_id) THEN 0
       ELSE 1
     END,
     created_at DESC
   LIMIT 1
  FOR UPDATE;

  IF FOUND THEN
    v_roving_id := COALESCE(v_existing_plt.roving_assignment_id, p_roving_assignment_id, v_app.roving_assignment_id);

    IF v_roving_id IS NULL THEN
      INSERT INTO public.roving_assignments (
        master_applicant_id, account, account_id,
        primary_vcode, label, created_by, updated_by
      ) VALUES (
        v_app.id, v_vac.account, v_vac.account_id,
        COALESCE(v_existing_plt.vcode, v_vac.vcode),
        v_full_name,
        v_profile_id, v_profile_id
      )
      RETURNING id INTO v_roving_id;

      v_new_roving := true;
    END IF;

    UPDATE public.applicants
    SET roving_assignment_id = v_roving_id, updated_at = NOW(), updated_by = v_profile_id
    WHERE id = v_app.id
    RETURNING * INTO v_app;

    UPDATE public.plantilla
    SET deployment_type = 'Roving', roving_assignment_id = v_roving_id, updated_at = NOW(), updated_by = v_profile_id
    WHERE id = v_existing_plt.id;

    IF v_existing_plt.vcode IS NOT NULL THEN
      SELECT id INTO v_plt_store_link_id
        FROM public.plantilla_store_links
       WHERE plantilla_id = v_existing_plt.id
         AND roving_assignment_id = v_roving_id
         AND (vacancy_id = v_existing_plt.vacancy_id OR vcode = v_existing_plt.vcode)
         AND deleted_at IS NULL
       LIMIT 1
      FOR UPDATE;

      IF v_plt_store_link_id IS NULL THEN
        INSERT INTO public.plantilla_store_links (
          plantilla_id, roving_assignment_id,
          vacancy_id, vcode, store_name, account,
          status, linked_at, linked_by, created_by, updated_by
        ) VALUES (
          v_existing_plt.id, v_roving_id,
          v_existing_plt.vacancy_id, v_existing_plt.vcode,
          v_existing_plt.store_name, v_existing_plt.account,
          'Active', NOW(), v_profile_id, v_profile_id, v_profile_id
        )
        ON CONFLICT DO NOTHING;
      END IF;
    END IF;

    v_plt_store_link_id := NULL;

    SELECT id INTO v_plt_store_link_id
      FROM public.plantilla_store_links
     WHERE plantilla_id = v_existing_plt.id
       AND roving_assignment_id = v_roving_id
       AND (
         vacancy_id = v_vac.id
         OR vcode = v_vac.vcode
         OR (account = v_vac.account AND LOWER(TRIM(COALESCE(store_name, ''))) = LOWER(TRIM(COALESCE(v_vac.store_name, ''))))
       )
       AND deleted_at IS NULL
     LIMIT 1
    FOR UPDATE;

    IF v_plt_store_link_id IS NULL THEN
      INSERT INTO public.plantilla_store_links (
        plantilla_id, roving_assignment_id,
        vacancy_id, vcode, store_name, account,
        status, linked_at, linked_by, created_by, updated_by
      ) VALUES (
        v_existing_plt.id, v_roving_id,
        v_vac.id, v_vac.vcode, v_vac.store_name, v_vac.account,
        'Active', NOW(), v_profile_id, v_profile_id, v_profile_id
      )
      ON CONFLICT DO NOTHING
      RETURNING id INTO v_plt_store_link_id;

      IF v_plt_store_link_id IS NULL THEN
        SELECT id INTO v_plt_store_link_id
          FROM public.plantilla_store_links
         WHERE plantilla_id = v_existing_plt.id
           AND roving_assignment_id = v_roving_id
           AND (
             vacancy_id = v_vac.id
             OR vcode = v_vac.vcode
             OR (account = v_vac.account AND LOWER(TRIM(COALESCE(store_name, ''))) = LOWER(TRIM(COALESCE(v_vac.store_name, ''))))
           )
           AND deleted_at IS NULL
         LIMIT 1;
      END IF;
    ELSE
      UPDATE public.plantilla_store_links
      SET status = 'Active', unlinked_at = NULL, unlinked_by = NULL, updated_at = NOW(), updated_by = v_profile_id
      WHERE id = v_plt_store_link_id;
    END IF;

    UPDATE public.vacancies
    SET status = 'Filled', updated_at = NOW(), updated_by = v_profile_id
    WHERE id = v_vac.id;

    INSERT INTO public.employee_activity_log (emploc_no, vcode, activity_type, description, performed_by, metadata)
    VALUES (
      COALESCE(v_existing_plt.emploc_no, v_existing_plt.employee_no, v_app.full_name),
      v_vac.vcode,
      'confirmed_onboard_fast_track',
      'Existing Plantilla employee fast-tracked to new store, bypassing HR Emploc queue for ' || v_vac.vcode,
      v_actor_name,
      jsonb_build_object(
        'applicant_id', v_app.id,
        'hr_emploc_id', NULL,
        'plantilla_id', v_existing_plt.id,
        'plantilla_store_link_id', v_plt_store_link_id,
        'vacancy_id', v_vac.id,
        'employee_no', v_existing_plt.employee_no,
        'roving_assignment_id', v_roving_id,
        'new_roving_created', v_new_roving,
        'skipped_hr_emploc', true,
        'role', v_role,
        'hired_by_user_id', v_hired_by_id,
        'movement_at', NOW()
      )
    );

    RETURN jsonb_build_object(
      'ok', true,
      'applicant_id', v_app.id,
      'applicant_status', v_app.status,
      'hr_emploc_id', NULL,
      'plantilla_id', v_existing_plt.id,
      'plantilla_store_link_id', v_plt_store_link_id,
      'vcode', v_vac.vcode,
      'hired_by_user_id', v_hired_by_id,
      'is_roving', true,
      'fast_tracked', true,
      'skipped_hr_emploc', true,
      'new_roving_created', v_new_roving
    );
  END IF;

  IF v_is_roving THEN
    SELECT * INTO v_hr
      FROM public.hr_emploc
     WHERE roving_assignment_id = COALESCE(p_roving_assignment_id, v_app.roving_assignment_id)
       AND assignment_type = 'Roving'
       AND deleted_at IS NULL
     ORDER BY created_at ASC LIMIT 1
    FOR UPDATE;

    v_roving_hr_found := FOUND;

    IF v_roving_hr_found THEN
      v_existing_employee_no := COALESCE(NULLIF(BTRIM(v_hr.employee_no), ''), NULLIF(BTRIM(v_hr.emploc_no), ''));

      IF v_hr.status = 'Moved to Plantilla' OR v_existing_employee_no IS NOT NULL THEN
        SELECT * INTO v_existing_plt
          FROM public.plantilla
         WHERE is_deleted = false
           AND status IN ('Active', 'For Deactivation', 'On Leave')
           AND (
             roving_assignment_id = COALESCE(p_roving_assignment_id, v_app.roving_assignment_id)
             OR hr_emploc_id = v_hr.id
             OR (v_existing_employee_no IS NOT NULL AND employee_no = v_existing_employee_no AND account = v_vac.account)
           )
         ORDER BY
           CASE
             WHEN roving_assignment_id = COALESCE(p_roving_assignment_id, v_app.roving_assignment_id) THEN 0
             WHEN hr_emploc_id = v_hr.id THEN 1
             ELSE 2
           END,
           created_at DESC
         LIMIT 1
        FOR UPDATE;

        IF FOUND THEN
          v_roving_id := COALESCE(v_existing_plt.roving_assignment_id, v_hr.roving_assignment_id, p_roving_assignment_id, v_app.roving_assignment_id);

          UPDATE public.applicants
          SET roving_assignment_id = v_roving_id, updated_at = NOW(), updated_by = v_profile_id
          WHERE id = v_app.id
          RETURNING * INTO v_app;

          UPDATE public.plantilla
          SET deployment_type = 'Roving', roving_assignment_id = v_roving_id, updated_at = NOW(), updated_by = v_profile_id
          WHERE id = v_existing_plt.id;

          SELECT id INTO v_plt_store_link_id
            FROM public.plantilla_store_links
           WHERE plantilla_id = v_existing_plt.id
             AND roving_assignment_id = v_roving_id
             AND (
               vacancy_id = v_vac.id
               OR vcode = v_vac.vcode
               OR (account = v_vac.account AND LOWER(TRIM(COALESCE(store_name, ''))) = LOWER(TRIM(COALESCE(v_vac.store_name, ''))))
             )
             AND deleted_at IS NULL
           LIMIT 1
          FOR UPDATE;

          IF v_plt_store_link_id IS NULL THEN
            INSERT INTO public.plantilla_store_links (
              plantilla_id, roving_assignment_id,
              vacancy_id, vcode, store_name, account,
              status, linked_at, linked_by, created_by, updated_by
            ) VALUES (
              v_existing_plt.id, v_roving_id,
              v_vac.id, v_vac.vcode, v_vac.store_name, v_vac.account,
              'Active', NOW(), v_profile_id, v_profile_id, v_profile_id
            )
            ON CONFLICT DO NOTHING
            RETURNING id INTO v_plt_store_link_id;

            IF v_plt_store_link_id IS NULL THEN
              SELECT id INTO v_plt_store_link_id
                FROM public.plantilla_store_links
               WHERE plantilla_id = v_existing_plt.id
                 AND roving_assignment_id = v_roving_id
                 AND (
                   vacancy_id = v_vac.id
                   OR vcode = v_vac.vcode
                   OR (account = v_vac.account AND LOWER(TRIM(COALESCE(store_name, ''))) = LOWER(TRIM(COALESCE(v_vac.store_name, ''))))
                 )
                 AND deleted_at IS NULL
               LIMIT 1;
            END IF;
          ELSE
            UPDATE public.plantilla_store_links
            SET status = 'Active', unlinked_at = NULL, unlinked_by = NULL, updated_at = NOW(), updated_by = v_profile_id
            WHERE id = v_plt_store_link_id;
          END IF;

          UPDATE public.vacancies
          SET status = 'Filled', updated_at = NOW(), updated_by = v_profile_id
          WHERE id = v_vac.id;

          INSERT INTO public.employee_activity_log (emploc_no, vcode, activity_type, description, performed_by, metadata)
          VALUES (
            COALESCE(v_existing_plt.emploc_no, v_existing_plt.employee_no, v_existing_employee_no, v_app.full_name),
            v_vac.vcode,
            'confirmed_onboard_fast_track',
            'Existing roving employee fast-tracked to new store, bypassing duplicate HR Emploc creation for ' || v_vac.vcode,
            v_actor_name,
            jsonb_build_object(
              'applicant_id', v_app.id,
              'hr_emploc_id', v_hr.id,
              'plantilla_id', v_existing_plt.id,
              'plantilla_store_link_id', v_plt_store_link_id,
              'vacancy_id', v_vac.id,
              'employee_no', COALESCE(v_existing_plt.employee_no, v_existing_employee_no),
              'roving_assignment_id', v_roving_id,
              'skipped_hr_emploc_insert', true,
              'role', v_role,
              'hired_by_user_id', v_hired_by_id,
              'movement_at', NOW()
            )
          );

          RETURN jsonb_build_object(
            'ok', true,
            'applicant_id', v_app.id,
            'applicant_status', v_app.status,
            'hr_emploc_id', v_hr.id,
            'plantilla_id', v_existing_plt.id,
            'plantilla_store_link_id', v_plt_store_link_id,
            'vcode', v_vac.vcode,
            'hired_by_user_id', v_hired_by_id,
            'is_roving', true,
            'fast_tracked', true,
            'skipped_hr_emploc', true,
            'duplicate_roving_guard', true
          );
        END IF;
      END IF;
    END IF;

    IF NOT v_roving_hr_found THEN
      INSERT INTO public.hr_emploc (
        applicant_name, applicant_name_snapshot, applicant_id,
        vcode, vacancy_code_snapshot,
        account, account_id, chain_id, province_id,
        area_name_snapshot, hrco_user_id_snapshot, om_user_id_snapshot,
        atl_user_id_snapshot, position_id_snapshot, position,
        hrco_name, status, hr_status, hired_date,
        deployed_by_user_id, created_by, updated_by, date_requested,
        assignment_type, roving_assignment_id, covered_stores
      ) VALUES (
        v_app.full_name, v_app.full_name, v_app.id,
        v_vac.vcode, v_vac.vcode,
        v_vac.account, v_vac.account_id, v_vac.chain_id, v_vac.province_id,
        v_vac.area_name, v_vac.hrco_user_id, v_vac.om_user_id,
        v_vac.atl_user_id, v_vac.position_id, v_vac.position,
        v_vac.hrco_name, 'Pending Emploc', 'Pending', v_app.hired_date,
        v_profile_id, v_profile_id, v_profile_id, NOW(),
        'Roving'::public.hr_emploc_assignment_type,
        COALESCE(p_roving_assignment_id, v_app.roving_assignment_id),
        '[]'::jsonb
      )
      ON CONFLICT DO NOTHING
      RETURNING * INTO v_hr;

      IF v_hr.id IS NULL THEN
        SELECT * INTO v_hr
          FROM public.hr_emploc
         WHERE roving_assignment_id = COALESCE(p_roving_assignment_id, v_app.roving_assignment_id)
           AND assignment_type = 'Roving'
           AND deleted_at IS NULL
         ORDER BY created_at ASC LIMIT 1
        FOR UPDATE;
      END IF;
    END IF;

    INSERT INTO public.hr_emploc_store_links (
      hr_emploc_id, roving_assignment_id, vacancy_id, vcode,
      store_name, account, status, confirmed_at, confirmed_by,
      created_by, updated_by
    ) VALUES (
      v_hr.id,
      COALESCE(p_roving_assignment_id, v_app.roving_assignment_id),
      v_vac.id, v_vac.vcode, v_vac.store_name, v_vac.account,
      'Confirmed', NOW(), v_profile_id, v_profile_id, v_profile_id
    )
    ON CONFLICT DO NOTHING
    RETURNING id INTO v_store_link_id;

    IF v_hr.status = 'Moved to Plantilla' AND v_store_link_id IS NOT NULL THEN
      SELECT public.link_late_store_to_plantilla(v_store_link_id) INTO v_late_result;
    END IF;

  ELSE
    SELECT * INTO v_hr
      FROM public.hr_emploc
     WHERE deleted_at IS NULL
       AND (
         applicant_id = v_app.id
         OR (applicant_name = v_app.full_name AND vcode = v_app.vacancy_vcode)
       )
     ORDER BY created_at DESC LIMIT 1
    FOR UPDATE;

    IF NOT FOUND THEN
      INSERT INTO public.hr_emploc (
        applicant_name, applicant_name_snapshot, applicant_id,
        vcode, vacancy_id, vacancy_code_snapshot,
        account, account_id, chain_id, store_id, province_id,
        area_name_snapshot, hrco_user_id_snapshot, om_user_id_snapshot,
        atl_user_id_snapshot, position_id_snapshot, position,
        store_name, hrco_name, status, hr_status, hired_date,
        deployed_by_user_id, created_by, updated_by, date_requested,
        assignment_type, roving_assignment_id, covered_stores
      ) VALUES (
        v_app.full_name, v_app.full_name, v_app.id,
        v_vac.vcode, v_vac.id, v_vac.vcode,
        v_vac.account, v_vac.account_id, v_vac.chain_id, v_vac.store_id, v_vac.province_id,
        v_vac.area_name, v_vac.hrco_user_id, v_vac.om_user_id,
        v_vac.atl_user_id, v_vac.position_id, v_vac.position,
        v_vac.store_name, v_vac.hrco_name, 'Pending Emploc', 'Pending', v_app.hired_date,
        v_profile_id, v_profile_id, v_profile_id, NOW(),
        'Stationary'::public.hr_emploc_assignment_type,
        NULL, '[]'::jsonb
      )
      RETURNING * INTO v_hr;
    END IF;
  END IF;

  INSERT INTO public.employee_activity_log (
    emploc_no, vcode, activity_type, description, performed_by, metadata
  ) VALUES (
    COALESCE(v_hr.emploc_no, v_app.full_name),
    v_vac.vcode,
    'confirmed_onboard',
    'Applicant confirmed onboard and moved to HR Emploc for ' || v_vac.vcode,
    v_actor_name,
    jsonb_build_object(
      'applicant_id', v_app.id,
      'hr_emploc_id', v_hr.id,
      'vacancy_id', v_vac.id,
      'role', v_role,
      'hired_by_user_id', v_hired_by_id,
      'endorsed_by_deployer_id', p_endorsed_by_deployer_id,
      'endorsed_by_name', p_endorsed_by_name,
      'is_roving', v_is_roving,
      'late_store_linked', v_late_result IS NOT NULL,
      'movement_at', NOW()
    )
  );

  RETURN jsonb_build_object(
    'ok', true,
    'applicant_id', v_app.id,
    'applicant_status', v_app.status,
    'hr_emploc_id', v_hr.id,
    'vcode', v_vac.vcode,
    'hired_by_user_id', v_hired_by_id,
    'is_roving', v_is_roving,
    'late_store_linked', v_late_result
  );
END;
$function$;

-- 8. Enforce status transitions for pool vacancies inside fn_update_applicant_pipeline
CREATE OR REPLACE FUNCTION public.fn_update_applicant_pipeline(
  p_applicant_id uuid,
  p_new_status text DEFAULT NULL,
  p_follow_up_date date DEFAULT NULL,
  p_recruitment_remarks text DEFAULT NULL,
  p_ops_remarks text DEFAULT NULL,
  p_deployed_reliever boolean DEFAULT NULL,
  p_deployed_commando boolean DEFAULT NULL,
  p_reason_id uuid DEFAULT NULL,
  p_reason_type text DEFAULT NULL,
  p_clear_recruitment_remarks boolean DEFAULT false,
  p_clear_ops_remarks boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_level int := COALESCE(public.get_my_role_level(), 0);
  v_profile_id uuid := public.get_my_profile_id();
  v_actor_name text;

  v_app record;
  v_vac record;
  v_old_status_code text;
  v_old_status_terminal boolean := false;
  v_new_status public.applicant_status_options%ROWTYPE;
  v_new_status_code text;
  v_new_status_label text;

  v_now timestamptz := now();
  v_history_ids uuid[] := ARRAY[]::uuid[];
  v_change_count int := 0;

  v_old_recruitment_remarks text;
  v_new_recruitment_remarks text;
  v_old_ops_remarks text;
  v_new_ops_remarks text;
  v_old_follow_up_date date;
  v_new_follow_up_date date;

  v_has_deployed_reliever boolean := false;
  v_has_deployed_commando boolean := false;
  v_old_deployed_reliever boolean;
  v_old_deployed_commando boolean;

  v_status_changed boolean := false;
  v_follow_up_changed boolean := false;
  v_recruitment_remarks_changed boolean := false;
  v_ops_remarks_changed boolean := false;
  v_deployed_reliever_changed boolean := false;
  v_deployed_commando_changed boolean := false;

  v_history_id uuid;
BEGIN
  IF v_level = 0 THEN
    RAISE EXCEPTION 'forbidden: authenticated user with a recognized role required'
      USING ERRCODE = '42501';
  END IF;

  IF p_reason_type IS NOT NULL
     AND p_reason_type NOT IN ('backout', 'rejected', 'other') THEN
    RAISE EXCEPTION 'invalid reason_type: %. Must be backout | rejected | other', p_reason_type
      USING ERRCODE = '22023';
  END IF;

  IF p_new_status IS NULL
     AND p_follow_up_date IS NULL
     AND p_recruitment_remarks IS NULL
     AND p_ops_remarks IS NULL
     AND p_deployed_reliever IS NULL
     AND p_deployed_commando IS NULL
     AND NOT COALESCE(p_clear_recruitment_remarks, false)
     AND NOT COALESCE(p_clear_ops_remarks, false) THEN
    RAISE EXCEPTION 'no applicant pipeline changes requested'
      USING ERRCODE = '22023';
  END IF;

  -- Vacancy module lock is authoritative for applicant pipeline updates.
  PERFORM public.fn_assert_vacancy_edit_allowed_op('UPDATE');

  SELECT up.full_name
  INTO v_actor_name
  FROM public.users_profile up
  WHERE up.id = v_profile_id;

  SELECT *
  INTO v_app
  FROM public.applicants
  WHERE id = p_applicant_id
    AND COALESCE(is_archived, false) = false
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'applicant % not found or archived', p_applicant_id
      USING ERRCODE = 'P0002';
  END IF;

  -- Load vacancy to check if it is a pool vacancy
  IF COALESCE(v_app.vacancy_vcode, '') <> '' THEN
    SELECT * INTO v_vac FROM public.vacancies WHERE vcode = v_app.vacancy_vcode AND deleted_at IS NULL LIMIT 1;
    IF FOUND AND COALESCE(v_vac.is_pool_vacancy, false) = true THEN
      IF NOT (v_level = 100 OR public.i_am_recruitment()) THEN
        RAISE EXCEPTION 'forbidden: applicant pipeline updates for pool vacancies are limited to Recruitment and Super Admin'
          USING ERRCODE = '42501';
      END IF;
    END IF;
  END IF;

  -- HA has full read visibility elsewhere but is explicitly read-only here.
  IF v_level = 90 THEN
    RAISE EXCEPTION 'Head Admin is read-only for applicant pipeline updates'
      USING ERRCODE = '42501';
  END IF;

  IF NOT (v_level = 100 OR public.i_am_recruitment() OR public.i_am_ops()) THEN
    RAISE EXCEPTION 'forbidden: applicant pipeline updates are limited to Recruitment, HRCO/ATL/TL/OM, and Super Admin'
      USING ERRCODE = '42501';
  END IF;

  IF NOT public.i_have_full_access() AND NOT (COALESCE(v_vac.is_pool_vacancy, false) = true AND public.i_am_recruitment()) THEN
    IF NOT EXISTS (
      SELECT 1
      FROM public.vacancies v
      WHERE v.vcode = v_app.vacancy_vcode
        AND v.account = ANY(public.get_my_allowed_accounts())
        AND v.deleted_at IS NULL
    ) THEN
      RAISE EXCEPTION 'forbidden: applicant is outside your account scope'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  SELECT aso.status_code, aso.is_terminal
  INTO v_old_status_code, v_old_status_terminal
  FROM public.applicant_status_options aso
  WHERE aso.status_code = v_app.status
     OR aso.label = v_app.status
     OR lower(regexp_replace(aso.label, '[^a-zA-Z0-9]+', '_', 'g')) =
        lower(regexp_replace(COALESCE(v_app.status, ''), '[^a-zA-Z0-9]+', '_', 'g'))
  ORDER BY CASE WHEN aso.status_code = v_app.status THEN 0 ELSE 1 END
  LIMIT 1;

  IF v_old_status_code IS NULL THEN
    v_old_status_code := lower(regexp_replace(COALESCE(v_app.status, ''), '[^a-zA-Z0-9]+', '_', 'g'));
    v_old_status_terminal := false;
  END IF;

  IF v_old_status_code = 'confirmed_onboard' AND v_level < 100 THEN
    RAISE EXCEPTION 'applicant is onboarded; only Super Admin may update applicant pipeline fields'
      USING ERRCODE = '42501';
  END IF;

  IF COALESCE(v_old_status_terminal, false) AND p_new_status IS NOT NULL AND v_level < 100 THEN
    RAISE EXCEPTION 'cannot change status from terminal status % without Super Admin override', v_app.status
      USING ERRCODE = '42501';
  END IF;

  IF (p_new_status IS NOT NULL OR p_follow_up_date IS NOT NULL)
     AND NOT (v_level = 100 OR public.i_am_recruitment() OR public.i_am_ops()) THEN
    RAISE EXCEPTION 'only Recruitment, HRCO/ATL/TL/OM, or Super Admin may update status or follow_up_date'
      USING ERRCODE = '42501';
  END IF;

  IF (p_recruitment_remarks IS NOT NULL OR COALESCE(p_clear_recruitment_remarks, false))
     AND NOT (v_level = 100 OR public.i_am_recruitment()) THEN
    RAISE EXCEPTION 'only Recruitment or Super Admin may update recruitment_remarks'
      USING ERRCODE = '42501';
  END IF;

  IF (p_ops_remarks IS NOT NULL OR COALESCE(p_clear_ops_remarks, false))
     AND NOT (v_level = 100 OR public.i_am_ops()) THEN
    RAISE EXCEPTION 'only HRCO/ATL/TL/OM or Super Admin may update ops_remarks'
      USING ERRCODE = '42501';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'applicants'
      AND column_name = 'deployed_reliever'
  )
  INTO v_has_deployed_reliever;

  SELECT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'applicants'
      AND column_name = 'deployed_commando'
  )
  INTO v_has_deployed_commando;

  IF p_deployed_reliever IS NOT NULL AND NOT v_has_deployed_reliever THEN
    RAISE EXCEPTION 'applicants.deployed_reliever is not available in this schema'
      USING ERRCODE = '42703';
  END IF;

  IF p_deployed_commando IS NOT NULL AND NOT v_has_deployed_commando THEN
    RAISE EXCEPTION 'applicants.deployed_commando is not available in this schema'
      USING ERRCODE = '42703';
  END IF;

  IF (p_deployed_reliever IS NOT NULL OR p_deployed_commando IS NOT NULL)
     AND NOT (v_level = 100 OR public.i_am_ops()) THEN
    RAISE EXCEPTION 'only HRCO/ATL/TL/OM or Super Admin may update deployment flags'
      USING ERRCODE = '42501';
  END IF;

  IF p_new_status IS NOT NULL THEN
    v_new_status_code := lower(regexp_replace(btrim(p_new_status), '[^a-zA-Z0-9]+', '_', 'g'));

    SELECT *
    INTO v_new_status
    FROM public.applicant_status_options aso
    WHERE aso.is_active = true
      AND (
        aso.status_code = v_new_status_code
        OR aso.label = btrim(p_new_status)
        OR lower(regexp_replace(aso.label, '[^a-zA-Z0-9]+', '_', 'g')) = v_new_status_code
      )
    LIMIT 1;

    IF v_new_status.status_code IS NULL THEN
      RAISE EXCEPTION 'invalid status: %', p_new_status
        USING ERRCODE = '22023';
    END IF;

    IF v_new_status.status_code <> v_old_status_code THEN
      v_status_changed := true;
      v_new_status_label := v_new_status.label;
    END IF;
  END IF;

  IF p_follow_up_date IS NOT NULL AND COALESCE(v_app.follow_up_date, '1970-01-01'::date) <> p_follow_up_date THEN
    v_follow_up_changed := true;
    v_old_follow_up_date := v_app.follow_up_date;
    v_new_follow_up_date := p_follow_up_date;
  END IF;

  IF COALESCE(p_clear_recruitment_remarks, false) THEN
    IF v_app.recruitment_remarks IS NOT NULL THEN
      v_recruitment_remarks_changed := true;
      v_old_recruitment_remarks := v_app.recruitment_remarks;
      v_new_recruitment_remarks := NULL;
    END IF;
  ELSIF p_recruitment_remarks IS NOT NULL AND COALESCE(v_app.recruitment_remarks, '') <> btrim(p_recruitment_remarks) THEN
    v_recruitment_remarks_changed := true;
    v_old_recruitment_remarks := v_app.recruitment_remarks;
    v_new_recruitment_remarks := btrim(p_recruitment_remarks);
  END IF;

  IF COALESCE(p_clear_ops_remarks, false) THEN
    IF v_app.ops_remarks IS NOT NULL THEN
      v_ops_remarks_changed := true;
      v_old_ops_remarks := v_app.ops_remarks;
      v_new_ops_remarks := NULL;
    END IF;
  ELSIF p_ops_remarks IS NOT NULL AND COALESCE(v_app.ops_remarks, '') <> btrim(p_ops_remarks) THEN
    v_ops_remarks_changed := true;
    v_old_ops_remarks := v_app.ops_remarks;
    v_new_ops_remarks := btrim(p_ops_remarks);
  END IF;

  IF v_has_deployed_reliever AND p_deployed_reliever IS NOT NULL THEN
    EXECUTE 'SELECT COALESCE(deployed_reliever, false) FROM public.applicants WHERE id = $1'
      INTO v_old_deployed_reliever USING v_app.id;
    IF v_old_deployed_reliever <> p_deployed_reliever THEN
      v_deployed_reliever_changed := true;
    END IF;
  END IF;

  IF v_has_deployed_commando AND p_deployed_commando IS NOT NULL THEN
    EXECUTE 'SELECT COALESCE(deployed_commando, false) FROM public.applicants WHERE id = $1'
      INTO v_old_deployed_commando USING v_app.id;
    IF v_old_deployed_commando <> p_deployed_commando THEN
      v_deployed_commando_changed := true;
    END IF;
  END IF;

  IF NOT (
    v_status_changed OR
    v_follow_up_changed OR
    v_recruitment_remarks_changed OR
    v_ops_remarks_changed OR
    v_deployed_reliever_changed OR
    v_deployed_commando_changed
  ) THEN
    RETURN jsonb_build_object('ok', true, 'applicant_id', v_app.id, 'changed', false);
  END IF;

  UPDATE public.applicants
  SET
    status = CASE WHEN v_status_changed THEN v_new_status_label ELSE status END,
    follow_up_date = CASE WHEN v_follow_up_changed THEN v_new_follow_up_date ELSE follow_up_date END,
    recruitment_remarks = CASE WHEN v_recruitment_remarks_changed THEN v_new_recruitment_remarks ELSE recruitment_remarks END,
    ops_remarks = CASE WHEN v_ops_remarks_changed THEN v_new_ops_remarks ELSE ops_remarks END,
    deployed_reliever = CASE WHEN v_deployed_reliever_changed THEN p_deployed_reliever ELSE COALESCE(v_app.deployed_reliever, false) END,
    deployed_commando = CASE WHEN v_deployed_commando_changed THEN p_deployed_commando ELSE COALESCE(v_app.deployed_commando, false) END,
    updated_at = v_now,
    updated_by = v_profile_id
  WHERE id = v_app.id;

  IF v_status_changed THEN
    INSERT INTO public.applicant_status_history (
      applicant_id, status, remarks,
      performed_by, performed_by_name, performed_by_team,
      created_at, reason_id, reason_type
    ) VALUES (
      v_app.id, v_new_status_label, COALESCE(p_recruitment_remarks, p_ops_remarks, ''),
      v_profile_id, v_actor_name, public.get_my_role(),
      v_now, p_reason_id, p_reason_type
    ) RETURNING id INTO v_history_id;

    v_history_ids := array_append(v_history_ids, v_history_id);
    v_change_count := v_change_count + 1;
  END IF;

  IF v_follow_up_changed THEN
    INSERT INTO public.applicant_pipeline_history (
      applicant_id, field_name, old_value, new_value,
      performed_by_id, performed_by_name, created_at
    ) VALUES (
      v_app.id, 'follow_up_date', v_old_follow_up_date::text, v_new_follow_up_date::text,
      v_profile_id, v_actor_name, v_now
    ) RETURNING id INTO v_history_id;

    v_history_ids := array_append(v_history_ids, v_history_id);
    v_change_count := v_change_count + 1;
  END IF;

  IF v_recruitment_remarks_changed THEN
    INSERT INTO public.applicant_pipeline_history (
      applicant_id, field_name, old_value, new_value,
      performed_by_id, performed_by_name, created_at
    ) VALUES (
      v_app.id, 'recruitment_remarks', v_old_recruitment_remarks, v_new_recruitment_remarks,
      v_profile_id, v_actor_name, v_now
    ) RETURNING id INTO v_history_id;

    v_history_ids := array_append(v_history_ids, v_history_id);
    v_change_count := v_change_count + 1;
  END IF;

  IF v_ops_remarks_changed THEN
    INSERT INTO public.applicant_pipeline_history (
      applicant_id, field_name, old_value, new_value,
      performed_by_id, performed_by_name, created_at
    ) VALUES (
      v_app.id, 'ops_remarks', v_old_ops_remarks, v_new_ops_remarks,
      v_profile_id, v_actor_name, v_now
    ) RETURNING id INTO v_history_id;

    v_history_ids := array_append(v_history_ids, v_history_id);
    v_change_count := v_change_count + 1;
  END IF;

  IF v_deployed_reliever_changed THEN
    INSERT INTO public.applicant_pipeline_history (
      applicant_id, field_name, old_value, new_value,
      performed_by_id, performed_by_name, created_at
    ) VALUES (
      v_app.id, 'deployed_reliever', v_old_deployed_reliever::text, p_deployed_reliever::text,
      v_profile_id, v_actor_name, v_now
    ) RETURNING id INTO v_history_id;

    v_history_ids := array_append(v_history_ids, v_history_id);
    v_change_count := v_change_count + 1;
  END IF;

  IF v_deployed_commando_changed THEN
    INSERT INTO public.applicant_pipeline_history (
      applicant_id, field_name, old_value, new_value,
      performed_by_id, performed_by_name, created_at
    ) VALUES (
      v_app.id, 'deployed_commando', v_old_deployed_commando::text, p_deployed_commando::text,
      v_profile_id, v_actor_name, v_now
    ) RETURNING id INTO v_history_id;

    v_history_ids := array_append(v_history_ids, v_history_id);
    v_change_count := v_change_count + 1;
  END IF;

  -- Perform slot sync cascade
  IF v_status_changed THEN
    DECLARE
      v_slot_type text := 'stationary';
      v_cov_group_found boolean := false;
    BEGIN
      IF v_app.coverage_slot_id IS NOT NULL THEN
        v_slot_type := 'roving';
      END IF;

      IF v_slot_type = 'roving' THEN
        IF v_new_status.is_terminal THEN
          PERFORM public.fn_release_coverage_slot(v_app.coverage_slot_id, v_profile_id);
        END IF;
      ELSE
        PERFORM public.fn_sync_vacancy_slot_open_pipeline(
          v_app.vacancy_vcode,
          v_profile_id,
          p_source_fn => 'fn_update_applicant_pipeline'
        );
      END IF;
    END;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'applicant_id', v_app.id,
    'changed', true,
    'change_count', v_change_count,
    'history_ids', v_history_ids
  );
END;
$$;
