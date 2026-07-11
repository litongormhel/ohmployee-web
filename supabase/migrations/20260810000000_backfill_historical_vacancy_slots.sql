-- ============================================================
-- OHM2026_0013 — Historical Vacancy → Plantilla Slot Backfill
-- Migration: 20260810000000_backfill_historical_vacancy_slots.sql
-- Depends on (all applied):
--   20260804000000_plantilla_slot_foundation_v1.sql
--     (plantilla_slots, slot_history, slot_reason_codes)
--   20260805000000_fn_create_slots_from_hc_request.sql
--   20260806000000_wire_slot_creation_into_hc_completion.sql
--     (source_hc_request_id on plantilla_slots)
--   20260807000000_plantilla_slots_legacy_vcode_link.sql
--     (legacy_vcode on plantilla_slots)
--   20260809000000_vw_slot_derived_vacancy_shadow.sql
--   Pre-existing: vacancies (vcode PK), vw_vacancy_list,
--     accounts, groups, stores, users_profile.
-- Plan: docs/architecture/vacancy_slot_backfill_plan.md (approved)
-- Reconciliation baseline: OHM2026_0011 (.ai/handoff.md, R1–R6)
-- ============================================================
-- Scope: ONE-TIME, CONTROLLED DATA MIGRATION.
--   Creates one plantilla_slots row (+ one slot_history row) for each
--   eligible legacy Open/Pipeline vacancy that has no slot yet, and
--   patches the single known Gap B slot (VCDG2_0001) so its legacy_vcode
--   link is set instead of creating a duplicate.
--
--   This is Phase 5 of the slot-derived Vacancy read-model sequence
--   (slot_derived_vacancy_read_model.md §9). The shadow view stays the
--   only slot consumer; legacy vacancies remain the authoritative UI
--   read source. NO UI behavior changes.
--
--   This migration deliberately does NOT:
--     • change the Vacancy / HR Emploc / Plantilla / Transfer / Import
--       read or write paths,
--     • wire any slot lifecycle automation (Phase 6 — deferred),
--     • backfill roving vacancies (Q2·5 carve-out — deferred until the
--       roving coverage model lands; one slot per roving VCODE would make
--       Required HC = N instead of 1),
--     • backfill occupied / closed / HR-processing vacancies (only empty
--       open/pipeline slots are ever created here),
--     • touch MFR / CENCOM.
--
--   ATOMICITY & IDEMPOTENCY:
--     The whole backfill runs inside this migration's single transaction
--     via one DO block. Any in-block assert failure RAISEs and rolls the
--     entire migration back (zero partial rows). The slot INSERT uses a
--     dual-key NOT EXISTS guard (legacy_vcode OR source_hc_request_id) and
--     the Gap B patch uses a `legacy_vcode IS NULL` guard, so a re-run is
--     a no-op for every already-represented vacancy.
--
--   AGING PRESERVATION:
--     Each created slot's slot_history.created_at is set to the legacy
--     vacancies.vacant_date (NOT now()), so the shadow view's open-episode
--     aging matches the legacy SLA chip one-for-one. plantilla_slots.created_at
--     stays now() (audit-honest true backfill timestamp).
--
--   REVERSIBILITY:
--     Every history row written here is tagged
--       remarks LIKE 'OHM2026_0013 historical backfill%'
--     so the backfill's own rows can be identified and removed child-first
--     if a post-commit correction is approved (see REVERSAL PLAN below).
--
-- Expected effect (per OHM2026_0011 baseline, 2026-05-29):
--   • ~13 new slots (11 Gap A pre-migration + 2 Gap C post-migration),
--     minus any roving carve-out.
--   • 1 patched slot (Gap B: VCDG2_0001 → legacy_vcode set).
--   Exact counts may differ if the underlying data changed since baseline;
--   the DO block asserts internal consistency, not a hardcoded count.
-- ============================================================


-- ============================================================
-- §1  Backfill transaction (single atomic DO block)
-- ============================================================
DO $$
DECLARE
  -- Backfill operator. In a migration context (no auth.uid) this resolves to
  -- NULL, which is acceptable: created_by / performed_by are nullable FKs.
  v_operator         uuid := public.get_current_profile_id();
  v_patch_count      integer;
  v_eligible_count   integer;
  v_inserted_history integer;
  v_dup_groups       integer;
BEGIN
  -- ── 1. Gap B patch — VCDG2_0001 (slot exists, legacy_vcode NULL) ──────────
  -- Targeted 1-row UPDATE, NOT a slot INSERT. The `legacy_vcode IS NULL`
  -- guard makes it idempotent (0 rows on a safe re-run). The dual-key
  -- NOT EXISTS guard in step 3 keeps this same slot out of the INSERT path.
  UPDATE public.plantilla_slots
  SET    legacy_vcode = 'VCDG2_0001',
         updated_at   = NOW(),
         updated_by   = v_operator
  WHERE  id                   = '60cc15dc-4f61-4806-80cd-5087cab08884'
    AND  source_hc_request_id = '170b44a9-e618-4b6b-8b2e-178a7db7a88e'
    AND  legacy_vcode IS NULL;
  GET DIAGNOSTICS v_patch_count = ROW_COUNT;

  IF v_patch_count NOT IN (0, 1) THEN
    RAISE EXCEPTION
      'OHM2026_0013 backfill aborted: Gap B patch affected % rows (expected 0 or 1)',
      v_patch_count;
  END IF;

  -- ── 2. Count eligible vacancies (for the post-INSERT consistency assert) ──
  -- Same predicate as the INSERT in step 3. Drives eligibility off
  -- vw_vacancy_list.derived_status so the backfill mirrors exactly what the
  -- Vacancy UI considers active today.
  SELECT COUNT(*)
  INTO   v_eligible_count
  FROM   public.vacancies v
  JOIN   public.vw_vacancy_list vl ON vl.vcode = v.vcode
  WHERE  vl.derived_status IN ('Open', 'Pipeline')
    AND  (v.is_archived IS NULL OR v.is_archived = FALSE)
    AND  v.deleted_at IS NULL
    AND  v.employment_type <> 'Roving'                    -- Q2·5 roving carve-out
    AND  NOT EXISTS (                                      -- Q10 dual-key idempotency
           SELECT 1 FROM public.plantilla_slots ps
           WHERE  ps.legacy_vcode = v.vcode
              OR (v.source_headcount_request_id IS NOT NULL
                  AND ps.source_hc_request_id = v.source_headcount_request_id));

  -- ── 3. Create slots + history atomically (one statement) ──────────────────
  -- `eligible` is evaluated once against the statement snapshot, so the
  -- NOT EXISTS guard does not see rows inserted by `ins` in the same
  -- statement. `ins` creates the slots; the outer INSERT writes exactly one
  -- slot_history row per new slot, joining back on the 1:1 legacy_vcode to
  -- carry the legacy vacant_date as the aging basis.
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
    WHERE  vl.derived_status IN ('Open', 'Pipeline')
      AND  (v.is_archived IS NULL OR v.is_archived = FALSE)
      AND  v.deleted_at IS NULL
      AND  v.employment_type <> 'Roving'
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
      e.employment_type,
      FALSE,                      -- roving carved out (Q2·5); every backfilled slot is non-roving
      e.slot_status,              -- 'open' | 'pipeline' from vw_vacancy_list.derived_status
      e.source_headcount_request_id,
      e.vcode,                    -- 1:1 legacy bridge (Q5)
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
    'open',                       -- Q7: 'open' even for pipeline slots — anchors the open episode
    'HC_ADD',
    v_operator,
    'OHM2026_0013 historical backfill — vcode=' || ins.legacy_vcode,
    -- Q8: aging basis = legacy vacant_date; COALESCE guards the NOT NULL column
    -- for the (unexpected) case of a NULL vacant_date.
    COALESCE(e.vacant_date::timestamptz, NOW())
  FROM ins
  JOIN eligible e ON e.vcode = ins.legacy_vcode;
  GET DIAGNOSTICS v_inserted_history = ROW_COUNT;

  -- ── 4. In-transaction asserts (any failure ⇒ full ROLLBACK) ───────────────
  -- 4a. One history row per eligible vacancy → one slot per eligible vacancy.
  IF v_inserted_history <> v_eligible_count THEN
    RAISE EXCEPTION
      'OHM2026_0013 backfill aborted: inserted % history rows but % vacancies were eligible',
      v_inserted_history, v_eligible_count;
  END IF;

  -- 4b. No legacy_vcode collisions anywhere in plantilla_slots.
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
      'OHM2026_0013 backfill aborted: % duplicate legacy_vcode group(s) detected',
      v_dup_groups;
  END IF;

  RAISE NOTICE 'OHM2026_0013 backfill OK — % slot(s) created, % Gap B patch row(s), 0 dup legacy_vcode.',
    v_inserted_history, v_patch_count;
END;
$$;


-- ============================================================
-- §2  Post-commit validation queries (run manually, read-only)
-- ============================================================
-- Reuses the OHM2026_0011 reconciliation suite. Cutover (Phase 7) is blocked
-- until completeness (P2/P3 = 0, excluding the deferred roving carve-out) AND
-- count + aging parity (P5/P6) hold for every non-roving account/group.
--
-- P1 — Backfill rows actually written (tagged):
--   SELECT COUNT(*) AS backfill_slots
--   FROM   public.slot_history
--   WHERE  remarks LIKE 'OHM2026_0013 historical backfill%';
--   -- Expect ≈ 13 (Gap A 11 + Gap C 2) minus any roving carve-out.
--
-- P2 — Count parity: slot shadow vs legacy by account/tab (OHM2026_0011 R2):
--   SELECT 'slot_shadow' AS source, account_id, vacancy_tab AS tab, COUNT(*) AS cnt
--   FROM   public.vw_slot_derived_vacancy_shadow
--   GROUP  BY account_id, vacancy_tab
--   UNION ALL
--   SELECT 'legacy_vacancy', account_id, derived_status, COUNT(*)
--   FROM   public.vw_vacancy_list
--   WHERE  derived_status IN ('Open','Pipeline')
--     AND  (is_archived IS NULL OR is_archived = FALSE)
--   GROUP  BY account_id, derived_status
--   ORDER  BY account_id, tab, source;
--   -- Expect: slot_shadow == legacy per account/tab (roving rows are the only
--   --         legacy-only residue, by design).
--
-- P3 — Missing slots: legacy active with NO slot (OHM2026_0011 R3):
--   SELECT v.vcode, v.account_id, v.status, v.employment_type,
--          v.source_headcount_request_id
--   FROM   public.vacancies v
--   LEFT JOIN public.plantilla_slots ps ON ps.legacy_vcode = v.vcode
--   WHERE  v.status IN ('Open','For Sourcing','Pipeline')
--     AND  (v.is_archived IS NULL OR v.is_archived = FALSE)
--     AND  v.deleted_at IS NULL
--     AND  ps.id IS NULL
--   ORDER  BY v.account_id, v.status, v.vcode;
--   -- Expect: only roving rows remain (deliberately deferred); 0 non-roving.
--
-- P4 — Orphaned slots: slots with NO legacy match (OHM2026_0011 R5):
--   SELECT ps.id, ps.legacy_vcode, ps.slot_status, ps.account_id
--   FROM   public.plantilla_slots ps
--   LEFT JOIN public.vacancies v ON v.vcode = ps.legacy_vcode
--   WHERE  ps.legacy_vcode IS NOT NULL AND v.id IS NULL;
--   -- Expect: 0 rows.
--
-- P5 — NULL legacy_vcode slots remaining:
--   SELECT id, slot_status, source_hc_request_id
--   FROM   public.plantilla_slots
--   WHERE  legacy_vcode IS NULL;
--   -- Expect: 0 rows (Gap B patched; every backfilled slot carries its vcode).
--
-- P6 — Duplicate legacy_vcode slots:
--   SELECT legacy_vcode, COUNT(*)
--   FROM   public.plantilla_slots
--   WHERE  legacy_vcode IS NOT NULL
--   GROUP  BY legacy_vcode HAVING COUNT(*) > 1;
--   -- Expect: 0 rows.
--
-- P7 — Aging parity: shadow aging_days == legacy elapsed days per vcode:
--   SELECT s.legacy_vcode,
--          s.aging_days                    AS slot_aging_days,
--          (CURRENT_DATE - v.vacant_date)  AS legacy_aging_days
--   FROM   public.vw_slot_derived_vacancy_shadow s
--   JOIN   public.vacancies v ON v.vcode = s.legacy_vcode
--   WHERE  s.aging_days IS DISTINCT FROM (CURRENT_DATE - v.vacant_date);
--   -- Expect: 0 rows (advance/future-dated vacancies excluded — both NULL).
--
-- P8 — Shadow view health (OHM2026_0011 R1):
--   SELECT slot_status, vacancy_tab, COUNT(*)
--   FROM   public.vw_slot_derived_vacancy_shadow
--   GROUP  BY slot_status, vacancy_tab ORDER BY slot_status;
--
-- ============================================================
-- §3  REVERSAL PLAN (post-commit correction — requires explicit approval)
-- ============================================================
-- The single transaction above is the primary rollback (an in-flight abort
-- leaves zero residue). For a post-commit undo, the backfill's own rows are
-- identifiable by their remarks tag. Run in its own transaction, child-first:
--
--   WITH bf AS (
--     SELECT DISTINCT slot_id
--     FROM   public.slot_history
--     WHERE  remarks LIKE 'OHM2026_0013 historical backfill%'
--   )
--   -- 1) DELETE FROM public.slot_history  WHERE slot_id IN (SELECT slot_id FROM bf);
--   -- 2) DELETE FROM public.plantilla_slots ps
--   --      WHERE ps.id IN (SELECT slot_id FROM bf)
--   --        AND ps.current_occupant_plantilla_id IS NULL;  -- never remove an occupied slot
--   -- 3) Reverse the Gap B patch separately IF needed:
--   --      UPDATE public.plantilla_slots SET legacy_vcode = NULL
--   --      WHERE id = '60cc15dc-4f61-4806-80cd-5087cab08884'
--   --        AND legacy_vcode = 'VCDG2_0001';
--   SELECT * FROM bf;  -- dry-run: list what would be removed
--
-- Hard-delete is acceptable here only because these are freshly-created EMPTY
-- slots (no occupant, no downstream references) produced by the backfill
-- itself before any UI cutover; the occupant guard makes deleting an occupied
-- slot impossible. If policy disallows hard-delete at execution time, the
-- fallback is to close the rows (slot_status='closed',
-- closure_reason_code='HC_REDUCTION'). See backfill plan §4·5.
-- ============================================================
