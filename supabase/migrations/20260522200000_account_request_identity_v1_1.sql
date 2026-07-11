-- ============================================================
-- OHM2026_2010 — Request Account v1.1 Identity Foundation
-- ============================================================
-- Adds separated name fields, mobile number, full_name_search,
-- and directory_status to account_requests + users_profile.
-- Adds fn_enrich_account_request RPC for post-signup identity
-- enrichment with scope request and role-scoped validation.
-- Updates approve_account_request_v2 to propagate identity.
-- Updates v_approval_queue / get_approval_queue to surface new fields.
-- Updates handle_new_auth_user to read extended signup metadata.
--
-- Safe to apply after: 20260520012857_remote_schema.sql
-- Does NOT depend on any pending unapplied migrations.
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- §1  Identity columns — account_requests
-- ─────────────────────────────────────────────────────────────

ALTER TABLE public.account_requests
  ADD COLUMN IF NOT EXISTS last_name        TEXT,
  ADD COLUMN IF NOT EXISTS first_name       TEXT,
  ADD COLUMN IF NOT EXISTS middle_name      TEXT,         -- NULL when blank/NA/N/A/-/.
  ADD COLUMN IF NOT EXISTS mobile_number    TEXT,         -- stored as +639XXXXXXXXX
  ADD COLUMN IF NOT EXISTS full_name_search TEXT;         -- lowercase searchable index

-- ─────────────────────────────────────────────────────────────
-- §2  Identity columns — users_profile
-- ─────────────────────────────────────────────────────────────

ALTER TABLE public.users_profile
  ADD COLUMN IF NOT EXISTS last_name        TEXT,
  ADD COLUMN IF NOT EXISTS first_name       TEXT,
  ADD COLUMN IF NOT EXISTS middle_name      TEXT,
  ADD COLUMN IF NOT EXISTS mobile_number    TEXT,
  ADD COLUMN IF NOT EXISTS full_name_search TEXT,
  ADD COLUMN IF NOT EXISTS directory_status TEXT NOT NULL DEFAULT 'Available';

-- ─────────────────────────────────────────────────────────────
-- §3  Helper: middle name null-coalesce
-- ─────────────────────────────────────────────────────────────
-- Treats blank, NA, N/A, -, . as null. Case-insensitive.

CREATE OR REPLACE FUNCTION public.fn_coalesce_middle_name(p_val TEXT)
  RETURNS TEXT
  LANGUAGE sql
  IMMUTABLE
  PARALLEL SAFE
  SET search_path TO 'public'
AS $$
  SELECT CASE
    WHEN TRIM(UPPER(COALESCE(p_val, ''))) = ANY(ARRAY['', 'NA', 'N/A', '-', '.'])
      THEN NULL
    ELSE NULLIF(TRIM(p_val), '')
  END;
$$;

-- ─────────────────────────────────────────────────────────────
-- §4  Helper: PH mobile number normalizer/validator
-- ─────────────────────────────────────────────────────────────
-- Accepts  09XXXXXXXXX (11 digits)
-- Returns  +639XXXXXXXXX
-- NULL in  → NULL out
-- Invalid  → raises exception with SQLSTATE '22023'

CREATE OR REPLACE FUNCTION public.fn_normalize_ph_mobile(p_raw TEXT)
  RETURNS TEXT
  LANGUAGE plpgsql
  IMMUTABLE
  PARALLEL SAFE
  SET search_path TO 'public'
AS $$
DECLARE
  v_clean TEXT;
BEGIN
  IF p_raw IS NULL THEN
    RETURN NULL;
  END IF;

  v_clean := REGEXP_REPLACE(TRIM(p_raw), '[^0-9]', '', 'g');

  -- Accept 09XXXXXXXXX (11 digits starting with 09)
  IF v_clean ~ '^09[0-9]{9}$' THEN
    RETURN '+63' || SUBSTRING(v_clean, 2);  -- +639XXXXXXXXX
  END IF;

  -- Accept +639XXXXXXXXX (already normalized, 12 chars with leading +)
  IF TRIM(p_raw) ~ '^\+639[0-9]{9}$' THEN
    RETURN TRIM(p_raw);
  END IF;

  RAISE EXCEPTION 'invalid_ph_mobile: must be 09XXXXXXXXX format, got: %', p_raw
    USING ERRCODE = '22023';
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- §5  Mobile uniqueness constraints
-- ─────────────────────────────────────────────────────────────
-- account_requests: exclude rejected rows so re-submission is allowed
-- users_profile:    always unique (active approved profile)

CREATE UNIQUE INDEX IF NOT EXISTS uq_account_requests_mobile
  ON public.account_requests (mobile_number)
  WHERE mobile_number IS NOT NULL
    AND status <> 'rejected'::public.account_request_status;

CREATE UNIQUE INDEX IF NOT EXISTS uq_users_profile_mobile
  ON public.users_profile (mobile_number)
  WHERE mobile_number IS NOT NULL;

-- ─────────────────────────────────────────────────────────────
-- §6  full_name_search auto-compute — account_requests trigger
-- ─────────────────────────────────────────────────────────────
-- Format: "dela cruz juan yap"  (last first [middle], lowercase, no nulls)

CREATE OR REPLACE FUNCTION public.trg_fn_account_request_identity_sync()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO 'public'
AS $$
BEGIN
  -- Null-coalesce middle name on every write
  NEW.middle_name := public.fn_coalesce_middle_name(NEW.middle_name);

  -- Rebuild full_name_search from separated fields when available;
  -- fall back to full_name for legacy rows.
  IF NEW.last_name IS NOT NULL OR NEW.first_name IS NOT NULL THEN
    NEW.full_name_search := TRIM(LOWER(
      CONCAT_WS(' ',
        NULLIF(TRIM(NEW.last_name),  ''),
        NULLIF(TRIM(NEW.first_name), ''),
        NULLIF(TRIM(NEW.middle_name),'')
      )
    ));
  ELSIF NEW.full_name IS NOT NULL THEN
    NEW.full_name_search := LOWER(TRIM(NEW.full_name));
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_account_request_identity_sync ON public.account_requests;
CREATE TRIGGER trg_account_request_identity_sync
  BEFORE INSERT OR UPDATE ON public.account_requests
  FOR EACH ROW EXECUTE FUNCTION public.trg_fn_account_request_identity_sync();

-- ─────────────────────────────────────────────────────────────
-- §7  full_name_search auto-compute — users_profile trigger
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.trg_fn_users_profile_identity_sync()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO 'public'
AS $$
BEGIN
  NEW.middle_name := public.fn_coalesce_middle_name(NEW.middle_name);

  IF NEW.last_name IS NOT NULL OR NEW.first_name IS NOT NULL THEN
    NEW.full_name_search := TRIM(LOWER(
      CONCAT_WS(' ',
        NULLIF(TRIM(NEW.last_name),  ''),
        NULLIF(TRIM(NEW.first_name), ''),
        NULLIF(TRIM(NEW.middle_name),'')
      )
    ));
  ELSIF NEW.full_name IS NOT NULL THEN
    NEW.full_name_search := LOWER(TRIM(NEW.full_name));
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_users_profile_identity_sync ON public.users_profile;
CREATE TRIGGER trg_users_profile_identity_sync
  BEFORE INSERT OR UPDATE ON public.users_profile
  FOR EACH ROW EXECUTE FUNCTION public.trg_fn_users_profile_identity_sync();

-- ─────────────────────────────────────────────────────────────
-- §8  GIN index on full_name_search (performance)
-- ─────────────────────────────────────────────────────────────

CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE INDEX IF NOT EXISTS idx_account_requests_full_name_search
ON public.account_requests (full_name_search);

CREATE INDEX IF NOT EXISTS idx_users_profile_full_name_search
ON public.users_profile (full_name_search);

-- ─────────────────────────────────────────────────────────────
-- §9  Update handle_new_auth_user to read extended metadata
-- ─────────────────────────────────────────────────────────────
-- Reads: last_name, first_name, middle_name, mobile_number, full_name
-- Preserves existing idempotency guard and error-raise behavior.

CREATE OR REPLACE FUNCTION public.handle_new_auth_user()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_meta           JSONB := NEW.raw_user_meta_data;
  v_last_name      TEXT;
  v_first_name     TEXT;
  v_middle_name    TEXT;
  v_mobile_raw     TEXT;
  v_mobile_norm    TEXT;
  v_full_name      TEXT;
BEGIN
  -- Idempotency guard
  IF EXISTS (
    SELECT 1 FROM public.account_requests WHERE auth_user_id = NEW.id
  ) THEN
    RETURN NEW;
  END IF;

  -- Extract metadata
  v_last_name   := NULLIF(TRIM(COALESCE(v_meta->>'last_name',  '')), '');
  v_first_name  := NULLIF(TRIM(COALESCE(v_meta->>'first_name', '')), '');
  v_middle_name := public.fn_coalesce_middle_name(v_meta->>'middle_name');
  v_mobile_raw  := NULLIF(TRIM(COALESCE(v_meta->>'mobile_number', '')), '');

  -- full_name: prefer metadata field, fall back to first+last composition
  v_full_name := COALESCE(
    NULLIF(TRIM(v_meta->>'full_name'), ''),
    NULLIF(TRIM(CONCAT_WS(' ', v_first_name, v_last_name)), ''),
    'No Name'
  );

  -- Normalize mobile silently — invalid format is stored as NULL at signup
  -- (fn_enrich_account_request will validate strictly later)
  IF v_mobile_raw IS NOT NULL THEN
    BEGIN
      v_mobile_norm := public.fn_normalize_ph_mobile(v_mobile_raw);
    EXCEPTION WHEN OTHERS THEN
      v_mobile_norm := NULL;
    END;
  END IF;

  INSERT INTO public.account_requests (
    auth_user_id,
    email,
    full_name,
    last_name,
    first_name,
    middle_name,
    mobile_number,
    status
  )
  VALUES (
    NEW.id,
    NEW.email,
    v_full_name,
    v_last_name,
    v_first_name,
    v_middle_name,
    v_mobile_norm,
    'pending'::public.account_request_status
  );

  RETURN NEW;

EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING
      'handle_new_auth_user FAILED | user=% email=% sqlstate=% msg=%',
      NEW.id, NEW.email, SQLSTATE, SQLERRM;
    RAISE;
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- §10  RPC: fn_enrich_account_request
-- ─────────────────────────────────────────────────────────────
-- Called by Flutter immediately after auth.signUp(), before signOut().
-- Updates the pending account_request row with identity data and
-- optional scope/role request. Validates:
--   - Only the request owner may call
--   - Request must be pending
--   - Mobile: valid PH format, not already taken by non-rejected request
--   - Role-scope rules (see §10a below)
-- Scope rules enforced:
--   - OM / ENCODER             : groups only (no accounts)
--   - SUPER ADMIN / HEAD ADMIN : rejected — admin-controlled only
--   - RECRUITMENT / HRCO / ATL / TL: groups + accounts allowed
--   - Other roles              : no account scope restriction

CREATE OR REPLACE FUNCTION public.fn_enrich_account_request(
  p_last_name       TEXT,
  p_first_name      TEXT,
  p_middle_name     TEXT     DEFAULT NULL,
  p_mobile_number   TEXT     DEFAULT NULL,
  p_requested_role_id UUID   DEFAULT NULL,
  p_group_ids       UUID[]   DEFAULT ARRAY[]::UUID[],
  p_account_ids     UUID[]   DEFAULT ARRAY[]::UUID[]
)
  RETURNS JSONB
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public', 'auth'
AS $$
DECLARE
  v_request        public.account_requests%ROWTYPE;
  v_mobile_norm    TEXT;
  v_role_name      TEXT;
  v_role_upper     TEXT;
  v_gid            UUID;
  v_aid            UUID;
  v_dup_count      INT;
BEGIN
  -- ── 1. Caller must be authenticated ──────────────────────────────────────
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'unauthenticated' USING ERRCODE = '42501';
  END IF;

  -- ── 2. Load and lock own pending request ─────────────────────────────────
  SELECT * INTO v_request
  FROM public.account_requests
  WHERE auth_user_id = auth.uid()
    AND status = 'pending'::public.account_request_status
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'no pending account request found for caller'
      USING ERRCODE = 'P0002';
  END IF;

  -- ── 3. Validate required name fields ─────────────────────────────────────
  IF NULLIF(TRIM(p_last_name),  '') IS NULL THEN
    RAISE EXCEPTION 'last_name is required' USING ERRCODE = '23502';
  END IF;
  IF NULLIF(TRIM(p_first_name), '') IS NULL THEN
    RAISE EXCEPTION 'first_name is required' USING ERRCODE = '23502';
  END IF;

  -- ── 4. Mobile normalization & duplicate check ─────────────────────────────
  IF p_mobile_number IS NOT NULL AND TRIM(p_mobile_number) <> '' THEN
    v_mobile_norm := public.fn_normalize_ph_mobile(p_mobile_number);

    -- Check for duplicate mobile (exclude current request and rejected rows)
    SELECT COUNT(*) INTO v_dup_count
    FROM public.account_requests
    WHERE mobile_number = v_mobile_norm
      AND id <> v_request.id
      AND status <> 'rejected'::public.account_request_status;

    IF v_dup_count > 0 THEN
      RAISE EXCEPTION 'mobile_number_already_registered: % is already in use', v_mobile_norm
        USING ERRCODE = '23505';
    END IF;
  END IF;

  -- ── 5. Role validation ────────────────────────────────────────────────────
  IF p_requested_role_id IS NOT NULL THEN
    SELECT UPPER(role_name) INTO v_role_name
    FROM public.roles
    WHERE id = p_requested_role_id;

    IF v_role_name IS NULL THEN
      RAISE EXCEPTION 'requested role not found: %', p_requested_role_id
        USING ERRCODE = 'P0002';
    END IF;

    v_role_upper := v_role_name;

    -- Super Admin and Head Admin are admin-controlled only
    IF v_role_upper IN ('SUPER ADMIN', 'SUPERADMIN', 'HEAD ADMIN', 'HEADADMIN') THEN
      RAISE EXCEPTION 'super_admin and head_admin roles cannot be self-requested'
        USING ERRCODE = '42501';
    END IF;

    -- §10a  Scope rules per role ──────────────────────────────────────────────
    -- OM / Encoder: group only, no accounts
    IF v_role_upper IN ('OM', 'ENCODER') THEN
      IF COALESCE(ARRAY_LENGTH(p_account_ids, 1), 0) > 0 THEN
        RAISE EXCEPTION 'role_scope_violation: % may only request group scope (no accounts)', v_role_upper
          USING ERRCODE = '22023';
      END IF;
    END IF;

    -- All roles requesting accounts must have at least one group
    IF COALESCE(ARRAY_LENGTH(p_account_ids, 1), 0) > 0
      AND COALESCE(ARRAY_LENGTH(p_group_ids, 1), 0) = 0 THEN
      RAISE EXCEPTION 'account scope requires at least one group'
        USING ERRCODE = '22023';
    END IF;
  END IF;

  -- ── 6. Update account_requests with identity fields ───────────────────────
  UPDATE public.account_requests
  SET
    last_name          = TRIM(p_last_name),
    first_name         = TRIM(p_first_name),
    middle_name        = public.fn_coalesce_middle_name(p_middle_name),
    mobile_number      = v_mobile_norm,
    -- Rebuild full_name for backward-compat display
    full_name          = TRIM(CONCAT_WS(' ',
                           TRIM(p_first_name),
                           public.fn_coalesce_middle_name(p_middle_name),
                           TRIM(p_last_name)
                         )),
    requested_role_id  = COALESCE(p_requested_role_id, requested_role_id),
    updated_at         = NOW()
  WHERE id = v_request.id;

  -- ── 7. Scope rows: replace requested scope ────────────────────────────────
  DELETE FROM public.account_request_group_scopes
  WHERE account_request_id = v_request.id;

  DELETE FROM public.account_request_account_scopes
  WHERE account_request_id = v_request.id;

  FOREACH v_gid IN ARRAY p_group_ids LOOP
    INSERT INTO public.account_request_group_scopes (account_request_id, group_id)
    VALUES (v_request.id, v_gid)
    ON CONFLICT DO NOTHING;
  END LOOP;

  FOREACH v_aid IN ARRAY p_account_ids LOOP
    INSERT INTO public.account_request_account_scopes (account_request_id, account_id)
    VALUES (v_request.id, v_aid)
    ON CONFLICT DO NOTHING;
  END LOOP;

  -- ── 8. Return summary ─────────────────────────────────────────────────────
  RETURN jsonb_build_object(
    'success',        TRUE,
    'request_id',     v_request.id,
    'last_name',      TRIM(p_last_name),
    'first_name',     TRIM(p_first_name),
    'mobile_number',  v_mobile_norm,
    'role_id',        p_requested_role_id,
    'group_count',    COALESCE(ARRAY_LENGTH(p_group_ids, 1), 0),
    'account_count',  COALESCE(ARRAY_LENGTH(p_account_ids, 1), 0)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_enrich_account_request(TEXT, TEXT, TEXT, TEXT, UUID, UUID[], UUID[])
  TO authenticated;

-- ─────────────────────────────────────────────────────────────
-- §11  Update approve_account_request_v2: propagate identity
-- ─────────────────────────────────────────────────────────────
-- Adds: last_name, first_name, middle_name, mobile_number,
--       full_name_search, directory_status = 'Available'
-- to the users_profile upsert. All other behavior preserved.

CREATE OR REPLACE FUNCTION public.approve_account_request_v2(
  p_request_id  UUID,
  p_role_id     UUID,
  p_scope_type  TEXT,
  p_group_ids   UUID[] DEFAULT ARRAY[]::UUID[],
  p_account_ids UUID[] DEFAULT ARRAY[]::UUID[]
)
  RETURNS JSONB
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public', 'auth'
AS $$
DECLARE
  v_request              public.account_requests%ROWTYPE;
  v_profile_id           UUID;
  v_role_name            TEXT;
  v_caller_role_level    INT;
  v_gid                  UUID;
  v_aid                  UUID;
  v_invalid_account_count INT;
BEGIN
  -- Authorize approver
  SELECT r.role_level
  INTO v_caller_role_level
  FROM public.users_profile up
  JOIN public.roles r ON r.id = up.role_id
  WHERE up.auth_user_id = auth.uid();

  IF COALESCE(v_caller_role_level, 0) < 90 THEN
    RAISE EXCEPTION 'unauthorized: requires Head Admin or higher'
      USING ERRCODE = '42501';
  END IF;

  IF p_scope_type NOT IN ('global', 'scoped', 'custom') THEN
    RAISE EXCEPTION 'invalid scope_type: %', p_scope_type
      USING ERRCODE = '22023';
  END IF;

  IF p_scope_type = 'scoped' AND COALESCE(ARRAY_LENGTH(p_group_ids, 1), 0) = 0 THEN
    RAISE EXCEPTION 'scoped access requires at least one group'
      USING ERRCODE = '22023';
  END IF;

  SELECT COUNT(*) INTO v_invalid_account_count
  FROM public.accounts a
  WHERE a.id = ANY(p_account_ids)
    AND NOT (a.group_id = ANY(p_group_ids));

  IF v_invalid_account_count > 0 THEN
    RAISE EXCEPTION 'one or more accounts do not belong to selected groups'
      USING ERRCODE = '22023';
  END IF;

  SELECT role_name INTO v_role_name
  FROM public.roles WHERE id = p_role_id;

  IF v_role_name IS NULL THEN
    RAISE EXCEPTION 'role not found' USING ERRCODE = 'P0002';
  END IF;

  SELECT * INTO v_request
  FROM public.account_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'account request not found' USING ERRCODE = 'P0002';
  END IF;

  IF v_request.status <> 'pending'::account_request_status THEN
    RAISE EXCEPTION 'request already processed' USING ERRCODE = '22023';
  END IF;

  -- Upsert users_profile with identity fields from request
  INSERT INTO public.users_profile (
    auth_user_id,
    full_name,
    last_name,
    first_name,
    middle_name,
    email,
    role_id,
    mobile_number,
    directory_status,
    is_active
  )
  VALUES (
    v_request.auth_user_id,
    v_request.full_name,
    v_request.last_name,
    v_request.first_name,
    v_request.middle_name,
    v_request.email,
    p_role_id,
    v_request.mobile_number,
    'Available',
    TRUE
  )
  ON CONFLICT (auth_user_id) DO UPDATE SET
    role_id          = EXCLUDED.role_id,
    full_name        = EXCLUDED.full_name,
    last_name        = COALESCE(EXCLUDED.last_name,    users_profile.last_name),
    first_name       = COALESCE(EXCLUDED.first_name,   users_profile.first_name),
    middle_name      = COALESCE(EXCLUDED.middle_name,  users_profile.middle_name),
    mobile_number    = COALESCE(EXCLUDED.mobile_number, users_profile.mobile_number),
    directory_status = COALESCE(users_profile.directory_status, 'Available'),
    is_active        = TRUE,
    updated_at       = NOW()
  RETURNING id INTO v_profile_id;

  -- Rebuild user_scopes
  DELETE FROM public.user_scopes WHERE user_id = v_profile_id;

  IF p_scope_type <> 'global' THEN
    FOREACH v_gid IN ARRAY p_group_ids LOOP
      INSERT INTO public.user_scopes (user_id, group_id, account_id)
      VALUES (v_profile_id, v_gid, NULL)
      ON CONFLICT DO NOTHING;
    END LOOP;

    FOREACH v_aid IN ARRAY p_account_ids LOOP
      INSERT INTO public.user_scopes (user_id, group_id, account_id)
      SELECT v_profile_id, a.group_id, a.id
      FROM public.accounts a WHERE a.id = v_aid
      ON CONFLICT DO NOTHING;
    END LOOP;
  END IF;

  -- Snapshot scope on request
  DELETE FROM public.account_request_group_scopes   WHERE account_request_id = p_request_id;
  DELETE FROM public.account_request_account_scopes WHERE account_request_id = p_request_id;

  FOREACH v_gid IN ARRAY p_group_ids LOOP
    INSERT INTO public.account_request_group_scopes (account_request_id, group_id)
    VALUES (p_request_id, v_gid)
    ON CONFLICT DO NOTHING;
  END LOOP;

  FOREACH v_aid IN ARRAY p_account_ids LOOP
    INSERT INTO public.account_request_account_scopes (account_request_id, account_id)
    VALUES (p_request_id, v_aid)
    ON CONFLICT DO NOTHING;
  END LOOP;

  -- Mark approved
  UPDATE public.account_requests
  SET
    status                   = 'approved'::account_request_status,
    approved_by              = auth.uid(),
    approved_at              = NOW(),
    reviewed_by              = auth.uid(),
    reviewed_at              = NOW(),
    assigned_role_id         = p_role_id,
    assigned_scope_type      = p_scope_type,
    assigned_groups_snapshot = to_jsonb(p_group_ids),
    assigned_accounts_snapshot = to_jsonb(p_account_ids),
    updated_at               = NOW()
  WHERE id = p_request_id;

  RETURN jsonb_build_object(
    'success',       TRUE,
    'request_id',    p_request_id,
    'profile_id',    v_profile_id,
    'scope_type',    p_scope_type,
    'group_count',   COALESCE(ARRAY_LENGTH(p_group_ids, 1), 0),
    'account_count', COALESCE(ARRAY_LENGTH(p_account_ids, 1), 0)
  );
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- §12  Update v_approval_queue + get_approval_queue RPC
-- ─────────────────────────────────────────────────────────────
-- Adds: last_name, first_name, middle_name, mobile_number,
--       requested_group_names, requested_account_names,
--       reviewer_display_name, assigned_role_name, assigned_role_level,
--       rejection_reason, rejected_at, assigned_scope_type

-- Drop dependent RPC first (returns SETOF the old view type)
DROP VIEW IF EXISTS public.v_approval_queue CASCADE;

-- Recreate the view with new identity + scope request fields
CREATE VIEW public.v_approval_queue AS
  SELECT
    ar.id,
    ar.auth_user_id,
    ar.email,
    ar.full_name,
    ar.last_name,
    ar.first_name,
    ar.middle_name,
    ar.mobile_number,
    ar.full_name_search,
    ar.status,
    ar.notes,
    ar.requested_role_id,
    req_r.role_name  AS requested_role_name,
    req_r.role_level AS requested_role_level,
    ar.assigned_role_id,
    asgn_r.role_name  AS assigned_role_name,
    asgn_r.role_level AS assigned_role_level,
    ar.assigned_scope_type,
    ar.assigned_groups_snapshot,
    ar.assigned_accounts_snapshot,
    ar.reviewed_by,
    ar.reviewed_at,
    ar.rejection_reason,
    ar.rejected_at,
    ar.created_at,
    ar.updated_at,
    reviewer_up.full_name AS reviewer_display_name,
    -- Requested group names (from scope tables)
    COALESCE(
      (
        SELECT ARRAY_AGG(g.group_name ORDER BY g.group_name)
        FROM public.account_request_group_scopes rgs
        JOIN public.groups g ON g.id = rgs.group_id
        WHERE rgs.account_request_id = ar.id
      ),
      ARRAY[]::TEXT[]
    ) AS requested_group_names,
    -- Requested account names
    COALESCE(
      (
        SELECT ARRAY_AGG(a.account_name ORDER BY a.account_name)
        FROM public.account_request_account_scopes ras
        JOIN public.accounts a ON a.id = ras.account_id
        WHERE ras.account_request_id = ar.id
      ),
      ARRAY[]::TEXT[]
    ) AS requested_account_names,
    ((EXTRACT(EPOCH FROM (NOW() - ar.created_at))::INT) / 86400) AS days_pending
  FROM public.account_requests ar
  LEFT JOIN public.roles req_r   ON req_r.id  = ar.requested_role_id
  LEFT JOIN public.roles asgn_r  ON asgn_r.id = ar.assigned_role_id
  LEFT JOIN public.users_profile reviewer_up ON reviewer_up.auth_user_id = ar.reviewed_by
  ORDER BY
    CASE ar.status
      WHEN 'pending'  THEN 1
      WHEN 'rejected' THEN 2
      WHEN 'approved' THEN 3
      ELSE NULL
    END,
    ar.created_at DESC;

-- Recreate the RPC returning the updated view
CREATE OR REPLACE FUNCTION public.get_approval_queue(
  p_status public.account_request_status DEFAULT 'pending'::public.account_request_status
)
  RETURNS SETOF public.v_approval_queue
  LANGUAGE sql
  STABLE
  SET search_path TO 'public', 'pg_temp'
AS $$
  SELECT * FROM public.v_approval_queue WHERE status = p_status;
$$;

-- ─────────────────────────────────────────────────────────────
-- §13  RLS policy for fn_enrich_account_request
-- ─────────────────────────────────────────────────────────────
-- account_requests already has RLS enabled.
-- The enrich RPC is SECURITY DEFINER so it bypasses RLS internally.
-- No new RLS policies needed for the new columns — they inherit
-- existing row-level policies.

-- ─────────────────────────────────────────────────────────────
-- VALIDATION QUERIES (read-only, execute manually to verify)
-- ─────────────────────────────────────────────────────────────
/*
-- V1: Middle name coalesce
SELECT public.fn_coalesce_middle_name('NA')   IS NULL,   -- TRUE
       public.fn_coalesce_middle_name('N/A')  IS NULL,   -- TRUE
       public.fn_coalesce_middle_name('-')    IS NULL,   -- TRUE
       public.fn_coalesce_middle_name('.')    IS NULL,   -- TRUE
       public.fn_coalesce_middle_name('')     IS NULL,   -- TRUE
       public.fn_coalesce_middle_name('YAP')  = 'YAP';  -- TRUE

-- V2: Mobile normalization
SELECT public.fn_normalize_ph_mobile('09171234567')  = '+639171234567',  -- TRUE
       public.fn_normalize_ph_mobile('+639171234567') = '+639171234567'; -- TRUE

-- V3: Mobile normalization — invalid (should raise exception)
DO $$ BEGIN
  PERFORM public.fn_normalize_ph_mobile('1234567890');
  RAISE EXCEPTION 'should have failed';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM LIKE '%invalid_ph_mobile%' THEN
    RAISE NOTICE 'V3 PASS: invalid mobile rejected';
  ELSE RAISE;
  END IF;
END $$;

-- V4: full_name_search is built correctly
SELECT full_name_search
FROM public.account_requests
WHERE last_name IS NOT NULL
LIMIT 5;

-- V5: v_approval_queue has new columns
SELECT id, last_name, first_name, mobile_number, requested_group_names, requested_account_names
FROM public.v_approval_queue
LIMIT 5;

-- V6: approve_account_request_v2 propagates identity
-- (run after approving a test request and checking users_profile)
SELECT last_name, first_name, mobile_number, directory_status
FROM public.users_profile
WHERE last_name IS NOT NULL
LIMIT 5;
*/
