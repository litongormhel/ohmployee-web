-- ============================================================
-- ohm#reqfix01 — Request Notification Wiring + Deep Links
-- Migration: 20261220000000_request_notification_wiring.sql
-- ============================================================
-- Goal: Close request-lifecycle notification + deep-link gaps found in the
--       request-notification audit, WITHOUT rewriting the large production
--       approval RPCs (regression-safe). Notifications are wired as AFTER
--       triggers that call the canonical public.notify_user() helper.
--
-- Canonical helper (verified, 20260520012857_remote_schema.sql):
--   notify_user(p_recipient_user_id uuid, p_recipient_role text,
--               p_title text, p_message text,
--               p_notification_type text, p_event_type text,
--               p_reference_type text, p_reference_id text,
--               p_deep_link_route text, p_sla_level smallint DEFAULT NULL)
--
-- Scope (priority order from prompt):
--   §1  Module helpers (_rnw_auth_uid, _rnw_notify_roles)
--   §2  MOSES HQ Pool Requests       (workforce_pool_requests)
--   §3  HC / Headcount Requests      (headcount_requests)
--   §4  Coverage / Coverage Group    (coverage_requests)
--   §5  Account Creation submit      (handle_new_auth_user_request: add deep link)
--   §5b Account Creation approve     (account_requests: notify requestor on approval)
--   §6  Reliever Coverage            (workforce_assignment_requests — GUARDED)
--   §7  Deactivation submit          (employee_deactivation_requests)
--   §8  Temporary Access revoke      (revoke_temp_permission_override)
--
-- NOT touched (already complete / out of scope):
--   - HR Emploc Deletion requests (submit+approve+reject already notify)
--   - Deactivation approve/reject (already notify requestor)
--   - Vacancy Closure, AMR (out of scope; must not regress)
--
-- Safety:
--   - No destructive schema changes. No request approval-behavior changes.
--   - Triggers never notify archived/inactive users (is_active = true guard).
--   - Idempotent: CREATE OR REPLACE FUNCTION + DROP TRIGGER IF EXISTS.
--   - Reliever triggers are created ONLY IF absent (no duplicates vs the
--     legacy escalation engine, per ohm#reqfix01 "verify safely").
--
-- Deep-link route contract (must match Flutter notification_navigation_service):
--   Pool       -> /workforce/pool-requests/:id   (reference_type workforce_pool_request)
--   HC         -> /headcount-requests/:id        (reference_type headcount_request)
--   Coverage   -> /coverage-requests/:id         (reference_type coverage_request)
--   Account    -> /account-requests/:profile_id  (reference_type account_request)
--   Reliever   -> /workforce/requests/:id        (reference_type workforce_request)
--   Deactivate -> /deactivation-requests/:id     (reference_type deactivation_request)
--   TempAccess -> /access-requests/:override_id  (reference_type temp_permission)
-- ============================================================


-- ============================================================
-- §1  Module-scoped helpers
-- ============================================================

-- Resolve an auth.users id from a value that may be either a users_profile.id
-- or an auth_user_id. Prefers the profile-id interpretation. Returns NULL when
-- nothing matches (callers then skip the notification — no error raised).
CREATE OR REPLACE FUNCTION public._rnw_auth_uid(p_id uuid)
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT up.auth_user_id
  FROM public.users_profile up
  WHERE up.is_active = true
    AND (up.id = p_id OR up.auth_user_id = p_id)
  ORDER BY (up.id = p_id) DESC
  LIMIT 1;
$$;

-- Fan a single notification out to every ACTIVE user holding one of p_roles.
-- Returns the number of notifications created. Never targets inactive users.
CREATE OR REPLACE FUNCTION public._rnw_notify_roles(
  p_roles      text[],
  p_title      text,
  p_message    text,
  p_notif_type text,
  p_event_type text,
  p_ref_type   text,
  p_ref_id     text,
  p_deep_link  text
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  r record;
  n int := 0;
BEGIN
  FOR r IN
    SELECT up.auth_user_id, ro.role_name
    FROM public.users_profile up
    JOIN public.roles ro ON ro.id = up.role_id
    WHERE up.is_active = true
      AND up.auth_user_id IS NOT NULL
      AND ro.role_name = ANY (p_roles)
  LOOP
    PERFORM public.notify_user(
      r.auth_user_id, r.role_name, p_title, p_message,
      p_notif_type, p_event_type, p_ref_type, p_ref_id, p_deep_link, NULL
    );
    n := n + 1;
  END LOOP;
  RETURN n;
END;
$$;

REVOKE ALL ON FUNCTION public._rnw_auth_uid(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public._rnw_notify_roles(text[],text,text,text,text,text,text,text) FROM PUBLIC, anon;


-- ============================================================
-- §2  MOSES HQ Pool Requests  (workforce_pool_requests)
-- ============================================================
-- created_by holds the requester's users_profile.id stored AS TEXT.
-- Ops requests insert with status='pending' (need Data Team approval).
-- Data Team requests insert with status='approved' directly (auto-approved →
-- intentionally NOT notified on submit; the UPDATE guard also won't fire).

CREATE OR REPLACE FUNCTION public.trg_pool_request_notify()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_link     text := '/workforce/pool-requests/' || NEW.id::text;
  v_label    text;
  v_req_auth uuid;
  v_req_role text;
  v_req_pid  uuid;
BEGIN
  v_label := COALESCE(NEW.position_name, 'Pool position')
           || ' ×' || COALESCE(NEW.headcount_needed, 1)::text
           || ' (' || COALESCE(NULLIF(NEW.requesting_account, ''),
                               NULLIF(NEW.operational_account_name, ''),
                               'Global Pool') || ')';

  IF TG_OP = 'INSERT' THEN
    IF NEW.status = 'pending' AND COALESCE(NEW.is_ops_request, false) THEN
      PERFORM public._rnw_notify_roles(
        ARRAY['Super Admin','Head Admin','Encoder'],
        'New Pool Request',
        COALESCE(NEW.created_by_name, 'A user') || ' submitted a pool request: ' || v_label || '.',
        'workforce_pool_request', 'POOL_REQUEST_SUBMITTED',
        'workforce_pool_request', NEW.id::text, v_link
      );
    END IF;
    RETURN NEW;
  END IF;

  -- UPDATE OF status: notify requestor on terminal decision
  IF NEW.status IS DISTINCT FROM OLD.status
     AND OLD.status = 'pending'
     AND NEW.status IN ('approved','rejected') THEN

    v_req_pid := CASE
                   WHEN NEW.created_by ~ '^[0-9a-fA-F-]{36}$' THEN NEW.created_by::uuid
                   ELSE NULL
                 END;
    v_req_auth := public._rnw_auth_uid(v_req_pid);

    IF v_req_auth IS NOT NULL THEN
      SELECT ro.role_name INTO v_req_role
      FROM public.users_profile up
      JOIN public.roles ro ON ro.id = up.role_id
      WHERE up.auth_user_id = v_req_auth
      LIMIT 1;

      PERFORM public.notify_user(
        v_req_auth, COALESCE(v_req_role, 'ops'),
        CASE WHEN NEW.status = 'approved' THEN 'Pool Request Approved'
             ELSE 'Pool Request Rejected' END,
        'Your pool request ' || v_label || ' was ' || NEW.status || '.',
        'workforce_pool_request',
        CASE WHEN NEW.status = 'approved' THEN 'POOL_REQUEST_APPROVED'
             ELSE 'POOL_REQUEST_REJECTED' END,
        'workforce_pool_request', NEW.id::text, v_link, NULL
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_pool_request_notify_ins ON public.workforce_pool_requests;
CREATE TRIGGER trg_pool_request_notify_ins
  AFTER INSERT ON public.workforce_pool_requests
  FOR EACH ROW EXECUTE FUNCTION public.trg_pool_request_notify();

DROP TRIGGER IF EXISTS trg_pool_request_notify_upd ON public.workforce_pool_requests;
CREATE TRIGGER trg_pool_request_notify_upd
  AFTER UPDATE OF status ON public.workforce_pool_requests
  FOR EACH ROW EXECUTE FUNCTION public.trg_pool_request_notify();


-- ============================================================
-- §3  HC / Headcount Requests  (headcount_requests)
-- ============================================================
-- status: 'Pending Approval' -> 'Approved' -> 'Slot Created' | 'Rejected' | 'Cancelled'
-- requested_by_user_id may be a profile id or auth id (resolved defensively).

CREATE OR REPLACE FUNCTION public.trg_hc_request_notify()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_link     text := '/headcount-requests/' || NEW.id::text;
  v_label    text;
  v_req_auth uuid;
  v_req_role text;
BEGIN
  v_label := COALESCE(NEW.position_name_snapshot, 'Headcount')
           || ' ×' || COALESCE(NEW.headcount_needed, 1)::text
           || ' @ ' || COALESCE(NULLIF(NEW.store_name_snapshot, ''),
                                NULLIF(NEW.account_name_snapshot, ''), 'store');

  IF TG_OP = 'INSERT' THEN
    IF NEW.status = 'Pending Approval' THEN
      PERFORM public._rnw_notify_roles(
        ARRAY['Super Admin','Head Admin','Encoder'],
        'New Headcount Request',
        COALESCE(NEW.requested_by_name, 'A user') || ' submitted an HC request: ' || v_label || '.',
        'headcount_request', 'HC_REQUEST_SUBMITTED',
        'headcount_request', NEW.id::text, v_link
      );
    END IF;
    RETURN NEW;
  END IF;

  -- UPDATE OF status: notify requestor on Approved / Rejected / Slot Created
  IF NEW.status IS DISTINCT FROM OLD.status
     AND NEW.status IN ('Approved','Rejected','Slot Created') THEN

    v_req_auth := public._rnw_auth_uid(NEW.requested_by_user_id);
    IF v_req_auth IS NOT NULL THEN
      SELECT ro.role_name INTO v_req_role
      FROM public.users_profile up
      JOIN public.roles ro ON ro.id = up.role_id
      WHERE up.auth_user_id = v_req_auth
      LIMIT 1;

      PERFORM public.notify_user(
        v_req_auth, COALESCE(v_req_role, NEW.requested_by_role, 'ops'),
        CASE NEW.status
          WHEN 'Approved'     THEN 'Headcount Request Approved'
          WHEN 'Rejected'     THEN 'Headcount Request Rejected'
          ELSE                     'Headcount Request Fulfilled'
        END,
        'Your headcount request ' || v_label || ' is now "' || NEW.status || '".',
        'headcount_request',
        CASE NEW.status
          WHEN 'Approved'     THEN 'HC_REQUEST_APPROVED'
          WHEN 'Rejected'     THEN 'HC_REQUEST_REJECTED'
          ELSE                     'HC_REQUEST_COMPLETED'
        END,
        'headcount_request', NEW.id::text, v_link, NULL
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_hc_request_notify_ins ON public.headcount_requests;
CREATE TRIGGER trg_hc_request_notify_ins
  AFTER INSERT ON public.headcount_requests
  FOR EACH ROW EXECUTE FUNCTION public.trg_hc_request_notify();

DROP TRIGGER IF EXISTS trg_hc_request_notify_upd ON public.headcount_requests;
CREATE TRIGGER trg_hc_request_notify_upd
  AFTER UPDATE OF status ON public.headcount_requests
  FOR EACH ROW EXECUTE FUNCTION public.trg_hc_request_notify();


-- ============================================================
-- §4  Coverage / Coverage Group Requests  (coverage_requests)
-- ============================================================
-- status enum public.request_status: draft -> pending -> approved|rejected|cancelled
-- request_type enum distinguishes coverage vs coverage-group requests.
-- requested_by is a users_profile.id.

CREATE OR REPLACE FUNCTION public.trg_coverage_request_notify()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_link     text := '/coverage-requests/' || NEW.id::text;
  v_kind     text;
  v_req_auth uuid;
  v_req_role text;
BEGIN
  v_kind := CASE WHEN NEW.request_type::text ILIKE '%group%'
                 THEN 'Coverage Group Request' ELSE 'Coverage Request' END;

  -- Submitted: draft -> pending
  IF NEW.status::text = 'pending' AND OLD.status::text = 'draft' THEN
    PERFORM public._rnw_notify_roles(
      ARRAY['Super Admin','Head Admin','Encoder'],
      'New ' || v_kind,
      COALESCE(NEW.requested_by_name, 'A user') || ' submitted a '
        || lower(v_kind) || ' for review.',
      'coverage_request', 'COVERAGE_REQUEST_SUBMITTED',
      'coverage_request', NEW.id::text, v_link
    );
    RETURN NEW;
  END IF;

  -- Decision: pending -> approved | rejected
  IF NEW.status IS DISTINCT FROM OLD.status
     AND OLD.status::text = 'pending'
     AND NEW.status::text IN ('approved','rejected') THEN

    v_req_auth := public._rnw_auth_uid(NEW.requested_by);
    IF v_req_auth IS NOT NULL THEN
      SELECT ro.role_name INTO v_req_role
      FROM public.users_profile up
      JOIN public.roles ro ON ro.id = up.role_id
      WHERE up.auth_user_id = v_req_auth
      LIMIT 1;

      PERFORM public.notify_user(
        v_req_auth, COALESCE(v_req_role, NEW.requested_by_role, 'ops'),
        v_kind || ' ' || initcap(NEW.status::text),
        'Your ' || lower(v_kind) || ' was ' || NEW.status::text
          || COALESCE('. Reason: ' || NULLIF(NEW.rejection_reason, ''), '') || '.',
        'coverage_request',
        CASE WHEN NEW.status::text = 'approved'
             THEN 'COVERAGE_REQUEST_APPROVED' ELSE 'COVERAGE_REQUEST_REJECTED' END,
        'coverage_request', NEW.id::text, v_link, NULL
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_coverage_request_notify_upd ON public.coverage_requests;
CREATE TRIGGER trg_coverage_request_notify_upd
  AFTER UPDATE OF status ON public.coverage_requests
  FOR EACH ROW EXECUTE FUNCTION public.trg_coverage_request_notify();


-- ============================================================
-- §5  Account Creation submit — add deep link (preserve HA + SA)
-- ============================================================
-- The signup trigger already notifies BOTH Super Admin AND Head Admin on a new
-- request. We re-emit it ONLY to add deep_link_route + notification_type +
-- event_type to the existing notifications. All other behavior is preserved
-- verbatim. (Approval/rejection notifications to the pre-activation applicant
-- are intentionally deferred — see migration notes / handoff.)

CREATE OR REPLACE FUNCTION public.handle_new_auth_user_request()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
declare
  viewer_role_id uuid;
  first_name text;
  last_name text;
  computed_full_name text;
  profile_id uuid;
begin
  select id into viewer_role_id
  from public.roles
  where role_name = 'Viewer'
  limit 1;

  if viewer_role_id is null then
    raise exception 'Viewer role is not configured in public.roles';
  end if;

  first_name := nullif(trim(coalesce(new.raw_user_meta_data ->> 'first_name', '')), '');
  last_name := nullif(trim(coalesce(new.raw_user_meta_data ->> 'last_name', '')), '');
  computed_full_name := trim(
    both ' ' from coalesce(
      nullif(trim(coalesce(new.raw_user_meta_data ->> 'full_name', '')), ''),
      concat_ws(' ', first_name, last_name),
      split_part(coalesce(new.email, ''), '@', 1)
    )
  );

  select id into profile_id
  from public.users_profile
  where auth_user_id = new.id
  limit 1;

  if profile_id is null then
    insert into public.users_profile (
      auth_user_id, email, full_name, role_id, is_active
    )
    values (
      new.id, lower(new.email), computed_full_name, viewer_role_id, false
    )
    returning id into profile_id;
  else
    update public.users_profile
      set email = lower(new.email),
          full_name = computed_full_name
    where id = profile_id;
  end if;

  -- Notify BOTH Super Admin and Head Admin (preserved) — now with a deep link.
  insert into public.notifications (
    recipient_role,
    notification_type,
    event_type,
    title,
    message,
    deep_link_route,
    reference_type,
    reference_id
  )
  values
    (
      'Super Admin',
      'account_request',
      'ACCOUNT_REQUEST_SUBMITTED',
      'New account request',
      computed_full_name || ' requested account access.',
      '/account-requests/' || profile_id::text,
      'account_request',
      profile_id
    ),
    (
      'Head Admin',
      'account_request',
      'ACCOUNT_REQUEST_SUBMITTED',
      'New account request',
      computed_full_name || ' requested account access.',
      '/account-requests/' || profile_id::text,
      'account_request',
      profile_id
    );

  return new;
end;
$$;

-- Trigger already exists (on_auth_user_created_handle_request); re-asserting is
-- harmless and keeps this migration self-contained.
DROP TRIGGER IF EXISTS on_auth_user_created_handle_request ON auth.users;
CREATE TRIGGER on_auth_user_created_handle_request
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_auth_user_request();


-- ============================================================
-- §5b Account Creation approve → requestor notification
-- ============================================================
-- Fires AFTER UPDATE OF status on account_requests when status transitions to
-- 'approved'. Notifies the now-activated requestor with the same deep link
-- pattern used for the submit notification (/account-requests/:profile_id).
--
-- No is_active guard on the profile lookup: the approval RPC activates the user
-- within the same transaction, so is_active may still be false when this trigger
-- fires — we must resolve by auth_user_id only.
--
-- Reject → requestor remains deferred (pre-activation user has no in-app
-- surface during rejection; revisit if a pre-activation notification surface
-- is added).

CREATE OR REPLACE FUNCTION public.trg_account_request_approved_notify()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_profile_id uuid;
  v_auth_id    uuid;
  v_role       text;
BEGIN
  -- Only fire on a genuine pending → approved transition
  IF NEW.status::text <> 'approved' OR OLD.status::text = 'approved' THEN
    RETURN NEW;
  END IF;

  -- Resolve the requestor's profile — no is_active filter (see note above)
  SELECT up.id, up.auth_user_id, ro.role_name
    INTO v_profile_id, v_auth_id, v_role
    FROM public.users_profile up
    LEFT JOIN public.roles ro ON ro.id = up.role_id
   WHERE up.auth_user_id = NEW.auth_user_id
   LIMIT 1;

  IF v_auth_id IS NULL THEN RETURN NEW; END IF;

  PERFORM public.notify_user(
    v_auth_id,
    COALESCE(v_role, 'Viewer'),
    'Account Request Approved',
    'Your account request has been approved. You can now log in.',
    'account_request',
    'ACCOUNT_REQUEST_APPROVED',
    'account_request',
    COALESCE(v_profile_id, NEW.id)::text,
    '/account-requests/' || COALESCE(v_profile_id, NEW.id)::text,
    NULL
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_account_request_approved_notify ON public.account_requests;
CREATE TRIGGER trg_account_request_approved_notify
  AFTER UPDATE OF status ON public.account_requests
  FOR EACH ROW EXECUTE FUNCTION public.trg_account_request_approved_notify();


-- ============================================================
-- §6  Reliever Coverage  (workforce_assignment_requests) — GUARDED
-- ============================================================
-- The legacy escalation engine (20260518130000, _legacy_unversioned) already
-- defines submit/approve/reject notification triggers. To avoid duplicate
-- notifications we create a self-contained fallback ONLY when those triggers
-- are absent on the live DB. The fallback uses notify_user() directly so it
-- does not depend on the legacy helper functions.

CREATE OR REPLACE FUNCTION public.fn_rnw_reliever_submit()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_emp  text;
  v_link text := '/workforce/requests/' || NEW.id::text;
BEGIN
  SELECT full_name INTO v_emp FROM public.plantilla WHERE id = NEW.employee_id LIMIT 1;
  PERFORM public._rnw_notify_roles(
    ARRAY['Super Admin','Head Admin','Encoder'],
    'New Reliever Coverage Request',
    'A reliever coverage request was submitted for '
      || COALESCE(v_emp, 'a pool employee') || '. Review in the Request Queue.',
    'workforce_request', 'WF_REQUEST_SUBMITTED',
    'workforce_request', NEW.id::text, v_link
  );
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_rnw_reliever_decided()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_emp      text;
  v_link     text := '/workforce/requests/' || NEW.id::text;
  v_req_auth uuid;
  v_approved boolean := lower(NEW.status) = 'approved';
BEGIN
  v_req_auth := public._rnw_auth_uid(NEW.requested_by_id);
  IF v_req_auth IS NULL THEN RETURN NEW; END IF;
  SELECT full_name INTO v_emp FROM public.plantilla WHERE id = NEW.employee_id LIMIT 1;

  PERFORM public.notify_user(
    v_req_auth, 'ops',
    CASE WHEN v_approved THEN 'Coverage Request Approved'
         ELSE 'Coverage Request Rejected' END,
    CASE WHEN v_approved
         THEN 'Your reliever coverage request for ' || COALESCE(v_emp,'the pool employee') || ' was approved.'
         ELSE 'Your reliever coverage request for ' || COALESCE(v_emp,'the pool employee')
              || ' was rejected. Reason: ' || COALESCE(NEW.rejection_reason, 'No reason provided.') END,
    'workforce_request',
    CASE WHEN v_approved THEN 'WF_REQUEST_APPROVED' ELSE 'WF_REQUEST_REJECTED' END,
    'workforce_request', NEW.id::text, v_link, NULL
  );
  RETURN NEW;
END;
$$;

DO $reliever$
BEGIN
  -- Only wire fallback triggers if the legacy submit trigger is NOT present.
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname = 'trg_wf_request_submitted'
      AND tgrelid = 'public.workforce_assignment_requests'::regclass
  ) THEN
    DROP TRIGGER IF EXISTS trg_rnw_reliever_submit ON public.workforce_assignment_requests;
    CREATE TRIGGER trg_rnw_reliever_submit
      AFTER INSERT ON public.workforce_assignment_requests
      FOR EACH ROW EXECUTE FUNCTION public.fn_rnw_reliever_submit();

    DROP TRIGGER IF EXISTS trg_rnw_reliever_decided ON public.workforce_assignment_requests;
    CREATE TRIGGER trg_rnw_reliever_decided
      AFTER UPDATE OF status ON public.workforce_assignment_requests
      FOR EACH ROW
      WHEN (NEW.status IS DISTINCT FROM OLD.status
            AND lower(NEW.status) IN ('approved','rejected'))
      EXECUTE FUNCTION public.fn_rnw_reliever_decided();

    RAISE NOTICE 'ohm#reqfix01: reliever fallback notification triggers installed (legacy engine absent).';
  ELSE
    RAISE NOTICE 'ohm#reqfix01: legacy reliever notification triggers present — fallback skipped (no duplicates).';
  END IF;
EXCEPTION
  WHEN undefined_table THEN
    RAISE NOTICE 'ohm#reqfix01: workforce_assignment_requests not found — reliever wiring skipped.';
END;
$reliever$;


-- ============================================================
-- §7  Deactivation submit  (employee_deactivation_requests)
-- ============================================================
-- Approve/reject already notify the requestor (20260524116000). The only gap
-- is the SUBMIT → Backoffice approver notification. requestor_profile_id is a
-- users_profile.id.

CREATE OR REPLACE FUNCTION public.trg_deactivation_request_notify()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF NEW.status = 'Pending' THEN
    PERFORM public._rnw_notify_roles(
      ARRAY['Super Admin','Head Admin','Backoffice Personnel','Backoffice','Back Office'],
      'New Deactivation Request',
      'Deactivation requested for ' || COALESCE(NEW.employee_name, 'an employee')
        || COALESCE(' (' || NULLIF(NEW.employee_no, '') || ')', '')
        || ' at ' || COALESCE(NEW.account_name, 'account') || '.',
      'deactivation_request', 'DEACTIVATION_REQUEST_SUBMITTED',
      'deactivation_request', NEW.id::text,
      '/deactivation-requests/' || NEW.id::text
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_deactivation_request_notify_ins ON public.employee_deactivation_requests;
CREATE TRIGGER trg_deactivation_request_notify_ins
  AFTER INSERT ON public.employee_deactivation_requests
  FOR EACH ROW EXECUTE FUNCTION public.trg_deactivation_request_notify();


-- ============================================================
-- §8  Temporary Access revoke  (revoke_temp_permission_override)
-- ============================================================
-- Re-emit the RPC verbatim with a notify_user() call appended so the affected
-- user is told their temporary access was revoked. All existing revoke logic
-- (RBAC guard, scope cleanup, safety rules A/B) is preserved unchanged.

CREATE OR REPLACE FUNCTION public.revoke_temp_permission_override(
  p_override_id uuid,
  p_revoked_by  text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_target_user_id    uuid;
  v_additional_groups text[];
  v_override_created  timestamptz;
  v_group_name        text;
  v_group_id          uuid;
  v_covered_by_other  boolean;
  v_target_auth       uuid;
BEGIN
  -- Auth: only SA or HA may revoke
  IF NOT public.i_have_full_access() THEN
    RAISE EXCEPTION 'PERMISSION_DENIED: Only Super Admin or Head Admin can revoke permission overrides.';
  END IF;

  -- Fetch override (must exist and be active)
  SELECT user_id, additional_groups, created_at
    INTO v_target_user_id, v_additional_groups, v_override_created
    FROM public.temp_permission_overrides
   WHERE id = p_override_id
     AND is_active = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'NOT_FOUND: Override not found or already revoked.';
  END IF;

  -- Mark the override as revoked
  UPDATE public.temp_permission_overrides
     SET is_active   = false,
         revoked_at  = NOW(),
         revoked_by  = COALESCE(p_revoked_by, public.get_my_profile_id()::text)
   WHERE id = p_override_id;

  -- Remove temp-added user_scopes for each group in the override
  FOREACH v_group_name IN ARRAY v_additional_groups LOOP
    SELECT id INTO v_group_id
      FROM public.groups
     WHERE group_name = v_group_name
     LIMIT 1;

    CONTINUE WHEN v_group_id IS NULL;

    SELECT EXISTS (
      SELECT 1
        FROM public.temp_permission_overrides tpo
       WHERE tpo.user_id    = v_target_user_id
         AND tpo.id        != p_override_id
         AND tpo.is_active  = true
         AND tpo.expires_at > NOW()
         AND v_group_name   = ANY(tpo.additional_groups)
    ) INTO v_covered_by_other;

    CONTINUE WHEN v_covered_by_other;

    DELETE FROM public.user_scopes
     WHERE user_id   = v_target_user_id
       AND group_id  = v_group_id
       AND created_at >= v_override_created;
  END LOOP;

  -- ── ohm#reqfix01: notify the affected user of the revoke ──────────────
  v_target_auth := public._rnw_auth_uid(v_target_user_id);
  IF v_target_auth IS NOT NULL THEN
    PERFORM public.notify_user(
      v_target_auth, 'Encoder',
      'Temporary Access Revoked',
      'Your temporary access'
        || COALESCE(' to: ' || NULLIF(array_to_string(v_additional_groups, ', '), ''), '')
        || ' has been revoked.',
      'temp_permission', 'TEMP_ACCESS_REVOKED',
      'temp_permission', p_override_id::text,
      '/access-requests/' || p_override_id::text, NULL
    );
  END IF;
END;
$$;


-- ============================================================
-- SMOKE TESTS (run manually after applying — non-destructive)
-- ============================================================
-- S1. Helpers + triggers exist:
--   SELECT proname FROM pg_proc
--   WHERE proname IN ('_rnw_auth_uid','_rnw_notify_roles',
--     'trg_pool_request_notify','trg_hc_request_notify',
--     'trg_coverage_request_notify','trg_deactivation_request_notify')
--   ORDER BY proname;
--   SELECT tgname, tgrelid::regclass FROM pg_trigger
--   WHERE tgname LIKE 'trg_%request_notify%' OR tgname LIKE 'trg_rnw_%'
--   ORDER BY tgname;
--
-- S2. No duplicate reliever wiring (exactly one submit trigger source):
--   SELECT tgname FROM pg_trigger
--   WHERE tgrelid = 'public.workforce_assignment_requests'::regclass
--     AND tgname IN ('trg_wf_request_submitted','trg_rnw_reliever_submit');
--   -- Expect ONLY ONE of the two.
--
-- S3. Account submit notification now carries a deep link (after a test signup):
--   SELECT recipient_role, deep_link_route, reference_type
--   FROM public.notifications
--   WHERE notification_type = 'account_request'
--   ORDER BY created_at DESC LIMIT 4;
--   -- Expect two rows (Super Admin + Head Admin) with /account-requests/<id>.
--
-- S3b. Account approve trigger notifies requestor (after approve_account_request_v2):
--   SELECT recipient_role, event_type, deep_link_route
--   FROM public.notifications
--   WHERE notification_type = 'account_request'
--     AND event_type = 'ACCOUNT_REQUEST_APPROVED'
--   ORDER BY created_at DESC LIMIT 2;
--   -- Expect one row targeting the requestor with /account-requests/<profile_id>.
--
-- S4. Pool submit notifies Data Team (after an Ops create_pool_vacancy call):
--   SELECT recipient_role, title, deep_link_route FROM public.notifications
--   WHERE notification_type = 'workforce_pool_request'
--   ORDER BY created_at DESC LIMIT 5;
--
-- S5. Inactive users never notified:
--   -- Set a user is_active=false, trigger an event, confirm no row for them.
-- ============================================================
