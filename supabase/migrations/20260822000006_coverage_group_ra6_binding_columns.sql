-- ============================================================
-- OHM2026_0066 — Coverage Group Phase R-A — RA6 binding columns
-- Migration:  20260822000006_coverage_group_ra6_binding_columns.sql
-- Plan:       docs/architecture/coverage_group_phase_ra_schema_plan.md (§RA6, §7)
-- Depends on: RA1 (coverage_groups), RA4 (coverage_slots).
-- ============================================================
-- Scope: Additive, NULLABLE, EMPTY record-binding columns. Successors to
--   roving_assignment_id (which is KEPT — legacy + target coexist until
--   R-F/R-G). Populated by R-B (applicants) and R-C (hr_emploc/plantilla);
--   NOTHING is populated here.
--
--   On applicants / hr_emploc / plantilla:
--     • coverage_slot_id  → coverage_slots(id)   ON DELETE SET NULL
--     • coverage_group_id → coverage_groups(id)  ON DELETE SET NULL
--
--   FKs are declared NOT VALID: these are large, actively-mutated tables.
--   The columns start all-NULL so new rows are still checked; skipping the
--   validation scan avoids an ACCESS EXCLUSIVE lock on a big table (same
--   pattern as plantilla_slots_occupant_fkey).
--
--   The active-per-coverage-slot uniqueness guards
--   (uq_*_one_active_per_coverage_slot) are DEFERRED to R-B/R-C — adding
--   them against all-NULL columns now would be a no-op and would couple RA
--   to binding semantics it does not own (plan §4, §7).
--
-- Validation (run after apply):
--   V1  -- columns exist, nullable, default NULL on all three tables
--   V2  -- every existing stationary record still has coverage_slot_id IS NULL
--          (zero rows touched)
-- ============================================================

-- ── applicants ───────────────────────────────────────────────
ALTER TABLE public.applicants
  ADD COLUMN IF NOT EXISTS coverage_slot_id  uuid,
  ADD COLUMN IF NOT EXISTS coverage_group_id uuid;

ALTER TABLE public.applicants
  DROP CONSTRAINT IF EXISTS applicants_coverage_slot_fkey,
  ADD  CONSTRAINT applicants_coverage_slot_fkey
    FOREIGN KEY (coverage_slot_id)  REFERENCES public.coverage_slots(id)  ON DELETE SET NULL NOT VALID;
ALTER TABLE public.applicants
  DROP CONSTRAINT IF EXISTS applicants_coverage_group_fkey,
  ADD  CONSTRAINT applicants_coverage_group_fkey
    FOREIGN KEY (coverage_group_id) REFERENCES public.coverage_groups(id) ON DELETE SET NULL NOT VALID;

COMMENT ON COLUMN public.applicants.coverage_slot_id IS
  'Roving binding — successor to roving_assignment_id. Empty in RA; populated by R-B.';
COMMENT ON COLUMN public.applicants.coverage_group_id IS
  'Roving group binding — successor to roving_assignment_id. Empty in RA; populated by R-B.';

-- ── hr_emploc ────────────────────────────────────────────────
ALTER TABLE public.hr_emploc
  ADD COLUMN IF NOT EXISTS coverage_slot_id  uuid,
  ADD COLUMN IF NOT EXISTS coverage_group_id uuid;

ALTER TABLE public.hr_emploc
  DROP CONSTRAINT IF EXISTS hr_emploc_coverage_slot_fkey,
  ADD  CONSTRAINT hr_emploc_coverage_slot_fkey
    FOREIGN KEY (coverage_slot_id)  REFERENCES public.coverage_slots(id)  ON DELETE SET NULL NOT VALID;
ALTER TABLE public.hr_emploc
  DROP CONSTRAINT IF EXISTS hr_emploc_coverage_group_fkey,
  ADD  CONSTRAINT hr_emploc_coverage_group_fkey
    FOREIGN KEY (coverage_group_id) REFERENCES public.coverage_groups(id) ON DELETE SET NULL NOT VALID;

COMMENT ON COLUMN public.hr_emploc.coverage_slot_id IS
  'Roving binding — successor to roving_assignment_id. Empty in RA; populated by R-C.';
COMMENT ON COLUMN public.hr_emploc.coverage_group_id IS
  'Roving group binding — successor to roving_assignment_id. Empty in RA; populated by R-C.';

-- ── plantilla ────────────────────────────────────────────────
ALTER TABLE public.plantilla
  ADD COLUMN IF NOT EXISTS coverage_slot_id  uuid,
  ADD COLUMN IF NOT EXISTS coverage_group_id uuid;

ALTER TABLE public.plantilla
  DROP CONSTRAINT IF EXISTS plantilla_coverage_slot_fkey,
  ADD  CONSTRAINT plantilla_coverage_slot_fkey
    FOREIGN KEY (coverage_slot_id)  REFERENCES public.coverage_slots(id)  ON DELETE SET NULL NOT VALID;
ALTER TABLE public.plantilla
  DROP CONSTRAINT IF EXISTS plantilla_coverage_group_fkey,
  ADD  CONSTRAINT plantilla_coverage_group_fkey
    FOREIGN KEY (coverage_group_id) REFERENCES public.coverage_groups(id) ON DELETE SET NULL NOT VALID;

COMMENT ON COLUMN public.plantilla.coverage_slot_id IS
  'Roving binding — successor to roving_assignment_id. Empty in RA; populated by R-C.';
COMMENT ON COLUMN public.plantilla.coverage_group_id IS
  'Roving group binding — successor to roving_assignment_id. Empty in RA; populated by R-C.';
