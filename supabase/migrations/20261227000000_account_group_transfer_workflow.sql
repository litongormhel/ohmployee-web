-- ============================================================
-- OHM2026_0110 — Account Group Transfer Request Workflow
-- Migration:  20261227000000_account_group_transfer_workflow.sql
--
-- Creates:
--   • account_group_transfer_requests        — core request table
--   • account_group_transfer_request_history — transition audit trail
--   • simulate_account_group_transfer        — impact simulation RPC
--   • submit_account_group_transfer_request  — request submission RPC
--   • approve_account_group_transfer_request — approval & execution RPC
--   • reject_account_group_transfer_request  — rejection RPC
-- ============================================================

-- ─── Cleanup existing tables if re-applying ───────────────────
DROP TABLE IF EXISTS public.account_group_transfer_request_history CASCADE;
DROP TABLE IF EXISTS public.account_group_transfer_requests CASCADE;

-- ─── Extend audit_action enum with transfer request actions ───
ALTER TYPE public.audit_action ADD VALUE IF NOT EXISTS 'SUBMIT_REQUEST';
ALTER TYPE public.audit_action ADD VALUE IF NOT EXISTS 'APPROVE_REQUEST';
ALTER TYPE public.audit_action ADD VALUE IF NOT EXISTS 'REJECT_REQUEST';

-- ─── Sequence for human-readable request numbers ─────────────
CREATE SEQUENCE IF NOT EXISTS public.agt_request_number_seq
  START WITH 1
  INCREMENT BY 1
  NO MINVALUE
  NO MAXVALUE
  CACHE 1;

-- ─── Core request table ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.account_group_transfer_requests (
  id                     uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  request_number         text        NOT NULL UNIQUE,
  account_id             uuid        NOT NULL REFERENCES public.accounts(id) ON DELETE RESTRICT,
  from_group_id          uuid        NOT NULL REFERENCES public.groups(id) ON DELETE RESTRICT,
  to_group_id            uuid        NOT NULL REFERENCES public.groups(id) ON DELETE RESTRICT,
  reason                 text        NOT NULL,
  status                 text        NOT NULL DEFAULT 'pending'
                           CHECK (status IN ('pending', 'approved', 'rejected')),
  
  -- Persisted simulation snapshot at submission time
  simulation_snapshot    jsonb       NOT NULL DEFAULT '{}'::jsonb,
  
  -- Requester
  requested_by           uuid        NOT NULL REFERENCES public.users_profile(id) ON DELETE RESTRICT,
  requested_by_name      text        NOT NULL,
  requested_at           timestamptz NOT NULL DEFAULT now(),
  
  -- Reviewer
  reviewed_by            uuid        REFERENCES public.users_profile(id) ON DELETE SET NULL,
  reviewed_by_name       text,
  reviewed_at            timestamptz,
  rejection_reason       text,
  
  created_at             timestamptz NOT NULL DEFAULT now(),
  updated_at             timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.account_group_transfer_requests IS
  'Account group transfer requests allowing Head Admins to submit and Super Admins to approve/reject.';

-- ─── History / audit trail ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.account_group_transfer_request_history (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id    uuid        NOT NULL
                  REFERENCES public.account_group_transfer_requests(id) ON DELETE CASCADE,
  from_status   text,
  to_status     text        NOT NULL,
  action        text        NOT NULL
                  CHECK (action IN ('submitted', 'approved', 'rejected')),
  actor_id      uuid        REFERENCES public.users_profile(id) ON DELETE SET NULL,
  actor_name    text,
  note          text,
  created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_agt_history_request_id
  ON public.account_group_transfer_request_history(request_id);

-- ─── Auto-update updated_at ────────────────────────────────────
CREATE TRIGGER trg_agt_set_updated_at
  BEFORE UPDATE ON public.account_group_transfer_requests
  FOR EACH ROW EXECUTE FUNCTION public.fn_set_updated_at();

-- ─── RLS ──────────────────────────────────────────────────────
ALTER TABLE public.account_group_transfer_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.account_group_transfer_request_history ENABLE ROW LEVEL SECURITY;

-- Read policy: only visible to HA and SA (role_level >= 90)
CREATE POLICY agt_select_scoped ON public.account_group_transfer_requests
  FOR SELECT TO authenticated
  USING (
    public.i_have_full_access()
    OR public.get_my_role_level() >= 90
  );

-- Requests: no direct writes — all operations through SECURE DEFINER RPCs
CREATE POLICY agt_no_direct_insert ON public.account_group_transfer_requests
  FOR INSERT WITH CHECK (false);
CREATE POLICY agt_no_direct_update ON public.account_group_transfer_requests
  FOR UPDATE USING (false);
CREATE POLICY agt_no_direct_delete ON public.account_group_transfer_requests
  FOR DELETE USING (false);

-- History: read-only via parent request access
CREATE POLICY agt_history_select ON public.account_group_transfer_request_history
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.account_group_transfer_requests r
      WHERE r.id = request_id
        AND (
          public.i_have_full_access()
          OR public.get_my_role_level() >= 90
        )
    )
  );

CREATE POLICY agt_history_no_write ON public.account_group_transfer_request_history
  FOR ALL USING (false);

-- ─── RPC: simulate_account_group_transfer ──────────────────────
CREATE OR REPLACE FUNCTION public.simulate_account_group_transfer(
  p_account_id   uuid,
  p_to_group_id  uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path TO 'public'
AS $$
DECLARE
  v_caller_role_level      integer;
  v_current_group_id       uuid;
  v_current_group_name     text;
  v_current_group_code     text;
  v_to_group_name          text;
  v_to_group_code          text;
  
  v_stores_count           integer;
  v_plantilla_count        integer;
  v_vacancies_count        integer;
  v_hr_emploc_count        integer;
  
  v_losing_count           integer;
  v_gaining_count          integer;
  
  v_conflicts              jsonb := '[]'::jsonb;
  v_cg_warnings            jsonb := '[]'::jsonb;
  v_deployment_warnings    jsonb := '[]'::jsonb;
  v_warnings               jsonb := '[]'::jsonb;
  v_warning_count          integer := 0;
BEGIN
  -- Verify caller role
  v_caller_role_level := COALESCE(public.get_my_role_level(), 0);
  IF v_caller_role_level < 90 AND NOT public.i_have_full_access() THEN
    RAISE EXCEPTION 'forbidden: Head Admin or Super Admin role required' USING ERRCODE = '42501';
  END IF;

  -- Get current group info
  SELECT a.group_id, g.group_name, g.group_code
    INTO v_current_group_id, v_current_group_name, v_current_group_code
  FROM public.accounts a
  JOIN public.groups g ON g.id = a.group_id
  WHERE a.id = p_account_id;

  IF v_current_group_id IS NULL THEN
    RAISE EXCEPTION 'account not found' USING ERRCODE = 'P0002';
  END IF;

  -- Get destination group info
  SELECT g.group_name, g.group_code
    INTO v_to_group_name, v_to_group_code
  FROM public.groups g
  WHERE g.id = p_to_group_id;

  IF v_to_group_name IS NULL THEN
    RAISE EXCEPTION 'destination group not found' USING ERRCODE = 'P0002';
  END IF;

  -- Same group validation - warning only
  IF v_current_group_id = p_to_group_id THEN
    v_warnings := jsonb_build_array('Account is already owned by the destination group.');
  END IF;

  -- 1. Affected stores count
  SELECT COUNT(*) INTO v_stores_count
  FROM public.stores
  WHERE account_id = p_account_id
    AND is_active = true
    AND lower(COALESCE(status, 'active')) <> 'archived';

  -- 2. Affected plantilla count (active employees only)
  SELECT COUNT(*) INTO v_plantilla_count
  FROM public.plantilla
  WHERE account_id = p_account_id
    AND status = 'Active';

  -- 3. Affected vacancies count (open only)
  SELECT COUNT(*) INTO v_vacancies_count
  FROM public.vacancies
  WHERE account_id = p_account_id
    AND status = 'Open'
    AND archived_at IS NULL
    AND deleted_at IS NULL;

  -- 4. Affected HR Emploc count (active/pending only)
  SELECT COUNT(*) INTO v_hr_emploc_count
  FROM public.hr_emploc
  WHERE account_id = p_account_id
    AND deleted_at IS NULL;

  -- 5. Calculate visibility impact (group-scoped users losing/gaining access)
  -- Users with group-level scopes who will lose visibility of this account
  SELECT COUNT(DISTINCT us.user_id) INTO v_losing_count
  FROM public.user_scopes us
  JOIN public.users_profile up ON up.id = us.user_id
  JOIN public.roles r ON r.id = up.role_id
  WHERE us.group_id = v_current_group_id
    AND us.account_id IS NULL
    AND r.role_level < 90;

  -- Users with group-level scopes who will gain visibility of this account
  SELECT COUNT(DISTINCT us.user_id) INTO v_gaining_count
  FROM public.user_scopes us
  JOIN public.users_profile up ON up.id = us.user_id
  JOIN public.roles r ON r.id = up.role_id
  WHERE us.group_id = p_to_group_id
    AND us.account_id IS NULL
    AND r.role_level < 90;

  -- 6. Detect coverage group warnings (Coverage groups containing stores that will move ownership groups after transfer)
  SELECT COALESCE(
    jsonb_agg(
      'Coverage Group ' || cg.coverage_code || ' contains stores that will move ownership groups after transfer.'
    ),
    '[]'::jsonb
  ) INTO v_cg_warnings
  FROM (
    SELECT DISTINCT cg.coverage_code
    FROM public.coverage_group_stores cgs
    JOIN public.coverage_groups cg ON cg.id = cgs.coverage_group_id
    JOIN public.stores s ON s.id = cgs.store_id
    WHERE s.account_id = p_account_id
      AND cgs.archived_at IS NULL
      AND cg.archived_at IS NULL
    ORDER BY cg.coverage_code
  ) cg;

  -- 7. Detect active reliever/commando deployments warnings (from other groups)
  SELECT COALESCE(
    jsonb_agg(
      'Active reliever/commando deployment: ' || p.employee_name || ' deployed at ' || s.store_name || ' (Home Group: ' || g_home.group_name || ').'
    ),
    '[]'::jsonb
  ) INTO v_deployment_warnings
  FROM public.workforce_assignments wa
  JOIN public.plantilla p ON p.id = wa.employee_id
  JOIN public.accounts a_home ON a_home.id = p.account_id
  JOIN public.groups g_home ON g_home.id = a_home.group_id
  JOIN public.stores s ON s.id = wa.assigned_store_id
  WHERE s.account_id = p_account_id
    AND wa.status IN ('Active', 'Approved')
    AND g_home.id <> p_to_group_id;

  -- Format conflicts details if needed by UI
  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'employee_name', p.employee_name,
        'store_name', s.store_name,
        'home_group_name', g_home.group_name,
        'conflict_type', 'cross-group deployment'
      )
    ),
    '[]'::jsonb
  ) INTO v_conflicts
  FROM public.workforce_assignments wa
  JOIN public.plantilla p ON p.id = wa.employee_id
  JOIN public.accounts a_home ON a_home.id = p.account_id
  JOIN public.groups g_home ON g_home.id = a_home.group_id
  JOIN public.stores s ON s.id = wa.assigned_store_id
  WHERE s.account_id = p_account_id
    AND wa.status IN ('Active', 'Approved')
    AND g_home.id <> p_to_group_id;

  -- Combine all warnings
  v_warnings := v_warnings || v_cg_warnings || v_deployment_warnings;
  v_warning_count := jsonb_array_length(v_warnings);

  RETURN jsonb_build_object(
    'current_group_id', v_current_group_id,
    'current_group_name', v_current_group_name,
    'current_group_code', v_current_group_code,
    'destination_group_id', p_to_group_id,
    'destination_group_name', v_to_group_name,
    'destination_group_code', v_to_group_code,
    'affected_stores', v_stores_count,
    'affected_plantilla_count', v_plantilla_count,
    'affected_vacancies_count', v_vacancies_count,
    'affected_hr_emploc_count', v_hr_emploc_count,
    'coverage_group_conflicts', v_conflicts,
    'users_gaining_visibility', COALESCE(v_gaining_count, 0),
    'users_losing_visibility', COALESCE(v_losing_count, 0),
    'has_coverage_conflict', false, -- Warning only, never blocks
    'blocking_reason', null,
    'warnings', v_warnings,
    'warning_count', v_warning_count
  );
END;
$$;

-- ─── RPC: submit_account_group_transfer_request ─────────────────
CREATE OR REPLACE FUNCTION public.submit_account_group_transfer_request(
  p_account_id   uuid,
  p_to_group_id  uuid,
  p_reason       text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_caller_id        uuid;
  v_caller_name      text;
  v_caller_role_lvl  integer;
  
  v_current_group_id uuid;
  v_account_name     text;
  v_request_id       uuid;
  v_req_num          text;
  v_simulation       jsonb;
  
  -- Notification variables
  v_rec_user_id      uuid;
  v_rec_role         text;
BEGIN
  -- Get caller profile
  SELECT id, full_name, public.get_my_role_level()
    INTO v_caller_id, v_caller_name, v_caller_role_lvl
  FROM public.users_profile
  WHERE auth_user_id = auth.uid()
    AND is_active = true;

  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'forbidden: active profile not found' USING ERRCODE = '42501';
  END IF;

  -- Only Head Admin or Super Admin can submit
  IF v_caller_role_lvl < 90 THEN
    RAISE EXCEPTION 'forbidden: Head Admin or Super Admin role required' USING ERRCODE = '42501';
  END IF;

  -- Check current group of the account
  SELECT group_id, account_name INTO v_current_group_id, v_account_name
  FROM public.accounts WHERE id = p_account_id;

  IF v_current_group_id IS NULL THEN
    RAISE EXCEPTION 'account not found' USING ERRCODE = 'P0002';
  END IF;

  -- Prevent duplicate pending requests
  IF EXISTS (
    SELECT 1 FROM public.account_group_transfer_requests
    WHERE account_id = p_account_id AND status = 'pending'
  ) THEN
    RAISE EXCEPTION 'An active pending transfer request already exists for this account.' USING ERRCODE = 'P0001';
  END IF;

  -- Run simulation
  v_simulation := public.simulate_account_group_transfer(p_account_id, p_to_group_id);

  -- Generate human-readable request number AGT-YYYY-XXXX
  v_req_num := 'AGT-' || to_char(now(), 'YYYY') || '-' || lpad(nextval('public.agt_request_number_seq')::text, 4, '0');
  v_request_id := gen_random_uuid();

  -- Insert request
  INSERT INTO public.account_group_transfer_requests (
    id,
    request_number,
    account_id,
    from_group_id,
    to_group_id,
    reason,
    status,
    simulation_snapshot,
    requested_by,
    requested_by_name,
    requested_at
  ) VALUES (
    v_request_id,
    v_req_num,
    p_account_id,
    v_current_group_id,
    p_to_group_id,
    p_reason,
    'pending',
    v_simulation,
    v_caller_id,
    v_caller_name,
    now()
  );

  -- Insert history
  INSERT INTO public.account_group_transfer_request_history (
    request_id,
    to_status,
    action,
    actor_id,
    actor_name,
    note
  ) VALUES (
    v_request_id,
    'pending',
    'submitted',
    v_caller_id,
    v_caller_name,
    'Request submitted for review'
  );

  -- Insert audit log
  INSERT INTO public.audit_logs (actor_id, module, action, record_id, new_data)
  VALUES (auth.uid(), 'account_group_transfer', 'SUBMIT_REQUEST', v_request_id, v_simulation);

  -- ─── NOTIFICATIONS ───
  
  -- 1. Notify the requester
  PERFORM public.notify_user(
    auth.uid(),
    'Head Admin',
    'Account Transfer Submitted — ' || v_account_name,
    'Your transfer request ' || v_req_num || ' for account ' || v_account_name || ' has been submitted.',
    'account_transfer',
    'ACCOUNT_TRANSFER_SUBMITTED',
    'account_group_transfer_request',
    v_request_id::text,
    '/account-group-transfers/' || v_request_id::text
  );

  -- 2. Notify Current Group HRCOs
  FOR v_rec_user_id, v_rec_role IN
    SELECT DISTINCT up.auth_user_id, r.role_name
    FROM public.users_profile up
    JOIN public.roles r ON r.id = up.role_id
    JOIN public.user_scopes us ON us.user_id = up.id
    WHERE us.group_id = v_current_group_id
      AND up.is_active = true
      AND r.role_level = 45
  LOOP
    PERFORM public.notify_user(
      v_rec_user_id,
      v_rec_role,
      'Account Leaving Group — ' || v_account_name,
      'Account ' || v_account_name || ' is requested to be transferred out of your group.',
      'account_transfer',
      'ACCOUNT_TRANSFER_SUBMITTED',
      'account_group_transfer_request',
      v_request_id::text,
      '/account-group-transfers/' || v_request_id::text
    );
  END LOOP;

  -- 3. Notify Destination Group HRCOs
  FOR v_rec_user_id, v_rec_role IN
    SELECT DISTINCT up.auth_user_id, r.role_name
    FROM public.users_profile up
    JOIN public.roles r ON r.id = up.role_id
    JOIN public.user_scopes us ON us.user_id = up.id
    WHERE us.group_id = p_to_group_id
      AND up.is_active = true
      AND r.role_level = 45
  LOOP
    PERFORM public.notify_user(
      v_rec_user_id,
      v_rec_role,
      'Account Joining Group — ' || v_account_name,
      'Account ' || v_account_name || ' is requested to be transferred into your group.',
      'account_transfer',
      'ACCOUNT_TRANSFER_SUBMITTED',
      'account_group_transfer_request',
      v_request_id::text,
      '/account-group-transfers/' || v_request_id::text
    );
  END LOOP;

  -- 4. Notify SA and HA users
  FOR v_rec_user_id, v_rec_role IN
    SELECT DISTINCT up.auth_user_id, r.role_name
    FROM public.users_profile up
    JOIN public.roles r ON r.id = up.role_id
    WHERE up.is_active = true
      AND r.role_level IN (90, 100)
      AND up.id <> v_caller_id -- Exclude self if they are HA
  LOOP
    PERFORM public.notify_user(
      v_rec_user_id,
      v_rec_role,
      'New Account Transfer Request — ' || v_account_name,
      'Transfer request ' || v_req_num || ' for account ' || v_account_name || ' is pending review.',
      'account_transfer',
      'ACCOUNT_TRANSFER_SUBMITTED',
      'account_group_transfer_request',
      v_request_id::text,
      '/account-group-transfers/' || v_request_id::text
    );
  END LOOP;

  RETURN v_request_id;
END;
$$;

-- ─── RPC: approve_account_group_transfer_request ───────────────
CREATE OR REPLACE FUNCTION public.approve_account_group_transfer_request(
  p_request_id   uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_caller_id        uuid;
  v_caller_name      text;
  v_caller_role_lvl  integer;
  
  v_request_number   text;
  v_account_id       uuid;
  v_account_name     text;
  v_from_group_id    uuid;
  v_to_group_id      uuid;
  v_requested_by     uuid;
  v_requester_auth   uuid;
  
  v_simulation       jsonb;
  
  -- Notification variables
  v_rec_user_id      uuid;
  v_rec_role         text;
BEGIN
  -- Get caller profile
  SELECT id, full_name, public.get_my_role_level()
    INTO v_caller_id, v_caller_name, v_caller_role_lvl
  FROM public.users_profile
  WHERE auth_user_id = auth.uid()
    AND is_active = true;

  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'forbidden: active profile not found' USING ERRCODE = '42501';
  END IF;

  -- Only Super Admin can approve
  IF v_caller_role_lvl < 100 THEN
    RAISE EXCEPTION 'forbidden: Super Admin role required' USING ERRCODE = '42501';
  END IF;

  -- Fetch request details
  SELECT r.request_number, r.account_id, r.from_group_id, r.to_group_id, r.requested_by, a.account_name, up.auth_user_id
    INTO v_request_number, v_account_id, v_from_group_id, v_to_group_id, v_requested_by, v_account_name, v_requester_auth
  FROM public.account_group_transfer_requests r
  JOIN public.accounts a ON a.id = r.account_id
  JOIN public.users_profile up ON up.id = r.requested_by
  WHERE r.id = p_request_id
    AND r.status = 'pending';

  IF v_account_id IS NULL THEN
    RAISE EXCEPTION 'Request not found or not in pending state.' USING ERRCODE = 'P0002';
  END IF;

  -- Prevent self-approval (requester cannot approve own request, unless caller is Super Admin)
  IF (v_requested_by = v_caller_id OR v_requester_auth = auth.uid()) AND v_caller_role_lvl < 100 THEN
    RAISE EXCEPTION 'forbidden: You cannot approve your own transfer request.' USING ERRCODE = '42501';
  END IF;

  -- Re-evaluate simulation
  v_simulation := public.simulate_account_group_transfer(v_account_id, v_to_group_id);

  -- ─── EXECUTE TRANSFER ───
  
  -- Update account group ownership
  UPDATE public.accounts
  SET group_id = v_to_group_id,
      updated_at = now(),
      updated_by = v_caller_id
  WHERE id = v_account_id;

  -- Update stores group ownership (stores remain linked to the account)
  UPDATE public.stores
  SET group_id = v_to_group_id,
      updated_at = now(),
      updated_by = v_caller_id
  WHERE account_id = v_account_id;

  -- Update request status
  UPDATE public.account_group_transfer_requests
  SET status = 'approved',
      reviewed_by = v_caller_id,
      reviewed_by_name = v_caller_name,
      reviewed_at = now()
  WHERE id = p_request_id;

  -- Insert history
  INSERT INTO public.account_group_transfer_request_history (
    request_id,
    from_status,
    to_status,
    action,
    actor_id,
    actor_name,
    note
  ) VALUES (
    p_request_id,
    'pending',
    'approved',
    'approved',
    v_caller_id,
    v_caller_name,
    'Request approved and executed by Super Admin'
  );

  -- Insert audit log
  INSERT INTO public.audit_logs (actor_id, module, action, record_id, old_data, new_data)
  VALUES (
    auth.uid(),
    'account_group_transfer',
    'APPROVE_REQUEST',
    p_request_id,
    jsonb_build_object(
      'request_id', p_request_id,
      'account_id', v_account_id,
      'from_group_id', v_from_group_id,
      'approver_id', v_caller_id,
      'executed_at', now()
    ),
    jsonb_build_object(
      'request_id', p_request_id,
      'account_id', v_account_id,
      'to_group_id', v_to_group_id,
      'approver_id', v_caller_id,
      'executed_at', now()
    )
  );

  -- ─── NOTIFICATIONS ───

  -- 1. Notify the requester
  IF v_requester_auth IS NOT NULL THEN
    PERFORM public.notify_user(
      v_requester_auth,
      'Head Admin',
      'Account Transfer APPROVED — ' || v_account_name,
      'Your transfer request ' || v_request_number || ' for account ' || v_account_name || ' has been approved and executed.',
      'account_transfer',
      'ACCOUNT_TRANSFER_APPROVED',
      'account_group_transfer_request',
      p_request_id::text,
      '/account-group-transfers/' || p_request_id::text
    );
  END IF;

  -- 2. Notify Current Group HRCOs (Group they left)
  FOR v_rec_user_id, v_rec_role IN
    SELECT DISTINCT up.auth_user_id, r.role_name
    FROM public.users_profile up
    JOIN public.roles r ON r.id = up.role_id
    JOIN public.user_scopes us ON us.user_id = up.id
    WHERE us.group_id = v_from_group_id
      AND up.is_active = true
      AND r.role_level = 45
  LOOP
    PERFORM public.notify_user(
      v_rec_user_id,
      v_rec_role,
      'Account Transferred Out — ' || v_account_name,
      'Account ' || v_account_name || ' has been transferred out of your group.',
      'account_transfer',
      'ACCOUNT_TRANSFER_APPROVED',
      'account_group_transfer_request',
      p_request_id::text,
      '/account-group-transfers/' || p_request_id::text
    );
  END LOOP;

  -- 3. Notify Destination Group HRCOs (Group they joined)
  FOR v_rec_user_id, v_rec_role IN
    SELECT DISTINCT up.auth_user_id, r.role_name
    FROM public.users_profile up
    JOIN public.roles r ON r.id = up.role_id
    JOIN public.user_scopes us ON us.user_id = up.id
    WHERE us.group_id = v_to_group_id
      AND up.is_active = true
      AND r.role_level = 45
  LOOP
    PERFORM public.notify_user(
      v_rec_user_id,
      v_rec_role,
      'Account Transferred In — ' || v_account_name,
      'Account ' || v_account_name || ' has been transferred into your group.',
      'account_transfer',
      'ACCOUNT_TRANSFER_APPROVED',
      'account_group_transfer_request',
      p_request_id::text,
      '/account-group-transfers/' || p_request_id::text
    );
  END LOOP;

  -- 4. Notify SA and HA users
  FOR v_rec_user_id, v_rec_role IN
    SELECT DISTINCT up.auth_user_id, r.role_name
    FROM public.users_profile up
    JOIN public.roles r ON r.id = up.role_id
    WHERE up.is_active = true
      AND r.role_level IN (90, 100)
      AND up.id <> v_caller_id
  LOOP
    PERFORM public.notify_user(
      v_rec_user_id,
      v_rec_role,
      'Account Transfer Executed — ' || v_account_name,
      'Transfer request ' || v_request_number || ' for account ' || v_account_name || ' has been approved by Super Admin.',
      'account_transfer',
      'ACCOUNT_TRANSFER_APPROVED',
      'account_group_transfer_request',
      p_request_id::text,
      '/account-group-transfers/' || p_request_id::text
    );
  END LOOP;

  -- Reload schema trigger
  NOTIFY pgrst, 'reload schema';
END;
$$;

-- ─── RPC: reject_account_group_transfer_request ───────────────
CREATE OR REPLACE FUNCTION public.reject_account_group_transfer_request(
  p_request_id     uuid,
  p_reason         text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_caller_id        uuid;
  v_caller_name      text;
  v_caller_role_lvl  integer;
  
  v_request_number   text;
  v_account_id       uuid;
  v_account_name     text;
  v_from_group_id    uuid;
  v_to_group_id      uuid;
  v_requested_by     uuid;
  v_requester_auth   uuid;
  
  -- Notification variables
  v_rec_user_id      uuid;
  v_rec_role         text;
BEGIN
  -- Get caller profile
  SELECT id, full_name, public.get_my_role_level()
    INTO v_caller_id, v_caller_name, v_caller_role_lvl
  FROM public.users_profile
  WHERE auth_user_id = auth.uid()
    AND is_active = true;

  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'forbidden: active profile not found' USING ERRCODE = '42501';
  END IF;

  -- Only Super Admin can reject
  IF v_caller_role_lvl < 100 THEN
    RAISE EXCEPTION 'forbidden: Super Admin role required' USING ERRCODE = '42501';
  END IF;

  -- Rejection reason is required
  IF nullif(trim(p_reason), '') IS NULL THEN
    RAISE EXCEPTION 'Rejection reason is required.' USING ERRCODE = 'P0001';
  END IF;

  -- Fetch request details
  SELECT r.request_number, r.account_id, r.from_group_id, r.to_group_id, r.requested_by, a.account_name, up.auth_user_id
    INTO v_request_number, v_account_id, v_from_group_id, v_to_group_id, v_requested_by, v_account_name, v_requester_auth
  FROM public.account_group_transfer_requests r
  JOIN public.accounts a ON a.id = r.account_id
  JOIN public.users_profile up ON up.id = r.requested_by
  WHERE r.id = p_request_id
    AND r.status = 'pending';

  IF v_account_id IS NULL THEN
    RAISE EXCEPTION 'Request not found or not in pending state.' USING ERRCODE = 'P0002';
  END IF;

  -- Update request status
  UPDATE public.account_group_transfer_requests
  SET status = 'rejected',
      reviewed_by = v_caller_id,
      reviewed_by_name = v_caller_name,
      reviewed_at = now(),
      rejection_reason = p_reason
  WHERE id = p_request_id;

  -- Insert history
  INSERT INTO public.account_group_transfer_request_history (
    request_id,
    from_status,
    to_status,
    action,
    actor_id,
    actor_name,
    note
  ) VALUES (
    p_request_id,
    'pending',
    'rejected',
    'rejected',
    v_caller_id,
    v_caller_name,
    'Request rejected by Super Admin. Reason: ' || p_reason
  );

  -- Insert audit log
  INSERT INTO public.audit_logs (actor_id, module, action, record_id, new_data)
  VALUES (
    auth.uid(),
    'account_group_transfer',
    'REJECT_REQUEST',
    p_request_id,
    jsonb_build_object(
      'request_id', p_request_id,
      'account_id', v_account_id,
      'rejection_reason', p_reason,
      'reviewer_id', v_caller_id,
      'rejected_at', now()
    )
  );

  -- ─── NOTIFICATIONS ───

  -- 1. Notify the requester
  IF v_requester_auth IS NOT NULL THEN
    PERFORM public.notify_user(
      v_requester_auth,
      'Head Admin',
      'Account Transfer REJECTED — ' || v_account_name,
      'Your transfer request ' || v_request_number || ' for account ' || v_account_name || ' was rejected. Reason: ' || p_reason,
      'account_transfer',
      'ACCOUNT_TRANSFER_REJECTED',
      'account_group_transfer_request',
      p_request_id::text,
      '/account-group-transfers/' || p_request_id::text
    );
  END IF;

  -- 2. Notify Current Group HRCOs
  FOR v_rec_user_id, v_rec_role IN
    SELECT DISTINCT up.auth_user_id, r.role_name
    FROM public.users_profile up
    JOIN public.roles r ON r.id = up.role_id
    JOIN public.user_scopes us ON us.user_id = up.id
    WHERE us.group_id = v_from_group_id
      AND up.is_active = true
      AND r.role_level = 45
  LOOP
    PERFORM public.notify_user(
      v_rec_user_id,
      v_rec_role,
      'Account Transfer Request Rejected — ' || v_account_name,
      'The requested transfer for account ' || v_account_name || ' has been rejected by Super Admin.',
      'account_transfer',
      'ACCOUNT_TRANSFER_REJECTED',
      'account_group_transfer_request',
      p_request_id::text,
      '/account-group-transfers/' || p_request_id::text
    );
  END LOOP;

  -- 3. Notify Destination Group HRCOs
  FOR v_rec_user_id, v_rec_role IN
    SELECT DISTINCT up.auth_user_id, r.role_name
    FROM public.users_profile up
    JOIN public.roles r ON r.id = up.role_id
    JOIN public.user_scopes us ON us.user_id = up.id
    WHERE us.group_id = v_to_group_id
      AND up.is_active = true
      AND r.role_level = 45
  LOOP
    PERFORM public.notify_user(
      v_rec_user_id,
      v_rec_role,
      'Account Transfer Request Rejected — ' || v_account_name,
      'The requested transfer for account ' || v_account_name || ' has been rejected by Super Admin.',
      'account_transfer',
      'ACCOUNT_TRANSFER_REJECTED',
      'account_group_transfer_request',
      p_request_id::text,
      '/account-group-transfers/' || p_request_id::text
    );
  END LOOP;

  -- 4. Notify SA and HA users
  FOR v_rec_user_id, v_rec_role IN
    SELECT DISTINCT up.auth_user_id, r.role_name
    FROM public.users_profile up
    JOIN public.roles r ON r.id = up.role_id
    WHERE up.is_active = true
      AND r.role_level IN (90, 100)
      AND up.id <> v_caller_id
  LOOP
    PERFORM public.notify_user(
      v_rec_user_id,
      v_rec_role,
      'Account Transfer Rejected — ' || v_account_name,
      'Transfer request ' || v_request_number || ' for account ' || v_account_name || ' has been rejected by Super Admin.',
      'account_transfer',
      'ACCOUNT_TRANSFER_REJECTED',
      'account_group_transfer_request',
      p_request_id::text,
      '/account-group-transfers/' || p_request_id::text
    );
  END LOOP;

  -- Reload schema trigger
  NOTIFY pgrst, 'reload schema';
END;
$$;
