-- ============================================================
-- Enforce Role and Scope in Account Requests (RBAC Integrity)
-- ============================================================

-- §1. Update handle_new_auth_user trigger function to read and validate requested role and scope
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

  -- Insert pending account request with requested_role_id
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
    status
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
    'pending'::public.account_request_status
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

-- §2. Add check constraint on account_requests to prevent empty role on pending requests
-- (Check if constraint already exists first, but migration is running clean, so standard ALTER is fine)
-- Clean up any legacy pending requests that have no requested_role_id to prevent constraint violation
UPDATE public.account_requests
  SET status = 'rejected'::public.account_request_status,
      rejection_reason = 'Automatically rejected during migration: requested role was missing',
      rejected_at = NOW(),
      updated_at = NOW()
  WHERE status = 'pending' AND requested_role_id IS NULL;

ALTER TABLE public.account_requests
  DROP CONSTRAINT IF EXISTS chk_account_requests_role_required;

ALTER TABLE public.account_requests
  ADD CONSTRAINT chk_account_requests_role_required
  CHECK (status <> 'pending' OR requested_role_id IS NOT NULL);
