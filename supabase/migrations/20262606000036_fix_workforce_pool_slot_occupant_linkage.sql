-- Migration: 20262606000036_fix_workforce_pool_slot_occupant_linkage
-- Created: 2026-08-10
-- Purpose: Fix Bundler Pool (and all Workforce Pool types) showing N identical
--          duplicate applicant cards for a single hired employee on a multi-HC
--          VCode. Root cause: v_workforce_pool_employees joined plantilla to
--          workforce_pool_slots by vcode alone; since ohm#p9x4k7m2 (1 VCode =
--          N slots), that join fans one employee row out across every slot
--          sharing the VCode. Compounding write bug: move_to_plantilla() marked
--          ALL slots for a vcode 'filled' instead of exactly one. This migration
--          adds a per-slot occupant column, fixes both the write path and the
--          read-side view to key off it, and backfills/repairs existing data.
--
-- Smoke Tests:
-- S1: For a VCode with HC=6 and exactly 1 hired pool employee, after this
--     migration `SELECT count(*) FROM v_workforce_pool_employees WHERE vcode
--     (via pool_slot_id join) resolves to that VCode` should show ONE row for
--     that employee, and `SELECT status, occupant_employee_id FROM
--     workforce_pool_slots WHERE vcode = '<vcode>'` should show exactly 1 row
--     'filled' with occupant_employee_id set, and 5 rows 'open' with NULL.
-- S2: Submitting a fresh HC Request, approving it, then adding 1 applicant via
--     move_to_plantilla must occupy exactly 1 slot (not all slots) and the
--     Active/Available pool tab must show exactly 1 card for that applicant.
-- S3: Existing single-HC (HC=1) VCodes must be unaffected — one slot, one
--     employee, one card, both before and after.

BEGIN;

-- ── 1. Schema: per-slot occupant linkage ────────────────────────────────────
ALTER TABLE public.workforce_pool_slots
  ADD COLUMN IF NOT EXISTS occupant_employee_id uuid REFERENCES public.plantilla(id);

CREATE UNIQUE INDEX IF NOT EXISTS workforce_pool_slots_occupant_employee_id_key
  ON public.workforce_pool_slots (occupant_employee_id)
  WHERE occupant_employee_id IS NOT NULL;

-- ── 2. Deterministic backfill / repair of existing corrupted data ──────────
-- move_to_plantilla() previously marked every slot sharing a vcode 'filled'
-- regardless of real occupancy. Rank-match existing pool employees to existing
-- active slots within the same vcode by creation order (stable, reproducible),
-- assign occupant_employee_id to the matched slot, and reset every unmatched
-- slot on that vcode back to 'open'. VCodes with 0 employees are untouched.
WITH ranked_employees AS (
  SELECT p.id AS employee_id,
         p.vcode,
         ROW_NUMBER() OVER (PARTITION BY p.vcode ORDER BY p.created_at, p.id) AS rn
    FROM public.plantilla p
   WHERE p.is_pool_employee = true
     AND p.is_deleted = false
     AND p.deactivated_at IS NULL
     AND p.vcode IS NOT NULL
),
ranked_slots AS (
  SELECT wps.id AS slot_id,
         wps.vcode,
         ROW_NUMBER() OVER (PARTITION BY wps.vcode ORDER BY wps.created_at, wps.id) AS rn
    FROM public.workforce_pool_slots wps
   WHERE wps.deleted_at IS NULL
     AND wps.is_active = true
),
matched AS (
  SELECT rs.slot_id, re.employee_id
    FROM ranked_slots rs
    JOIN ranked_employees re ON re.vcode = rs.vcode AND re.rn = rs.rn
)
UPDATE public.workforce_pool_slots wps
   SET occupant_employee_id = m.employee_id,
       status     = 'filled',
       updated_at = NOW()
  FROM matched m
 WHERE wps.id = m.slot_id
   AND wps.occupant_employee_id IS DISTINCT FROM m.employee_id;

-- Any slot left 'filled' with no matched occupant was a phantom-filled slot
-- from the old bug (e.g. the other 5 of a 6-HC vcode with only 1 real hire) —
-- restore it to 'open'.
UPDATE public.workforce_pool_slots wps
   SET status     = 'open',
       updated_at = NOW()
 WHERE wps.deleted_at IS NULL
   AND wps.is_active = true
   AND wps.status = 'filled'
   AND wps.occupant_employee_id IS NULL;

-- ── 3. Fix the read side: key the employee↔slot join off occupant, not vcode ─
CREATE OR REPLACE VIEW public.v_workforce_pool_employees AS
 SELECT p.id AS employee_id,
    p.employee_no AS employee_number,
    p.employee_name AS full_name,
    p.last_name,
    p.first_name,
    p.middle_name,
    p.account AS home_account,
    p.account_id AS home_account_id,
    p.store_id AS home_store_id,
    wps.id AS pool_slot_id,
    COALESCE(wps.pool_type_id, p.pool_type_id) AS pool_type_id,
    wpt.code AS pool_type_code,
    wpt.name AS pool_type_name,
    wps.group_id AS tagged_group_id,
    g.group_name AS tagged_group_name,
    COALESCE(agg.active_deployment_count, 0::bigint) AS active_deployment_count,
    COALESCE(agg.active_store_count, 0::bigint) AS active_store_count,
        CASE
            WHEN COALESCE(agg.active_deployment_count, 0::bigint) = 0 THEN 'None'::text
            WHEN agg.active_deployment_count >= 1 AND agg.active_deployment_count <= 5 THEN 'Low'::text
            WHEN agg.active_deployment_count >= 6 AND agg.active_deployment_count <= 10 THEN 'Medium'::text
            WHEN agg.active_deployment_count >= 11 AND agg.active_deployment_count <= 20 THEN 'High'::text
            ELSE 'Critical'::text
        END AS deployment_load_indicator,
        CASE
            WHEN p.is_deleted = true OR p.deactivated_at IS NOT NULL OR p.status <> 'Active'::text THEN 'Inactive'::text
            WHEN pend.pending_request_id IS NOT NULL THEN 'Reserved'::text
            WHEN COALESCE(agg.active_deployment_count, 0::bigint) > 0 THEN 'Deployed'::text
            ELSE 'Available'::text
        END AS availability_status,
    wps.group_id IS NULL AS is_global_visible,
    pend.pending_request_id IS NOT NULL AS has_pending_request,
    pend.pending_request_id,
    pend.pending_requested_account,
    pend.pending_requested_store,
    p.status AS employee_status,
    p.date_hired,
    p."position",
    p.deployment_type AS home_deployment_type,
    COALESCE(lt.has_longterm, false) AS needs_review
   FROM public.plantilla p
     -- ohm#9x2k7m4q: was `wps.vcode = p.vcode`, which fans one employee out
     -- across every slot sharing a multi-HC vcode. Key off the specific
     -- occupied slot instead; fall back to vcode only when a legacy row has
     -- no occupant recorded yet (kept LEFT so such rows still surface once,
     -- not dropped, but never duplicated because occupant match is unique).
     LEFT JOIN public.workforce_pool_slots wps
       ON wps.deleted_at IS NULL
      AND (
            wps.occupant_employee_id = p.id
         OR (
              wps.occupant_employee_id IS NULL
              AND wps.vcode = p.vcode
              AND NOT EXISTS (
                SELECT 1 FROM public.workforce_pool_slots wps2
                 WHERE wps2.vcode = p.vcode
                   AND wps2.occupant_employee_id = p.id
                   AND wps2.deleted_at IS NULL
              )
            )
          )
     JOIN public.workforce_pool_types wpt
       ON wpt.id = COALESCE(wps.pool_type_id, p.pool_type_id) AND wpt.is_active = true
     LEFT JOIN public.groups g ON g.id = wps.group_id
     LEFT JOIN ( SELECT workforce_assignments.employee_id,
            count(*) FILTER (WHERE (workforce_assignments.status = ANY (ARRAY['Active'::text, 'Approved'::text])) AND workforce_assignments.deleted_at IS NULL) AS active_deployment_count,
            count(DISTINCT workforce_assignments.assigned_store_id) FILTER (WHERE (workforce_assignments.status = ANY (ARRAY['Active'::text, 'Approved'::text])) AND workforce_assignments.deleted_at IS NULL) AS active_store_count
           FROM public.workforce_assignments
          GROUP BY workforce_assignments.employee_id) agg ON agg.employee_id = p.id
     LEFT JOIN ( SELECT DISTINCT workforce_assignments.employee_id,
            true AS has_longterm
           FROM public.workforce_assignments
          WHERE (workforce_assignments.status = ANY (ARRAY['Active'::text, 'Approved'::text])) AND workforce_assignments.start_date <= (CURRENT_DATE - '30 days'::interval) AND workforce_assignments.deleted_at IS NULL) lt ON lt.employee_id = p.id
     LEFT JOIN ( SELECT war.employee_id,
            war.id AS pending_request_id,
            a.account_name AS pending_requested_account,
            s.store_name AS pending_requested_store
           FROM public.workforce_assignment_requests war
             LEFT JOIN public.accounts a ON a.id = war.requested_account_id
             LEFT JOIN public.stores s ON s.id = war.requested_store_id
          WHERE war.status = 'Pending'::text) pend ON pend.employee_id = p.id
  WHERE p.is_deleted = false AND p.is_pool_employee = true AND p.deactivated_at IS NULL
    AND ((public.get_my_role_level() = ANY (ARRAY[100, 90, 30])) OR public.i_have_full_access() OR wps.group_id IS NULL OR (EXISTS ( SELECT 1
           FROM public.accounts a
          WHERE a.group_id = wps.group_id AND (a.id::text = ANY (public.get_my_allowed_accounts())))));

-- ── 4. Fix the write side: claim exactly one open slot, not every slot on the vcode ─
CREATE OR REPLACE FUNCTION public.move_to_plantilla(p_id uuid)
 RETURNS plantilla
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_emp             public.hr_emploc;
  v_pl              public.plantilla;
  v_actor           uuid := get_my_profile_id();
  v_is_pool         boolean := false;
  v_pool_type_id    uuid;
  v_home_account_id uuid;
  v_home_acct       public.accounts;
  v_slot_id         uuid := NULL;
  v_slot_auth       jsonb;
  v_pool_slot_id    uuid := NULL;
BEGIN
  -- Data Team = Encoder + Head Admin + Super Admin
  IF NOT (i_have_full_access() OR get_my_role() = 'Encoder') THEN
    RAISE EXCEPTION 'forbidden: Data Team role required' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_emp FROM hr_emploc WHERE id = p_id FOR UPDATE;
  IF NOT FOUND OR v_emp.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'hr_emploc % not found or archived', p_id USING ERRCODE = 'P0002';
  END IF;
  IF v_emp.status <> 'Ready for Plantilla' THEN
    RAISE EXCEPTION 'cannot move: status is "%", expected "Ready for Plantilla"', v_emp.status
      USING ERRCODE = '22023';
  END IF;
  IF v_emp.employee_no IS NULL THEN
    RAISE EXCEPTION 'cannot move: employee_no is null' USING ERRCODE = '22023';
  END IF;

  -- Guard A: hr_emploc_id already active in plantilla
  IF EXISTS (
    SELECT 1
      FROM public.plantilla
     WHERE hr_emploc_id              = p_id
       AND COALESCE(is_deleted, false) = false
  ) THEN
    RAISE EXCEPTION 'hr_emploc % already moved to plantilla', p_id USING ERRCODE = '23505';
  END IF;

  -- Guard B: moved_to_plantilla_at already stamped
  IF v_emp.moved_to_plantilla_at IS NOT NULL THEN
    RAISE EXCEPTION
      'hr_emploc % already has moved_to_plantilla_at set', p_id USING ERRCODE = '23505';
  END IF;

  -- Detect pool vacancy
  IF v_emp.vacancy_id IS NOT NULL THEN
    SELECT v.is_pool_vacancy, v.pool_type_id, v.home_account_id
      INTO v_is_pool, v_pool_type_id, v_home_account_id
      FROM vacancies v
     WHERE v.id = v_emp.vacancy_id;
  END IF;
  v_is_pool := COALESCE(v_is_pool, false);

  -- ── 1. ATOMIC SLOT SELECTION & RESERVATION (Stationary non-pool non-roving path) ──
  IF NOT v_is_pool AND COALESCE(v_emp.assignment_type, 'Stationary') <> 'Roving' AND v_emp.coverage_slot_id IS NULL THEN
    -- Atomic slot selection using FOR UPDATE SKIP LOCKED
    SELECT id INTO v_slot_id
    FROM public.plantilla_slots
    WHERE legacy_vcode = v_emp.vcode
      AND slot_status = 'open'
    ORDER BY created_at ASC
    LIMIT 1
    FOR UPDATE SKIP LOCKED;

    -- 2. HANDLE NO AVAILABLE SLOT
    IF v_slot_id IS NULL THEN
      -- Fallback: check if hr_emploc already holds a reserved slot in open/hr_processing state
      IF v_emp.slot_id IS NOT NULL THEN
        SELECT id INTO v_slot_id
        FROM public.plantilla_slots
        WHERE id = v_emp.slot_id
          AND slot_status IN ('open', 'hr_processing')
        FOR UPDATE SKIP LOCKED;
      END IF;

      IF v_slot_id IS NULL THEN
        RAISE EXCEPTION 'No available headcount for this VCode.' USING ERRCODE = '22023';
      END IF;
    END IF;

    -- 3. TRANSITION SLOT STATE (RESERVE FIRST)
    -- ohm#7k2d9f4a: routed through fn_set_slot_status (slot authority)
    v_slot_auth := public.fn_set_slot_status(
      p_slot_id      => v_slot_id,
      p_new_status   => 'hr_processing',
      p_reason_code  => NULL,
      p_performed_by => v_actor,
      p_remarks      => 'move_to_plantilla: slot reserved for hr_emploc ' || p_id::text
    );
    IF (v_slot_auth->>'status') NOT IN ('ok', 'no_op') THEN
      RAISE EXCEPTION 'move_to_plantilla: slot % reservation blocked: %',
        v_slot_id, COALESCE(v_slot_auth->>'blocked_reason', 'unknown')
        USING ERRCODE = '22023';
    END IF;
  END IF;

  -- ── 4. INSERT INTO PLANTILLA ───────────────────────────────────────────────

  -- ── POOL PATH ───────────────────────────────────────────────────────────────
  IF v_is_pool THEN

    IF v_home_account_id IS NULL THEN
      RAISE EXCEPTION 'pool vacancy % has no home_account_id — cannot route to pool',
        v_emp.vcode USING ERRCODE = '22023';
    END IF;

    SELECT * INTO v_home_acct FROM accounts WHERE id = v_home_account_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'home account % not found', v_home_account_id USING ERRCODE = 'P0002';
    END IF;

    IF EXISTS (
      SELECT 1 FROM plantilla
       WHERE employee_no = v_emp.employee_no
         AND account_id  = v_home_account_id
         AND is_deleted  = false
         AND status IN ('Active', 'For Deactivation', 'On Leave')
    ) THEN
      RAISE EXCEPTION
        'pool plantilla already has active record for employee_no % under home account',
        v_emp.employee_no USING ERRCODE = '23505';
    END IF;

    -- ohm#9x2k7m4q: claim exactly one open, undeleted, active slot for this
    -- vcode up front (was previously selected implicitly by updating every
    -- slot sharing the vcode after insert). Lock it so concurrent moves on
    -- the same multi-HC vcode cannot double-claim the same slot.
    SELECT id INTO v_pool_slot_id
      FROM public.workforce_pool_slots
     WHERE vcode = v_emp.vcode
       AND deleted_at IS NULL
       AND is_active = true
       AND status = 'open'
     ORDER BY created_at ASC
     LIMIT 1
     FOR UPDATE SKIP LOCKED;

    IF v_pool_slot_id IS NULL THEN
      RAISE EXCEPTION 'No available pool slot for VCode %.', v_emp.vcode USING ERRCODE = '22023';
    END IF;

    INSERT INTO plantilla (
      account,              account_id,
      store_id,             store_name,
      position,             position_id,
      employee_no,          emploc_no,
      employee_name,        employee_name_snapshot,
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
      v_emp.employee_no,        v_emp.employee_no,
      COALESCE(v_emp.employee_name_snapshot, v_emp.applicant_name),
      COALESCE(v_emp.employee_name_snapshot, v_emp.applicant_name),
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
      v_actor, v_actor, v_actor,
      NOW(), NOW()
    )
    RETURNING * INTO v_pl;

    -- Close via vacancy_id if available
    IF v_emp.vacancy_id IS NOT NULL THEN
      UPDATE vacancies
         SET status     = 'Filled',
             updated_at = NOW(),
             updated_by = v_actor
       WHERE id = v_emp.vacancy_id;
    END IF;

    -- VCODE fallback: close any remaining Open vacancy for this VCODE
    UPDATE public.vacancies
       SET status     = 'Filled',
           updated_at = NOW(),
           updated_by = v_actor
     WHERE vcode      = v_emp.vcode
       AND status     IN ('Open', 'For Sourcing')
       AND COALESCE(is_archived, false) = false
       AND deleted_at IS NULL;

    -- ohm#9x2k7m4q: mark ONLY the claimed slot occupied (was: every slot
    -- sharing the vcode), and record who occupies it.
    UPDATE public.workforce_pool_slots
       SET status               = 'filled',
           occupant_employee_id = v_pl.id,
           updated_at           = NOW()
     WHERE id = v_pool_slot_id;

  -- ── ROVING PATH ─────────────────────────────────────────────────────────────
  ELSIF v_emp.assignment_type = 'Roving' THEN

    IF EXISTS (
      SELECT 1 FROM plantilla
       WHERE roving_assignment_id = v_emp.roving_assignment_id
         AND is_deleted = false
    ) THEN
      RAISE EXCEPTION
        'roving plantilla master already exists for roving_assignment_id %. '
        'Use link_late_store_to_plantilla for new store additions.',
        v_emp.roving_assignment_id USING ERRCODE = '23505';
    END IF;

    IF NOT EXISTS (
      SELECT 1 FROM hr_emploc_store_links
       WHERE hr_emploc_id = p_id
         AND status       = 'Confirmed'
         AND deleted_at   IS NULL
    ) THEN
      RAISE EXCEPTION 'no confirmed store links found for roving hr_emploc %', p_id
        USING ERRCODE = '22023';
    END IF;

    INSERT INTO plantilla (
      account,              account_id,           chain_id,             province_id,
      position,             position_id,
      employee_no,          emploc_no,
      employee_name,        employee_name_snapshot,
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
      v_emp.employee_no, v_emp.employee_no,
      COALESCE(v_emp.employee_name_snapshot, v_emp.applicant_name),
      COALESCE(v_emp.employee_name_snapshot, v_emp.applicant_name),
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
      v_actor, v_actor, v_actor,
      NOW(), NOW()
    )
    RETURNING * INTO v_pl;

    INSERT INTO public.plantilla_store_links (
      plantilla_id,
      roving_assignment_id,
      hr_emploc_store_link_id,
      vacancy_id,
      vcode,
      store_name,
      account,
      status,
      linked_at,
      linked_by,
      created_by,
      updated_by
    )
    SELECT
      v_pl.id,
      sl.roving_assignment_id,
      sl.id,
      sl.vacancy_id,
      sl.vcode,
      sl.store_name,
      sl.account,
      'Active',
      NOW(),
      v_actor,
      v_actor,
      v_actor
    FROM public.hr_emploc_store_links sl
    WHERE sl.hr_emploc_id = p_id
      AND sl.status       = 'Confirmed'
      AND sl.deleted_at   IS NULL;

    -- Close confirmed store vacancies via vacancy_id
    UPDATE public.vacancies
       SET status     = 'Filled',
           updated_at = NOW(),
           updated_by = v_actor
     WHERE id IN (
       SELECT vacancy_id
         FROM public.hr_emploc_store_links
        WHERE hr_emploc_id = p_id
          AND status       = 'Confirmed'
          AND deleted_at   IS NULL
          AND vacancy_id   IS NOT NULL
     )
     AND status NOT IN ('Filled', 'Closed', 'Archived');

    -- VCODE fallback: close any remaining Open vacancy for the roving VCODE
    UPDATE public.vacancies
       SET status     = 'Filled',
           updated_at = NOW(),
           updated_by = v_actor
     WHERE vcode      = v_emp.vcode
       AND status     IN ('Open', 'For Sourcing')
       AND COALESCE(is_archived, false) = false
       AND deleted_at IS NULL;

  -- ── STATIONARY PATH / CGCODE COVERAGE SUB-PATH ─────────────────────────────
  ELSE

    IF v_emp.coverage_slot_id IS NOT NULL THEN
      -- ── CGCODE COVERAGE SUB-PATH ───────────────────────────────────────────
      INSERT INTO plantilla (
        account,              account_id,           chain_id,             province_id,
        position,             position_id,
        employee_no,          emploc_no,
        employee_name,        employee_name_snapshot,
        civil_status,         date_of_birth,
        sss_no,               philhealth_no,         pagibig_no,
        date_hired,           vacancy_id,            vacancy_code_snapshot,
        vcode,
        hrco_name,            hrco_user_id_snapshot,
        om_user_id_snapshot,  atl_user_id_snapshot,
        area,                 area_name_snapshot,
        hr_emploc_id,
        coverage_slot_id,     coverage_group_id,
        deployment_type,
        status,               tagged_at,
        moved_by_user_id,     created_by,            updated_by,
        created_at,           updated_at
      )
      VALUES (
        v_emp.account, v_emp.account_id, v_emp.chain_id, v_emp.province_id,
        v_emp.position, v_emp.position_id_snapshot,
        v_emp.employee_no, v_emp.employee_no,
        COALESCE(v_emp.employee_name_snapshot, v_emp.applicant_name),
        COALESCE(v_emp.employee_name_snapshot, v_emp.applicant_name),
        v_emp.civil_status_snapshot, v_emp.birthdate_snapshot,
        v_emp.sss_snapshot, v_emp.philhealth_snapshot, v_emp.pagibig_snapshot,
        v_emp.hired_date, v_emp.vacancy_id, v_emp.vacancy_code_snapshot,
        v_emp.vcode,
        v_emp.hrco_name, v_emp.hrco_user_id_snapshot,
        v_emp.om_user_id_snapshot, v_emp.atl_user_id_snapshot,
        v_emp.area_name_snapshot, v_emp.area_name_snapshot,
        v_emp.id,
        v_emp.coverage_slot_id, v_emp.coverage_group_id,
        'Roving',
        'Active', CURRENT_DATE,
        v_actor, v_actor, v_actor,
        NOW(), NOW()
      )
      RETURNING * INTO v_pl;

      -- Close carrier CGCODE vacancy via vacancy_id if available
      IF v_emp.vacancy_id IS NOT NULL THEN
        UPDATE vacancies
           SET status     = 'Filled',
               updated_at = NOW(),
               updated_by = v_actor
         WHERE id = v_emp.vacancy_id;
      END IF;

      -- VCODE fallback: close any remaining Open carrier vacancy
      UPDATE public.vacancies
         SET status     = 'Filled',
             updated_at = NOW(),
             updated_by = v_actor
       WHERE vcode      = v_emp.vcode
         AND status     IN ('Open', 'For Sourcing')
         AND COALESCE(is_archived, false) = false
         AND deleted_at IS NULL;

    ELSE
      -- ── PURE STATIONARY PATH ──────────────────────────────────────────────
      IF EXISTS (
        SELECT 1 FROM plantilla
         WHERE employee_no = v_emp.employee_no
           AND is_deleted  = false
           AND status IN ('Active', 'For Deactivation', 'On Leave')
      ) THEN
        RAISE EXCEPTION 'plantilla already has active record for employee_no %',
          v_emp.employee_no USING ERRCODE = '23505';
      END IF;

      INSERT INTO plantilla (
        account,              account_id,            chain_id,             store_id,
        store_name,           position,              position_id,
        province_id,
        employee_no,          emploc_no,
        employee_name,        employee_name_snapshot,
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
        v_emp.employee_no,    v_emp.employee_no,
        COALESCE(v_emp.employee_name_snapshot, v_emp.applicant_name),
        COALESCE(v_emp.employee_name_snapshot, v_emp.applicant_name),
        v_emp.civil_status_snapshot, v_emp.birthdate_snapshot,
        v_emp.sss_snapshot,   v_emp.philhealth_snapshot, v_emp.pagibig_snapshot,
        v_emp.hired_date,     v_emp.vacancy_id,        v_emp.vacancy_code_snapshot,
        v_emp.vcode,
        v_emp.hrco_name,      v_emp.hrco_user_id_snapshot,
        v_emp.om_user_id_snapshot, v_emp.atl_user_id_snapshot,
        v_emp.area_name_snapshot, v_emp.area_name_snapshot,
        v_emp.id,
        'Active',             CURRENT_DATE,
        v_actor, v_actor, v_actor, NOW(), NOW()
      )
      RETURNING * INTO v_pl;

    END IF; -- end coverage/pure-stationary split

  END IF; -- end pool/roving/stationary split

  -- ── 5. FINALIZE SLOT (Mark slot filled & link occupant) ───────────────────
  IF v_slot_id IS NOT NULL THEN
    -- ohm#7k2d9f4a: routed through fn_set_slot_status (slot authority)
    v_slot_auth := public.fn_set_slot_status(
      p_slot_id               => v_slot_id,
      p_new_status            => 'filled',
      p_reason_code           => NULL,
      p_performed_by          => v_actor,
      p_remarks               => 'move_to_plantilla: slot filled by plantilla ' || v_pl.id::text,
      p_occupant_plantilla_id => v_pl.id
    );
    IF (v_slot_auth->>'status') NOT IN ('ok', 'no_op') THEN
      RAISE EXCEPTION 'move_to_plantilla: slot % finalization blocked: %',
        v_slot_id, COALESCE(v_slot_auth->>'blocked_reason', 'unknown')
        USING ERRCODE = '22023';
    END IF;
  END IF;

  -- ── Vacancy Closure for Pure Stationary Path ─────────────────────────────
  IF NOT v_is_pool AND COALESCE(v_emp.assignment_type, 'Stationary') <> 'Roving' AND v_emp.coverage_slot_id IS NULL THEN
    IF v_emp.vacancy_id IS NOT NULL THEN
      UPDATE vacancies
         SET status     = 'Filled',
             updated_at = NOW(),
             updated_by = v_actor
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
           updated_by = v_actor
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

  -- ── Common: update hr_emploc status ─────────────────────────────────────────
  UPDATE hr_emploc
     SET status                = 'Moved to Plantilla',
         hr_status             = 'Transferred',
         moved_to_plantilla_at = NOW(),
         moved_to_plantilla_by = v_actor,
         updated_at            = NOW(),
         updated_by            = v_actor
   WHERE id = p_id;

  PERFORM log_audit_event('plantilla', 'INSERT', v_pl.id, NULL, to_jsonb(v_pl));
  PERFORM log_audit_event('hr_emploc', 'UPDATE', p_id, to_jsonb(v_emp),
                          to_jsonb((SELECT h FROM hr_emploc h WHERE h.id = p_id)));

  IF v_emp.coverage_slot_id IS NOT NULL THEN
    PERFORM public.fn_sync_coverage_slot_to_active(
      p_coverage_slot_id => v_emp.coverage_slot_id,
      p_plantilla_id     => v_pl.id,
      p_performed_by     => v_actor,
      p_source_fn        => 'move_to_plantilla'
    );
  END IF;

  RETURN v_pl;

-- ── 6. FAILURE SAFETY (Rollback Revert) ──────────────────────────────────────
EXCEPTION WHEN OTHERS THEN
  IF v_slot_id IS NOT NULL THEN
    UPDATE public.plantilla_slots
    SET slot_status = 'open',
        updated_at = NOW()
    WHERE id = v_slot_id;
  END IF;
  IF v_pool_slot_id IS NOT NULL THEN
    UPDATE public.workforce_pool_slots
       SET status = 'open',
           occupant_employee_id = NULL,
           updated_at = NOW()
     WHERE id = v_pool_slot_id;
  END IF;
  RAISE;
END
$function$
;

COMMIT;
