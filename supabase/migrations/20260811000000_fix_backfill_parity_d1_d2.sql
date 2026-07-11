-- ============================================================
-- OHM2026_0015 — Patch Backfill Parity Defects D1 & D2
-- Migration: 20260811000000_fix_backfill_parity_d1_d2.sql
-- Depends on (all applied):
--   20260810000000_backfill_historical_vacancy_slots.sql (OHM2026_0013)
--   20260807000000_plantilla_slots_legacy_vcode_link.sql
--   20260809000000_vw_slot_derived_vacancy_shadow.sql
--   Pre-existing: vacancies (vcode PK), vw_vacancy_list,
--     plantilla_slots, slot_history.
-- Verification baseline: OHM2026_0014 (.ai/handoff.md, P1–P8)
-- ============================================================
-- Scope: SURGICAL PARITY PATCH ONLY. Fixes the two blocking defects
--   found in OHM2026_0014 so Vacancy ↔ Slot reconciliation can reach
--   cutover readiness. NO architectural / UI / read-model changes.
--
--   D1 — Missing slots (PG-DAU-069, VCOG2_0001)
--     Root cause: the OHM2026_0013 roving carve-out predicate
--       `v.employment_type <> 'Roving'`
--     evaluates to NULL (three-valued logic) for these two vacancies,
--     which have employment_type IS NULL, silently excluding them as if
--     they were Roving. A NULL employment_type is NOT roving — both are
--     Gap A pre-migration vacancies eligible for backfill. This patch
--     creates their missing slots using the SAME mapping rules as
--     OHM2026_0013, with the corrected predicate
--       (v.employment_type IS NULL OR v.employment_type <> 'Roving').
--
--   D2 — Aging correction (VCDG2_0001)
--     Root cause: the OHM2026_0013 Gap B patch set legacy_vcode on the
--     pre-existing slot 60cc15dc but left its only slot_history row's
--     created_at at the HC-request-creation timestamp (2026-05-29), so
--     the shadow view's open-episode aging resolved to 0 days instead of
--     the legacy 177. This patch UPDATEs that single open-episode history
--     row's created_at to the vacancy's vacant_date. It creates NO new
--     history rows and touches no other slot.
--
--   ATOMICITY & IDEMPOTENCY:
--     The whole patch runs inside one DO block (single transaction). Any
--     in-block assert failure RAISEs and rolls the entire migration back.
--     D1 reuses the dual-key NOT EXISTS guard (legacy_vcode OR
--     source_hc_request_id) so a re-run creates no duplicate slot. D2 is
--     guarded by `created_at IS DISTINCT FROM vacant_date`, so a re-run is
--     a no-op once the basis is correct.
--
--   AGING PRESERVATION:
--     D1 created slots set slot_history.created_at = vacancies.vacant_date
--     (NOT now()), matching OHM2026_0013. D2 preserves the original
--     vacancy vacant_date as the open-episode aging basis.
--
--   REVERSIBILITY:
--     D1 history rows are tagged
--       remarks LIKE 'OHM2026_0014 NULL-employment-type fix%'
--     so they can be identified and removed child-first if a post-commit
--     correction is approved (same pattern as OHM2026_0013 §3).
--
-- Expected effect (per OHM2026_0014 baseline, 2026-05-29):
--   • 2 new slots (PG-DAU-069 Open, VCOG2_0001 Pipeline).
--   • 1 corrected slot_history.created_at (VCDG2_0001 slot 60cc15dc).
-- ============================================================


DO $$
DECLARE
  v_operator         uuid := public.get_current_profile_id();
  v_eligible_count   integer;
  v_inserted_history integer;
  v_aging_patch      integer;
  v_dup_groups       integer;
BEGIN
  -- ──────────────────────────────────────────────────────────────────────
  -- D1 — Create the 2 missing slots (NULL employment_type, not Roving)
  -- ──────────────────────────────────────────────────────────────────────
  -- Surgically scoped to the two identified defects (vcode IN list) AND
  -- restricted to employment_type IS NULL (the root-cause population), while
  -- applying the full OHM2026_0013 eligibility + dual-key idempotency guard.

  SELECT COUNT(*)
  INTO   v_eligible_count
  FROM   public.vacancies v
  JOIN   public.vw_vacancy_list vl ON vl.vcode = v.vcode
  WHERE  v.vcode IN ('PG-DAU-069', 'VCOG2_0001')
    AND  v.employment_type IS NULL                       -- D1 root-cause population
    AND  vl.derived_status IN ('Open', 'Pipeline')
    AND  (v.is_archived IS NULL OR v.is_archived = FALSE)
    AND  v.deleted_at IS NULL
    AND  NOT EXISTS (                                     -- dual-key idempotency
           SELECT 1 FROM public.plantilla_slots ps
           WHERE  ps.legacy_vcode = v.vcode
              OR (v.source_headcount_request_id IS NOT NULL
                  AND ps.source_hc_request_id = v.source_headcount_request_id));

  WITH eligible AS (
    SELECT
      v.vcode,
      v.account_id,
      v.group_id,
      v.store_id,
      v.position,
      v.employment_type,
      v.source_headcount_request_id,
      v.vacant_date,
      CASE WHEN vl.derived_status = 'Pipeline' THEN 'pipeline' ELSE 'open' END AS slot_status
    FROM   public.vacancies v
    JOIN   public.vw_vacancy_list vl ON vl.vcode = v.vcode
    WHERE  v.vcode IN ('PG-DAU-069', 'VCOG2_0001')
      AND  v.employment_type IS NULL
      AND  vl.derived_status IN ('Open', 'Pipeline')
      AND  (v.is_archived IS NULL OR v.is_archived = FALSE)
      AND  v.deleted_at IS NULL
      AND  NOT EXISTS (
             SELECT 1 FROM public.plantilla_slots ps
             WHERE  ps.legacy_vcode = v.vcode
                OR (v.source_headcount_request_id IS NOT NULL
                    AND ps.source_hc_request_id = v.source_headcount_request_id))
  ),
  ins AS (
    INSERT INTO public.plantilla_slots (
      store_id,
      account_id,
      group_id,
      position,
      employment_type,
      is_roving,
      slot_status,
      source_hc_request_id,
      legacy_vcode,
      created_by,
      updated_by
    )
    SELECT
      e.store_id,
      e.account_id,
      e.group_id,
      e.position,
      COALESCE(e.employment_type, 'Stationary') AS employment_type,         -- NOT-NULL constraint: NULL → 'Stationary' (these are not roving)
      FALSE,                      -- non-roving; carve-out only excludes employment_type = 'Roving'
      e.slot_status,              -- 'open' | 'pipeline' from vw_vacancy_list.derived_status
      e.source_headcount_request_id,
      e.vcode,                    -- 1:1 legacy bridge
      v_operator,
      v_operator
    FROM eligible e
    RETURNING id, legacy_vcode, account_id
  )
  INSERT INTO public.slot_history (
    slot_id,
    account_id,
    action_type,
    new_value,
    reason_code,
    performed_by,
    remarks,
    created_at
  )
  SELECT
    ins.id,
    ins.account_id,
    'created',
    'open',                       -- anchors the open episode (even for pipeline slots)
    'HC_ADD',
    v_operator,
    'OHM2026_0014 NULL-employment-type fix — vcode=' || ins.legacy_vcode,
    COALESCE(e.vacant_date::timestamptz, NOW())          -- aging basis = legacy vacant_date
  FROM ins
  JOIN eligible e ON e.vcode = ins.legacy_vcode;
  GET DIAGNOSTICS v_inserted_history = ROW_COUNT;

  IF v_inserted_history <> v_eligible_count THEN
    RAISE EXCEPTION
      'OHM2026_0015 D1 aborted: inserted % history rows but % vacancies were eligible',
      v_inserted_history, v_eligible_count;
  END IF;

  -- ──────────────────────────────────────────────────────────────────────
  -- D2 — Correct VCDG2_0001 aging basis (slot 60cc15dc)
  -- ──────────────────────────────────────────────────────────────────────
  -- UPDATE the single existing open-episode history row's created_at to the
  -- vacancy's vacant_date. Creates NO new history row; touches only this
  -- slot's open-episode row. The IS DISTINCT FROM guard makes it idempotent.
  UPDATE public.slot_history sh
  SET    created_at = v.vacant_date::timestamptz
  FROM   public.vacancies v
  WHERE  sh.slot_id   = '60cc15dc-4f61-4806-80cd-5087cab08884'
    AND  sh.new_value = 'open'
    AND  v.vcode      = 'VCDG2_0001'
    AND  v.vacant_date IS NOT NULL
    AND  sh.created_at IS DISTINCT FROM v.vacant_date::timestamptz;
  GET DIAGNOSTICS v_aging_patch = ROW_COUNT;

  IF v_aging_patch > 1 THEN
    RAISE EXCEPTION
      'OHM2026_0015 D2 aborted: aging patch affected % rows (expected 0 or 1)',
      v_aging_patch;
  END IF;

  -- ──────────────────────────────────────────────────────────────────────
  -- Asserts: no legacy_vcode collisions introduced anywhere.
  -- ──────────────────────────────────────────────────────────────────────
  SELECT COUNT(*)
  INTO   v_dup_groups
  FROM (
    SELECT legacy_vcode
    FROM   public.plantilla_slots
    WHERE  legacy_vcode IS NOT NULL
    GROUP  BY legacy_vcode
    HAVING COUNT(*) > 1
  ) d;

  IF v_dup_groups > 0 THEN
    RAISE EXCEPTION
      'OHM2026_0015 aborted: % duplicate legacy_vcode group(s) detected',
      v_dup_groups;
  END IF;

  RAISE NOTICE 'OHM2026_0015 OK — D1: % slot(s) created; D2: % aging row(s) corrected; 0 dup legacy_vcode.',
    v_inserted_history, v_aging_patch;
END;
$$;


-- ============================================================
-- §2  Post-commit validation queries (run manually, read-only)
-- ============================================================
-- Re-run the OHM2026_0014 P1–P8 suite. Gate: P3 = 0 non-roving, P5 = 0,
-- P6 = 0, P7 = 0 rows, P2 all match.
--
-- P3 — Missing slots (expect only roving residue; 0 non-roving):
--   SELECT v.vcode, v.account_id, v.status, v.employment_type, v.source_headcount_request_id
--   FROM   public.vacancies v
--   LEFT JOIN public.plantilla_slots ps ON ps.legacy_vcode = v.vcode
--   WHERE  v.status IN ('Open','For Sourcing','Pipeline')
--     AND  (v.is_archived IS NULL OR v.is_archived = FALSE)
--     AND  v.deleted_at IS NULL AND ps.id IS NULL
--   ORDER  BY v.account_id, v.status, v.vcode;
--
-- P5 — NULL legacy_vcode slots (expect 0):
--   SELECT id, slot_status, source_hc_request_id
--   FROM   public.plantilla_slots WHERE legacy_vcode IS NULL;
--
-- P6 — Duplicate legacy_vcode (expect 0):
--   SELECT legacy_vcode, COUNT(*) FROM public.plantilla_slots
--   WHERE  legacy_vcode IS NOT NULL GROUP BY legacy_vcode HAVING COUNT(*) > 1;
--
-- P7 — Aging parity (expect 0 rows after D2):
--   SELECT s.legacy_vcode, s.aging_days AS slot_aging_days,
--          (CURRENT_DATE - v.vacant_date) AS legacy_aging_days, v.vacant_date
--   FROM   public.vw_slot_derived_vacancy_shadow s
--   JOIN   public.vacancies v ON v.vcode = s.legacy_vcode
--   WHERE  s.aging_days IS DISTINCT FROM (CURRENT_DATE - v.vacant_date);
--
-- ============================================================
-- §3  REVERSAL PLAN (post-commit correction — requires explicit approval)
-- ============================================================
--   -- D1 slots (tagged), child-first, only if unoccupied:
--   WITH bf AS (
--     SELECT DISTINCT slot_id FROM public.slot_history
--     WHERE remarks LIKE 'OHM2026_0014 NULL-employment-type fix%'
--   )
--   -- 1) DELETE FROM public.slot_history  WHERE slot_id IN (SELECT slot_id FROM bf);
--   -- 2) DELETE FROM public.plantilla_slots ps
--   --      WHERE ps.id IN (SELECT slot_id FROM bf)
--   --        AND ps.current_occupant_plantilla_id IS NULL;
--   SELECT * FROM bf;
--   -- D2 reversal (only if needed): reset the open-episode row's created_at to
--   -- the HC-request creation timestamp (2026-05-29 10:41:16+00) for slot
--   -- 60cc15dc. Source from audit if exact reversal is required.
-- ============================================================
