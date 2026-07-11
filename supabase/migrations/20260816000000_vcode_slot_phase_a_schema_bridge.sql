-- ============================================================
-- OHM2026_0038 — VCODE ↔ Slot Phase A Schema Bridge
-- Migration:  20260816000000_vcode_slot_phase_a_schema_bridge.sql
-- Depends on:
--   20260804000000_plantilla_slot_foundation_v1.sql
--     (plantilla_slots, slot_history, slot_reason_codes)
--   20260807000000_plantilla_slots_legacy_vcode_link.sql
--     (legacy_vcode column + idx_plantilla_slots_legacy_vcode)
--   20260810000000_backfill_historical_vacancy_slots.sql
--     (historical 1:1 slot rows; P5 = 0 NULL-legacy_vcode active slots)
--   Pre-existing: applicants, hr_emploc, vacancies, users_profile
-- ============================================================
-- Scope: ADDITIVE SCHEMA BRIDGE ONLY — no behavior change.
--
-- Authorising documents (locked):
--   docs/architecture/vcode_slot_bridge_redesign.md  (OHM2026_0035)
--   docs/architecture/vcode_slot_phase_a_schema_plan.md (OHM2026_0037)
--
-- Phase A adds the identity and binding columns that allow one VCODE
-- to own N discrete plantilla_slots while applicants and HR Emploc
-- rows bind to a specific slot. No logic is wired — assignment (Phase B),
-- HR Emploc binding (Phase C), shadow aggregation (Phase D), and closure
-- fan-out (Phase E) come later.
--
-- This migration deliberately does NOT:
--   • modify Flutter UI, lifecycle helpers, or shadow views
--   • modify HC request VCODE generation
--   • modify transfer or closure logic
--   • recreate or apply 20260815000000_one_store_one_vcode.sql (BLOCKED)
--   • populate applicants.slot_id or hr_emploc.slot_id (Phase B/C)
--   • add plantilla.slot_id (deferred per Phase A plan §Q1)
--   • change any read path or workflow behavior
--
-- Implementation order (per Phase A plan §Q8):
--   A0  Pre-migration gate (run manually — see validation queries below)
--   A1  Add plantilla_slots.slot_ordinal (nullable)
--   A2  Backfill slot_ordinal via ROW_NUMBER window
--   A3  SET NOT NULL + CHECK (slot_ordinal >= 1)
--   A4  Create composite partial UNIQUE (legacy_vcode, slot_ordinal)
--   A5  No-op: the "partial-unique" on legacy_vcode recommended in the
--       backfill plan Q10 was never implemented as a UNIQUE index — only
--       the regular partial index idx_plantilla_slots_legacy_vcode exists.
--       That index is retained (useful for lookup performance).
--   A6  Add applicants.slot_id nullable FK + partial index
--   A7  Add hr_emploc.slot_id nullable FK + partial index
--   A8  plantilla.slot_id deferred — not added here
--   A9  Run post-migration validation (see queries below)
--
-- ============================================================
-- A0 — Pre-migration gate (run MANUALLY before applying)
-- ============================================================
-- Run these queries and confirm all expectations hold before applying.
-- Gate must be GREEN for Phase A to proceed.
--
--   Gate 1: 1:1 precondition — every non-NULL legacy_vcode maps to exactly
--           one plantilla_slots row (clean dataset required for backfill).
--     SELECT legacy_vcode, COUNT(*) AS slot_count
--       FROM public.plantilla_slots
--       WHERE legacy_vcode IS NOT NULL
--       GROUP BY legacy_vcode
--       HAVING COUNT(*) > 1;
--     -- Expected: 0 rows. Any rows = STOP and investigate duplicates.
--
--   Gate 2: No NULL-bridge active slots (P5 = 0, established by OHM2026_0013).
--     SELECT COUNT(*) AS null_vcode_active_slots
--       FROM public.plantilla_slots ps
--       JOIN public.vacancies v ON v.vcode IS NOT NULL
--       WHERE ps.legacy_vcode IS NULL
--         AND ps.slot_status NOT IN ('closed');
--     -- Expected: 0 (all active slots should have legacy_vcode from backfill).
--
--   Gate 3: slot_ordinal does not already exist.
--     SELECT column_name FROM information_schema.columns
--       WHERE table_schema = 'public'
--         AND table_name   = 'plantilla_slots'
--         AND column_name  = 'slot_ordinal';
--     -- Expected: 0 rows. If present, a prior partial run landed — reconcile.
--
--   Gate 4: applicants.slot_id and hr_emploc.slot_id do not already exist.
--     SELECT table_name, column_name FROM information_schema.columns
--       WHERE table_schema = 'public'
--         AND table_name IN ('applicants', 'hr_emploc')
--         AND column_name = 'slot_id';
--     -- Expected: 0 rows.
--
--   Gate 5: Shadow parity baseline (P1–P8) is GREEN before this migration.
--     -- Run the P1–P8 parity suite manually; confirm shadow == legacy 14/14.
-- ============================================================


-- ============================================================
-- §A1 — Add slot_ordinal (nullable for now, populated in §A2)
-- ============================================================
-- smallint is sufficient: no VCODE will ever have 32 767 slots.
-- Nullable first so §A2 can backfill before §A3 enforces NOT NULL.

ALTER TABLE public.plantilla_slots
  ADD COLUMN IF NOT EXISTS slot_ordinal smallint;

COMMENT ON COLUMN public.plantilla_slots.slot_ordinal IS
  'Stable per-VCODE slot identity (1..N within a legacy_vcode). '
  'Backfilled to 1 for all historical 1:1 slots (OHM2026_0038 Phase A). '
  'New slots receive MAX(slot_ordinal)+1 within their legacy_vcode at '
  'creation time (wired in a later phase). Ordinals are never recycled — '
  'a closed slot retains its ordinal so history stays unambiguous. '
  'Uniqueness within a VCODE is enforced by uq_plantilla_slots_legacy_vcode_ordinal '
  '(partial: WHERE legacy_vcode IS NOT NULL). See OHM2026_0035/0037.';


-- ============================================================
-- §A2 — Backfill slot_ordinal
-- ============================================================
-- Assigns ordinals using a deterministic window function so that:
--   • In the expected clean 1:1 dataset every partition has exactly
--     one row → all ordinals become 1 (verifiable post-condition).
--   • If any VCODE already has >1 slot (latent duplicate the A0 gate
--     should have caught), ordinals are assigned 1,2,… rather than
--     colliding, turning a hard failure into a detectable anomaly.
--   • NULL-legacy_vcode rows are partitioned together and receive
--     1,2,3,… — harmless because the composite unique (§A4) is
--     partial WHERE legacy_vcode IS NOT NULL, so those rows are not
--     subject to the uniqueness guard.

UPDATE public.plantilla_slots AS ps
SET    slot_ordinal = sub.rn
FROM (
  SELECT
    id,
    ROW_NUMBER() OVER (
      PARTITION BY legacy_vcode
      ORDER BY created_at, id
    ) AS rn
  FROM public.plantilla_slots
) AS sub
WHERE ps.id = sub.id;


-- ============================================================
-- §A3 — Set NOT NULL and add range CHECK
-- ============================================================
-- Both steps are safe now that every row has been backfilled.

ALTER TABLE public.plantilla_slots
  ALTER COLUMN slot_ordinal SET NOT NULL,
  ADD CONSTRAINT plantilla_slots_slot_ordinal_positive
    CHECK (slot_ordinal >= 1);


-- ============================================================
-- §A4 — Create composite partial unique (new N-slot guard)
-- ============================================================
-- Replaces the old 1:1 mental model with the correct N-slot guarantee:
--   one (legacy_vcode, slot_ordinal) pair is unique within a VCODE.
-- Partial (WHERE legacy_vcode IS NOT NULL) so foundation/seed slots
-- with NULL legacy_vcode are not forced into the uniqueness scope.
-- The composite unique is created BEFORE the regular legacy_vcode index
-- is considered for any change (see §A5), so there is never a window
-- with zero uniqueness guard during Phase A.

CREATE UNIQUE INDEX IF NOT EXISTS uq_plantilla_slots_legacy_vcode_ordinal
  ON public.plantilla_slots (legacy_vcode, slot_ordinal)
  WHERE legacy_vcode IS NOT NULL;


-- ============================================================
-- §A5 — No-op: legacy_vcode unique index
-- ============================================================
-- The backfill plan Q10 recommended adding a partial UNIQUE index on
-- legacy_vcode to guarantee 1:1 resolution. That recommendation was
-- never implemented as a UNIQUE index — only the regular partial index
-- idx_plantilla_slots_legacy_vcode was created (20260807000000).
-- A regular index does NOT enforce uniqueness and therefore does NOT
-- block a second slot per VCODE.
--
-- Action: none. idx_plantilla_slots_legacy_vcode is RETAINED as-is.
-- It is a useful btree lookup index for legacy_vcode-keyed queries
-- (shadow view joins, lifecycle transitions). Keeping it alongside the
-- new composite unique is safe and beneficial for read performance.
-- The composite unique (§A4) is now the sole uniqueness guard.


-- ============================================================
-- §A6 — Add applicants.slot_id (nullable FK, empty)
-- ============================================================
-- Binds an applicant to the exact plantilla_slots row it fills.
-- Left NULL in Phase A; populated by Phase B (applicant binding).
-- ON DELETE RESTRICT aligns with archive-first: slots are never
-- hard-deleted, so RESTRICT surfaces any attempted violation.

ALTER TABLE public.applicants
  ADD COLUMN IF NOT EXISTS slot_id uuid;

-- Add FK in a separate statement so IF NOT EXISTS on ADD COLUMN
-- does not silently skip the constraint on re-runs.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_schema = 'public'
      AND table_name        = 'applicants'
      AND constraint_name   = 'applicants_slot_id_fkey'
  ) THEN
    ALTER TABLE public.applicants
      ADD CONSTRAINT applicants_slot_id_fkey
        FOREIGN KEY (slot_id)
        REFERENCES public.plantilla_slots (id)
        ON DELETE RESTRICT;
  END IF;
END;
$$;

COMMENT ON COLUMN public.applicants.slot_id IS
  'Phase A bridge (OHM2026_0038): FK to the specific plantilla_slots row '
  'this applicant fills. NULL until Phase B (applicant binding) populates it. '
  'ON DELETE RESTRICT — slots are archive-first; hard-delete should be blocked.';

-- Partial btree index: Phase B/D look up applicants by slot;
-- partial avoids indexing the NULL majority while the column ships empty.
CREATE INDEX IF NOT EXISTS idx_applicants_slot_id
  ON public.applicants (slot_id)
  WHERE slot_id IS NOT NULL;


-- ============================================================
-- §A7 — Add hr_emploc.slot_id (nullable FK, empty)
-- ============================================================
-- Binds the HR Emploc row to the same slot the applicant occupied.
-- Left NULL in Phase A; populated by Phase C (HR Emploc binding).

ALTER TABLE public.hr_emploc
  ADD COLUMN IF NOT EXISTS slot_id uuid;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_schema = 'public'
      AND table_name        = 'hr_emploc'
      AND constraint_name   = 'hr_emploc_slot_id_fkey'
  ) THEN
    ALTER TABLE public.hr_emploc
      ADD CONSTRAINT hr_emploc_slot_id_fkey
        FOREIGN KEY (slot_id)
        REFERENCES public.plantilla_slots (id)
        ON DELETE RESTRICT;
  END IF;
END;
$$;

COMMENT ON COLUMN public.hr_emploc.slot_id IS
  'Phase A bridge (OHM2026_0038): FK to the specific plantilla_slots row '
  'this HR Emploc record tracks. NULL until Phase C (HR Emploc binding) '
  'populates it. ON DELETE RESTRICT — slots are archive-first.';

CREATE INDEX IF NOT EXISTS idx_hr_emploc_slot_id
  ON public.hr_emploc (slot_id)
  WHERE slot_id IS NOT NULL;


-- ============================================================
-- §A8 — plantilla.slot_id: DEFERRED
-- ============================================================
-- plantilla_slots.current_occupant_plantilla_id already provides the
-- reverse link (slot → plantilla). A forward FK from plantilla → slot
-- is deferred until Phase D/E determine whether a forward index is
-- actually needed for the occupant binding path.


-- ============================================================
-- §A9 — Post-migration validation queries (run manually)
-- ============================================================
--
-- V1 — slot_ordinal column exists, is smallint, NOT NULL.
--   SELECT column_name, data_type, is_nullable
--     FROM information_schema.columns
--     WHERE table_schema = 'public'
--       AND table_name   = 'plantilla_slots'
--       AND column_name  = 'slot_ordinal';
--   -- Expected: 1 row, data_type = 'smallint', is_nullable = 'NO'.
--
-- V2 — All existing ordinals = 1 (clean 1:1 precondition confirmed).
--   SELECT slot_ordinal, COUNT(*) AS cnt
--     FROM public.plantilla_slots
--     GROUP BY slot_ordinal
--     ORDER BY slot_ordinal;
--   -- Expected: only one row: slot_ordinal = 1, cnt = total row count.
--   -- (NULL-legacy_vcode seed rows may also show ordinal 1 or higher —
--   --  all are acceptable since the composite unique excludes NULLs.)
--
-- V3 — No (legacy_vcode, slot_ordinal) duplicates.
--   SELECT legacy_vcode, slot_ordinal, COUNT(*) AS dup_count
--     FROM public.plantilla_slots
--     WHERE legacy_vcode IS NOT NULL
--     GROUP BY legacy_vcode, slot_ordinal
--     HAVING COUNT(*) > 1;
--   -- Expected: 0 rows.
--
-- V4 — Composite unique index exists and is partial.
--   SELECT indexname, indexdef
--     FROM pg_indexes
--     WHERE schemaname = 'public'
--       AND tablename  = 'plantilla_slots'
--       AND indexname  = 'uq_plantilla_slots_legacy_vcode_ordinal';
--   -- Expected: 1 row; indexdef contains WHERE (legacy_vcode IS NOT NULL).
--
-- V5 — CHECK constraint exists.
--   SELECT constraint_name, check_clause
--     FROM information_schema.check_constraints
--     WHERE constraint_schema = 'public'
--       AND constraint_name   = 'plantilla_slots_slot_ordinal_positive';
--   -- Expected: 1 row, check_clause references slot_ordinal >= 1.
--
-- V6 — applicants.slot_id: column exists, is nullable, FK + index present.
--   SELECT column_name, data_type, is_nullable
--     FROM information_schema.columns
--     WHERE table_schema = 'public'
--       AND table_name   = 'applicants'
--       AND column_name  = 'slot_id';
--   -- Expected: 1 row, data_type = 'uuid', is_nullable = 'YES'.
--
--   SELECT constraint_name FROM information_schema.table_constraints
--     WHERE constraint_schema = 'public'
--       AND table_name        = 'applicants'
--       AND constraint_name   = 'applicants_slot_id_fkey';
--   -- Expected: 1 row.
--
--   SELECT indexname FROM pg_indexes
--     WHERE schemaname = 'public'
--       AND tablename  = 'applicants'
--       AND indexname  = 'idx_applicants_slot_id';
--   -- Expected: 1 row.
--
-- V7 — hr_emploc.slot_id: column exists, is nullable, FK + index present.
--   SELECT column_name, data_type, is_nullable
--     FROM information_schema.columns
--     WHERE table_schema = 'public'
--       AND table_name   = 'hr_emploc'
--       AND column_name  = 'slot_id';
--   -- Expected: 1 row, data_type = 'uuid', is_nullable = 'YES'.
--
--   SELECT constraint_name FROM information_schema.table_constraints
--     WHERE constraint_schema = 'public'
--       AND table_name        = 'hr_emploc'
--       AND constraint_name   = 'hr_emploc_slot_id_fkey';
--   -- Expected: 1 row.
--
--   SELECT indexname FROM pg_indexes
--     WHERE schemaname = 'public'
--       AND tablename  = 'hr_emploc'
--       AND indexname  = 'idx_hr_emploc_slot_id';
--   -- Expected: 1 row.
--
-- V8 — plantilla.slot_id NOT added (deferred per Phase A plan).
--   SELECT column_name FROM information_schema.columns
--     WHERE table_schema = 'public'
--       AND table_name   = 'plantilla'
--       AND column_name  = 'slot_id';
--   -- Expected: 0 rows.
--
-- V9 — applicants.slot_id and hr_emploc.slot_id are entirely NULL (ships empty).
--   SELECT COUNT(*) AS populated_applicant_slot_ids
--     FROM public.applicants WHERE slot_id IS NOT NULL;
--   -- Expected: 0.
--
--   SELECT COUNT(*) AS populated_hr_emploc_slot_ids
--     FROM public.hr_emploc WHERE slot_id IS NOT NULL;
--   -- Expected: 0.
--
-- V10 — Row counts unchanged across vacancies, plantilla_slots, shadow view.
--   SELECT
--     (SELECT COUNT(*) FROM public.vacancies)        AS vacancy_count,
--     (SELECT COUNT(*) FROM public.plantilla_slots)  AS slot_count;
--   -- Compare to pre-migration baseline; values must be identical.
--
-- V11 — Shadow parity P1–P8 re-run GREEN; shadow == legacy 14/14.
--   -- Run the P1–P8 parity suite. Phase A adds no read-path changes so
--   -- all counts must match the pre-migration baseline exactly.
-- ============================================================
