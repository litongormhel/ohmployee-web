-- ============================================================
-- OHM2026_0087A_FIX3 — Fix Coverage HR Emploc vcode FK + slot ID on store links
-- Migration: 20261004000000_coverage_slot_id_to_store_links.sql
-- ============================================================
-- Root cause of previous failures:
--
--   FIX2 failure: hr_emploc.vcode is text NOT NULL FK → vacancies(vcode).
--   Coverage rows were inserted with vcode = CGCODE (e.g. CG-MG1-0006), which is
--   not a row in vacancies → fk_hr_emploc_vcode violation.
--
--   FIX3 intermediate failure: hr_emploc_store_links has unique index
--   uq_hr_emploc_store_links_emploc_vcode_active on (hr_emploc_id, vcode).
--   All Coverage store links for one onboarding share the same hr_emploc_id and
--   CGCODE as vcode, so rows 2+ collide on the unique index.
--
-- Fix design (final):
--   hr_emploc.vcode        = NULL for Coverage rows.
--     FK fk_hr_emploc_vcode is preserved — PostgreSQL skips FK checks on NULL.
--     CGCODE kept in vacancy_code_snapshot (no FK constraint).
--
--   hr_emploc_store_links.vcode = NULL for Coverage store-link rows.
--     No FK on store-links vcode → NULL is safe AND avoids the
--     uq_hr_emploc_store_links_emploc_vcode_active collision.
--     CGCODE is recoverable from parent hr_emploc.vacancy_code_snapshot.
--     New unique index (hr_emploc_id, store_id) guards against duplicate
--     Coverage store links per store.
--
-- §0a — Make hr_emploc.vcode nullable
-- §0b — Make hr_emploc_store_links.vcode nullable + add Coverage unique guard
-- §1  — Add coverage_slot_id to hr_emploc_store_links
-- §2  — Replace confirm_coverage_group_onboarding (NULL vcode in both tables)
-- §3  — Repair test applicant f4f276f3-324e-4807-af04-e4b690b8626b

-- §0a. Allow hr_emploc.vcode to be NULL for Coverage rows.
--      fk_hr_emploc_vcode still enforces referential integrity for non-NULL rows.
ALTER TABLE public.hr_emploc
  ALTER COLUMN vcode DROP NOT NULL;

COMMENT ON COLUMN public.hr_emploc.vcode IS
  'OHM2026_0087A_FIX3: nullable for Coverage rows (CGCODE kept in '
  'vacancy_code_snapshot; no FK on that column). fk_hr_emploc_vcode enforces '
  'referential integrity for non-NULL Stationary/Roving rows only.';

-- §0b. Allow hr_emploc_store_links.vcode to be NULL for Coverage store links.
--      The existing uq_hr_emploc_store_links_emploc_vcode_active unique index on
--      (hr_emploc_id, vcode) treats each NULL as distinct, so Coverage rows with
--      vcode = NULL will not collide. We add a separate unique guard on
--      (hr_emploc_id, store_id) to prevent duplicate Coverage store links.
ALTER TABLE public.hr_emploc_store_links
  ALTER COLUMN vcode DROP NOT NULL;

COMMENT ON COLUMN public.hr_emploc_store_links.vcode IS
  'OHM2026_0087A_FIX3: nullable for Coverage store links. '
  'Legacy Roving links keep vcode = VCODE. Coverage links use vcode = NULL; '
  'CGCODE is recoverable from parent hr_emploc.vacancy_code_snapshot.';

CREATE UNIQUE INDEX IF NOT EXISTS uq_hr_emploc_store_links_emploc_store_active
  ON public.hr_emploc_store_links (hr_emploc_id, store_id)
  WHERE deleted_at IS NULL AND store_id IS NOT NULL;

COMMENT ON INDEX public.uq_hr_emploc_store_links_emploc_store_active IS
  'OHM2026_0087A_FIX3: prevents duplicate active Coverage store links '
  'per (hr_emploc, store). Complements uq_hr_emploc_store_links_emploc_vcode_active '
  'which guards legacy Roving rows.';

-- §1. Add coverage_slot_id to hr_emploc_store_links
ALTER TABLE public.hr_emploc_store_links
  ADD COLUMN IF NOT EXISTS coverage_slot_id uuid;

ALTER TABLE public.hr_emploc_store_links
  DROP CONSTRAINT IF EXISTS hr_emploc_store_links_coverage_slot_fkey,
  ADD CONSTRAINT hr_emploc_store_links_coverage_slot_fkey
    FOREIGN KEY (coverage_slot_id) REFERENCES public.coverage_slots(id) ON DELETE SET NULL NOT VALID;

ALTER TABLE public.hr_emploc_store_links
  VALIDATE CONSTRAINT hr_emploc_store_links_coverage_slot_fkey;

COMMENT ON COLUMN public.hr_emploc_store_links.coverage_slot_id IS
  'OHM2026_0087A_FIX3: exact coverage slot that drove this store-link row. '
  'NULL for legacy Roving and Stationary links; populated for Coverage Group onboarding.';

-- §2. Replace confirm_coverage_group_onboarding.
--     hr_emploc insert:       vcode = NULL, vacancy_code_snapshot = CGCODE.
--     store-link inserts:     vcode = NULL, coverage_slot_id populated.
--     Legacy Roving/Stationary paths are unchanged.
CREATE OR REPLACE FUNCTION public.confirm_coverage_group_onboarding(
  p_applicant_id             uuid,
  p_selected_store_ids       uuid[],
  p_hired_by_user_id         uuid    DEFAULT NULL,
  p_hired_date               date    DEFAULT NULL,
  p_remarks                  text    DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role         text    := public.get_my_role();
  v_role_level   int     := COALESCE(public.get_my_role_level(), 0);
  v_profile_id   uuid    := public.get_my_profile_id();
  v_actor_name   text    := public.get_my_full_name();
  v_app          public.applicants%ROWTYPE;
  v_group        public.coverage_groups%ROWTYPE;
  v_hr           public.hr_emploc%ROWTYPE;
  v_hired_by_id  uuid;
  v_store_record record;
  v_covered_json jsonb   := '[]'::jsonb;
  v_store_id     uuid;
BEGIN
  -- 1. RBAC Guard
  IF NOT (
    public.i_have_full_access()
    OR v_role_level = 30
    OR v_role IN ('OM', 'HRCO', 'ATL', 'TL', 'Operations Manager')
  ) THEN
    RAISE EXCEPTION 'forbidden: Ops Team, Data Team, or Super Admin required'
      USING ERRCODE = '42501';
  END IF;

  -- 2. Fetch and lock applicant
  SELECT * INTO v_app FROM public.applicants WHERE id = p_applicant_id FOR UPDATE;
  IF NOT FOUND OR COALESCE(v_app.is_archived, false) THEN
    RAISE EXCEPTION 'applicant not found or archived' USING ERRCODE = 'P0002';
  END IF;

  IF v_app.coverage_group_id IS NULL OR v_app.coverage_slot_id IS NULL THEN
    RAISE EXCEPTION 'applicant is not assigned to a coverage group slot' USING ERRCODE = '22023';
  END IF;

  IF COALESCE(v_app.status, 'New') IN ('Failed', 'Backout', 'Did Not Report', 'Rejected by Ops') THEN
    RAISE EXCEPTION 'cannot onboard: applicant is in terminal status %', v_app.status USING ERRCODE = '22023';
  END IF;

  -- 3. Fetch and lock coverage group
  SELECT * INTO v_group FROM public.coverage_groups WHERE id = v_app.coverage_group_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'coverage group not found' USING ERRCODE = 'P0002';
  END IF;

  -- 4. Scope Guard
  IF NOT public.i_have_full_access() AND NOT (v_group.account_id = ANY(public.get_my_allowed_account_ids())) THEN
    RAISE EXCEPTION 'forbidden: coverage group is outside caller scope' USING ERRCODE = '42501';
  END IF;

  IF array_length(p_selected_store_ids, 1) IS NULL OR array_length(p_selected_store_ids, 1) < 1 THEN
    RAISE EXCEPTION 'at least one store must be selected' USING ERRCODE = '22023';
  END IF;

  -- 5. Build covered_stores JSONB array and validate footprint
  FOR v_store_id IN SELECT DISTINCT unnest(p_selected_store_ids) LOOP
    SELECT s.store_name, cgs.is_anchor INTO v_store_record
      FROM public.coverage_group_stores cgs
      JOIN public.stores s ON s.id = cgs.store_id
     WHERE cgs.coverage_group_id = v_group.id
       AND cgs.store_id = v_store_id
       AND cgs.archived_at IS NULL;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'store % is not part of active coverage group footprint', v_store_id USING ERRCODE = '22023';
    END IF;

    v_covered_json := v_covered_json || jsonb_build_object(
      'store_id',   v_store_id,
      'store_name', v_store_record.store_name,
      'is_anchor',  v_store_record.is_anchor
    );
  END LOOP;

  v_hired_by_id := COALESCE(p_hired_by_user_id, v_profile_id);

  -- 6. Update applicant status
  UPDATE public.applicants
     SET status             = 'Confirmed Onboard',
         hired_date         = COALESCE(p_hired_date, hired_date, CURRENT_DATE),
         hired_at           = COALESCE(hired_at, NOW()),
         hired_by           = v_actor_name,
         hired_by_team      = v_role,
         hired_by_user_id   = v_hired_by_id,
         deployed_by_user_id = v_profile_id,
         updated_at         = NOW(),
         updated_by         = v_profile_id
   WHERE id = p_applicant_id;

  -- 7. Insert Coverage HR Emploc.
  --    vcode = NULL            : fk_hr_emploc_vcode skips NULL values.
  --    vacancy_code_snapshot   : CGCODE for display/traceability; no FK.
  INSERT INTO public.hr_emploc (
    applicant_name, applicant_name_snapshot, applicant_id,
    vcode, vacancy_code_snapshot,
    account, account_id, position_id_snapshot, position,
    status, hr_status, hired_date,
    deployed_by_user_id, created_by, updated_by, date_requested,
    assignment_type, coverage_group_id, coverage_slot_id, covered_stores,
    ops_remarks
  ) VALUES (
    v_app.full_name, v_app.full_name, v_app.id,
    NULL, v_group.coverage_code,
    (SELECT account_name FROM public.accounts WHERE id = v_group.account_id),
    v_group.account_id, v_group.position_id,
    (SELECT position_name FROM public.positions WHERE id = v_group.position_id),
    'Pending Emploc', 'Pending', COALESCE(p_hired_date, CURRENT_DATE),
    v_profile_id, v_profile_id, v_profile_id, NOW(),
    'Coverage'::public.hr_emploc_assignment_type,
    v_group.id, v_app.coverage_slot_id, v_covered_json,
    p_remarks
  )
  RETURNING * INTO v_hr;

  -- 8. Populate hr_emploc_store_links for each selected store.
  --    vcode = NULL            : avoids uq_hr_emploc_store_links_emploc_vcode_active
  --                              collision (all Coverage links share the same CGCODE).
  --                              NULL values are treated as distinct in B-tree indexes.
  --    coverage_slot_id        : full slot traceability per store link.
  FOR v_store_id IN SELECT DISTINCT unnest(p_selected_store_ids) LOOP
    SELECT s.store_name, cgs.is_anchor INTO v_store_record
      FROM public.coverage_group_stores cgs
      JOIN public.stores s ON s.id = cgs.store_id
     WHERE cgs.coverage_group_id = v_group.id
       AND cgs.store_id = v_store_id
       AND cgs.archived_at IS NULL;

    INSERT INTO public.hr_emploc_store_links (
      hr_emploc_id, coverage_group_id, coverage_slot_id, store_id,
      vcode, store_name, account,
      status, confirmed_at, confirmed_by, created_by, updated_by
    ) VALUES (
      v_hr.id, v_group.id, v_app.coverage_slot_id, v_store_id,
      NULL, v_store_record.store_name, v_hr.account,
      'Confirmed', NOW(), v_profile_id, v_profile_id, v_profile_id
    );
  END LOOP;

  -- 9. Transition slot from pipeline → hr_processing
  PERFORM public.fn_sync_coverage_slot_to_hr_processing(
    p_coverage_slot_id => v_app.coverage_slot_id,
    p_applicant_id     => v_app.id,
    p_performed_by     => v_profile_id,
    p_source_fn        => 'confirm_coverage_group_onboarding'
  );

  -- 10. Log activity
  INSERT INTO public.employee_activity_log (
    emploc_no, vcode, activity_type, description, performed_by, metadata
  ) VALUES (
    v_app.full_name,
    v_group.coverage_code,
    'confirmed_onboard',
    'Coverage applicant confirmed onboard to ' || array_to_string(p_selected_store_ids::text[], ', '),
    v_actor_name,
    jsonb_build_object(
      'applicant_id',       v_app.id,
      'hr_emploc_id',       v_hr.id,
      'coverage_group_id',  v_group.id,
      'coverage_slot_id',   v_app.coverage_slot_id,
      'selected_stores',    v_covered_json
    )
  );

  RETURN jsonb_build_object(
    'ok',                true,
    'hr_emploc_id',      v_hr.id,
    'coverage_group_id', v_group.id,
    'coverage_slot_id',  v_app.coverage_slot_id
  );
END;
$$;

COMMENT ON FUNCTION public.confirm_coverage_group_onboarding(uuid, uuid[], uuid, date, text) IS
  'OHM2026_0087A_FIX3: Confirms Coverage Group onboarding. '
  'hr_emploc: vcode=NULL, vacancy_code_snapshot=CGCODE, assignment_type=Coverage. '
  'store links: vcode=NULL, coverage_slot_id populated per link. '
  'Slot transitions pipeline→hr_processing. Legacy Stationary/Roving paths unchanged.';

REVOKE ALL ON FUNCTION public.confirm_coverage_group_onboarding(uuid, uuid[], uuid, date, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.confirm_coverage_group_onboarding(uuid, uuid[], uuid, date, text) TO authenticated;

-- §3. Repair test applicant f4f276f3-324e-4807-af04-e4b690b8626b.
--     Left half-transitioned (For Onboard / slot pipeline / no hr_emploc) by:
--       20261002000000 — Roving constraint rollback
--       FIX2           — fk_hr_emploc_vcode violation (CGCODE in hr_emploc.vcode)
--       FIX3 (prev)    — uq_hr_emploc_store_links_emploc_vcode_active collision
--     This block is idempotent: skips if hr_emploc already exists for the applicant.
DO $$
DECLARE
  v_app     record;
  v_group   record;
  v_hr_id   uuid;
  v_store   record;
  v_covered jsonb := '[]'::jsonb;
  v_test_id uuid  := 'f4f276f3-324e-4807-af04-e4b690b8626b';
BEGIN
  -- Fetch applicant
  SELECT id, full_name, coverage_group_id, coverage_slot_id,
         status, hired_date, is_archived, created_by
    INTO v_app
    FROM public.applicants
   WHERE id = v_test_id;

  IF NOT FOUND THEN
    RAISE NOTICE 'OHM2026_0087A_FIX3 repair: applicant % not found — skipping', v_test_id;
    RETURN;
  END IF;

  -- Skip if already onboarded (idempotent guard)
  IF EXISTS (
    SELECT 1 FROM public.hr_emploc
     WHERE applicant_id = v_test_id AND deleted_at IS NULL
  ) THEN
    RAISE NOTICE 'OHM2026_0087A_FIX3 repair: hr_emploc already exists for % — skipping', v_test_id;
    RETURN;
  END IF;

  IF COALESCE(v_app.is_archived, false) THEN
    RAISE NOTICE 'OHM2026_0087A_FIX3 repair: applicant % is archived — skipping', v_test_id;
    RETURN;
  END IF;

  IF v_app.coverage_group_id IS NULL OR v_app.coverage_slot_id IS NULL THEN
    RAISE NOTICE 'OHM2026_0087A_FIX3 repair: applicant % has no coverage binding — skipping', v_test_id;
    RETURN;
  END IF;

  -- Fetch coverage group
  SELECT id, coverage_code, account_id, position_id
    INTO v_group
    FROM public.coverage_groups
   WHERE id = v_app.coverage_group_id;

  IF NOT FOUND THEN
    RAISE NOTICE 'OHM2026_0087A_FIX3 repair: coverage group % not found — skipping', v_app.coverage_group_id;
    RETURN;
  END IF;

  -- Build covered_stores from all active group stores
  FOR v_store IN
    SELECT cgs.store_id, s.store_name, cgs.is_anchor
      FROM public.coverage_group_stores cgs
      JOIN public.stores s ON s.id = cgs.store_id
     WHERE cgs.coverage_group_id = v_group.id
       AND cgs.archived_at IS NULL
  LOOP
    v_covered := v_covered || jsonb_build_object(
      'store_id',   v_store.store_id,
      'store_name', v_store.store_name,
      'is_anchor',  v_store.is_anchor
    );
  END LOOP;

  -- Advance applicant to Confirmed Onboard
  UPDATE public.applicants
     SET status     = 'Confirmed Onboard',
         hired_date = COALESCE(hired_date, CURRENT_DATE),
         hired_at   = COALESCE(hired_at, NOW()),
         updated_at = NOW()
   WHERE id = v_test_id;

  -- Insert hr_emploc.
  --   vcode = NULL          : fk_hr_emploc_vcode does not fire on NULL.
  --   vacancy_code_snapshot : CGCODE for display; no FK constraint.
  --   created_by/updated_by : v_app.created_by (uuid → users_profile, nullable).
  --                           Not v_app.id — applicants.id is not a users_profile row.
  INSERT INTO public.hr_emploc (
    applicant_name, applicant_name_snapshot, applicant_id,
    vcode, vacancy_code_snapshot,
    account, account_id, position_id_snapshot, position,
    status, hr_status, hired_date,
    created_by, updated_by, date_requested,
    assignment_type, coverage_group_id, coverage_slot_id, covered_stores,
    ops_remarks
  ) VALUES (
    v_app.full_name, v_app.full_name, v_app.id,
    NULL, v_group.coverage_code,
    (SELECT account_name FROM public.accounts WHERE id = v_group.account_id),
    v_group.account_id, v_group.position_id,
    (SELECT position_name FROM public.positions WHERE id = v_group.position_id),
    'Pending Emploc', 'Pending', COALESCE(v_app.hired_date, CURRENT_DATE),
    v_app.created_by, v_app.created_by, NOW(),
    'Coverage'::public.hr_emploc_assignment_type,
    v_group.id, v_app.coverage_slot_id, v_covered,
    'OHM2026_0087A_FIX3: direct repair — prior attempts failed fk_hr_emploc_vcode and uq_hr_emploc_store_links_emploc_vcode_active'
  )
  RETURNING id INTO v_hr_id;

  -- Insert store links for all active group stores.
  --   vcode = NULL          : avoids uq_hr_emploc_store_links_emploc_vcode_active
  --                           collision; CGCODE recoverable from parent hr_emploc.
  --   coverage_slot_id      : full slot traceability.
  --   created_by/updated_by : v_app.created_by (nullable; see above).
  FOR v_store IN
    SELECT cgs.store_id, s.store_name, cgs.is_anchor
      FROM public.coverage_group_stores cgs
      JOIN public.stores s ON s.id = cgs.store_id
     WHERE cgs.coverage_group_id = v_group.id
       AND cgs.archived_at IS NULL
  LOOP
    INSERT INTO public.hr_emploc_store_links (
      hr_emploc_id, coverage_group_id, coverage_slot_id, store_id,
      vcode, store_name, account,
      status, confirmed_at, created_by, updated_by
    ) VALUES (
      v_hr_id, v_group.id, v_app.coverage_slot_id, v_store.store_id,
      NULL, v_store.store_name,
      (SELECT account_name FROM public.accounts WHERE id = v_group.account_id),
      'Confirmed', NOW(),
      v_app.created_by, v_app.created_by
    );
  END LOOP;

  -- Transition slot pipeline → hr_processing
  UPDATE public.coverage_slots
     SET slot_status = 'hr_processing',
         updated_at  = NOW()
   WHERE id = v_app.coverage_slot_id
     AND slot_status = 'pipeline';

  RAISE NOTICE 'OHM2026_0087A_FIX3 repair: completed onboarding for applicant %, hr_emploc_id=%',
    v_test_id, v_hr_id;
END;
$$;
