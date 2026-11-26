-- ============================================================================
-- Migration: 20262606000196_fix_store_vcode_reuse_and_reconcile_super1.sql
-- Module: Plantilla / Headcount Request / Store VCode Architecture (ADR-001 Invariant 20)
--
-- Work items:
--   1. Upgrade find_reusable_store_vcode helper:
--      Check stores.vcode, plantilla.vcode, active/pipeline vacancies, and historical
--      vacancies so existing stores NEVER mint duplicate or divergent VCodes upon
--      headcount expansion.
--   2. Reconcile SUPER 1 (BANKO) data:
--      Re-key divergent 'BK-G1-0054' records back to canonical store code 'TEST001'.
-- ============================================================================

-- ── 1. Upgrade find_reusable_store_vcode ─────────────────────────────────────
-- Base: 20261216000000_fix_hc_request_duplicate_vcode_per_store.sql
CREATE OR REPLACE FUNCTION public.find_reusable_store_vcode(
  p_account_id  uuid,
  p_store_id    uuid,
  p_store_name  text
)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_vcode text;
BEGIN
  -- 1. Primary Store VCode Check: stores.vcode by store_id
  IF p_store_id IS NOT NULL THEN
    SELECT vcode INTO v_vcode
    FROM public.stores
    WHERE id = p_store_id
      AND account_id = p_account_id
      AND vcode IS NOT NULL
      AND btrim(vcode) <> ''
      AND COALESCE(is_archived, false) = false;
  END IF;

  -- 2. Store VCode Check Fallback: stores.vcode by normalised store_name
  IF v_vcode IS NULL AND p_store_name IS NOT NULL THEN
    SELECT vcode INTO v_vcode
    FROM public.stores
    WHERE account_id = p_account_id
      AND LOWER(TRIM(store_name)) = LOWER(TRIM(p_store_name))
      AND vcode IS NOT NULL
      AND btrim(vcode) <> ''
      AND COALESCE(is_archived, false) = false
    ORDER BY created_at ASC
    LIMIT 1;
  END IF;

  -- 3. Plantilla VCode Check: check existing active/inactive plantilla assignments
  IF v_vcode IS NULL AND p_store_id IS NOT NULL THEN
    SELECT vcode INTO v_vcode
    FROM public.plantilla
    WHERE account_id = p_account_id
      AND store_id = p_store_id
      AND vcode IS NOT NULL
      AND btrim(vcode) <> ''
      AND COALESCE(is_archived, false) = false
    ORDER BY CASE WHEN status = 'Active' THEN 0 ELSE 1 END, created_at ASC
    LIMIT 1;
  END IF;

  IF v_vcode IS NULL AND p_store_name IS NOT NULL THEN
    SELECT vcode INTO v_vcode
    FROM public.plantilla
    WHERE account_id = p_account_id
      AND LOWER(TRIM(store_name)) = LOWER(TRIM(p_store_name))
      AND vcode IS NOT NULL
      AND btrim(vcode) <> ''
      AND COALESCE(is_archived, false) = false
    ORDER BY CASE WHEN status = 'Active' THEN 0 ELSE 1 END, created_at ASC
    LIMIT 1;
  END IF;

  -- 4. Open/Pipeline Vacancies Check: by store_id
  IF v_vcode IS NULL AND p_store_id IS NOT NULL THEN
    SELECT vcode INTO v_vcode
    FROM public.vacancies
    WHERE account_id                       = p_account_id
      AND store_id                         = p_store_id
      AND status                           IN ('Open', 'Pipeline')
      AND COALESCE(is_archived, false)     = false
      AND deleted_at                       IS NULL
      AND COALESCE(is_pool_vacancy, false) = false
    ORDER BY created_at ASC
    LIMIT 1;
  END IF;

  -- 5. Open/Pipeline Vacancies Check: by store_name
  IF v_vcode IS NULL AND p_store_name IS NOT NULL THEN
    SELECT vcode INTO v_vcode
    FROM public.vacancies
    WHERE account_id                       = p_account_id
      AND LOWER(TRIM(store_name))          = LOWER(TRIM(p_store_name))
      AND status                           IN ('Open', 'Pipeline')
      AND COALESCE(is_archived, false)     = false
      AND deleted_at                       IS NULL
      AND COALESCE(is_pool_vacancy, false) = false
    ORDER BY created_at ASC
    LIMIT 1;
  END IF;

  -- 6. Historical Vacancies Check (any status, non-archived): by store_id
  IF v_vcode IS NULL AND p_store_id IS NOT NULL THEN
    SELECT vcode INTO v_vcode
    FROM public.vacancies
    WHERE account_id                       = p_account_id
      AND store_id                         = p_store_id
      AND COALESCE(is_archived, false)     = false
      AND deleted_at                       IS NULL
      AND COALESCE(is_pool_vacancy, false) = false
    ORDER BY created_at DESC
    LIMIT 1;
  END IF;

  -- 7. Historical Vacancies Check: by store_name
  IF v_vcode IS NULL AND p_store_name IS NOT NULL THEN
    SELECT vcode INTO v_vcode
    FROM public.vacancies
    WHERE account_id                       = p_account_id
      AND LOWER(TRIM(store_name))          = LOWER(TRIM(p_store_name))
      AND COALESCE(is_archived, false)     = false
      AND deleted_at                       IS NULL
      AND COALESCE(is_pool_vacancy, false) = false
    ORDER BY created_at DESC
    LIMIT 1;
  END IF;

  RETURN v_vcode;
END;
$$;

COMMENT ON FUNCTION public.find_reusable_store_vcode(uuid, uuid, text) IS
  'Returns the reusable store VCode in priority order: stores.vcode, plantilla.vcode, '
  'active open/pipeline vacancies, and historical vacancies. Enforces ADR-001 Invariant 20 '
  'preventing duplicate/divergent VCode creation on existing stores.';

GRANT EXECUTE ON FUNCTION public.find_reusable_store_vcode(uuid, uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.find_reusable_store_vcode(uuid, uuid, text) TO service_role;


-- ── 2. Data Reconcile for SUPER 1 (BANKO) ────────────────────────────────────
-- Reconcile divergent 'BK-G1-0054' back to canonical store code 'TEST001'
-- Upgrades fk_hr_emploc_vcode to ON UPDATE CASCADE and safely sequences FK updates.
ALTER TABLE public.hr_emploc
  DROP CONSTRAINT IF EXISTS fk_hr_emploc_vcode,
  ADD CONSTRAINT fk_hr_emploc_vcode
    FOREIGN KEY (vcode) REFERENCES public.vacancies(vcode)
    ON UPDATE CASCADE ON DELETE CASCADE;

DO $$
DECLARE
  v_target_vcode text := 'TEST001';
  v_old_vcode text := 'BK-G1-0054';
  v_hc_req_id uuid := 'fad9d3cc-2c10-4001-96cc-d7a6d1db307f';
  v_affected_emploc_ids uuid[];
BEGIN
  -- 0. Identify any hr_emploc records bound to old vcode
  SELECT COALESCE(array_agg(id), ARRAY[]::uuid[])
  INTO v_affected_emploc_ids
  FROM public.hr_emploc
  WHERE vcode = v_old_vcode;

  -- Temporarily clear hr_emploc.vcode to satisfy FK checks if CASCADE is not yet active
  IF array_length(v_affected_emploc_ids, 1) > 0 THEN
    UPDATE public.hr_emploc
    SET vcode = NULL
    WHERE id = ANY(v_affected_emploc_ids);
  END IF;

  -- 1. Reconcile vacancies
  UPDATE public.vacancies
  SET vcode = v_target_vcode,
      updated_at = now()
  WHERE vcode = v_old_vcode;

  -- 2. Restore/reconcile hr_emploc records to target canonical vcode
  IF array_length(v_affected_emploc_ids, 1) > 0 THEN
    UPDATE public.hr_emploc
    SET vcode = v_target_vcode,
        updated_at = now()
    WHERE id = ANY(v_affected_emploc_ids);
  END IF;

  -- 3. Reconcile plantilla vacant slot
  UPDATE public.plantilla
  SET vcode = v_target_vcode,
      updated_at = now()
  WHERE vcode = v_old_vcode;

  -- 4. Reconcile plantilla_slots (assign ordinal 2 so it is sequential with occupied slot 1)
  UPDATE public.plantilla_slots
  SET legacy_vcode = v_target_vcode,
      slot_ordinal = 2,
      updated_at = now()
  WHERE legacy_vcode = v_old_vcode;

  -- 5. Reconcile headcount_requests
  UPDATE public.headcount_requests
  SET created_vcode = v_target_vcode,
      created_vcodes = ARRAY[v_target_vcode],
      updated_at = now()
  WHERE id = v_hc_req_id
     OR created_vcode = v_old_vcode;

  -- 6. Reconcile applicants if any
  UPDATE public.applicants
  SET vacancy_vcode = v_target_vcode,
      updated_at = now()
  WHERE vacancy_vcode = v_old_vcode;
END;
$$;
