-- ====================================================================
-- MIGRATION: 20262606000081_hr_emploc_final_workflow_and_registry.sql
-- Module: HR Emploc (Phase 2a: DB foundation & registry on STAGING)
--
-- Authoritative Workflow:
-- 1. No "Ready" tab and no manual "Move to Plantilla" path.
-- 2. Emploc ID assignment (via Pending or Review Approve) auto-moves
--    the record to Plantilla in the SAME atomic transaction.
-- 3. Final state: status = 'Moved to Plantilla', hr_status = 'Transferred'.
-- 4. Reuses move_to_plantilla logic via shared private core:
--    _assign_and_deploy_emploc_core.
-- 5. Strict Plantilla validation (no silent defaults: hired_date required,
--    structured applicant names required).
-- 6. Slot occupancy reconciled to 'occupied'.
-- 7. Permanent employee_number_registry with race-safe rules (a, b, c, d).
-- 8. Centralized role helpers matching Ohm's final role matrix:
--    - can_tag_or_review_hr_emploc()
--    - can_assign_pending_hr_emploc()
--    - can_submit_hr_emploc_correction()
--    - can_edit_deployed_hr_emploc()
-- ====================================================================

-- SECTION 1: NAME NORMALIZATION HELPERS (IMMUTABLE)
-- ====================================================================

CREATE OR REPLACE FUNCTION public.fn_clean_name_token(p_token text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE PARALLEL SAFE
AS $$
DECLARE
  v_clean text;
BEGIN
  IF p_token IS NULL THEN
    RETURN NULL;
  END IF;
  
  -- Uppercase, trim, strip punctuation and special characters
  v_clean := regexp_replace(upper(trim(p_token)), '[.,\/#!$%\^&\*;:{}=\-_`~()]', '', 'g');
  v_clean := regexp_replace(v_clean, '\s+', ' ', 'g');
  v_clean := trim(v_clean);
  
  IF v_clean = '' THEN
    RETURN NULL;
  END IF;
  
  -- Expand common abbreviations
  IF v_clean = 'MA' THEN
    RETURN 'MARIA';
  END IF;
  
  -- Strip standalone generational suffixes if present as token
  IF v_clean IN ('JR', 'SR', 'III', 'II', 'IV') THEN
    RETURN NULL;
  END IF;
  
  RETURN v_clean;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_normalize_person_name(
  p_first    text DEFAULT NULL,
  p_middle   text DEFAULT NULL,
  p_last     text DEFAULT NULL,
  p_suffix   text DEFAULT NULL,
  p_raw_full text DEFAULT NULL
)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE PARALLEL SAFE
AS $$
DECLARE
  v_first   text;
  v_middle  text;
  v_last    text;
  v_raw     text;
  v_parts   text[];
  v_tokens  text[];
  v_t       text;
  v_clean_t text;
BEGIN
  -- If structured first and last are provided, use them
  IF NULLIF(trim(coalesce(p_first, '')), '') IS NOT NULL 
     AND NULLIF(trim(coalesce(p_last, '')), '') IS NOT NULL THEN
    v_first  := public.fn_clean_name_token(p_first);
    v_middle := public.fn_clean_name_token(p_middle);
    v_last   := public.fn_clean_name_token(p_last);
    
    RETURN coalesce(v_last, '') || '|' || coalesce(v_first, '') || '|' || coalesce(v_middle, '');
  END IF;

  v_raw := trim(coalesce(p_raw_full, ''));
  IF v_raw = '' THEN
    RETURN '';
  END IF;

  -- If raw contains comma: "LAST, FIRST MIDDLE" (standard Plantilla format)
  IF position(',' IN v_raw) > 0 THEN
    v_parts  := string_to_array(v_raw, ',');
    v_last   := public.fn_clean_name_token(v_parts[1]);
    v_tokens := regexp_split_to_array(trim(coalesce(v_parts[2], '')), '\s+');
    
    v_first := NULL;
    v_middle := NULL;
    
    IF array_length(v_tokens, 1) >= 1 THEN
      v_first := public.fn_clean_name_token(v_tokens[1]);
      IF array_length(v_tokens, 1) >= 2 THEN
        -- Remaining tokens form middle name
        FOR i IN 2..array_length(v_tokens, 1) LOOP
          v_clean_t := public.fn_clean_name_token(v_tokens[i]);
          IF v_clean_t IS NOT NULL THEN
            IF v_middle IS NULL THEN
              v_middle := v_clean_t;
            ELSE
              v_middle := v_middle || ' ' || v_clean_t;
            END IF;
          END IF;
        END LOOP;
      END IF;
    END IF;
    
    RETURN coalesce(v_last, '') || '|' || coalesce(v_first, '') || '|' || coalesce(v_middle, '');
  ELSE
    -- No comma: "FIRST MIDDLE LAST" (hr_emploc format)
    v_tokens := regexp_split_to_array(v_raw, '\s+');
    IF array_length(v_tokens, 1) = 1 THEN
      v_clean_t := public.fn_clean_name_token(v_tokens[1]);
      RETURN coalesce(v_clean_t, '') || '|' || coalesce(v_clean_t, '') || '|';
    END IF;
    
    v_first := public.fn_clean_name_token(v_tokens[1]);
    v_last  := public.fn_clean_name_token(v_tokens[array_length(v_tokens, 1)]);
    v_middle := NULL;
    
    IF array_length(v_tokens, 1) > 2 THEN
      FOR i IN 2..(array_length(v_tokens, 1) - 1) LOOP
        v_clean_t := public.fn_clean_name_token(v_tokens[i]);
        IF v_clean_t IS NOT NULL THEN
          IF v_middle IS NULL THEN
            v_middle := v_clean_t;
          ELSE
            v_middle := v_middle || ' ' || v_clean_t;
          END IF;
        END IF;
      END LOOP;
    END IF;
    
    RETURN coalesce(v_last, '') || '|' || coalesce(v_first, '') || '|' || coalesce(v_middle, '');
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_match_person_name(
  p_norm1 text,
  p_norm2 text
)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE PARALLEL SAFE
AS $$
DECLARE
  v_p1_parts  text[];
  v_p2_parts  text[];
  v_last1     text;
  v_first1    text;
  v_middle1   text;
  v_last2     text;
  v_first2    text;
  v_middle2   text;
  v_is_alias  boolean := false;
BEGIN
  IF p_norm1 = p_norm2 THEN
    RETURN jsonb_build_object('match', true, 'type', 'EXACT', 'reason', 'Identical normalized key');
  END IF;

  v_p1_parts := string_to_array(p_norm1, '|');
  v_p2_parts := string_to_array(p_norm2, '|');
  
  v_last1   := coalesce(v_p1_parts[1], '');
  v_first1  := coalesce(v_p1_parts[2], '');
  v_middle1 := coalesce(v_p1_parts[3], '');
  
  v_last2   := coalesce(v_p2_parts[1], '');
  v_first2  := coalesce(v_p2_parts[2], '');
  v_middle2 := coalesce(v_p2_parts[3], '');

  -- Check registered alias for Hautea / Huatea
  IF (v_last1 IN ('HAUTEA', 'HUATEA') AND v_last2 IN ('HAUTEA', 'HUATEA'))
     AND v_first1 = v_first2 THEN
    RETURN jsonb_build_object('match', true, 'type', 'ALIAS_MATCH', 'reason', 'Registered name alias (Hautea/Huatea)');
  END IF;

  IF v_last1 <> v_last2 THEN
    RETURN jsonb_build_object('match', false, 'type', 'DIFFERENT_LAST_NAME', 'reason', 'Last names do not match');
  END IF;

  IF v_first1 <> v_first2 THEN
    RETURN jsonb_build_object('match', false, 'type', 'DIFFERENT_FIRST_NAME', 'reason', 'First names do not match');
  END IF;

  -- Middle name rules
  IF v_middle1 <> '' AND v_middle2 <> '' THEN
    IF v_middle1 = v_middle2 THEN
      RETURN jsonb_build_object('match', true, 'type', 'EXACT', 'reason', 'Full name match');
    END IF;
    -- Initial match
    IF (length(v_middle1) = 1 AND starts_with(v_middle2, v_middle1)) OR
       (length(v_middle2) = 1 AND starts_with(v_middle1, v_middle2)) THEN
      RETURN jsonb_build_object('match', true, 'type', 'INITIAL_MATCH', 'reason', 'Middle initial matches full middle name');
    END IF;
    RETURN jsonb_build_object('match', false, 'type', 'DIFFERENT_MIDDLE_NAME', 'reason', 'Different middle names');
  END IF;

  IF v_middle1 = '' AND v_middle2 = '' THEN
    RETURN jsonb_build_object('match', true, 'type', 'EXACT_NO_MIDDLE', 'reason', 'Both missing middle name');
  END IF;

  -- One side missing middle -> matches with warning
  RETURN jsonb_build_object('match', true, 'type', 'WARNING_MISSING_MIDDLE', 'reason', 'One record missing middle name');
END;
$$;


-- SECTION 2: PERMANENT EMPLOYEE NUMBER REGISTRY & CONFLICTS
-- ====================================================================

CREATE TABLE IF NOT EXISTS public.employee_number_registry (
  emploc_no            text PRIMARY KEY,
  normalized_name      text NOT NULL,
  display_name         text NOT NULL,
  status               text NOT NULL CHECK (status IN ('assigned', 'released', 'rehire_reused')),
  aliases              text[] NOT NULL DEFAULT '{}'::text[],
  alias_of             text DEFAULT NULL,
  history              jsonb NOT NULL DEFAULT '[]'::jsonb,
  first_assigned_at    timestamptz NOT NULL DEFAULT now(),
  first_assigned_by    uuid,
  last_assigned_at     timestamptz NOT NULL DEFAULT now(),
  last_assigned_by     uuid,
  source_hr_emploc_id  uuid,
  source_plantilla_id  uuid,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_emploc_registry_normalized_name 
  ON public.employee_number_registry (normalized_name);

CREATE TABLE IF NOT EXISTS public.registry_conflicts (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_no          text NOT NULL,
  record_type          text NOT NULL,
  record_id            uuid NOT NULL,
  display_name         text,
  normalized_name      text,
  conflict_reason      text NOT NULL,
  conflict_details     jsonb NOT NULL DEFAULT '{}'::jsonb,
  resolved_at          timestamptz,
  resolved_by          uuid,
  resolution_notes     text,
  created_at           timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.registry_name_aliases (
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  normalized_name        text NOT NULL,
  alias_normalized_name  text NOT NULL,
  reason                 text NOT NULL,
  created_at             timestamptz NOT NULL DEFAULT now()
);

-- Enable RLS: direct DML forbidden, authenticated/anon can only SELECT
ALTER TABLE public.employee_number_registry ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.registry_conflicts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.registry_name_aliases ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'employee_number_registry' AND policyname = 'p_select_employee_number_registry'
  ) THEN
    CREATE POLICY p_select_employee_number_registry ON public.employee_number_registry
      FOR SELECT TO authenticated, anon USING (true);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'registry_conflicts' AND policyname = 'p_select_registry_conflicts'
  ) THEN
    CREATE POLICY p_select_registry_conflicts ON public.registry_conflicts
      FOR SELECT TO authenticated USING (true);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'registry_name_aliases' AND policyname = 'p_select_registry_name_aliases'
  ) THEN
    CREATE POLICY p_select_registry_name_aliases ON public.registry_name_aliases
      FOR SELECT TO authenticated USING (true);
  END IF;
END $$;

-- Super Admin management function for typos/aliases in registry
CREATE OR REPLACE FUNCTION public.admin_correct_registry_name(
  p_employee_no text,
  p_new_display_name text,
  p_new_normalized_name text,
  p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_actor_profile_id uuid := public.get_my_profile_id();
  v_clean_no text := btrim(coalesce(p_employee_no, ''));
  v_old public.employee_number_registry;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'forbidden: Super Admin required to edit registry' USING ERRCODE = '42501';
  END IF;

  IF coalesce(btrim(p_reason), '') = '' THEN
    RAISE EXCEPTION 'reason is required for registry modification' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_old FROM public.employee_number_registry WHERE emploc_no = v_clean_no FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Registry record for % not found', v_clean_no USING ERRCODE = 'P0002';
  END IF;

  UPDATE public.employee_number_registry
  SET display_name    = p_new_display_name,
      normalized_name = p_new_normalized_name,
      history         = history || jsonb_build_object(
        'action', 'admin_correct_name',
        'actor', v_actor_profile_id,
        'timestamp', now(),
        'old_display', v_old.display_name,
        'new_display', p_new_display_name,
        'old_norm', v_old.normalized_name,
        'new_norm', p_new_normalized_name,
        'reason', p_reason
      ),
      updated_at      = now()
  WHERE emploc_no = v_clean_no;

  PERFORM public.log_audit_event(
    'employee_number_registry',
    'UPDATE',
    v_old.source_hr_emploc_id,
    to_jsonb(v_old),
    jsonb_build_object('emploc_no', v_clean_no, 'reason', p_reason, 'action', 'admin_correct_name')
  );

  RETURN jsonb_build_object('status', 'ok', 'emploc_no', v_clean_no);
END;
$$;


-- SECTION 3: BACKFILL STAGING REGISTRY APPLYING OHM'S DECISIONS
-- ====================================================================

-- Register alias Hautea / Huatea
INSERT INTO public.registry_name_aliases (normalized_name, alias_normalized_name, reason)
VALUES ('HUATEA|EDGIE|MENDOZA', 'HAUTEA|EDGIE|MENDOZA', 'Decision 5: Huatea vs Hautea alias mapping')
ON CONFLICT DO NOTHING;

DO $$
DECLARE
  r RECORD;
  v_norm text;
  v_display text;
BEGIN
  -- Backfill from plantilla rows (earliest first)
  FOR r IN (
    SELECT 
      p.id,
      btrim(p.employee_no) as emp_no,
      p.employee_name,
      p.first_name,
      p.middle_name,
      p.last_name,
      p.status,
      p.created_at,
      p.created_by,
      p.hr_emploc_id
    FROM public.plantilla p
    WHERE p.employee_no IS NOT NULL 
      AND btrim(p.employee_no) <> ''
      AND btrim(p.employee_no) <> '(PENDING)'
    ORDER BY p.created_at ASC
  ) LOOP
    v_norm := public.fn_normalize_person_name(r.first_name, r.middle_name, r.last_name, NULL, r.employee_name);
    v_display := coalesce(r.employee_name, r.last_name || ', ' || r.first_name);

    -- Special handling for Decision 4: 2026-08678
    IF r.emp_no = '2026-08678' AND v_norm LIKE '%DELA CRUZ%' THEN
      -- Later assignee: log as conflict, do not insert to registry
      INSERT INTO public.registry_conflicts (
        employee_no, record_type, record_id, display_name, normalized_name, conflict_reason, conflict_details
      ) VALUES (
        r.emp_no, 'plantilla', r.id, v_display, v_norm,
        'Decision 4: Earliest owner is Babia, Frak Dave. Dela Cruz, Juan Santos recorded for manual resolution.',
        jsonb_build_object('plantilla_id', r.id, 'status', r.status, 'created_at', r.created_at)
      ) ON CONFLICT DO NOTHING;
      CONTINUE;
    END IF;

    -- Upsert into registry
    INSERT INTO public.employee_number_registry (
      emploc_no, normalized_name, display_name, status,
      first_assigned_at, first_assigned_by, last_assigned_at, last_assigned_by,
      source_plantilla_id, source_hr_emploc_id
    ) VALUES (
      r.emp_no, v_norm, v_display, 'assigned',
      r.created_at, r.created_by, r.created_at, r.created_by,
      r.id, r.hr_emploc_id
    )
    ON CONFLICT (emploc_no) DO UPDATE SET
      last_assigned_at = EXCLUDED.last_assigned_at,
      source_plantilla_id = COALESCE(public.employee_number_registry.source_plantilla_id, EXCLUDED.source_plantilla_id);
  END LOOP;

  -- Backfill from hr_emploc (already moved/deployed rows)
  FOR r IN (
    SELECT 
      h.id,
      btrim(coalesce(h.employee_no, h.emploc_no)) as emp_no,
      h.applicant_name,
      h.employee_name_snapshot,
      h.created_at,
      h.created_by,
      a.first_name as app_first,
      a.middle_name as app_middle,
      a.last_name as app_last
    FROM public.hr_emploc h
    LEFT JOIN public.applicants a ON a.id = h.applicant_id
    WHERE (h.employee_no IS NOT NULL OR h.emploc_no IS NOT NULL)
      AND btrim(coalesce(h.employee_no, h.emploc_no)) <> ''
      AND btrim(coalesce(h.employee_no, h.emploc_no)) <> '(PENDING)'
      AND h.status = 'Moved to Plantilla'
    ORDER BY h.created_at ASC
  ) LOOP
    v_norm := public.fn_normalize_person_name(r.app_first, r.app_middle, r.app_last, NULL, coalesce(r.employee_name_snapshot, r.applicant_name));
    v_display := coalesce(r.employee_name_snapshot, r.applicant_name);

    INSERT INTO public.employee_number_registry (
      emploc_no, normalized_name, display_name, status,
      first_assigned_at, first_assigned_by, last_assigned_at, last_assigned_by,
      source_hr_emploc_id
    ) VALUES (
      r.emp_no, v_norm, v_display, 'assigned',
      r.created_at, r.created_by, r.created_at, r.created_by,
      r.id
    )
    ON CONFLICT (emploc_no) DO UPDATE SET
      source_hr_emploc_id = COALESCE(public.employee_number_registry.source_hr_emploc_id, EXCLUDED.source_hr_emploc_id);
  END LOOP;
END $$;


-- SECTION 4: ROLE GATE HELPER FUNCTIONS
-- ====================================================================

-- 1. can_tag_or_review_hr_emploc
-- Role: HR Personnel (+SA) ONLY. Head Admin and Encoder NOT allowed.
CREATE OR REPLACE FUNCTION public.can_tag_or_review_hr_emploc()
RETURNS boolean
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  IF public.is_super_admin() THEN
    RETURN true;
  END IF;
  RETURN public.i_am_hr_dept();
END;
$$;

-- 2. can_assign_pending_hr_emploc
-- Role: HR Personnel, Head Admin, Encoder (+SA).
CREATE OR REPLACE FUNCTION public.can_assign_pending_hr_emploc()
RETURNS boolean
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  IF public.is_super_admin() OR public.i_have_full_access() THEN
    RETURN true;
  END IF;
  IF public.i_am_hr_dept() OR public.get_my_role() = 'Encoder' THEN
    RETURN true;
  END IF;
  RETURN false;
END;
$$;

-- 3. can_submit_hr_emploc_correction
-- Role: Ops only: OM, TL, ATL, HRCO (+SA). HA, Encoder, HR Personnel NOT allowed.
CREATE OR REPLACE FUNCTION public.can_submit_hr_emploc_correction()
RETURNS boolean
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  IF public.is_super_admin() THEN
    RETURN true;
  END IF;
  RETURN public.i_am_ops();
END;
$$;

-- 4. can_edit_deployed_hr_emploc
-- Role: Data Team: Encoder, Head Admin (+SA) ONLY. HR Personnel NOT allowed.
CREATE OR REPLACE FUNCTION public.can_edit_deployed_hr_emploc()
RETURNS boolean
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  IF public.is_super_admin() OR public.i_have_full_access() THEN
    RETURN true;
  END IF;
  IF public.get_my_role() = 'Encoder' THEN
    RETURN true;
  END IF;
  RETURN false;
END;
$$;

REVOKE ALL ON FUNCTION public.can_tag_or_review_hr_emploc() FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.can_tag_or_review_hr_emploc() TO authenticated;

REVOKE ALL ON FUNCTION public.can_assign_pending_hr_emploc() FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.can_assign_pending_hr_emploc() TO authenticated;

REVOKE ALL ON FUNCTION public.can_submit_hr_emploc_correction() FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.can_submit_hr_emploc_correction() TO authenticated;

REVOKE ALL ON FUNCTION public.can_edit_deployed_hr_emploc() FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.can_edit_deployed_hr_emploc() TO authenticated;


-- SECTION 5: SHARED PRIVATE INTERNAL CORE
-- ====================================================================

CREATE OR REPLACE FUNCTION public._assign_and_deploy_emploc_core(
  p_hr_emploc_id       uuid,
  p_employee_no        text,
  p_confirm_reuse      boolean DEFAULT false,
  p_reuse_reason       text DEFAULT NULL,
  p_actor_profile_id   uuid DEFAULT NULL,
  p_source_fn          text DEFAULT 'assign_and_deploy_core'
)
RETURNS public.plantilla
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_actor_profile_id uuid := COALESCE(p_actor_profile_id, public.get_my_profile_id());
  v_actor_name       text := public.get_my_full_name();
  v_clean_id         text := btrim(COALESCE(p_employee_no, ''));
  v_emp              public.hr_emploc;
  v_app              public.applicants;
  v_pl               public.plantilla;
  v_existing_pl      public.plantilla;
  v_slot_id          uuid := NULL;
  v_slot_auth        jsonb;
  v_pool_slot_id     uuid := NULL;
  v_is_pool          boolean := false;
  v_pool_type_id     uuid;
  v_home_account_id  uuid;
  v_home_acct        public.accounts;
  v_formatted_name   text;
  v_norm_name        text;
  v_reg              public.employee_number_registry;
  v_match            jsonb;
  v_is_rehire        boolean := false;
  v_dup_reg          public.employee_number_registry;
BEGIN
  -- 1. Format validation
  IF v_clean_id = '' OR v_clean_id !~ '^[A-Za-z0-9._-]+$' THEN
    RAISE EXCEPTION 'EMPLOYEE_NO_FORMAT_INVALID: Employee number "%" is invalid. Allowed: alphanumeric, dots, underscores, dashes.', v_clean_id
      USING ERRCODE = '22023';
  END IF;

  -- 2. Pending deletion lock
  IF EXISTS (
    SELECT 1 FROM public.hr_emploc_deletion_requests
    WHERE hr_emploc_id = p_hr_emploc_id AND status = 'Pending'
  ) THEN
    RAISE EXCEPTION 'ACTION_LOCKED_PENDING_DELETION: An active deletion request exists for this record.'
      USING ERRCODE = 'P0001';
  END IF;

  -- 3. Lock hr_emploc record
  SELECT * INTO v_emp FROM public.hr_emploc WHERE id = p_hr_emploc_id FOR UPDATE;
  IF NOT FOUND OR v_emp.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'hr_emploc record % not found or archived', p_hr_emploc_id
      USING ERRCODE = 'P0002';
  END IF;

  -- Safe idempotent no-op check: already moved with same number
  IF v_emp.status = 'Moved to Plantilla' AND v_emp.employee_no = v_clean_id THEN
    SELECT * INTO v_existing_pl 
    FROM public.plantilla 
    WHERE hr_emploc_id = p_hr_emploc_id 
      AND COALESCE(is_deleted, false) = false
    LIMIT 1;
    IF FOUND THEN
      RETURN v_existing_pl;
    END IF;
  END IF;

  -- Fetch structured applicant data
  IF v_emp.applicant_id IS NOT NULL THEN
    SELECT * INTO v_app FROM public.applicants WHERE id = v_emp.applicant_id;
  END IF;

  -- 4. REQUIRED PLANTILLA FIELDS VALIDATION (NO SILENT DEFAULTS)
  IF v_emp.hired_date IS NULL THEN
    RAISE EXCEPTION 'FIELD_REQUIRED_MISSING: hired_date is required before deployment to Plantilla'
      USING ERRCODE = '22023';
  END IF;

  IF (v_app.first_name IS NULL OR btrim(v_app.first_name) = '') OR 
     (v_app.last_name IS NULL OR btrim(v_app.last_name) = '') THEN
    IF v_emp.employee_name_snapshot IS NULL OR btrim(v_emp.employee_name_snapshot) = '' THEN
      RAISE EXCEPTION 'FIELD_REQUIRED_MISSING: applicant first_name and last_name are required'
        USING ERRCODE = '22023';
    END IF;
  END IF;

  IF v_emp.account_id IS NULL AND (v_emp.account IS NULL OR btrim(v_emp.account) = '') THEN
    RAISE EXCEPTION 'FIELD_REQUIRED_MISSING: account is required'
      USING ERRCODE = '22023';
  END IF;

  IF v_emp.position IS NULL OR btrim(v_emp.position) = '' THEN
    RAISE EXCEPTION 'FIELD_REQUIRED_MISSING: position is required'
      USING ERRCODE = '22023';
  END IF;

  IF COALESCE(v_emp.assignment_type, 'Stationary') <> 'Roving' AND v_emp.coverage_slot_id IS NULL THEN
    IF v_emp.store_id IS NULL THEN
      RAISE EXCEPTION 'FIELD_REQUIRED_MISSING: store is required for stationary deployment'
        USING ERRCODE = '22023';
    END IF;
  END IF;

  -- Resolve canonical formatted name and normalized name
  IF v_app.last_name IS NOT NULL AND v_app.first_name IS NOT NULL THEN
    v_formatted_name := v_app.last_name || ', ' || v_app.first_name || COALESCE(' ' || NULLIF(btrim(v_app.middle_name), ''), '');
    v_norm_name      := public.fn_normalize_person_name(v_app.first_name, v_app.middle_name, v_app.last_name, NULL, NULL);
  ELSE
    v_formatted_name := COALESCE(v_emp.employee_name_snapshot, v_emp.applicant_name);
    v_norm_name      := public.fn_normalize_person_name(NULL, NULL, NULL, NULL, v_formatted_name);
  END IF;

  -- 5. REGISTRY RACE-SAFE CHECK UNDER FOR UPDATE LOCK
  SELECT * INTO v_reg 
  FROM public.employee_number_registry 
  WHERE emploc_no = v_clean_id 
  FOR UPDATE;

  IF FOUND THEN
    IF v_reg.status IN ('assigned', 'rehire_reused') THEN
      v_match := public.fn_match_person_name(v_reg.normalized_name, v_norm_name);
      
      -- Rule a: Number registered to a different person -> HARD BLOCK
      IF (v_match->>'match')::boolean = false THEN
        RAISE EXCEPTION 'EMPLOYEE_NO_ALREADY_ASSIGNED: Employee number % is permanently registered to %',
          v_clean_id, v_reg.display_name
          USING ERRCODE = '23505',
                DETAIL = jsonb_build_object(
                  'employee_no', v_clean_id,
                  'registered_to', v_reg.display_name,
                  'registered_norm', v_reg.normalized_name,
                  'incoming_name', v_formatted_name,
                  'reason', v_match->>'reason'
                )::text;
      END IF;

      -- Rule b: Same person, but prior row is ACTIVE -> HARD BLOCK
      IF EXISTS (
        SELECT 1 FROM public.plantilla p
        WHERE (p.employee_no = v_clean_id OR p.emploc_no = v_clean_id)
          AND p.status IN ('Active', 'On Leave', 'For Deactivation')
          AND COALESCE(p.is_deleted, false) = false
          AND (p.hr_emploc_id IS NULL OR p.hr_emploc_id <> p_hr_emploc_id)
      ) OR EXISTS (
        SELECT 1 FROM public.hr_emploc h
        WHERE (h.employee_no = v_clean_id OR h.emploc_no = v_clean_id)
          AND h.status NOT IN ('Backout', 'Moved to Plantilla')
          AND h.id <> p_hr_emploc_id
          AND h.deleted_at IS NULL
      ) THEN
        RAISE EXCEPTION 'EMPLOYEE_ALREADY_ACTIVE: % already has an active placement or active Plantilla record with number %',
          v_formatted_name, v_clean_id
          USING ERRCODE = '23505',
                DETAIL = jsonb_build_object(
                  'employee_no', v_clean_id,
                  'person', v_formatted_name
                )::text;
      END IF;

      -- Rule c: Same person, prior row is inactive -> requires confirm (rehire reuse)
      IF NOT p_confirm_reuse OR coalesce(btrim(p_reuse_reason), '') = '' THEN
        RAISE EXCEPTION 'REHIRE_CONFIRM_REQUIRED: % was previously assigned number %. Confirm rehire reuse with reason.',
          v_formatted_name, v_clean_id
          USING ERRCODE = '23505',
                DETAIL = jsonb_build_object(
                  'code', 'REHIRE_CONFIRM_REQUIRED',
                  'employee_no', v_clean_id,
                  'display_name', v_reg.display_name,
                  'first_assigned_at', v_reg.first_assigned_at,
                  'status', v_reg.status
                )::text;
      END IF;
      v_is_rehire := true;
    END IF;
  END IF;

  -- Rule d: Same person already owns another number in the registry
  SELECT * INTO v_dup_reg
  FROM public.employee_number_registry
  WHERE normalized_name = v_norm_name
    AND emploc_no <> v_clean_id
    AND status IN ('assigned', 'rehire_reused')
  LIMIT 1;

  IF FOUND THEN
    IF NOT p_confirm_reuse OR coalesce(btrim(p_reuse_reason), '') = '' THEN
      RAISE EXCEPTION 'POSSIBLE_DUPLICATE_PERSON: % is already registered with Employee number %. Confirm duplicate assignment with reason.',
        v_formatted_name, v_dup_reg.emploc_no
        USING ERRCODE = '23505',
              DETAIL = jsonb_build_object(
                'code', 'POSSIBLE_DUPLICATE_PERSON',
                'new_employee_no', v_clean_id,
                'existing_employee_no', v_dup_reg.emploc_no,
                'display_name', v_dup_reg.display_name
              )::text;
    END IF;
  END IF;

  -- 6. SLOT SELECTION AND RESERVATION (Stationary non-pool non-roving)
  IF v_emp.vacancy_id IS NOT NULL THEN
    SELECT v.is_pool_vacancy, v.pool_type_id, v.home_account_id
      INTO v_is_pool, v_pool_type_id, v_home_account_id
      FROM vacancies v
     WHERE v.id = v_emp.vacancy_id;
  END IF;
  v_is_pool := COALESCE(v_is_pool, false);

  IF NOT v_is_pool AND COALESCE(v_emp.assignment_type, 'Stationary') <> 'Roving' AND v_emp.coverage_slot_id IS NULL THEN
    SELECT id INTO v_slot_id
    FROM public.plantilla_slots
    WHERE legacy_vcode = v_emp.vcode
      AND slot_status = 'open'
    ORDER BY created_at ASC
    LIMIT 1
    FOR UPDATE SKIP LOCKED;

    IF v_slot_id IS NULL THEN
      IF v_emp.slot_id IS NOT NULL THEN
        SELECT id INTO v_slot_id
        FROM public.plantilla_slots
        WHERE id = v_emp.slot_id
          AND slot_status IN ('open', 'hr_processing')
        FOR UPDATE SKIP LOCKED;
      END IF;

      IF v_slot_id IS NULL THEN
        RAISE EXCEPTION 'SLOT_UNAVAILABLE: No available headcount slot for VCode %', v_emp.vcode
          USING ERRCODE = '22023';
      END IF;
    END IF;

    -- Reserve slot first
    v_slot_auth := public.fn_set_slot_status(
      p_slot_id      => v_slot_id,
      p_new_status   => 'hr_processing',
      p_reason_code  => NULL,
      p_performed_by => v_actor_profile_id,
      p_remarks      => 'auto_move_to_plantilla: reserved for hr_emploc ' || p_hr_emploc_id::text
    );
    IF (v_slot_auth->>'status') NOT IN ('ok', 'no_op') THEN
      RAISE EXCEPTION 'SLOT_UNAVAILABLE: Slot % reservation blocked: %',
        v_slot_id, COALESCE(v_slot_auth->>'blocked_reason', 'unknown')
        USING ERRCODE = '22023';
    END IF;
  END IF;

  -- 7. INSERT INTO PLANTILLA
  IF v_is_pool THEN
    SELECT * INTO v_home_acct FROM accounts WHERE id = v_home_account_id;

    INSERT INTO plantilla (
      account,              account_id,
      store_id,             store_name,
      position,             position_id,
      employee_no,          emploc_no,
      employee_name,        employee_name_snapshot,
      first_name,           middle_name,             last_name,
      civil_status,         date_of_birth,
      sss_no,               philhealth_no,          pagibig_no,
      date_hired,           vacancy_id,              vacancy_code_snapshot,
      vcode,
      hrco_name,            hrco_user_id_snapshot,
      om_user_id_snapshot,  atl_user_id_snapshot,
      area,                 area_name_snapshot,
      hr_emploc_id,
      is_pool_employee,     pool_type_id,
      requesting_account,   requesting_account_id,   requesting_store_id,
      status,               tagged_at,
      moved_by_user_id,     created_by,              updated_by,
      created_at,           updated_at
    )
    VALUES (
      v_home_acct.account_name, v_home_acct.id,
      NULL, NULL,
      v_emp.position,           v_emp.position_id_snapshot,
      v_clean_id,               v_clean_id,
      v_formatted_name,         v_formatted_name,
      v_app.first_name,         v_app.middle_name,       v_app.last_name,
      v_emp.civil_status_snapshot, v_emp.birthdate_snapshot,
      v_emp.sss_snapshot,       v_emp.philhealth_snapshot,    v_emp.pagibig_snapshot,
      v_emp.hired_date,         v_emp.vacancy_id,             v_emp.vacancy_code_snapshot,
      v_emp.vcode,
      v_emp.hrco_name,          v_emp.hrco_user_id_snapshot,
      v_emp.om_user_id_snapshot, v_emp.atl_user_id_snapshot,
      v_emp.area_name_snapshot,  v_emp.area_name_snapshot,
      v_emp.id,
      true,                     v_pool_type_id,
      v_emp.account,            v_emp.account_id,             v_emp.store_id,
      'Active',                 CURRENT_DATE,
      v_actor_profile_id, v_actor_profile_id, v_actor_profile_id,
      NOW(), NOW()
    )
    RETURNING * INTO v_pl;

  ELSIF COALESCE(v_emp.assignment_type, 'Stationary') = 'Roving' THEN
    INSERT INTO plantilla (
      account,              account_id,           chain_id,             province_id,
      position,             position_id,
      employee_no,          emploc_no,
      employee_name,        employee_name_snapshot,
      first_name,           middle_name,          last_name,
      civil_status,         date_of_birth,
      sss_no,               philhealth_no,         pagibig_no,
      date_hired,
      hrco_name,            hrco_user_id_snapshot,
      om_user_id_snapshot,  atl_user_id_snapshot,
      area,                 area_name_snapshot,
      hr_emploc_id,
      roving_assignment_id,
      deployment_type,
      status,               tagged_at,
      moved_by_user_id,     created_by,            updated_by,
      created_at,           updated_at
    )
    VALUES (
      v_emp.account, v_emp.account_id, v_emp.chain_id, v_emp.province_id,
      v_emp.position, v_emp.position_id_snapshot,
      v_clean_id, v_clean_id,
      v_formatted_name, v_formatted_name,
      v_app.first_name, v_app.middle_name, v_app.last_name,
      v_emp.civil_status_snapshot, v_emp.birthdate_snapshot,
      v_emp.sss_snapshot, v_emp.philhealth_snapshot, v_emp.pagibig_snapshot,
      v_emp.hired_date,
      v_emp.hrco_name, v_emp.hrco_user_id_snapshot,
      v_emp.om_user_id_snapshot, v_emp.atl_user_id_snapshot,
      v_emp.area_name_snapshot, v_emp.area_name_snapshot,
      v_emp.id,
      v_emp.roving_assignment_id,
      'Roving',
      'Active', CURRENT_DATE,
      v_actor_profile_id, v_actor_profile_id, v_actor_profile_id,
      NOW(), NOW()
    )
    RETURNING * INTO v_pl;

  ELSE
    -- Pure stationary path
    INSERT INTO plantilla (
      account,              account_id,            chain_id,             store_id,
      store_name,           position,              position_id,
      province_id,
      employee_no,          emploc_no,
      employee_name,        employee_name_snapshot,
      first_name,           middle_name,           last_name,
      civil_status,         date_of_birth,
      sss_no,               philhealth_no,          pagibig_no,
      date_hired,           vacancy_id,              vacancy_code_snapshot,
      vcode,
      hrco_name,            hrco_user_id_snapshot,
      om_user_id_snapshot,  atl_user_id_snapshot,
      area,                 area_name_snapshot,
      hr_emploc_id,
      status,               tagged_at,
      moved_by_user_id,     created_by,              updated_by,
      created_at,           updated_at
    )
    VALUES (
      v_emp.account,        v_emp.account_id,       v_emp.chain_id,       v_emp.store_id,
      v_emp.store_name,     v_emp.position,         v_emp.position_id_snapshot,
      v_emp.province_id,
      v_clean_id,           v_clean_id,
      v_formatted_name,     v_formatted_name,
      v_app.first_name,     v_app.middle_name,      v_app.last_name,
      v_emp.civil_status_snapshot, v_emp.birthdate_snapshot,
      v_emp.sss_snapshot,   v_emp.philhealth_snapshot, v_emp.pagibig_snapshot,
      v_emp.hired_date,     v_emp.vacancy_id,        v_emp.vacancy_code_snapshot,
      v_emp.vcode,
      v_emp.hrco_name,      v_emp.hrco_user_id_snapshot,
      v_emp.om_user_id_snapshot, v_emp.atl_user_id_snapshot,
      v_emp.area_name_snapshot, v_emp.area_name_snapshot,
      v_emp.id,
      'Active',             CURRENT_DATE,
      v_actor_profile_id, v_actor_profile_id, v_actor_profile_id, NOW(), NOW()
    )
    RETURNING * INTO v_pl;
  END IF;

  -- 8. FINALIZE SLOT AS 'occupied' (RECONCILED VALUE)
  IF v_slot_id IS NOT NULL THEN
    v_slot_auth := public.fn_set_slot_status(
      p_slot_id               => v_slot_id,
      p_new_status            => 'occupied',
      p_reason_code           => NULL,
      p_performed_by          => v_actor_profile_id,
      p_remarks               => 'auto_move_to_plantilla: slot occupied by plantilla ' || v_pl.id::text,
      p_occupant_plantilla_id => v_pl.id
    );
    IF (v_slot_auth->>'status') NOT IN ('ok', 'no_op') THEN
      RAISE EXCEPTION 'SLOT_UNAVAILABLE: Slot % occupancy blocked: %',
        v_slot_id, COALESCE(v_slot_auth->>'blocked_reason', 'unknown')
        USING ERRCODE = '22023';
    END IF;
  END IF;

  -- 9. VACANCY CLOSURE (if all slots filled)
  IF NOT v_is_pool AND COALESCE(v_emp.assignment_type, 'Stationary') <> 'Roving' AND v_emp.coverage_slot_id IS NULL THEN
    IF v_emp.vacancy_id IS NOT NULL THEN
      UPDATE public.vacancies
         SET status     = 'Filled',
             updated_at = NOW(),
             updated_by = v_actor_profile_id
       WHERE id = v_emp.vacancy_id
         AND NOT EXISTS (
           SELECT 1 FROM public.plantilla_slots ps
           WHERE ps.legacy_vcode = v_emp.vcode
             AND ps.is_roving    = false
             AND ps.slot_status IN ('open', 'pipeline', 'hr_processing')
         );
    END IF;

    UPDATE public.vacancies
       SET status     = 'Filled',
           updated_at = NOW(),
           updated_by = v_actor_profile_id
     WHERE vcode      = v_emp.vcode
       AND status     IN ('Open', 'For Sourcing')
       AND COALESCE(is_archived, false) = false
       AND deleted_at IS NULL
       AND NOT EXISTS (
         SELECT 1 FROM public.plantilla_slots ps
         WHERE ps.legacy_vcode = v_emp.vcode
           AND ps.is_roving    = false
           AND ps.slot_status IN ('open', 'pipeline', 'hr_processing')
       );
  END IF;

  -- 10. UPDATE HR_EMPLOC STATUS (Final: Moved to Plantilla / Transferred)
  UPDATE public.hr_emploc
     SET employee_no           = v_clean_id,
         emploc_no             = v_clean_id,
         status                = 'Moved to Plantilla',
         hr_status             = 'Transferred',
         moved_to_plantilla_at = NOW(),
         moved_to_plantilla_by = v_actor_profile_id,
         updated_at            = NOW(),
         updated_by            = v_actor_profile_id
   WHERE id = p_hr_emploc_id;

  -- 11. STAMP REGISTRY
  INSERT INTO public.employee_number_registry (
    emploc_no, normalized_name, display_name, status,
    first_assigned_at, first_assigned_by, last_assigned_at, last_assigned_by,
    source_hr_emploc_id, source_plantilla_id,
    history
  ) VALUES (
    v_clean_id, v_norm_name, v_formatted_name, 
    CASE WHEN v_is_rehire THEN 'rehire_reused' ELSE 'assigned' END,
    NOW(), v_actor_profile_id, NOW(), v_actor_profile_id,
    p_hr_emploc_id, v_pl.id,
    jsonb_build_array(
      jsonb_build_object(
        'action', CASE WHEN v_is_rehire THEN 'rehire_reuse' ELSE 'initial_assignment' END,
        'actor', v_actor_profile_id,
        'timestamp', now(),
        'source', p_source_fn,
        'reuse_reason', p_reuse_reason
      )
    )
  )
  ON CONFLICT (emploc_no) DO UPDATE SET
    normalized_name     = EXCLUDED.normalized_name,
    display_name        = EXCLUDED.display_name,
    status              = EXCLUDED.status,
    last_assigned_at    = NOW(),
    last_assigned_by    = v_actor_profile_id,
    source_hr_emploc_id = p_hr_emploc_id,
    source_plantilla_id = v_pl.id,
    history             = public.employee_number_registry.history || EXCLUDED.history;

  -- 12. SINGLE AUDIT / TIMELINE LOG ENTRY
  PERFORM public.log_audit_event(
    'hr_emploc',
    'UPDATE',
    p_hr_emploc_id,
    to_jsonb(v_emp),
    jsonb_build_object(
      'action', 'assign_and_move_to_plantilla',
      'employee_no', v_clean_id,
      'plantilla_id', v_pl.id,
      'actor_name', v_actor_name,
      'actor_id', v_actor_profile_id,
      'source', p_source_fn,
      'log_message', format('Assigned Employee ID %s and automatically moved to Plantilla (Slot %s) by %s', v_clean_id, coalesce(v_slot_id::text, 'Pool/Roving'), v_actor_name)
    )
  );

  RETURN v_pl;

EXCEPTION WHEN OTHERS THEN
  -- Failure safety: revert temporary slot reservation
  IF v_slot_id IS NOT NULL THEN
    UPDATE public.plantilla_slots
    SET slot_status = 'open',
        updated_at  = NOW()
    WHERE id = v_slot_id AND slot_status = 'hr_processing';
  END IF;
  RAISE;
END;
$$;

-- Revoke all execute from anon, authenticated, PUBLIC for the private core
REVOKE ALL ON FUNCTION public._assign_and_deploy_emploc_core(uuid, text, boolean, text, uuid, text) FROM PUBLIC, anon, authenticated;


-- SECTION 6: THIN WRAPPER MOVE_TO_PLANTILLA (BACKWARD COMPATIBILITY)
-- ====================================================================

CREATE OR REPLACE FUNCTION public.move_to_plantilla(p_id uuid)
RETURNS public.plantilla
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_emp public.hr_emploc;
BEGIN
  -- Role Gate: Data Team (Encoder, HA) or SA
  IF NOT public.can_edit_deployed_hr_emploc() THEN
    RAISE EXCEPTION 'forbidden: Data Team role required' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_emp FROM public.hr_emploc WHERE id = p_id;
  IF NOT FOUND OR v_emp.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'hr_emploc % not found or archived', p_id USING ERRCODE = 'P0002';
  END IF;

  IF v_emp.employee_no IS NULL OR btrim(v_emp.employee_no) = '' THEN
    RAISE EXCEPTION 'cannot move: employee_no is null' USING ERRCODE = '22023';
  END IF;

  RETURN public._assign_and_deploy_emploc_core(
    p_hr_emploc_id     => p_id,
    p_employee_no      => v_emp.employee_no,
    p_confirm_reuse    => true,
    p_reuse_reason     => 'move_to_plantilla wrapper invocation',
    p_actor_profile_id => public.get_my_profile_id(),
    p_source_fn        => 'move_to_plantilla_wrapper'
  );
END;
$$;

REVOKE ALL ON FUNCTION public.move_to_plantilla(uuid) FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.move_to_plantilla(uuid) TO authenticated;


-- SECTION 7: UPDATED MUTATION RPCS
-- ====================================================================

-- 1. assign_hr_emploc_number (supports 2-arg caller for mobile compatibility via default params)
DROP FUNCTION IF EXISTS public.assign_hr_emploc_number(uuid, text);
DROP FUNCTION IF EXISTS public.assign_hr_emploc_number(uuid, text, boolean, text);

CREATE OR REPLACE FUNCTION public.assign_hr_emploc_number(
  p_id            uuid,
  p_employee_no   text,
  p_confirm_reuse boolean DEFAULT false,
  p_reuse_reason  text DEFAULT NULL
)
RETURNS public.hr_emploc
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_res public.hr_emploc;
BEGIN
  -- Gate: HR Personnel, Head Admin, Encoder, Super Admin
  IF NOT public.can_assign_pending_hr_emploc() THEN
    RAISE EXCEPTION 'forbidden: HR Personnel, Head Admin, Encoder, or Super Admin role required'
      USING ERRCODE = '42501';
  END IF;

  PERFORM public._assign_and_deploy_emploc_core(
    p_hr_emploc_id     => p_id,
    p_employee_no      => p_employee_no,
    p_confirm_reuse    => p_confirm_reuse,
    p_reuse_reason     => p_reuse_reason,
    p_actor_profile_id => public.get_my_profile_id(),
    p_source_fn        => 'assign_hr_emploc_number'
  );

  SELECT * INTO v_res FROM public.hr_emploc WHERE id = p_id;
  RETURN v_res;
END;
$$;

REVOKE ALL ON FUNCTION public.assign_hr_emploc_number(uuid, text, boolean, text) FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.assign_hr_emploc_number(uuid, text, boolean, text) TO authenticated;


-- 2. review_web_hr_emploc_correction
-- Drop old signatures to guarantee exactly one overload
DROP FUNCTION IF EXISTS public.review_web_hr_emploc_correction(uuid, text, jsonb, text);
DROP FUNCTION IF EXISTS public.review_web_hr_emploc_correction(uuid, text, jsonb, text, text);

CREATE OR REPLACE FUNCTION public.review_web_hr_emploc_correction(
  p_hr_emploc_id  uuid,
  p_decision      text,
  p_resolved_keys jsonb DEFAULT NULL,
  p_remarks       text  DEFAULT NULL,
  p_employee_no   text  DEFAULT NULL,
  p_confirm_reuse boolean DEFAULT false,
  p_reuse_reason  text  DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_auth_uid         uuid    := auth.uid();
  v_profile_id       uuid    := public.get_my_profile_id();
  v_actor_name       text    := public.get_my_full_name();
  v_old              public.hr_emploc;
  v_new              public.hr_emploc;
  v_decision         text;
  v_clean_remarks    text;
  v_clean_employee_no text;
  v_pl               public.plantilla;
BEGIN
  IF v_auth_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated: correction review requires a valid session'
      USING ERRCODE = '42501';
  END IF;

  -- Gate: HR Personnel (+SA) ONLY. Head Admin and Encoder NOT allowed.
  IF NOT public.can_tag_or_review_hr_emploc() THEN
    RAISE EXCEPTION 'forbidden: HR Personnel or Super Admin role required for correction review'
      USING ERRCODE = '42501';
  END IF;

  v_decision := lower(btrim(coalesce(p_decision, '')));
  IF v_decision NOT IN ('approve', 'return') THEN
    RAISE EXCEPTION 'invalid decision: must be "approve" or "return"'
      USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_old FROM public.hr_emploc WHERE id = p_hr_emploc_id FOR UPDATE;
  IF NOT FOUND OR v_old.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'forbidden: hr_emploc record not found or archived'
      USING ERRCODE = '42501';
  END IF;

  -- Pending deletion lock
  IF EXISTS (
    SELECT 1 FROM public.hr_emploc_deletion_requests dr
    WHERE dr.hr_emploc_id = p_hr_emploc_id AND dr.status = 'Pending'
  ) THEN
    RAISE EXCEPTION 'action locked: a pending deletion request exists for this record'
      USING ERRCODE = 'P0001';
  END IF;

  IF v_old.hr_status <> 'For Review' THEN
    RAISE EXCEPTION 'invalid state: record hr_status is "%", expected "For Review"', v_old.hr_status
      USING ERRCODE = '22023';
  END IF;

  v_clean_remarks := NULLIF(btrim(coalesce(p_remarks, '')), '');

  IF v_decision = 'approve' THEN
    v_clean_employee_no := NULLIF(btrim(coalesce(p_employee_no, '')), '');
    IF v_clean_employee_no IS NULL THEN
      RAISE EXCEPTION 'EMPLOYEE_NO_REQUIRED: Employee ID is required to approve correction and deploy to Plantilla'
        USING ERRCODE = '22023';
    END IF;

    -- Clear deficiencies and update review metadata
    UPDATE public.hr_emploc
       SET correction_reason      = NULL,
           hr_remarks             = v_clean_remarks,
           hr_reviewed_at         = now(),
           hr_reviewed_by         = v_actor_name,
           hr_reviewed_by_user_id = v_profile_id,
           updated_at             = now(),
           updated_by             = v_profile_id
     WHERE id = p_hr_emploc_id;

    -- Delegate to core: validates format, registry, required Plantilla fields, slot, and deploys atomically
    v_pl := public._assign_and_deploy_emploc_core(
      p_hr_emploc_id     => p_hr_emploc_id,
      p_employee_no      => v_clean_employee_no,
      p_confirm_reuse    => p_confirm_reuse,
      p_reuse_reason     => p_reuse_reason,
      p_actor_profile_id => v_profile_id,
      p_source_fn        => 'review_web_hr_emploc_correction_approve'
    );

    SELECT * INTO v_new FROM public.hr_emploc WHERE id = p_hr_emploc_id;

    RETURN jsonb_build_object(
      'status', 'ok',
      'decision', 'approve',
      'hr_emploc_id', p_hr_emploc_id,
      'hr_status', v_new.hr_status,
      'deployment_status', v_new.status,
      'employee_no', v_new.employee_no,
      'plantilla_id', v_pl.id
    );

  ELSE -- decision = 'return'
    IF v_clean_remarks IS NULL THEN
      RAISE EXCEPTION 'remarks are required when returning a correction'
        USING ERRCODE = '22023';
    END IF;

    UPDATE public.hr_emploc
       SET hr_status              = 'For Correction',
           hr_remarks             = v_clean_remarks,
           hr_reviewed_at         = now(),
           hr_reviewed_by         = v_actor_name,
           hr_reviewed_by_user_id = v_profile_id,
           updated_at             = now(),
           updated_by             = v_profile_id
     WHERE id = p_hr_emploc_id
     RETURNING * INTO v_new;

    PERFORM public.log_audit_event(
      'hr_emploc',
      'UPDATE',
      p_hr_emploc_id,
      to_jsonb(v_old),
      jsonb_build_object(
        'action', 'return_to_correction',
        'actor_name', v_actor_name,
        'actor_id', v_profile_id,
        'remarks', v_clean_remarks,
        'log_message', format('Returned correction to Ops with remarks: %s', v_clean_remarks)
      )
    );

    RETURN jsonb_build_object(
      'status', 'ok',
      'decision', 'return',
      'hr_emploc_id', p_hr_emploc_id,
      'hr_status', v_new.hr_status,
      'deployment_status', v_new.status
    );
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.review_web_hr_emploc_correction(uuid, text, jsonb, text, text, boolean, text) FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.review_web_hr_emploc_correction(uuid, text, jsonb, text, text, boolean, text) TO authenticated;


-- 3. tag_web_hr_emploc_deficiency Gate Update
CREATE OR REPLACE FUNCTION public.tag_web_hr_emploc_deficiency(
  p_hr_emploc_id uuid,
  p_deficiencies jsonb,
  p_remarks text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_auth_uid      uuid    := auth.uid();
  v_profile_id    uuid    := public.get_my_profile_id();
  v_actor_name    text    := public.get_my_full_name();
  v_old           public.hr_emploc;
  v_new           public.hr_emploc;
  v_issue         jsonb;
  v_code          text;
  v_comment       text;
  v_needs_comment boolean;
BEGIN
  IF v_auth_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated: deficiency tagging requires a valid session'
      USING ERRCODE = '42501';
  END IF;

  -- Gate: HR Personnel (+SA) ONLY. Head Admin and Encoder NOT allowed.
  IF NOT public.can_tag_or_review_hr_emploc() THEN
    RAISE EXCEPTION 'forbidden: HR Personnel or Super Admin role required for deficiency tagging'
      USING ERRCODE = '42501';
  END IF;

  IF p_deficiencies IS NULL
     OR jsonb_typeof(p_deficiencies) <> 'array'
     OR jsonb_array_length(p_deficiencies) = 0 THEN
    RAISE EXCEPTION 'p_deficiencies must be a non-empty JSONB array of {code, comment} objects'
      USING ERRCODE = '22023';
  END IF;

  FOR v_issue IN SELECT * FROM jsonb_array_elements(p_deficiencies) LOOP
    v_code    := NULLIF(BTRIM(COALESCE(v_issue->>'code', '')), '');
    v_comment := BTRIM(COALESCE(v_issue->>'comment', ''));

    IF v_code IS NULL THEN
      RAISE EXCEPTION 'each deficiency must contain a non-empty code'
        USING ERRCODE = '22023';
    END IF;

    SELECT it.requires_comment INTO v_needs_comment
    FROM   public.hr_emploc_issue_types it
    WHERE  it.code = v_code AND it.is_active = TRUE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'unknown or inactive deficiency code: %', v_code
        USING ERRCODE = '22023';
    END IF;

    IF v_needs_comment AND (v_comment IS NULL OR v_comment = '') THEN
      RAISE EXCEPTION 'deficiency code % requires a non-empty comment', v_code
        USING ERRCODE = '22023';
    END IF;
  END LOOP;

  SELECT * INTO v_old
  FROM   public.hr_emploc
  WHERE  id = p_hr_emploc_id
  FOR UPDATE;

  IF NOT FOUND OR v_old.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'forbidden: hr_emploc record not found or archived'
      USING ERRCODE = '42501';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.hr_emploc_deletion_requests dr
    WHERE dr.hr_emploc_id = p_hr_emploc_id AND dr.status = 'Pending'
  ) THEN
    RAISE EXCEPTION 'action locked: a pending deletion request exists for this record'
      USING ERRCODE = 'P0001';
  END IF;

  IF v_old.status = 'Moved to Plantilla' OR v_old.hr_status = 'Transferred' THEN
    RAISE EXCEPTION 'invalid state: cannot tag deficiency on record already deployed to Plantilla'
      USING ERRCODE = '22023';
  END IF;

  UPDATE public.hr_emploc
  SET    hr_status              = 'For Correction',
         correction_reason      = p_deficiencies,
         hr_remarks             = NULLIF(BTRIM(COALESCE(p_remarks, '')), ''),
         hr_reviewed_at         = now(),
         hr_reviewed_by         = v_actor_name,
         hr_reviewed_by_user_id = v_profile_id,
         updated_at             = now(),
         updated_by             = v_profile_id
  WHERE  id = p_hr_emploc_id
  RETURNING * INTO v_new;

  PERFORM public.log_audit_event(
    'hr_emploc',
    'UPDATE',
    p_hr_emploc_id,
    to_jsonb(v_old),
    jsonb_build_object(
      'action', 'tag_deficiency',
      'deficiencies', p_deficiencies,
      'remarks', p_remarks,
      'actor_name', v_actor_name,
      'actor_id', v_profile_id,
      'log_message', format('Tagged %s deficiency items by %s', jsonb_array_length(p_deficiencies), v_actor_name)
    )
  );

  RETURN jsonb_build_object(
    'status', 'ok',
    'hr_emploc_id', p_hr_emploc_id,
    'hr_status', v_new.hr_status,
    'correction_reason', v_new.correction_reason
  );
END;
$$;

REVOKE ALL ON FUNCTION public.tag_web_hr_emploc_deficiency(uuid, jsonb, text) FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.tag_web_hr_emploc_deficiency(uuid, jsonb, text) TO authenticated;


-- 4. mark_for_correction Gate Update
CREATE OR REPLACE FUNCTION public.mark_for_correction(
  p_id uuid,
  p_issues jsonb,
  p_hr_remarks text DEFAULT NULL::text
)
RETURNS public.hr_emploc
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_old     public.hr_emploc;
  v_new     public.hr_emploc;
BEGIN
  -- Gate: HR Personnel (+SA) ONLY.
  IF NOT public.can_tag_or_review_hr_emploc() THEN
    RAISE EXCEPTION 'forbidden: HR Dept role required' USING ERRCODE = '42501';
  END IF;

  PERFORM public.tag_web_hr_emploc_deficiency(p_id, p_issues, p_hr_remarks);
  SELECT * INTO v_new FROM public.hr_emploc WHERE id = p_id;
  RETURN v_new;
END;
$$;

REVOKE ALL ON FUNCTION public.mark_for_correction(uuid, jsonb, text) FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.mark_for_correction(uuid, jsonb, text) TO authenticated;


-- 5. submit_hrco_correction_update Gate Update
CREATE OR REPLACE FUNCTION public.submit_hrco_correction_update(
  p_correction_request_id uuid,
  p_hrco_notes text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  -- Gate: Ops only: OM, TL, ATL, HRCO (+SA). HA, Encoder, HR Personnel NOT allowed.
  IF NOT public.can_submit_hr_emploc_correction() THEN
    RAISE EXCEPTION 'forbidden: Ops role (OM, HRCO, ATL, TL) required' USING ERRCODE = '42501';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.hr_emploc_deletion_requests
    WHERE hr_emploc_id = p_correction_request_id AND status = 'Pending'
  ) THEN
    RAISE EXCEPTION 'action locked: a pending deletion request exists for this record'
      USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.hr_emploc
  SET ops_remarks = nullif(trim(p_hrco_notes), ''),
      hr_status   = 'For Review',
      updated_at  = now(),
      updated_by  = public.get_my_profile_id()
  WHERE id = p_correction_request_id
    AND hr_status = 'For Correction';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Correction request not found or not in For Correction status'
      USING ERRCODE = 'P0002';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.submit_hrco_correction_update(uuid, text) FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_hrco_correction_update(uuid, text) TO authenticated;


-- 6. submit_correction Gate Update
CREATE OR REPLACE FUNCTION public.submit_correction(p_id uuid, p_ops_remark text)
RETURNS public.hr_emploc
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_old public.hr_emploc;
  v_new public.hr_emploc;
BEGIN
  -- Gate: Ops only: OM, TL, ATL, HRCO (+SA). HA, Encoder, HR Personnel NOT allowed.
  IF NOT public.can_submit_hr_emploc_correction() THEN
    RAISE EXCEPTION 'forbidden: Ops role required' USING ERRCODE = '42501';
  END IF;

  IF coalesce(btrim(p_ops_remark), '') = '' THEN
    RAISE EXCEPTION 'ops remark is required' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_old FROM public.hr_emploc WHERE id = p_id FOR UPDATE;
  IF NOT FOUND OR v_old.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'hr_emploc % not found or archived', p_id USING ERRCODE = 'P0002';
  END IF;

  IF v_old.hr_status <> 'For Correction' THEN
    RAISE EXCEPTION 'cannot submit correction: hr_status is %', v_old.hr_status USING ERRCODE = '22023';
  END IF;

  UPDATE public.hr_emploc
     SET hr_status   = 'For Review',
         ops_remarks = btrim(p_ops_remark),
         updated_at  = now(),
         updated_by  = public.get_my_profile_id()
   WHERE id = p_id
   RETURNING * INTO v_new;

  PERFORM public.log_audit_event(
    'hr_emploc',
    'UPDATE',
    p_id,
    to_jsonb(v_old),
    jsonb_build_object(
      'action', 'submit_correction',
      'ops_remarks', btrim(p_ops_remark),
      'actor_name', public.get_my_full_name(),
      'actor_id', public.get_my_profile_id(),
      'log_message', format('Ops submitted correction update: %s', btrim(p_ops_remark))
    )
  );

  RETURN v_new;
END;
$$;

REVOKE ALL ON FUNCTION public.submit_correction(uuid, text) FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_correction(uuid, text) TO authenticated;


-- 7. update_deployed_employee_id Gate Update (Decision 1: Data Team + SA ONLY)
CREATE OR REPLACE FUNCTION public.update_deployed_employee_id(
  p_hr_emploc_id uuid,
  p_new_employee_no text,
  p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_actor_profile_id uuid := public.get_my_profile_id();
  v_actor_name       text := public.get_my_full_name();
  v_clean_id         text := btrim(coalesce(p_new_employee_no, ''));
  v_reason           text := btrim(coalesce(p_reason, ''));
  v_emp              public.hr_emploc;
  v_old_id           text;
  v_check            jsonb;
BEGIN
  IF v_clean_id = '' THEN
    RAISE EXCEPTION 'New Employee ID is required' USING ERRCODE = '22023';
  END IF;
  IF v_reason = '' THEN
    RAISE EXCEPTION 'Reason for edit is required' USING ERRCODE = '22023';
  END IF;

  -- Gate: Data Team: Encoder, Head Admin (+SA) ONLY. Remove HR Personnel.
  IF NOT public.can_edit_deployed_hr_emploc() THEN
    RAISE EXCEPTION 'forbidden: Data Team (Encoder, Head Admin) or Super Admin required' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_emp FROM public.hr_emploc WHERE id = p_hr_emploc_id FOR UPDATE;
  IF NOT FOUND OR v_emp.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'Record not found or archived' USING ERRCODE = 'P0002';
  END IF;

  v_old_id := v_emp.employee_no;

  -- Ecosystem uniqueness check (excluding current record)
  v_check := public.check_ecosystem_employee_id_unique(v_clean_id, p_hr_emploc_id);
  IF (v_check->>'is_unique')::boolean = false THEN
    RAISE EXCEPTION '%', (v_check->>'message') USING ERRCODE = '23505';
  END IF;

  -- Update hr_emploc (trigger trg_sync_deployed_employee_no will sync registry & typo release)
  UPDATE public.hr_emploc
  SET employee_no = v_clean_id,
      emploc_no   = v_clean_id,
      updated_at  = now(),
      updated_by  = v_actor_profile_id
  WHERE id = p_hr_emploc_id;

  -- Update plantilla row
  UPDATE public.plantilla
  SET employee_no = v_clean_id,
      emploc_no   = v_clean_id,
      updated_at  = now(),
      updated_by  = v_actor_profile_id
  WHERE hr_emploc_id = p_hr_emploc_id
     OR (v_old_id IS NOT NULL AND employee_no = v_old_id);

  -- Log Activity History Trail
  PERFORM public.log_audit_event(
    'hr_emploc',
    'UPDATE',
    p_hr_emploc_id,
    jsonb_build_object('employee_no', v_old_id),
    jsonb_build_object(
      'employee_no', v_clean_id,
      'reason', v_reason,
      'log_message', format('Updated Employee ID from %s to %s (Reason: %s) by %s', coalesce(v_old_id, 'None'), v_clean_id, v_reason, v_actor_name)
    )
  );

  RETURN jsonb_build_object(
    'status', 'ok',
    'old_id', v_old_id,
    'new_id', v_clean_id,
    'message', format('Updated Employee ID from %s to %s', coalesce(v_old_id, 'None'), v_clean_id)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.update_deployed_employee_id(uuid, text, text) FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_deployed_employee_id(uuid, text, text) TO authenticated;


-- 8. revert_hr_emploc_to_pending Gate Update (Decision 7: Data Team + SA ONLY)
CREATE OR REPLACE FUNCTION public.revert_hr_emploc_to_pending(
  p_hr_emploc_id uuid,
  p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_actor_profile_id uuid := public.get_my_profile_id();
  v_actor_name       text := public.get_my_full_name();
  v_reason           text := btrim(coalesce(p_reason, ''));
  v_emp              public.hr_emploc;
  v_pl               public.plantilla;
  v_vcode            text;
BEGIN
  IF v_reason = '' THEN
    RAISE EXCEPTION 'Reason for revert is required' USING ERRCODE = '22023';
  END IF;

  -- Gate: Data Team (Encoder, Head Admin) or Super Admin ONLY (Decision 7)
  IF NOT public.can_edit_deployed_hr_emploc() THEN
    RAISE EXCEPTION 'forbidden: Data Team (Encoder, Head Admin) or Super Admin required' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_emp FROM public.hr_emploc WHERE id = p_hr_emploc_id FOR UPDATE;
  IF NOT FOUND OR v_emp.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'Record not found or archived' USING ERRCODE = 'P0002';
  END IF;

  v_vcode := v_emp.vcode;

  -- 1. Soft-delete Plantilla row
  SELECT * INTO v_pl FROM public.plantilla
  WHERE hr_emploc_id = p_hr_emploc_id AND coalesce(is_deleted, false) = false
  LIMIT 1;

  IF FOUND THEN
    UPDATE public.plantilla
    SET is_deleted = true,
        status     = 'Deactivated',
        updated_at = now(),
        updated_by = v_actor_profile_id
    WHERE id = v_pl.id;

    UPDATE public.plantilla_store_links
    SET status      = 'Backed Out',
        unlinked_at = now(),
        unlinked_by = v_actor_profile_id,
        updated_at  = now(),
        updated_by  = v_actor_profile_id
    WHERE plantilla_id = v_pl.id;

    -- Re-open slot
    UPDATE public.plantilla_slots
    SET slot_status                   = 'open',
        current_occupant_plantilla_id = NULL,
        updated_at                    = now(),
        updated_by                    = v_actor_profile_id
    WHERE current_occupant_plantilla_id = v_pl.id;
  END IF;

  -- Reconcile Vacancy if needed
  IF v_vcode IS NOT NULL THEN
    UPDATE public.vacancies
    SET status     = 'Open',
        updated_at = now(),
        updated_by = v_actor_profile_id
    WHERE vcode = v_vcode
      AND status IN ('Filled', 'Closed')
      AND coalesce(is_archived, false) = false
      AND deleted_at IS NULL;
  END IF;

  -- Release number in registry if assigned
  IF v_emp.employee_no IS NOT NULL AND btrim(v_emp.employee_no) <> '' THEN
    UPDATE public.employee_number_registry
    SET status = 'released',
        updated_at = now(),
        history = history || jsonb_build_object(
          'action', 'revert_to_pending_released',
          'actor', v_actor_profile_id,
          'timestamp', now(),
          'reason', v_reason
        )
    WHERE emploc_no = btrim(v_emp.employee_no);
  END IF;

  -- Revert hr_emploc record to Pending Emploc
  UPDATE public.hr_emploc
  SET employee_no           = NULL,
      emploc_no             = NULL,
      status                = 'Pending Emploc',
      hr_status             = 'Pending',
      moved_to_plantilla_at = NULL,
      moved_to_plantilla_by = NULL,
      updated_at            = now(),
      updated_by            = v_actor_profile_id
  WHERE id = p_hr_emploc_id;

  PERFORM public.log_audit_event(
    'hr_emploc',
    'UPDATE',
    p_hr_emploc_id,
    jsonb_build_object('status', v_emp.status, 'hr_status', v_emp.hr_status),
    jsonb_build_object(
      'action', 'revert_to_pending',
      'reason', v_reason,
      'log_message', format('Reverted record to Pending Emploc (Reason: %s) by %s', v_reason, v_actor_name)
    )
  );

  RETURN jsonb_build_object(
    'status', 'ok',
    'hr_emploc_id', p_hr_emploc_id,
    'message', 'Record reverted to Pending Emploc'
  );
END;
$$;

REVOKE ALL ON FUNCTION public.revert_hr_emploc_to_pending(uuid, text) FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.revert_hr_emploc_to_pending(uuid, text) TO authenticated;


-- SECTION 8: TRIGGER SYNC FOR DEPLOYED EDIT (DECISION 2 TYPO RELEASE)
-- ====================================================================

CREATE OR REPLACE FUNCTION public.trg_sync_deployed_employee_no_fn()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_old_no text := btrim(coalesce(OLD.employee_no, ''));
  v_new_no text := btrim(coalesce(NEW.employee_no, ''));
  v_norm_name text;
  v_display_name text;
  v_can_release boolean := false;
BEGIN
  IF TG_OP = 'UPDATE' AND v_new_no IS DISTINCT FROM v_old_no AND v_new_no <> '' THEN
    -- Check format
    IF v_new_no !~ '^[A-Za-z0-9._-]+$' THEN
      RAISE EXCEPTION 'EMPLOYEE_NO_FORMAT_INVALID: Employee number "%" is invalid', v_new_no
        USING ERRCODE = '22023';
    END IF;

    v_display_name := coalesce(NEW.employee_name_snapshot, NEW.applicant_name);
    v_norm_name := public.fn_normalize_person_name(NULL, NULL, NULL, NULL, v_display_name);

    -- Upsert new number in registry
    INSERT INTO public.employee_number_registry (
      emploc_no, normalized_name, display_name, status,
      first_assigned_at, first_assigned_by, last_assigned_at, last_assigned_by,
      source_hr_emploc_id, history
    ) VALUES (
      v_new_no, v_norm_name, v_display_name, 'assigned',
      now(), NEW.updated_by, now(), NEW.updated_by,
      NEW.id,
      jsonb_build_array(
        jsonb_build_object(
          'action', 'deployed_edit_sync',
          'actor', NEW.updated_by,
          'old_no', v_old_no,
          'timestamp', now()
        )
      )
    )
    ON CONFLICT (emploc_no) DO UPDATE SET
      last_assigned_at = now(),
      last_assigned_by = NEW.updated_by,
      source_hr_emploc_id = NEW.id;

    -- Decision 2: Typo release for old number
    -- Release old number ONLY if first assigned to this same record,
    -- and no other hr_emploc/plantilla row ever referenced it.
    IF v_old_no <> '' AND v_old_no <> '(PENDING)' THEN
      SELECT (
        NOT EXISTS (
          SELECT 1 FROM public.hr_emploc h 
          WHERE h.id <> NEW.id AND (h.employee_no = v_old_no OR h.emploc_no = v_old_no)
        ) AND NOT EXISTS (
          SELECT 1 FROM public.plantilla p
          WHERE (p.hr_emploc_id IS NULL OR p.hr_emploc_id <> NEW.id) 
            AND (p.employee_no = v_old_no OR p.emploc_no = v_old_no)
        )
      ) INTO v_can_release;

      IF v_can_release THEN
        UPDATE public.employee_number_registry
        SET status = 'released',
            updated_at = now(),
            history = history || jsonb_build_object(
              'action', 'typo_release_decision_2',
              'actor', NEW.updated_by,
              'timestamp', now(),
              'corrected_to', v_new_no
            )
        WHERE emploc_no = v_old_no
          AND source_hr_emploc_id = NEW.id;
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_deployed_employee_no ON public.hr_emploc;
CREATE TRIGGER trg_sync_deployed_employee_no
AFTER UPDATE OF employee_no ON public.hr_emploc
FOR EACH ROW
WHEN (NEW.employee_no IS DISTINCT FROM OLD.employee_no)
EXECUTE FUNCTION public.trg_sync_deployed_employee_no_fn();


-- SECTION 9: LIST_WEB_HR_EMPLOCS (PRESERVING LIVE BODY, UPDATING QUEUE & CAPABILITIES)
-- ====================================================================

CREATE OR REPLACE FUNCTION public.list_web_hr_emplocs(
  p_queue text DEFAULT NULL::text,
  p_status text DEFAULT NULL::text,
  p_deficiency text DEFAULT NULL::text,
  p_sla_filter text DEFAULT NULL::text,
  p_account_id uuid DEFAULT NULL::uuid,
  p_group_id uuid DEFAULT NULL::uuid,
  p_search text DEFAULT NULL::text,
  p_limit integer DEFAULT 50,
  p_offset integer DEFAULT 0,
  p_sort_by text DEFAULT 'date_requested'::text,
  p_sort_dir text DEFAULT 'desc'::text
)
RETURNS TABLE(
  hr_emploc_id uuid,
  applicant_name text,
  vcode text,
  account_id uuid,
  account_name text,
  group_id uuid,
  group_name text,
  store_id uuid,
  store_name text,
  position_title text,
  hr_status text,
  status text,
  emploc_no text,
  employee_no text,
  date_requested timestamp with time zone,
  created_at timestamp with time zone,
  hired_date date,
  assignment_type text,
  roving_assignment_id uuid,
  aging_days integer,
  sla_breached boolean,
  sla_status text,
  sla_deadline timestamp with time zone,
  deficiency_summary jsonb,
  is_pending_deletion boolean,
  row_capabilities jsonb,
  total_count bigint
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_auth_uid     uuid := auth.uid();
  v_profile_id   uuid;
  v_role_level   integer;
  v_role_name    text;
  v_limit        integer := LEAST(GREATEST(COALESCE(p_limit, 50), 1), 200);
  v_offset       integer := GREATEST(COALESCE(p_offset, 0), 0);
  v_sort_by      text    := LOWER(COALESCE(p_sort_by, 'date_requested'));
  v_sort_dir     text    := LOWER(COALESCE(p_sort_dir, 'desc'));
BEGIN
  IF v_auth_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated: list_web_hr_emplocs requires a valid session'
      USING ERRCODE = '42501';
  END IF;

  SELECT up.id, r.role_level, r.role_name
  INTO   v_profile_id, v_role_level, v_role_name
  FROM   public.users_profile up
  JOIN   public.roles r ON r.id = up.role_id
  WHERE  up.auth_user_id = v_auth_uid
    AND  up.is_active    = TRUE
    AND  up.archived_at  IS NULL
  ORDER  BY up.created_at DESC
  LIMIT  1;

  IF v_profile_id IS NULL THEN
    RAISE EXCEPTION 'forbidden: caller profile is inactive or not found'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  WITH scoped AS (
    SELECT
      h.id,
      COALESCE(h.applicant_name_snapshot, h.applicant_name) AS applicant_name,
      h.vcode,
      h.account_id,
      COALESCE(a.account_name, h.account) AS account_name,
      a.group_id,
      g.group_name,
      h.store_id,
      h.store_name,
      COALESCE(h.position_snapshot, h.position) AS position_title,
      h.hr_status,
      h.status,
      h.emploc_no,
      h.employee_no,
      h.date_requested,
      h.created_at,
      h.hired_date,
      h.assignment_type::text AS assignment_type,
      h.roving_assignment_id,
      h.deleted_at,
      h.moved_to_plantilla_at,
      
      -- SLA & Aging computation
      GREATEST(0, (EXTRACT(day FROM (now() - COALESCE(h.date_requested, h.created_at))))::integer) AS aging_days,
      
      ((h.deleted_at IS NULL) AND (h.employee_no IS NULL OR h.employee_no = '') AND (h.status = ANY (ARRAY['Pending Emploc'::text, 'Pending Requirements'::text, 'For Compliance'::text, 'In Review'::text])) AND (COALESCE(h.date_requested, h.created_at) < (now() - '3 days'::interval))) AS sla_breached,
      
      CASE
        WHEN (h.employee_no IS NOT NULL AND btrim(h.employee_no) <> '') OR (h.status = 'Moved to Plantilla') THEN 'completed'
        WHEN COALESCE(h.date_requested, h.created_at) < (now() - '3 days'::interval) THEN 'breached'
        WHEN COALESCE(h.date_requested, h.created_at) < (now() - '2 days'::interval) THEN 'warning'
        ELSE 'on_track'
      END AS sla_status,
      
      (COALESCE(h.date_requested, h.created_at) + INTERVAL '3 days') AS sla_deadline,
      
      -- Deficiency summary
      CASE
        WHEN h.correction_reason IS NULL OR h.correction_reason = 'null'::jsonb OR h.correction_reason = '[]'::jsonb THEN
          jsonb_build_object('active_count', 0, 'issues', '[]'::jsonb)
        ELSE jsonb_build_object(
          'active_count', CASE WHEN jsonb_typeof(h.correction_reason) = 'array' THEN jsonb_array_length(h.correction_reason) ELSE 1 END,
          'issues', CASE
            WHEN jsonb_typeof(h.correction_reason) = 'array' THEN (
              SELECT jsonb_agg(
                jsonb_build_object(
                  'code', el->>'code',
                  'comment', el->>'comment',
                  'label', COALESCE((SELECT it.label FROM public.hr_emploc_issue_types it WHERE it.code = el->>'code'), el->>'code')
                )
              )
              FROM jsonb_array_elements(h.correction_reason) el
            )
            ELSE jsonb_build_array(
              jsonb_build_object(
                'code', h.correction_reason->>'type',
                'comment', h.correction_reason->>'comment',
                'label', COALESCE((SELECT it.label FROM public.hr_emploc_issue_types it WHERE it.code = h.correction_reason->>'type'), h.correction_reason->>'type')
              )
            )
          END
        )
      END AS deficiency_summary,
      
      EXISTS (
        SELECT 1 FROM public.hr_emploc_deletion_requests dr
        WHERE dr.hr_emploc_id = h.id AND dr.status = 'Pending'
      ) AS is_pending_deletion,
      
      -- ROW CAPABILITIES MATCHING OHM'S FINAL ROLE MATRIX
      jsonb_build_object(
        'can_view_detail', true,
        'hrco_name', COALESCE(h.hrco_name, (SELECT up2.full_name FROM public.users_profile up2 WHERE up2.id = h.hrco_user_id_snapshot)),
        'remarks', COALESCE(h.ops_remarks, h.hr_remarks),
        'ops_remarks', h.ops_remarks,
        'hr_remarks', h.hr_remarks,
        'attachment_url', (
          SELECT ca.storage_path
          FROM public.hr_emploc_correction_attachments ca
          WHERE ca.hr_emploc_id = h.id AND ca.is_deleted = false
          ORDER BY ca.uploaded_at DESC
          LIMIT 1
        ),
        'attachment_file_name', (
          SELECT ca.original_filename
          FROM public.hr_emploc_correction_attachments ca
          WHERE ca.hr_emploc_id = h.id AND ca.is_deleted = false
          ORDER BY ca.uploaded_at DESC
          LIMIT 1
        ),
        'can_edit_emploc', (
          public.can_edit_deployed_hr_emploc()
          AND (h.status = 'Moved to Plantilla' OR h.hr_status = 'Transferred' OR (h.employee_no IS NOT NULL AND btrim(h.employee_no) <> ''))
        ),
        'can_revert_to_pending', (
          public.can_edit_deployed_hr_emploc()
          AND (h.status = 'Moved to Plantilla' OR h.hr_status = 'Transferred' OR (h.employee_no IS NOT NULL AND btrim(h.employee_no) <> ''))
        ),
        'can_request_deletion', (
          h.status <> 'Moved to Plantilla'
          AND h.hr_status <> 'Pending Deletion'
          AND NOT EXISTS (
            SELECT 1 FROM public.hr_emploc_deletion_requests dr
            WHERE dr.hr_emploc_id = h.id AND dr.status = 'Pending'
          )
          AND (v_role_level >= 70 OR v_role_name IN ('OM', 'HRCO', 'ATL', 'TL', 'ATL/TL') OR public.i_am_ops() OR public.i_have_full_access())
        ),
        'can_withdraw_deletion_request', (
          EXISTS (
            SELECT 1 FROM public.hr_emploc_deletion_requests dr
            WHERE dr.hr_emploc_id = h.id AND dr.status = 'Pending'
          )
          AND (
            public.i_have_full_access()
            OR EXISTS (
              SELECT 1 FROM public.hr_emploc_deletion_requests dr
              WHERE dr.hr_emploc_id = h.id AND dr.status = 'Pending' AND dr.requested_by_user_id = v_profile_id
            )
          )
        ),
        'can_review_deletion', (
          (public.i_have_full_access() OR v_role_name = 'Encoder' OR v_role_level = 30)
          AND EXISTS (
            SELECT 1 FROM public.hr_emploc_deletion_requests dr
            WHERE dr.hr_emploc_id = h.id AND dr.status = 'Pending'
          )
        ),
        'can_approve_correction', (
          public.can_tag_or_review_hr_emploc()
          AND h.hr_status = 'For Review'
          AND NOT EXISTS (
            SELECT 1 FROM public.hr_emploc_deletion_requests dr
            WHERE dr.hr_emploc_id = h.id AND dr.status = 'Pending'
          )
        ),
        'can_revert_correction', (
          public.can_tag_or_review_hr_emploc()
          AND h.hr_status = 'For Review'
          AND NOT EXISTS (
            SELECT 1 FROM public.hr_emploc_deletion_requests dr
            WHERE dr.hr_emploc_id = h.id AND dr.status = 'Pending'
          )
        ),
        'can_review_correction', (
          public.can_tag_or_review_hr_emploc()
          AND h.hr_status = 'For Review'
          AND NOT EXISTS (
            SELECT 1 FROM public.hr_emploc_deletion_requests dr
            WHERE dr.hr_emploc_id = h.id AND dr.status = 'Pending'
          )
        ),
        'can_submit_correction', (
          public.can_submit_hr_emploc_correction()
          AND h.hr_status = 'For Correction'
          AND NOT EXISTS (
            SELECT 1 FROM public.hr_emploc_deletion_requests dr
            WHERE dr.hr_emploc_id = h.id AND dr.status = 'Pending'
          )
        ),
        'can_move_to_plantilla', false, -- Deprecated & removed per final workflow
        'can_tag_deficiency', (
          public.can_tag_or_review_hr_emploc()
          AND h.status <> 'Moved to Plantilla'
          AND h.hr_status <> 'Transferred'
          AND NOT EXISTS (
            SELECT 1 FROM public.hr_emploc_deletion_requests dr
            WHERE dr.hr_emploc_id = h.id AND dr.status = 'Pending'
          )
        ),
        'can_assign_employee_no', (
          public.can_assign_pending_hr_emploc()
          AND COALESCE(h.employee_no, '') = ''
          AND h.status <> 'Moved to Plantilla'
          AND NOT EXISTS (
            SELECT 1 FROM public.hr_emploc_deletion_requests dr
            WHERE dr.hr_emploc_id = h.id AND dr.status = 'Pending'
          )
        )
      ) AS row_capabilities
    FROM public.hr_emploc h
    LEFT JOIN public.accounts a ON a.id = h.account_id
    LEFT JOIN public.groups g ON g.id = a.group_id
    WHERE
      h.deleted_at IS NULL
      AND (
        COALESCE(v_role_level, 0) >= 90
        OR (
          h.account = ANY (public.get_my_allowed_accounts())
          OR
          EXISTS (
            SELECT 1 FROM public.user_scopes us
            WHERE us.user_id = v_profile_id AND us.account_id = h.account_id
          )
          OR EXISTS (
            SELECT 1 FROM public.user_scopes us JOIN public.accounts ac ON ac.id = h.account_id
            WHERE us.user_id = v_profile_id AND us.account_id IS NULL AND us.group_id = ac.group_id
          )
          OR EXISTS (
            SELECT 1 FROM public.users_profile up_fallback JOIN public.accounts ac ON ac.id = h.account_id
            WHERE up_fallback.id = v_profile_id
              AND NOT EXISTS (SELECT 1 FROM public.user_scopes us_any WHERE us_any.user_id = v_profile_id AND (us_any.group_id IS NOT NULL OR us_any.account_id IS NOT NULL))
              AND (up_fallback.account_id = h.account_id OR up_fallback.group_id = ac.group_id)
          )
        )
      )
  ),
  filtered AS (
    SELECT s.*
    FROM scoped s
    WHERE
      -- Queue Filter: Deployed strictly mapped to status = 'Moved to Plantilla' OR hr_status = 'Transferred'
      (p_queue IS NULL
       OR (p_queue = 'pending' AND s.hr_status = 'Pending' AND s.status <> 'Backout' AND s.deleted_at IS NULL)
       OR (p_queue = 'correction' AND s.hr_status = 'For Correction' AND s.status <> 'Backout' AND s.deleted_at IS NULL)
       OR (p_queue = 'review' AND s.hr_status = 'For Review' AND s.status <> 'Backout' AND s.deleted_at IS NULL)
       OR (p_queue IN ('deployed', 'transferred') AND (
            s.status = 'Moved to Plantilla'
            OR s.hr_status = 'Transferred'
          )
          AND s.status <> 'Backout'
          AND s.deleted_at IS NULL
       )
       OR (p_queue = 'rejected' AND s.hr_status = 'Rejected' AND s.deleted_at IS NULL)
      )
      AND (p_deficiency IS NULL
       OR (p_deficiency = 'any' AND s.deficiency_summary->'active_count' > '0'::jsonb)
       OR (p_deficiency = 'none' AND s.deficiency_summary->'active_count' = '0'::jsonb)
       OR (
         s.deficiency_summary->'active_count' > '0'::jsonb AND EXISTS (
           SELECT 1 FROM jsonb_array_elements(s.deficiency_summary->'issues') el
           WHERE el->>'code' = p_deficiency
         )
       )
      )
      AND (p_sla_filter IS NULL OR s.sla_status = p_sla_filter)
      AND (p_account_id IS NULL OR s.account_id = p_account_id)
      AND (p_group_id IS NULL OR s.group_id = p_group_id)
      AND (
        p_search IS NULL
        OR s.applicant_name ILIKE '%' || p_search || '%'
        OR s.vcode ILIKE '%' || p_search || '%'
        OR s.emploc_no ILIKE '%' || p_search || '%'
        OR s.employee_no ILIKE '%' || p_search || '%'
        OR s.store_name ILIKE '%' || p_search || '%'
        OR s.position_title ILIKE '%' || p_search || '%'
      )
  ),
  counted AS (
    SELECT f.*, COUNT(*) OVER() AS full_count
    FROM filtered f
  )
  SELECT
    c.id AS hr_emploc_id,
    c.applicant_name,
    c.vcode,
    c.account_id,
    c.account_name,
    c.group_id,
    c.group_name,
    c.store_id,
    c.store_name,
    c.position_title,
    c.hr_status,
    c.status,
    c.emploc_no,
    c.employee_no,
    c.date_requested,
    c.created_at,
    c.hired_date,
    c.assignment_type,
    c.roving_assignment_id,
    c.aging_days,
    c.sla_breached,
    c.sla_status,
    c.sla_deadline,
    c.deficiency_summary,
    c.is_pending_deletion,
    c.row_capabilities,
    COALESCE(c.full_count, 0::bigint) AS total_count
  FROM counted c
  ORDER BY
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'vcode'            THEN c.vcode END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'vcode'            THEN c.vcode END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'applicant_name'   THEN c.applicant_name END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'applicant_name'   THEN c.applicant_name END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'account_name'     THEN c.account_name END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'account_name'     THEN c.account_name END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'group_name'       THEN c.group_name END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'group_name'       THEN c.group_name END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'store_name'       THEN c.store_name END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'store_name'       THEN c.store_name END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'position_title'   THEN c.position_title END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'position_title'   THEN c.position_title END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'hr_status'        THEN c.hr_status END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'hr_status'        THEN c.hr_status END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'status'           THEN c.status END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'status'           THEN c.status END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'emploc_no'        THEN c.emploc_no END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'emploc_no'        THEN c.emploc_no END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'employee_no'      THEN c.employee_no END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'employee_no'      THEN c.employee_no END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'date_requested'   THEN c.date_requested END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'date_requested'   THEN c.date_requested END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'created_at'       THEN c.created_at END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'created_at'       THEN c.created_at END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'aging_days'       THEN c.aging_days END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'aging_days'       THEN c.aging_days END DESC NULLS LAST,
    c.created_at DESC NULLS LAST
  LIMIT v_limit
  OFFSET v_offset;
END;
$function$;

REVOKE ALL ON FUNCTION public.list_web_hr_emplocs(text, text, text, text, uuid, uuid, text, integer, integer, text, text) FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.list_web_hr_emplocs(text, text, text, text, uuid, uuid, text, integer, integer, text, text) TO authenticated;


-- SECTION 10: GET_WEB_HR_EMPLOC_SUMMARY (PRESERVING EXACT TABLE RETURN SIGNATURE & NEW DEPLOYED LOGIC)
-- ====================================================================

CREATE OR REPLACE FUNCTION public.get_web_hr_emploc_summary(
  p_queue text DEFAULT NULL::text,
  p_status text DEFAULT NULL::text,
  p_deficiency text DEFAULT NULL::text,
  p_sla_filter text DEFAULT NULL::text,
  p_account_id uuid DEFAULT NULL::uuid,
  p_group_id uuid DEFAULT NULL::uuid,
  p_search text DEFAULT NULL::text
)
RETURNS TABLE(
  pending_count bigint,
  correction_count bigint,
  review_count bigint,
  ready_count bigint,
  sla_breached_count bigint,
  sla_warning_count bigint,
  with_deficiency_count bigint,
  pending_deletion_count bigint
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_auth_uid     uuid := auth.uid();
  v_profile_id   uuid;
  v_role_name    text;
  v_role_level   integer;
BEGIN
  IF v_auth_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated: web hr_emploc summary requires a valid session'
      USING ERRCODE = '42501';
  END IF;

  SELECT up.id, r.role_name, r.role_level
  INTO v_profile_id, v_role_name, v_role_level
  FROM public.users_profile up
  JOIN public.roles r ON r.id = up.role_id
  WHERE up.auth_user_id = v_auth_uid
    AND up.is_active = TRUE
    AND up.archived_at IS NULL
  ORDER BY up.created_at DESC
  LIMIT 1;

  IF v_profile_id IS NULL OR coalesce(v_role_level, 0) <= 0 THEN
    RAISE EXCEPTION 'forbidden: web hr_emploc summary caller is not allowed'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  WITH scoped AS (
    SELECT
      h.hr_status,
      h.status,
      h.account_id,
      a.account_name,
      a.group_id,
      h.applicant_name,
      h.vcode,
      h.employee_no,
      h.emploc_no,
      h.store_name,
      h.position AS position_title,
      COALESCE(h.hrco_name, (SELECT up2.full_name FROM public.users_profile up2 WHERE up2.id = h.hrco_user_id_snapshot)) AS hrco_name,
      h.correction_reason,
      h.deleted_at,
      h.moved_to_plantilla_at,
      
      ((h.deleted_at IS NULL) AND (h.employee_no IS NULL OR h.employee_no = '') AND (h.status = ANY (ARRAY['Pending Emploc'::text, 'Pending Requirements'::text, 'For Compliance'::text, 'In Review'::text])) AND (COALESCE(h.date_requested, h.created_at) < (now() - '3 days'::interval))) AS sla_breached,
      
      ((h.deleted_at IS NULL) AND (h.employee_no IS NULL OR h.employee_no = '') AND (h.status = ANY (ARRAY['Pending Emploc'::text, 'Pending Requirements'::text, 'For Compliance'::text, 'In Review'::text])) AND COALESCE(h.date_requested, h.created_at) >= (now() - '3 days'::interval) AND COALESCE(h.date_requested, h.created_at) < (now() - '2 days'::interval)) AS sla_warning,
      
      CASE
        WHEN (h.deleted_at IS NULL AND (h.employee_no IS NULL OR h.employee_no = '') AND h.status = ANY (ARRAY['Pending Emploc'::text, 'Pending Requirements'::text, 'For Compliance'::text, 'In Review'::text]) AND COALESCE(h.date_requested, h.created_at) < (now() - '3 days'::interval))
          THEN 'breached'
        WHEN (h.deleted_at IS NULL AND (h.employee_no IS NULL OR h.employee_no = '') AND h.status = ANY (ARRAY['Pending Emploc'::text, 'Pending Requirements'::text, 'For Compliance'::text, 'In Review'::text]) AND COALESCE(h.date_requested, h.created_at) >= (now() - '3 days'::interval) AND COALESCE(h.date_requested, h.created_at) < (now() - '2 days'::interval))
          THEN 'warning'
        ELSE 'normal'
      END AS sla_status
    FROM public.hr_emploc h
    LEFT JOIN public.accounts a ON a.id = h.account_id
    WHERE
      h.deleted_at IS NULL
      AND (
        COALESCE(v_role_level, 0) >= 90
        OR (
          h.account = ANY (public.get_my_allowed_accounts())
          OR
          EXISTS (
            SELECT 1 FROM public.user_scopes us
            WHERE us.user_id = v_profile_id AND us.account_id = h.account_id
          )
          OR EXISTS (
            SELECT 1 FROM public.user_scopes us JOIN public.accounts ac ON ac.id = h.account_id
            WHERE us.user_id = v_profile_id AND us.account_id IS NULL AND us.group_id = ac.group_id
          )
          OR EXISTS (
            SELECT 1 FROM public.users_profile up_fallback JOIN public.accounts ac ON ac.id = h.account_id
            WHERE up_fallback.id = v_profile_id
              AND NOT EXISTS (SELECT 1 FROM public.user_scopes us_any WHERE us_any.user_id = v_profile_id AND (us_any.group_id IS NOT NULL OR us_any.account_id IS NOT NULL))
              AND (up_fallback.account_id = h.account_id OR up_fallback.group_id = ac.group_id)
          )
        )
      )
  ),
  filtered AS (
    SELECT s.*
    FROM scoped s
    WHERE
      (p_deficiency IS NULL
       OR (p_deficiency = 'any' AND s.correction_reason IS NOT NULL)
       OR (p_deficiency = 'none' AND s.correction_reason IS NULL)
       OR (
         s.correction_reason IS NOT NULL AND (
           (jsonb_typeof(s.correction_reason) = 'array' AND EXISTS (
             SELECT 1 FROM jsonb_array_elements(s.correction_reason) el
             WHERE el->>'code' = p_deficiency
           ))
           OR
           (jsonb_typeof(s.correction_reason) = 'object' AND s.correction_reason->>'type' = p_deficiency)
         )
       )
      )
      AND (p_sla_filter IS NULL OR s.sla_status = p_sla_filter)
      AND (p_status IS NULL OR s.status = p_status)
      AND (p_account_id IS NULL OR s.account_id = p_account_id)
      AND (p_group_id IS NULL OR s.group_id = p_group_id)
      AND (
        p_search IS NULL
        OR nullif(btrim(p_search), '') IS NULL
        OR s.applicant_name ILIKE '%' || btrim(p_search) || '%'
        OR s.employee_no ILIKE '%' || btrim(p_search) || '%'
        OR s.emploc_no ILIKE '%' || btrim(p_search) || '%'
        OR s.vcode ILIKE '%' || btrim(p_search) || '%'
        OR s.account_name ILIKE '%' || btrim(p_search) || '%'
        OR s.store_name ILIKE '%' || btrim(p_search) || '%'
        OR s.position_title ILIKE '%' || btrim(p_search) || '%'
        OR s.hrco_name ILIKE '%' || btrim(p_search) || '%'
        OR s.hr_status ILIKE '%' || btrim(p_search) || '%'
        OR s.status ILIKE '%' || btrim(p_search) || '%'
      )
  )
  SELECT
    count(*) FILTER (WHERE f.hr_status = 'Pending' AND f.status <> 'Backout' AND f.deleted_at IS NULL)::bigint AS pending_count,
    count(*) FILTER (WHERE f.hr_status = 'For Correction' AND f.status <> 'Backout' AND f.deleted_at IS NULL)::bigint AS correction_count,
    count(*) FILTER (WHERE f.hr_status = 'For Review' AND f.status <> 'Backout' AND f.deleted_at IS NULL)::bigint AS review_count,
    count(*) FILTER (WHERE (f.status = 'Moved to Plantilla' OR f.hr_status = 'Transferred') AND f.status <> 'Backout' AND f.deleted_at IS NULL)::bigint AS ready_count,
    count(*) FILTER (WHERE f.sla_breached = true)::bigint AS sla_breached_count,
    count(*) FILTER (WHERE f.sla_warning = true)::bigint AS sla_warning_count,
    count(*) FILTER (WHERE f.correction_reason IS NOT NULL)::bigint AS with_deficiency_count,
    count(*) FILTER (WHERE f.hr_status = 'Pending Deletion' AND f.status <> 'Backout' AND f.deleted_at IS NULL)::bigint AS pending_deletion_count
  FROM filtered f;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_web_hr_emploc_summary(text, text, text, text, uuid, uuid, text) FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_web_hr_emploc_summary(text, text, text, text, uuid, uuid, text) TO authenticated;
