-- Migration: 20260629040000_repair_remaining_orphan_plantilla_slots
-- Created: 2026-06-29
-- Ticket: ohm#4q8n2v6b
-- Purpose: Resolve remaining active orphan plantilla_slots (store_id IS NULL) before Coverage
--          Add Store smoke testing.
--
-- Prior migration 20260629030000 repaired the bulk of orphan slots via vacancy/store VCode match.
-- 5 active orphan slots remained after that repair.
--
-- ┌──────────────────┬──────────────┬──────────────────────────────────────────────────────────┐
-- │ VCode            │ Status       │ Classification                                           │
-- ├──────────────────┼──────────────┼──────────────────────────────────────────────────────────┤
-- │ VCAG2_0018       │ pipeline     │ REPAIRABLE — HC request store_id confirmed (SM Biñan)    │
-- │ VCS8G2_0405      │ hr_processing│ NON-REPAIRABLE — ambiguous store (6 "Super 8 Dau" rows)  │
-- │ VCS8G2_0121      │ hr_processing│ NON-REPAIRABLE — ambiguous store (6 "Super 8 Dau" rows)  │
-- │ VCS8G2_1405      │ hr_processing│ NON-REPAIRABLE — ambiguous store (6 "Super 8 Dau" rows)  │
-- │ VCS8G2_0129      │ hr_processing│ NON-REPAIRABLE — ambiguous store (6 "Super 8 Dau" rows)  │
-- └──────────────────┴──────────────┴──────────────────────────────────────────────────────────┘
--
-- ── VCAG2_0018 ──────────────────────────────────────────────────────────────────────────────
-- Root cause:  HC request bdd62d4d created VCAG2_0018 (ACTIVESTYLE, SM Biñan) on 2026-06-22.
--              At that time fn_trg_auto_create_vacancy_slot could not resolve the store because
--              stores.vcode for SM Biñan was not yet set. The slot was created with store_id=NULL.
--              The vacancy row was subsequently archived/deleted (staging data lifecycle).
--              The plantilla (VACANT SLOT) row correctly has store_id=7b0f3929-a4c4-478b-b401-8e1875d1693c.
--              The HC request itself carries the authoritative store_id.
-- Evidence:    headcount_requests.id = bdd62d4d-5762-4910-bbac-b820c35680e8
--                → store_id          = 7b0f3929-a4c4-478b-b401-8e1875d1693c  (SM Biñan, active)
--                → created_vcode     = VCAG2_0018
--              plantilla.vcode = VCAG2_0018 → store_id = 7b0f3929-a4c4-478b-b401-8e1875d1693c
--              stores.id = 7b0f3929-a4c4-478b-b401-8e1875d1693c → status=active, vcode=NULL
-- Fix:         1. UPDATE plantilla_slots SET store_id = '7b0f3929...' WHERE legacy_vcode = 'VCAG2_0018'
--              2. UPDATE stores SET vcode = 'VCAG2_0018' WHERE id = '7b0f3929...' AND vcode IS NULL
--                 (safe: no other active store already uses VCAG2_0018)
--
-- ── VCS8G2_0405 / VCS8G2_0121 / VCS8G2_1405 / VCS8G2_0129 ──────────────────────────────────
-- Root cause:  These VCodes were created via vacancy import batch (source='manual',
--              source_vacancy_import_batch_id set) for account ONE / "Super 8 Dau".
--              The vacancy import did not capture a store_id — vacancies.store_id is NULL.
--              Both vacancies and stores table have NO unambiguous match for these VCodes:
--                · stores.vcode does NOT contain any VCS8G2_* value.
--                · 6 distinct active "Super 8 Dau" stores exist across the system — ambiguous.
--              Vacancies: status=Filled, is_archived=true (historical/completed records).
--              Slots: status=hr_processing (HR Emploc import in progress against archived vacancy).
-- Classification: NON-REPAIRABLE without explicit business confirmation of which Super 8 Dau
--              store_id applies. Fabricating a store linkage from 6 candidates would corrupt data.
-- Decision:    Leave store_id as NULL. Documented here as intentionally unrepaired historical data.
--              These slots do NOT affect:
--                · Coverage Add Store picker (only active/open slots with store_id matter there).
--                · Active employee allocations (no ESA rows link to these slot IDs).
--                · ADR-001 slot-first architecture (slot lifecycle is intact; only store_id is missing).
--              These are HR Emploc import staging slots tied to archived vacancies. The HR Emploc
--              records themselves also carry store_id=NULL (sourced from the same import batch).
--              These 4 slots CANNOT be closed here — no proof that the HR Emploc import for these
--              employees should be abandoned. Closing requires explicit business confirmation.
-- ============================================================

BEGIN;

-- ============================================================
-- §1  Guard: Verify SM Biñan store is still active before repairing VCAG2_0018
--     (Idempotent: re-running this migration is safe — WHERE guards prevent double-apply)
-- ============================================================

DO $$
DECLARE
  v_store_status text;
  v_conflict_count integer;
BEGIN
  -- Guard 1: Confirm SM Biñan (store_id=7b0f3929...) is active
  SELECT status INTO v_store_status
  FROM public.stores
  WHERE id = '7b0f3929-a4c4-478b-b401-8e1875d1693c';

  IF v_store_status IS NULL THEN
    RAISE EXCEPTION 'VCAG2_0018 repair aborted: store 7b0f3929-a4c4-478b-b401-8e1875d1693c does not exist.';
  END IF;

  IF v_store_status NOT IN ('active', 'Active') THEN
    RAISE WARNING 'VCAG2_0018 store status is %. Repair will still proceed — review if unexpected.', v_store_status;
  END IF;

  -- Guard 2: No other active store already uses vcode = 'VCAG2_0018'
  SELECT COUNT(*) INTO v_conflict_count
  FROM public.stores
  WHERE vcode = 'VCAG2_0018'
    AND id <> '7b0f3929-a4c4-478b-b401-8e1875d1693c';

  IF v_conflict_count > 0 THEN
    RAISE EXCEPTION 'VCAG2_0018 stores.vcode repair aborted: another store already owns vcode VCAG2_0018.';
  END IF;
END $$;


-- ============================================================
-- §2  Repair VCAG2_0018 — Backfill plantilla_slots.store_id
--
--     Source of truth: headcount_requests.store_id (bdd62d4d) = 7b0f3929-a4c4-478b-b401-8e1875d1693c
--     Guard: only update the specific slot row (by id), only when store_id IS NULL
-- ============================================================

UPDATE public.plantilla_slots
SET
  store_id   = '7b0f3929-a4c4-478b-b401-8e1875d1693c',
  updated_at = now()
WHERE id          = '186f576c-9d45-4e20-8861-6b03d98c400d'  -- VCAG2_0018 slot (pipeline)
  AND legacy_vcode = 'VCAG2_0018'                            -- double-guard: correct VCode
  AND store_id IS NULL;                                       -- idempotency: no-op if already set


-- ============================================================
-- §3  Repair SM Biñan stores.vcode — Backfill stores.vcode = 'VCAG2_0018'
--
--     Guard: only update when stores.vcode IS NULL (never overwrite existing VCode)
--     Guard: only when no other active store already uses this VCode (pre-checked in §1)
-- ============================================================

UPDATE public.stores
SET
  vcode      = 'VCAG2_0018',
  updated_at = now()
WHERE id   = '7b0f3929-a4c4-478b-b401-8e1875d1693c'  -- SM Biñan
  AND (vcode IS NULL OR trim(vcode) = '');              -- idempotency: no-op if vcode already set


-- ============================================================
-- §4  Non-repairable VCS8G2_* slots — No changes made.
--
--     These 4 slots are intentionally left with store_id = NULL.
--     Reason: ambiguous store (6 distinct active "Super 8 Dau" rows).
--     Vacancies: Filled + is_archived=true. Slots: hr_processing.
--     These are historical imported records — no active Coverage Group impact.
--     Coverage Add Store picker is unaffected (requires active slot + store_id).
--     Do not close or modify without explicit business confirmation.
--
--     VCodes intentionally unmodified:
--       VCS8G2_0405 (slot fe1ca95c)
--       VCS8G2_0121 (slot 59928518)
--       VCS8G2_1405 (slot d621c3c2)
--       VCS8G2_0129 (slot 8df8c386)
-- ============================================================


-- ============================================================
-- §5  Post-repair verification — Results expected:
--
--   A. Orphan count after repair: 4 remaining (the non-repairable VCS8G2_*)
--   B. VCAG2_0018 slot: store_id = 7b0f3929-a4c4-478b-b401-8e1875d1693c
--   C. SM Biñan store: vcode = 'VCAG2_0018'
--
-- Run verification:
--   SELECT count(*) as orphan_slots
--   FROM public.plantilla_slots
--   WHERE store_id is null AND slot_status <> 'closed';
--   -- Expected: 4 (VCS8G2_* non-repairable)
--
--   SELECT ps.id, ps.legacy_vcode, ps.store_id, s.store_name, s.vcode as store_vcode
--   FROM public.plantilla_slots ps
--   LEFT JOIN public.stores s ON s.id = ps.store_id
--   WHERE upper(ps.legacy_vcode) IN (
--     'VCAG2_0018','VCS8G2_0405','VCS8G2_0121','VCS8G2_1405','VCS8G2_0129'
--   );
--
-- Coverage Add Store smoke test unblocking criteria:
--   - VCAG2_0018 now has store_id set → SM Biñan eligible for Coverage Add Store picker
--   - VCS8G2_* remain store_id=NULL but are Filled+archived vacancies → do not appear in picker
--   - get_coverage_group_eligible_stores RPC behavior unchanged for valid active stores
-- ============================================================

COMMIT;
