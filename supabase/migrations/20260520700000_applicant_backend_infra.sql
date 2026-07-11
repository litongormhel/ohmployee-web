-- ============================================================
-- OHMployee — Migration: Applicant Status Master, Source
--   Channels, Rejected Reasons, Status History, and
--   Profile Correction Approval Backend
-- Prompt ID : OHM2026_2009
-- Date      : 2026-05-20
-- ============================================================
-- CRITICAL CONSTRAINTS (enforced by this migration):
--   1. ALL changes are ADDITIVE — zero existing tables/RPCs modified.
--   2. Vacancy module and all existing Vacancy RPCs remain untouched.
--   3. Existing VCODE generation logic is not touched.
--   4. Existing applicant duplicate-prevention indexes are not touched.
--   5. applicants.status column type/default/'New' unchanged.
--   6. Existing confirm_applicant_onboard / endorse_applicant_to_ops
--      RPCs unchanged — they continue to write their own status values.
--   7. No hard deletes on any table.
--   8. RLS + RBAC consistent with existing helper functions.
-- ============================================================

-- ============================================================
-- §0  HELPER: i_am_data_team()
--     Encoder (level 30) | Head Admin (90) | Super Admin (100)
--     Additive — CREATE OR REPLACE is safe.
-- ============================================================
CREATE OR REPLACE FUNCTION public.i_am_data_team()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.i_have_full_access()   -- Head Admin + Super Admin
      OR public.get_my_role_level() = 30; -- Encoder
$$;

-- ============================================================
-- §1  APPLICANT STATUS OPTIONS (master lookup)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.applicant_status_options (
  status_code     text        PRIMARY KEY,           -- machine key e.g. 'new', 'for_interview'
  label           text        NOT NULL UNIQUE,       -- display label; aligns with applicants.status values
  is_terminal     boolean     NOT NULL DEFAULT false,
  allow_on_create boolean     NOT NULL DEFAULT false, -- true only for 'new' / Add Applicant flow
  is_system_only  boolean     NOT NULL DEFAULT false, -- true for 'transferred' (set by backend only)
  color_key       text        CHECK (color_key IN ('primary','info','success','warning','danger','neutral')),
  sort_order      integer     NOT NULL DEFAULT 0,
  is_active       boolean     NOT NULL DEFAULT true,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.applicant_status_options IS
  'Master lookup for applicant workflow statuses. '
  'label matches values stored in applicants.status. '
  'New statuses use snake_case status_code; legacy DB values are also seeded for reference.';

ALTER TABLE public.applicant_status_options ENABLE ROW LEVEL SECURITY;

-- Seed: new statuses (from OHM2026_2009 spec)
INSERT INTO public.applicant_status_options
  (status_code, label, is_terminal, allow_on_create, is_system_only, color_key, sort_order)
VALUES
  ('new',              'New',              false, true,  false, 'info',    10),
  ('for_interview',    'For Interview',    false, false, false, 'primary', 20),
  ('for_requirements', 'For Requirements', false, false, false, 'warning', 30),
  ('for_onboard',      'For Onboard',      false, false, false, 'info',    40),
  ('backout',          'Backout',          true,  false, false, 'danger',  50),
  ('rejected',         'Rejected',         true,  false, false, 'danger',  60),
  ('transferred',      'Transferred',      true,  false, true,  'neutral', 70)
ON CONFLICT (status_code) DO NOTHING;

-- Seed: legacy status values currently stored in applicants.status
-- These are read-only reference rows (is_active=true so Flutter can look them up).
-- They reflect the existing system statuses that existing RPCs write.
INSERT INTO public.applicant_status_options
  (status_code, label, is_terminal, allow_on_create, is_system_only, color_key, sort_order)
VALUES
  ('endorsed',          'Endorsed to Ops',  false, false, true,  'info',    45),
  ('confirmed_onboard', 'Confirmed Onboard',false, false, true,  'success', 48),
  ('failed',            'Failed',           true,  false, false, 'danger',  80),
  ('did_not_report',    'Did Not Report',   true,  false, false, 'danger',  90),
  ('rejected_by_ops',   'Rejected by Ops',  true,  false, false, 'danger',  95)
ON CONFLICT (status_code) DO NOTHING;

-- Trigger to keep updated_at fresh
CREATE OR REPLACE FUNCTION public.trg_fn_status_options_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at := now(); RETURN NEW; END;
$$;

DROP TRIGGER IF EXISTS trg_status_options_updated_at ON public.applicant_status_options;
CREATE TRIGGER trg_status_options_updated_at
  BEFORE UPDATE ON public.applicant_status_options
  FOR EACH ROW EXECUTE FUNCTION public.trg_fn_status_options_updated_at();

-- ============================================================
-- §2  COMPATIBILITY VIEW: applicant_statuses
--     Resolves: "Flutter attempts to read public.applicant_statuses"
-- ============================================================
CREATE OR REPLACE VIEW public.applicant_statuses AS
  SELECT
    status_code,
    label,
    is_terminal,
    allow_on_create,
    is_system_only,
    color_key,
    sort_order,
    is_active
  FROM public.applicant_status_options
  WHERE is_active = true
  ORDER BY sort_order;

COMMENT ON VIEW public.applicant_statuses IS
  'Compatibility view over applicant_status_options. '
  'Flutter reads this view to resolve the missing public.applicant_statuses error.';

-- ============================================================
-- §3  APPLICANT SOURCE CHANNELS
-- ============================================================
CREATE TABLE IF NOT EXISTS public.applicant_source_channels (
  id         uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  label      text        NOT NULL UNIQUE,
  is_default boolean     NOT NULL DEFAULT false,
  sort_order integer     NOT NULL DEFAULT 0,
  is_active  boolean     NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.applicant_source_channels IS
  'Master lookup for applicant source channels. '
  'Walk-in is the default. Used to replace free-text source_channel field in UI.';

-- Only one default allowed at a time
CREATE UNIQUE INDEX IF NOT EXISTS applicant_source_channels_one_default
  ON public.applicant_source_channels (is_default)
  WHERE is_default = true;

ALTER TABLE public.applicant_source_channels ENABLE ROW LEVEL SECURITY;

INSERT INTO public.applicant_source_channels (label, is_default, sort_order)
VALUES
  ('Walk-in',          true,  10),
  ('Facebook',         false, 20),
  ('Referral',         false, 30),
  ('JobStreet',        false, 40),
  ('Indeed',           false, 50),
  ('TikTok',           false, 60),
  ('Employee Referral',false, 70),
  ('Others',           false, 80)
ON CONFLICT (label) DO NOTHING;

-- ============================================================
-- §4  REJECTED REASONS
--     NOTE: backout_reasons already exists — NOT recreated.
--     This table covers rejection reasons (interview/ops/general).
-- ============================================================
CREATE TABLE IF NOT EXISTS public.rejected_reasons (
  id         uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  reason     text        NOT NULL UNIQUE,
  is_active  boolean     NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.rejected_reasons IS
  'Rejection reason master for applicants. '
  'Separate from backout_reasons (which already exists). '
  'Used in applicant_status_history when reason_type = ''rejected''.';

ALTER TABLE public.rejected_reasons ENABLE ROW LEVEL SECURITY;

INSERT INTO public.rejected_reasons (reason)
VALUES
  ('Failed interview'),
  ('Incomplete requirements'),
  ('Not qualified'),
  ('No response'),
  ('Failed background check'),
  ('Position already filled'),
  ('Other')
ON CONFLICT (reason) DO NOTHING;

-- ============================================================
-- §5  APPLICANT STATUS HISTORY
--     Tracks every status transition for an applicant.
--     Designed to carry history through Vacancy → HR Emploc → Plantilla.
--     Immutable — no UPDATE, no hard DELETE.
-- ============================================================
CREATE TABLE IF NOT EXISTS public.applicant_status_history (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  applicant_id  uuid        NOT NULL REFERENCES public.applicants(id) ON DELETE CASCADE,
  from_status   text,                           -- NULL allowed for initial 'New' entry
  to_status     text        NOT NULL,
  reason_id     uuid,                           -- FK to backout_reasons OR rejected_reasons depending on reason_type
  reason_type   text        CHECK (reason_type IN ('backout', 'rejected', 'other')),
  remarks       text,
  changed_by    uuid        REFERENCES public.users_profile(id),
  changed_at    timestamptz NOT NULL DEFAULT now(),
  source_module text        NOT NULL DEFAULT 'vacancy'  -- vacancy | hr_emploc | plantilla
);

COMMENT ON TABLE public.applicant_status_history IS
  'Immutable audit trail of applicant status transitions. '
  'Carries history through Vacancy → HR Emploc → Plantilla via source_module. '
  'No UPDATE or DELETE allowed. reason_id is polymorphic: '
  'references backout_reasons when reason_type=backout, rejected_reasons when reason_type=rejected.';

CREATE INDEX IF NOT EXISTS idx_applicant_status_history_applicant_time
  ON public.applicant_status_history (applicant_id, changed_at DESC);

CREATE INDEX IF NOT EXISTS idx_applicant_status_history_module
  ON public.applicant_status_history (source_module, changed_at DESC);

ALTER TABLE public.applicant_status_history ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- §6  APPLICANT PROFILE EDIT REQUESTS
--     OPS + Recruitment → request correction of name/contact.
--     Encoder + Head Admin → approve/reject.
--     Super Admin → request, approve, or directly override.
-- ============================================================
CREATE TABLE IF NOT EXISTS public.applicant_profile_edit_requests (
  id                      uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  applicant_id            uuid        NOT NULL REFERENCES public.applicants(id) ON DELETE CASCADE,

  -- Requested new values (NULL = field not being changed in this request)
  new_first_name          text,
  new_middle_name         text,
  new_last_name           text,
  new_contact_number      text,

  -- Snapshot of existing values at time of request (for audit/display)
  snapshot_first_name     text,
  snapshot_middle_name    text,
  snapshot_last_name      text,
  snapshot_contact_number text,

  -- Request metadata
  reason                  text        NOT NULL,
  status                  text        NOT NULL DEFAULT 'Pending'
                          CHECK (status IN ('Pending', 'Approved', 'Rejected')),

  requested_by            uuid        NOT NULL REFERENCES public.users_profile(id),
  requested_by_role       text,
  requested_at            timestamptz NOT NULL DEFAULT now(),

  -- Review metadata
  reviewed_by             uuid        REFERENCES public.users_profile(id),
  reviewed_at             timestamptz,
  reviewer_remarks        text,

  -- Audit timestamps
  created_at              timestamptz NOT NULL DEFAULT now(),
  updated_at              timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.applicant_profile_edit_requests IS
  'Approval-based flow for correcting applicant name/contact fields. '
  'Requestors: Ops Team, Recruitment Team, Super Admin. '
  'Approvers: Encoder, Head Admin, Super Admin. '
  'Only one Pending request per applicant is allowed at a time.';

-- Block duplicate pending requests for the same applicant
CREATE UNIQUE INDEX IF NOT EXISTS applicant_profile_edit_requests_one_pending
  ON public.applicant_profile_edit_requests (applicant_id)
  WHERE status = 'Pending';

CREATE INDEX IF NOT EXISTS idx_applicant_profile_edit_requests_applicant
  ON public.applicant_profile_edit_requests (applicant_id, requested_at DESC);

CREATE INDEX IF NOT EXISTS idx_applicant_profile_edit_requests_status
  ON public.applicant_profile_edit_requests (status)
  WHERE status = 'Pending';

ALTER TABLE public.applicant_profile_edit_requests ENABLE ROW LEVEL SECURITY;

-- updated_at trigger
CREATE OR REPLACE FUNCTION public.trg_fn_profile_edit_request_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at := now(); RETURN NEW; END;
$$;

DROP TRIGGER IF EXISTS trg_profile_edit_request_updated_at ON public.applicant_profile_edit_requests;
CREATE TRIGGER trg_profile_edit_request_updated_at
  BEFORE UPDATE ON public.applicant_profile_edit_requests
  FOR EACH ROW EXECUTE FUNCTION public.trg_fn_profile_edit_request_updated_at();

-- ============================================================
-- §7  APPLICANT PROFILE CHANGE HISTORY
--     Immutable log of actual field changes applied to applicants.
--     Written on: approve_profile_edit, super_admin_update_profile.
-- ============================================================
CREATE TABLE IF NOT EXISTS public.applicant_profile_change_history (
  id             uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  applicant_id   uuid        NOT NULL REFERENCES public.applicants(id) ON DELETE CASCADE,
  request_id     uuid        REFERENCES public.applicant_profile_edit_requests(id),
  changed_fields jsonb       NOT NULL,  -- { "field_name": { "old": "val", "new": "val" } }
  changed_by     uuid        REFERENCES public.users_profile(id),
  approved_by    uuid        REFERENCES public.users_profile(id),
  reason         text,
  changed_at     timestamptz NOT NULL DEFAULT now(),
  source_module  text        NOT NULL DEFAULT 'vacancy'  -- vacancy | super_admin_override
);

COMMENT ON TABLE public.applicant_profile_change_history IS
  'Immutable audit log of field-level changes applied to applicant profiles. '
  'Each row records old/new values per changed field as jsonb. '
  'No UPDATE or DELETE allowed. request_id is NULL for Super Admin direct overrides.';

CREATE INDEX IF NOT EXISTS idx_applicant_profile_change_history_applicant
  ON public.applicant_profile_change_history (applicant_id, changed_at DESC);

ALTER TABLE public.applicant_profile_change_history ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- §8  RLS POLICIES
-- ============================================================

-- ── §8.1 applicant_status_options ───────────────────────────
-- Read-only master table. All authenticated users may read.
CREATE POLICY "aso_read_all"
  ON public.applicant_status_options
  FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "aso_delete_blocked"
  ON public.applicant_status_options
  FOR DELETE USING (false);

-- ── §8.2 applicant_source_channels ──────────────────────────
CREATE POLICY "asc_read_all"
  ON public.applicant_source_channels
  FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "asc_delete_blocked"
  ON public.applicant_source_channels
  FOR DELETE USING (false);

-- ── §8.3 rejected_reasons ────────────────────────────────────
CREATE POLICY "rr_read_all"
  ON public.rejected_reasons
  FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "rr_delete_blocked"
  ON public.rejected_reasons
  FOR DELETE USING (false);

-- ── §8.4 applicant_status_history ───────────────────────────
-- Read: full access OR scope-matched via vacancy account
CREATE POLICY "ash_read_scoped"
  ON public.applicant_status_history
  FOR SELECT TO authenticated
  USING (
    public.i_have_full_access()
    OR public.get_my_role_level() = 30  -- Encoder
    OR EXISTS (
      SELECT 1
      FROM public.applicants a
      JOIN public.vacancies  v ON v.vcode = a.vacancy_vcode
      WHERE a.id = applicant_status_history.applicant_id
        AND v.account = ANY(public.get_my_allowed_accounts())
        AND v.deleted_at IS NULL
    )
  );

-- Insert: authenticated users can write history (RPCs validate RBAC before calling)
CREATE POLICY "ash_insert_authenticated"
  ON public.applicant_status_history
  FOR INSERT TO authenticated
  WITH CHECK (true);

CREATE POLICY "ash_update_blocked"
  ON public.applicant_status_history
  FOR UPDATE USING (false);

CREATE POLICY "ash_delete_blocked"
  ON public.applicant_status_history
  FOR DELETE USING (false);

-- ── §8.5 applicant_profile_edit_requests ────────────────────
CREATE POLICY "aper_read_scoped"
  ON public.applicant_profile_edit_requests
  FOR SELECT TO authenticated
  USING (
    public.i_have_full_access()
    OR public.get_my_role_level() = 30  -- Encoder
    OR requested_by = public.get_my_profile_id()
    OR EXISTS (
      SELECT 1
      FROM public.applicants a
      JOIN public.vacancies  v ON v.vcode = a.vacancy_vcode
      WHERE a.id = applicant_profile_edit_requests.applicant_id
        AND v.account = ANY(public.get_my_allowed_accounts())
    )
  );

CREATE POLICY "aper_delete_blocked"
  ON public.applicant_profile_edit_requests
  FOR DELETE USING (false);

-- ── §8.6 applicant_profile_change_history ───────────────────
CREATE POLICY "apch_read_scoped"
  ON public.applicant_profile_change_history
  FOR SELECT TO authenticated
  USING (
    public.i_have_full_access()
    OR public.get_my_role_level() = 30  -- Encoder
    OR EXISTS (
      SELECT 1
      FROM public.applicants a
      JOIN public.vacancies  v ON v.vcode = a.vacancy_vcode
      WHERE a.id = applicant_profile_change_history.applicant_id
        AND v.account = ANY(public.get_my_allowed_accounts())
    )
  );

CREATE POLICY "apch_delete_blocked"
  ON public.applicant_profile_change_history
  FOR DELETE USING (false);

-- ============================================================
-- §9  GRANTS
--     Pattern: full grant to authenticated + service_role,
--     then RLS restricts. Consistent with existing schema.
-- ============================================================

-- applicant_status_options
GRANT SELECT, INSERT, UPDATE, REFERENCES, TRIGGER, TRUNCATE
  ON public.applicant_status_options TO authenticated;
GRANT ALL ON public.applicant_status_options TO service_role;

-- applicant_statuses (view)
GRANT SELECT ON public.applicant_statuses TO authenticated, service_role;

-- applicant_source_channels
GRANT SELECT, INSERT, UPDATE, REFERENCES, TRIGGER, TRUNCATE
  ON public.applicant_source_channels TO authenticated;
GRANT ALL ON public.applicant_source_channels TO service_role;

-- rejected_reasons
GRANT SELECT, INSERT, UPDATE, REFERENCES, TRIGGER, TRUNCATE
  ON public.rejected_reasons TO authenticated;
GRANT ALL ON public.rejected_reasons TO service_role;

-- applicant_status_history
GRANT SELECT, INSERT, UPDATE, DELETE, REFERENCES, TRIGGER, TRUNCATE
  ON public.applicant_status_history TO authenticated;
GRANT ALL ON public.applicant_status_history TO service_role;

-- applicant_profile_edit_requests
GRANT SELECT, INSERT, UPDATE, DELETE, REFERENCES, TRIGGER, TRUNCATE
  ON public.applicant_profile_edit_requests TO authenticated;
GRANT ALL ON public.applicant_profile_edit_requests TO service_role;

-- applicant_profile_change_history
GRANT SELECT, INSERT, UPDATE, DELETE, REFERENCES, TRIGGER, TRUNCATE
  ON public.applicant_profile_change_history TO authenticated;
GRANT ALL ON public.applicant_profile_change_history TO service_role;

-- ============================================================
-- §10  RPCs
--      All: SECURITY DEFINER, SET search_path = public.
--      All mutations call get_my_profile_id() for actor tracking.
-- ============================================================

-- ── §10.1  fn_get_applicant_status_options ──────────────────
CREATE OR REPLACE FUNCTION public.fn_get_applicant_status_options(
  p_include_inactive boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN (
    SELECT COALESCE(jsonb_agg(
      jsonb_build_object(
        'status_code',     s.status_code,
        'label',           s.label,
        'is_terminal',     s.is_terminal,
        'allow_on_create', s.allow_on_create,
        'is_system_only',  s.is_system_only,
        'color_key',       s.color_key,
        'sort_order',      s.sort_order,
        'is_active',       s.is_active
      ) ORDER BY s.sort_order
    ), '[]'::jsonb)
    FROM public.applicant_status_options s
    WHERE (p_include_inactive OR s.is_active = true)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_get_applicant_status_options(boolean)
  TO authenticated, service_role;

-- ── §10.2  fn_get_applicant_source_channels ─────────────────
CREATE OR REPLACE FUNCTION public.fn_get_applicant_source_channels(
  p_include_inactive boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN (
    SELECT COALESCE(jsonb_agg(
      jsonb_build_object(
        'id',         c.id,
        'label',      c.label,
        'is_default', c.is_default,
        'sort_order', c.sort_order,
        'is_active',  c.is_active
      ) ORDER BY c.sort_order
    ), '[]'::jsonb)
    FROM public.applicant_source_channels c
    WHERE (p_include_inactive OR c.is_active = true)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_get_applicant_source_channels(boolean)
  TO authenticated, service_role;

-- ── §10.3  fn_request_applicant_profile_edit ────────────────
-- Requestors: Ops Team (40–70), Recruitment Team (20), Super Admin (100).
-- Encoder (30) and Head Admin (90) are APPROVERS — not requestors.
-- One pending request per applicant at a time (enforced by unique index).
CREATE OR REPLACE FUNCTION public.fn_request_applicant_profile_edit(
  p_applicant_id       uuid,
  p_reason             text,
  p_new_first_name     text DEFAULT NULL,
  p_new_middle_name    text DEFAULT NULL,
  p_new_last_name      text DEFAULT NULL,
  p_new_contact_number text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_level      int  := COALESCE(public.get_my_role_level(), 0);
  v_profile_id uuid := public.get_my_profile_id();
  v_role       text := public.get_my_role();
  v_app        public.applicants%ROWTYPE;
  v_req_id     uuid;
BEGIN
  -- RBAC: Ops (40–70) | Recruitment (20) | Super Admin (100)
  -- Encoder (30) + Head Admin (90) must NOT request — they approve.
  IF NOT (
    public.i_am_ops()           -- 40–70
    OR public.i_am_recruitment() -- 20
    OR v_level = 100             -- Super Admin
  ) THEN
    RAISE EXCEPTION 'forbidden: Ops Team, Recruitment Team, or Super Admin required to request profile corrections'
      USING ERRCODE = '42501';
  END IF;

  -- Require at least one field
  IF p_new_first_name     IS NULL
     AND p_new_middle_name   IS NULL
     AND p_new_last_name     IS NULL
     AND p_new_contact_number IS NULL THEN
    RAISE EXCEPTION 'at least one field (first_name, middle_name, last_name, contact_number) must be specified'
      USING ERRCODE = '22023';
  END IF;

  -- Require reason
  IF TRIM(COALESCE(p_reason, '')) = '' THEN
    RAISE EXCEPTION 'reason is required for profile edit requests'
      USING ERRCODE = '22023';
  END IF;

  -- Fetch applicant
  SELECT * INTO v_app
    FROM public.applicants
   WHERE id = p_applicant_id
     AND COALESCE(is_archived, false) = false;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'applicant % not found or archived', p_applicant_id
      USING ERRCODE = 'P0002';
  END IF;

  -- Scope check (skip for full-access)
  IF NOT public.i_have_full_access() THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.vacancies v
      WHERE v.vcode = v_app.vacancy_vcode
        AND v.account = ANY(public.get_my_allowed_accounts())
        AND v.deleted_at IS NULL
    ) THEN
      RAISE EXCEPTION 'forbidden: applicant is outside your account scope'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  -- Block if a pending request already exists (unique index also enforces this)
  IF EXISTS (
    SELECT 1 FROM public.applicant_profile_edit_requests
    WHERE applicant_id = p_applicant_id AND status = 'Pending'
  ) THEN
    RAISE EXCEPTION 'a pending profile edit request already exists for this applicant — resolve it before creating another'
      USING ERRCODE = '23505';
  END IF;

  -- Create request with current field snapshot
  INSERT INTO public.applicant_profile_edit_requests (
    applicant_id,
    reason,
    status,
    new_first_name,
    new_middle_name,
    new_last_name,
    new_contact_number,
    snapshot_first_name,
    snapshot_middle_name,
    snapshot_last_name,
    snapshot_contact_number,
    requested_by,
    requested_by_role,
    requested_at
  ) VALUES (
    p_applicant_id,
    p_reason,
    'Pending',
    p_new_first_name,
    p_new_middle_name,
    p_new_last_name,
    p_new_contact_number,
    v_app.first_name,
    v_app.middle_name,
    v_app.last_name,
    v_app.contact_number,
    v_profile_id,
    v_role,
    NOW()
  )
  RETURNING id INTO v_req_id;

  RETURN v_req_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_request_applicant_profile_edit(uuid, text, text, text, text, text)
  TO authenticated;

-- ── §10.4  fn_approve_applicant_profile_edit_request ────────
-- Approvers: Encoder (30) | Head Admin (90) | Super Admin (100).
-- On approval: applies field changes to applicants row and logs to change history.
CREATE OR REPLACE FUNCTION public.fn_approve_applicant_profile_edit_request(
  p_request_id uuid,
  p_remarks    text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_level      int  := COALESCE(public.get_my_role_level(), 0);
  v_profile_id uuid := public.get_my_profile_id();
  v_req        public.applicant_profile_edit_requests%ROWTYPE;
  v_app        public.applicants%ROWTYPE;
  v_changed    jsonb := '{}';
  -- computed new full_name parts (resolved after applying overrides)
  v_new_last   text;
  v_new_first  text;
  v_new_middle text;
BEGIN
  -- RBAC: Encoder | Head Admin | Super Admin
  IF NOT (
    v_level IN (30, 90, 100)
    OR public.i_have_full_access()
  ) THEN
    RAISE EXCEPTION 'forbidden: Encoder, Head Admin, or Super Admin required to approve profile corrections'
      USING ERRCODE = '42501';
  END IF;

  -- Fetch and lock request
  SELECT * INTO v_req
    FROM public.applicant_profile_edit_requests
   WHERE id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'profile edit request % not found', p_request_id
      USING ERRCODE = 'P0002';
  END IF;

  IF v_req.status != 'Pending' THEN
    RAISE EXCEPTION 'request is not Pending (current status: %)', v_req.status
      USING ERRCODE = '22023';
  END IF;

  -- Fetch current applicant values
  SELECT * INTO v_app FROM public.applicants WHERE id = v_req.applicant_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'applicant % not found', v_req.applicant_id
      USING ERRCODE = 'P0002';
  END IF;

  -- Scope check for Encoder (not full-access)
  IF NOT public.i_have_full_access() THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.vacancies v
      WHERE v.vcode = v_app.vacancy_vcode
        AND v.account = ANY(public.get_my_allowed_accounts())
    ) THEN
      RAISE EXCEPTION 'forbidden: applicant is outside your account scope'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  -- Build changed_fields audit payload
  IF v_req.new_last_name IS NOT NULL
     AND v_req.new_last_name IS DISTINCT FROM v_app.last_name THEN
    v_changed := v_changed || jsonb_build_object('last_name',
      jsonb_build_object('old', v_app.last_name, 'new', v_req.new_last_name));
  END IF;
  IF v_req.new_first_name IS NOT NULL
     AND v_req.new_first_name IS DISTINCT FROM v_app.first_name THEN
    v_changed := v_changed || jsonb_build_object('first_name',
      jsonb_build_object('old', v_app.first_name, 'new', v_req.new_first_name));
  END IF;
  IF v_req.new_middle_name IS NOT NULL
     AND v_req.new_middle_name IS DISTINCT FROM v_app.middle_name THEN
    v_changed := v_changed || jsonb_build_object('middle_name',
      jsonb_build_object('old', v_app.middle_name, 'new', v_req.new_middle_name));
  END IF;
  IF v_req.new_contact_number IS NOT NULL
     AND v_req.new_contact_number IS DISTINCT FROM v_app.contact_number THEN
    v_changed := v_changed || jsonb_build_object('contact_number',
      jsonb_build_object('old', v_app.contact_number, 'new', v_req.new_contact_number));
  END IF;

  -- Resolve final name parts (for full_name rebuild)
  v_new_last   := COALESCE(v_req.new_last_name,   v_app.last_name);
  v_new_first  := COALESCE(v_req.new_first_name,  v_app.first_name);
  v_new_middle := COALESCE(v_req.new_middle_name, v_app.middle_name);

  -- Apply field changes to applicant record
  UPDATE public.applicants
  SET
    last_name      = COALESCE(v_req.new_last_name,      last_name),
    first_name     = COALESCE(v_req.new_first_name,     first_name),
    middle_name    = COALESCE(v_req.new_middle_name,    middle_name),
    contact_number = COALESCE(v_req.new_contact_number, contact_number),
    full_name      = TRIM(
                       v_new_last || ', ' || v_new_first
                       || CASE WHEN v_new_middle IS NOT NULL
                               THEN ' ' || v_new_middle
                               ELSE '' END
                     ),
    updated_at     = NOW(),
    updated_by     = v_profile_id
  WHERE id = v_req.applicant_id;

  -- Mark request Approved
  UPDATE public.applicant_profile_edit_requests
  SET
    status           = 'Approved',
    reviewed_by      = v_profile_id,
    reviewed_at      = NOW(),
    reviewer_remarks = p_remarks,
    updated_at       = NOW()
  WHERE id = p_request_id;

  -- Write immutable change history
  IF v_changed != '{}' THEN
    INSERT INTO public.applicant_profile_change_history (
      applicant_id,
      request_id,
      changed_fields,
      changed_by,
      approved_by,
      reason,
      changed_at,
      source_module
    ) VALUES (
      v_req.applicant_id,
      p_request_id,
      v_changed,
      v_req.requested_by,
      v_profile_id,
      v_req.reason,
      NOW(),
      'vacancy'
    );
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_approve_applicant_profile_edit_request(uuid, text)
  TO authenticated;

-- ── §10.5  fn_reject_applicant_profile_edit_request ─────────
-- Approvers: Encoder (30) | Head Admin (90) | Super Admin (100).
-- Rejection remarks are REQUIRED.
CREATE OR REPLACE FUNCTION public.fn_reject_applicant_profile_edit_request(
  p_request_id uuid,
  p_remarks    text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_level      int  := COALESCE(public.get_my_role_level(), 0);
  v_profile_id uuid := public.get_my_profile_id();
  v_req        public.applicant_profile_edit_requests%ROWTYPE;
BEGIN
  -- RBAC: Encoder | Head Admin | Super Admin
  IF NOT (
    v_level IN (30, 90, 100)
    OR public.i_have_full_access()
  ) THEN
    RAISE EXCEPTION 'forbidden: Encoder, Head Admin, or Super Admin required to reject profile corrections'
      USING ERRCODE = '42501';
  END IF;

  -- Rejection remarks required
  IF TRIM(COALESCE(p_remarks, '')) = '' THEN
    RAISE EXCEPTION 'reviewer_remarks is required when rejecting a profile edit request'
      USING ERRCODE = '22023';
  END IF;

  -- Fetch and lock request
  SELECT * INTO v_req
    FROM public.applicant_profile_edit_requests
   WHERE id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'profile edit request % not found', p_request_id
      USING ERRCODE = 'P0002';
  END IF;

  IF v_req.status != 'Pending' THEN
    RAISE EXCEPTION 'request is not Pending (current status: %)', v_req.status
      USING ERRCODE = '22023';
  END IF;

  -- Scope check for Encoder
  IF NOT public.i_have_full_access() THEN
    IF NOT EXISTS (
      SELECT 1
      FROM public.applicants a
      JOIN public.vacancies  v ON v.vcode = a.vacancy_vcode
      WHERE a.id = v_req.applicant_id
        AND v.account = ANY(public.get_my_allowed_accounts())
    ) THEN
      RAISE EXCEPTION 'forbidden: applicant is outside your account scope'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  -- Mark request Rejected
  UPDATE public.applicant_profile_edit_requests
  SET
    status           = 'Rejected',
    reviewed_by      = v_profile_id,
    reviewed_at      = NOW(),
    reviewer_remarks = p_remarks,
    updated_at       = NOW()
  WHERE id = p_request_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_reject_applicant_profile_edit_request(uuid, text)
  TO authenticated;

-- ── §10.6  fn_super_admin_update_applicant_profile ──────────
-- Super Admin ONLY direct override. No approval workflow.
-- Writes directly to applicants and logs to change history.
CREATE OR REPLACE FUNCTION public.fn_super_admin_update_applicant_profile(
  p_applicant_id       uuid,
  p_reason             text,
  p_new_first_name     text DEFAULT NULL,
  p_new_middle_name    text DEFAULT NULL,
  p_new_last_name      text DEFAULT NULL,
  p_new_contact_number text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_profile_id uuid := public.get_my_profile_id();
  v_app        public.applicants%ROWTYPE;
  v_changed    jsonb := '{}';
  v_new_last   text;
  v_new_first  text;
  v_new_middle text;
BEGIN
  -- Super Admin ONLY
  IF public.get_my_role_level() != 100 THEN
    RAISE EXCEPTION 'forbidden: Super Admin only for direct profile overrides'
      USING ERRCODE = '42501';
  END IF;

  IF TRIM(COALESCE(p_reason, '')) = '' THEN
    RAISE EXCEPTION 'reason is required for a Super Admin direct profile override'
      USING ERRCODE = '22023';
  END IF;

  IF p_new_first_name      IS NULL
     AND p_new_middle_name  IS NULL
     AND p_new_last_name    IS NULL
     AND p_new_contact_number IS NULL THEN
    RAISE EXCEPTION 'at least one field must be specified for the override'
      USING ERRCODE = '22023';
  END IF;

  -- Fetch applicant (super admin can access any)
  SELECT * INTO v_app FROM public.applicants WHERE id = p_applicant_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'applicant % not found', p_applicant_id
      USING ERRCODE = 'P0002';
  END IF;

  -- Build audit payload
  IF p_new_last_name IS NOT NULL
     AND p_new_last_name IS DISTINCT FROM v_app.last_name THEN
    v_changed := v_changed || jsonb_build_object('last_name',
      jsonb_build_object('old', v_app.last_name, 'new', p_new_last_name));
  END IF;
  IF p_new_first_name IS NOT NULL
     AND p_new_first_name IS DISTINCT FROM v_app.first_name THEN
    v_changed := v_changed || jsonb_build_object('first_name',
      jsonb_build_object('old', v_app.first_name, 'new', p_new_first_name));
  END IF;
  IF p_new_middle_name IS NOT NULL
     AND p_new_middle_name IS DISTINCT FROM v_app.middle_name THEN
    v_changed := v_changed || jsonb_build_object('middle_name',
      jsonb_build_object('old', v_app.middle_name, 'new', p_new_middle_name));
  END IF;
  IF p_new_contact_number IS NOT NULL
     AND p_new_contact_number IS DISTINCT FROM v_app.contact_number THEN
    v_changed := v_changed || jsonb_build_object('contact_number',
      jsonb_build_object('old', v_app.contact_number, 'new', p_new_contact_number));
  END IF;

  -- Resolve final name parts
  v_new_last   := COALESCE(p_new_last_name,   v_app.last_name);
  v_new_first  := COALESCE(p_new_first_name,  v_app.first_name);
  v_new_middle := COALESCE(p_new_middle_name, v_app.middle_name);

  -- Apply override directly (no approval required for Super Admin)
  UPDATE public.applicants
  SET
    last_name      = COALESCE(p_new_last_name,      last_name),
    first_name     = COALESCE(p_new_first_name,     first_name),
    middle_name    = COALESCE(p_new_middle_name,    middle_name),
    contact_number = COALESCE(p_new_contact_number, contact_number),
    full_name      = TRIM(
                       v_new_last || ', ' || v_new_first
                       || CASE WHEN v_new_middle IS NOT NULL
                               THEN ' ' || v_new_middle
                               ELSE '' END
                     ),
    updated_at     = NOW(),
    updated_by     = v_profile_id
  WHERE id = p_applicant_id;

  -- Write immutable change history (no request_id for direct overrides)
  IF v_changed != '{}' THEN
    INSERT INTO public.applicant_profile_change_history (
      applicant_id,
      request_id,
      changed_fields,
      changed_by,
      approved_by,
      reason,
      changed_at,
      source_module
    ) VALUES (
      p_applicant_id,
      NULL,
      v_changed,
      v_profile_id,
      v_profile_id,
      p_reason,
      NOW(),
      'super_admin_override'
    );
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_super_admin_update_applicant_profile(uuid, text, text, text, text, text)
  TO authenticated;

-- ── §10.7  fn_update_applicant_status ───────────────────────
-- Centralized, validated status transition for the NEW status flow.
-- Uses status_code from applicant_status_options.
-- Does NOT replace confirm_applicant_onboard / endorse_applicant_to_ops —
-- those existing RPCs remain unchanged and continue to write their own
-- status values (legacy flow). This RPC is for the NEW UI flow.
--
-- Status transition map (from status_code → allowed to status_codes):
--   new              → for_interview | rejected
--   for_interview    → for_requirements | rejected
--   for_requirements → for_onboard | backout | rejected
--   for_onboard      → transferred
--   Terminal statuses (backout/rejected/transferred): only Super Admin may override.
CREATE OR REPLACE FUNCTION public.fn_update_applicant_status(
  p_applicant_id uuid,
  p_new_status   text,      -- status_code from applicant_status_options
  p_remarks      text DEFAULT NULL,
  p_reason_id    uuid DEFAULT NULL,     -- FK to backout_reasons or rejected_reasons
  p_reason_type  text DEFAULT NULL      -- 'backout' | 'rejected' | 'other'
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_level      int  := COALESCE(public.get_my_role_level(), 0);
  v_profile_id uuid := public.get_my_profile_id();
  v_app        public.applicants%ROWTYPE;
  v_to_opt     public.applicant_status_options%ROWTYPE;
  v_from_code  text;
  v_old_status text;
  v_allowed    text[];

  -- Valid transitions by from_status_code
  -- Defined as a static mapping; only Super Admin bypasses for terminal statuses.
  c_transitions CONSTANT jsonb := '{
    "new":              ["for_interview","rejected"],
    "for_interview":    ["for_requirements","rejected"],
    "for_requirements": ["for_onboard","backout","rejected"],
    "for_onboard":      ["transferred"]
  }';
BEGIN
  -- Require an authenticated user with a recognized role
  IF v_level = 0 THEN
    RAISE EXCEPTION 'forbidden: authenticated user with a recognized role required'
      USING ERRCODE = '42501';
  END IF;

  -- Validate p_reason_type
  IF p_reason_type IS NOT NULL
     AND p_reason_type NOT IN ('backout', 'rejected', 'other') THEN
    RAISE EXCEPTION 'invalid reason_type: %. Must be backout | rejected | other', p_reason_type
      USING ERRCODE = '22023';
  END IF;

  -- Resolve target status option
  SELECT * INTO v_to_opt
    FROM public.applicant_status_options
   WHERE status_code = p_new_status
     AND is_active = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'invalid or inactive status_code: %', p_new_status
      USING ERRCODE = '22023';
  END IF;

  -- Block system-only statuses for non-Super Admin
  IF v_to_opt.is_system_only AND v_level != 100 THEN
    RAISE EXCEPTION 'status % is system-only and cannot be set manually', p_new_status
      USING ERRCODE = '42501';
  END IF;

  -- Fetch and lock applicant
  SELECT * INTO v_app
    FROM public.applicants
   WHERE id = p_applicant_id
     AND COALESCE(is_archived, false) = false
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'applicant % not found or archived', p_applicant_id
      USING ERRCODE = 'P0002';
  END IF;

  v_old_status := COALESCE(v_app.status, 'New');

  -- Map current stored label → status_code (for transition check)
  -- If no mapping found (legacy label), treat as 'new' for transition purposes.
  SELECT status_code INTO v_from_code
    FROM public.applicant_status_options
   WHERE label = v_old_status
  LIMIT 1;

  IF v_from_code IS NULL THEN
    v_from_code := 'new';
  END IF;

  -- Terminal guard: only Super Admin can move FROM a terminal status
  IF (
    SELECT is_terminal FROM public.applicant_status_options WHERE status_code = v_from_code
  ) THEN
    IF v_level != 100 THEN
      RAISE EXCEPTION 'cannot transition from terminal status "%" without Super Admin authority', v_old_status
        USING ERRCODE = '22023';
    END IF;
    -- Super Admin override — skip transition validation
  ELSE
    -- Validate forward transition
    SELECT ARRAY(
      SELECT jsonb_array_elements_text(c_transitions->v_from_code)
    ) INTO v_allowed;

    IF v_allowed IS NULL OR array_length(v_allowed, 1) = 0 THEN
      RAISE EXCEPTION 'no valid transitions defined from status_code "%"', v_from_code
        USING ERRCODE = '22023';
    END IF;

    IF NOT (p_new_status = ANY(v_allowed)) THEN
      RAISE EXCEPTION 'invalid transition: "%" → "%" is not allowed. Allowed: %',
        v_from_code, p_new_status, array_to_string(v_allowed, ', ')
        USING ERRCODE = '22023';
    END IF;
  END IF;

  -- Scope check (skip for full-access)
  IF NOT public.i_have_full_access() THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.vacancies v
      WHERE v.vcode = v_app.vacancy_vcode
        AND v.account = ANY(public.get_my_allowed_accounts())
        AND v.deleted_at IS NULL
    ) THEN
      RAISE EXCEPTION 'forbidden: applicant is outside your account scope'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  -- Apply status update (write the label value into applicants.status)
  UPDATE public.applicants
  SET
    status     = v_to_opt.label,
    updated_at = NOW(),
    updated_by = v_profile_id
  WHERE id = p_applicant_id;

  -- Write status history row
  INSERT INTO public.applicant_status_history (
    applicant_id,
    from_status,
    to_status,
    reason_id,
    reason_type,
    remarks,
    changed_by,
    changed_at,
    source_module
  ) VALUES (
    p_applicant_id,
    v_old_status,
    v_to_opt.label,
    p_reason_id,
    p_reason_type,
    p_remarks,
    v_profile_id,
    NOW(),
    'vacancy'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_update_applicant_status(uuid, text, text, uuid, text)
  TO authenticated;

-- ============================================================
-- §11  PIPELINE CLASSIFICATION VIEW (additive)
--      Open   = vacancy has no active applicant
--      Pipeline = vacancy has ≥1 active applicant
--
--      Active statuses include both new and legacy labels.
--      This view DOES NOT break existing vacancy list queries.
--      It is purely additive — no existing views touched.
-- ============================================================
CREATE OR REPLACE VIEW public.v_vacancy_pipeline_status
WITH (security_invoker = true)
AS
SELECT
  v.id                                    AS vacancy_id,
  v.vcode,
  v.account,
  v.status                                AS vacancy_status,
  COUNT(a.id)                             AS active_applicant_count,
  CASE
    WHEN COUNT(a.id) > 0 THEN 'Pipeline'
    ELSE 'Open'
  END                                     AS pipeline_classification
FROM public.vacancies v
LEFT JOIN public.applicants a
  ON  a.vacancy_vcode        = v.vcode
  AND COALESCE(a.is_archived, false) = false
  AND a.status IN (
    -- New status labels (OHM2026_2009)
    'New', 'For Interview', 'For Requirements', 'For Onboard',
    -- Legacy status labels (existing RPC output)
    'Endorsed to Ops', 'Endorsed', 'Confirmed Onboard'
  )
WHERE v.deleted_at    IS NULL
  AND COALESCE(v.is_archived, false) = false
GROUP BY v.id, v.vcode, v.account, v.status;

COMMENT ON VIEW public.v_vacancy_pipeline_status IS
  'Additive view. Classifies each active vacancy as Pipeline (has ≥1 active applicant) '
  'or Open (no active applicant). Covers both new and legacy applicant status labels. '
  'Does not replace or modify any existing vacancy list views or RPCs.';

GRANT SELECT ON public.v_vacancy_pipeline_status TO authenticated, service_role;

-- ============================================================
-- §12  RELIEVER / COMMANDO VISIBILITY SHAPE (read-only)
--      Backend shape only — no new assignment workflow.
--      Reads existing vacancy_coverage table which already tracks
--      Reliever/Commando coverage per vacancy.
--      No new tables created. No existing tables modified.
-- ============================================================
CREATE OR REPLACE VIEW public.v_vacancy_active_coverage
WITH (security_invoker = true)
AS
SELECT
  vc.id,
  vc.vacancy_id,
  v.vcode,
  v.account,
  v.status          AS vacancy_status,
  vc.coverage_type,            -- 'Reliever' | 'Commando' (enum vacancy_coverage_type)
  vc.status       AS coverage_status, -- 'Active' (enum vacancy_coverage_status)
  vc.notes        AS coverage_notes,
  vc.applicant_id,
  vc.covered_from,
  vc.covered_until,
  vc.archived_at,
  vc.created_at
FROM public.vacancy_coverage vc
JOIN public.vacancies         v ON v.id = vc.vacancy_id
WHERE vc.status     = 'Active'::public.vacancy_coverage_status
  AND vc.archived_at IS NULL
  AND v.deleted_at  IS NULL
  AND COALESCE(v.is_archived, false) = false;

COMMENT ON VIEW public.v_vacancy_active_coverage IS
  'Read-only view of active Reliever/Commando coverage records. '
  'Sourced from existing vacancy_coverage table. '
  'No new tables or assignment workflows created. '
  'Visible regardless of vacancy Pipeline/Open status.';

GRANT SELECT ON public.v_vacancy_active_coverage TO authenticated, service_role;

-- ============================================================
-- §13  VALIDATION CHECKS (run after migration to verify)
-- ============================================================
-- These are NOT executable migration steps — they are reference
-- queries to run manually in Supabase SQL Editor after push.
--
-- V1: Verify all 7 new tables/views exist
-- SELECT table_name FROM information_schema.tables
--   WHERE table_schema = 'public'
--     AND table_name IN (
--       'applicant_status_options','applicant_source_channels',
--       'rejected_reasons','applicant_status_history',
--       'applicant_profile_edit_requests','applicant_profile_change_history'
--     );
-- Expected: 6 rows
--
-- V2: Verify seed counts
-- SELECT (SELECT COUNT(*) FROM public.applicant_status_options)   AS status_options,
--        (SELECT COUNT(*) FROM public.applicant_source_channels)  AS source_channels,
--        (SELECT COUNT(*) FROM public.rejected_reasons)           AS rejected_reasons;
-- Expected: 12, 8, 7
--
-- V3: Verify compatibility view resolves
-- SELECT status_code, label FROM public.applicant_statuses ORDER BY sort_order;
-- Expected: rows returned (no error — resolves the Flutter applicant_statuses error)
--
-- V4: Verify allow_on_create constraint (only 'new' = true)
-- SELECT status_code FROM public.applicant_status_options WHERE allow_on_create = true;
-- Expected: 1 row → 'new'
--
-- V5: Verify terminal + system-only statuses
-- SELECT status_code, is_terminal, is_system_only
--   FROM public.applicant_status_options
--   WHERE is_terminal = true OR is_system_only = true
--   ORDER BY sort_order;
-- Expected: backout/rejected/transferred=terminal; transferred/endorsed/confirmed_onboard=system_only
--
-- V6: Verify RPC executability
-- SELECT public.fn_get_applicant_status_options();
-- SELECT public.fn_get_applicant_source_channels();
-- Expected: JSON arrays returned, no errors
--
-- V7: Verify existing vacancy RPCs still compile
-- \df confirm_applicant_onboard
-- \df endorse_applicant_to_ops
-- Expected: still present, signatures unchanged
--
-- V8: Verify one-pending-per-applicant index exists
-- SELECT indexname FROM pg_indexes
--   WHERE tablename = 'applicant_profile_edit_requests'
--     AND indexname = 'applicant_profile_edit_requests_one_pending';
-- Expected: 1 row
--
-- V9: Verify pipeline view
-- SELECT pipeline_classification, COUNT(*) FROM public.v_vacancy_pipeline_status
--   GROUP BY pipeline_classification;
-- Expected: Open and/or Pipeline rows (depends on data state)
-- ============================================================
