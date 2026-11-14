-- ============================================================
-- Restore Remarks Visibility in Request Details (Data Hydration)
-- ============================================================

-- §1. Update handle_new_auth_user trigger function to read remarks/notes from user metadata
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
  v_requested_role_id UUID;
  v_request_id     UUID;
  v_gid            TEXT;
  v_aid            TEXT;
  v_notes          TEXT;
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
  v_requested_role_id := NULLIF(TRIM(COALESCE(v_meta->>'requested_role_id', '')), '')::UUID;
  
  -- Extract remarks/notes (support both keys for robust compatibility)
  v_notes       := COALESCE(
                     NULLIF(TRIM(v_meta->>'notes'), ''),
                     NULLIF(TRIM(v_meta->>'remarks'), '')
                   );

  -- Enforce requested role is not null
  IF v_requested_role_id IS NULL THEN
    RAISE EXCEPTION 'requested_role_required: requested_role_id must be provided'
      USING ERRCODE = '23502';
  END IF;

  -- Enforce group scope is not empty
  IF NOT (v_meta ? 'group_ids') OR jsonb_typeof(v_meta->'group_ids') <> 'array' OR jsonb_array_length(v_meta->'group_ids') = 0 THEN
    RAISE EXCEPTION 'group_scope_required: at least one group_id must be provided'
      USING ERRCODE = '23502';
  END IF;

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

  -- Generate request ID
  v_request_id := gen_random_uuid();

  -- Insert pending account request with notes
  INSERT INTO public.account_requests (
    id,
    auth_user_id,
    email,
    full_name,
    last_name,
    first_name,
    middle_name,
    mobile_number,
    requested_role_id,
    status,
    notes
  )
  VALUES (
    v_request_id,
    NEW.id,
    NEW.email,
    v_full_name,
    v_last_name,
    v_first_name,
    v_middle_name,
    v_mobile_norm,
    v_requested_role_id,
    'pending'::public.account_request_status,
    v_notes
  );

  -- Insert group scopes
  FOR v_gid IN SELECT jsonb_array_elements_text(v_meta->'group_ids') LOOP
    INSERT INTO public.account_request_group_scopes (account_request_id, group_id)
    VALUES (v_request_id, v_gid::UUID)
    ON CONFLICT DO NOTHING;
  END LOOP;

  -- Insert account scopes (if any)
  IF v_meta ? 'account_ids' AND jsonb_typeof(v_meta->'account_ids') = 'array' THEN
    FOR v_aid IN SELECT jsonb_array_elements_text(v_meta->'account_ids') LOOP
      INSERT INTO public.account_request_account_scopes (account_request_id, account_id)
      VALUES (v_request_id, v_aid::UUID)
      ON CONFLICT DO NOTHING;
    END LOOP;
  END IF;

  RETURN NEW;

EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING
      'handle_new_auth_user FAILED | user=% email=% sqlstate=% msg=%',
      NEW.id, NEW.email, SQLSTATE, SQLERRM;
    RAISE;
END;
$$;


-- §2. Drop and recreate fn_enrich_account_request to support notes parameter
DROP FUNCTION IF EXISTS public.fn_enrich_account_request(TEXT, TEXT, TEXT, TEXT, UUID, UUID[], UUID[]);

CREATE OR REPLACE FUNCTION public.fn_enrich_account_request(
  p_last_name       TEXT,
  p_first_name      TEXT,
  p_middle_name     TEXT     DEFAULT NULL,
  p_mobile_number   TEXT     DEFAULT NULL,
  p_requested_role_id UUID   DEFAULT NULL,
  p_group_ids       UUID[]   DEFAULT ARRAY[]::UUID[],
  p_account_ids     UUID[]   DEFAULT ARRAY[]::UUID[],
  p_notes           TEXT     DEFAULT NULL
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

  -- ── 2. Governance gate ───────────────────────────────────────────────────
  PERFORM public.fn_assert_governance_enabled('account_registration');

  -- ── 3. Load and lock own pending request ─────────────────────────────────
  SELECT * INTO v_request
  FROM public.account_requests
  WHERE auth_user_id = auth.uid()
    AND status = 'pending'::public.account_request_status
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'no pending account request found for caller'
      USING ERRCODE = 'P0002';
  END IF;

  -- ── 4. Validate required name fields ─────────────────────────────────────
  IF NULLIF(TRIM(p_last_name),  '') IS NULL THEN
    RAISE EXCEPTION 'last_name is required' USING ERRCODE = '23502';
  END IF;
  IF NULLIF(TRIM(p_first_name), '') IS NULL THEN
    RAISE EXCEPTION 'first_name is required' USING ERRCODE = '23502';
  END IF;

  -- ── 5. Mobile normalization & duplicate check ─────────────────────────────
  IF p_mobile_number IS NOT NULL AND TRIM(p_mobile_number) <> '' THEN
    v_mobile_norm := public.fn_normalize_ph_mobile(p_mobile_number);

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

  -- ── 6. Role validation ────────────────────────────────────────────────────
  IF p_requested_role_id IS NOT NULL THEN
    SELECT UPPER(role_name) INTO v_role_name
    FROM public.roles
    WHERE id = p_requested_role_id;

    IF v_role_name IS NULL THEN
      RAISE EXCEPTION 'requested role not found: %', p_requested_role_id
        USING ERRCODE = 'P0002';
    END IF;

    v_role_upper := v_role_name;

    IF v_role_upper IN ('SUPER ADMIN', 'SUPERADMIN', 'HEAD ADMIN', 'HEADADMIN') THEN
      RAISE EXCEPTION 'super_admin and head_admin roles cannot be self-requested'
        USING ERRCODE = '42501';
    END IF;

    IF v_role_upper IN ('OM', 'ENCODER') THEN
      IF COALESCE(ARRAY_LENGTH(p_account_ids, 1), 0) > 0 THEN
        RAISE EXCEPTION 'role_scope_violation: % may only request group scope (no accounts)', v_role_upper
          USING ERRCODE = '22023';
      END IF;
    END IF;

    IF COALESCE(ARRAY_LENGTH(p_account_ids, 1), 0) > 0
      AND COALESCE(ARRAY_LENGTH(p_group_ids, 1), 0) = 0 THEN
      RAISE EXCEPTION 'account scope requires at least one group'
        USING ERRCODE = '22023';
    END IF;
  END IF;

  -- ── 7. Update account_requests with identity fields ───────────────────────
  UPDATE public.account_requests
  SET
    last_name          = TRIM(p_last_name),
    first_name         = TRIM(p_first_name),
    middle_name        = public.fn_coalesce_middle_name(p_middle_name),
    mobile_number      = v_mobile_norm,
    full_name          = TRIM(CONCAT_WS(' ',
                           TRIM(p_first_name),
                           public.fn_coalesce_middle_name(p_middle_name),
                           TRIM(p_last_name)
                         )),
    requested_role_id  = COALESCE(p_requested_role_id, requested_role_id),
    notes              = COALESCE(p_notes, notes),
    updated_at         = NOW()
  WHERE id = v_request.id;

  -- ── 8. Scope rows: replace requested scope ────────────────────────────────
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

  -- ── 9. Return summary ─────────────────────────────────────────────────────
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

GRANT EXECUTE ON FUNCTION public.fn_enrich_account_request(TEXT, TEXT, TEXT, TEXT, UUID, UUID[], UUID[], TEXT)
  TO authenticated;

COMMENT ON FUNCTION public.fn_enrich_account_request IS
  'OHM2026_0041: Adds account_registration governance gate (§2). '
  'Carries forward OHM2026_2010 identity enrichment and p_notes (remarks) parameter.';
