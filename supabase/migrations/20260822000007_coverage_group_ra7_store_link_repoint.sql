-- ============================================================
-- OHM2026_0066 — Coverage Group Phase R-A — RA7 store-link re-point
-- Migration:  20260822000007_coverage_group_ra7_store_link_repoint.sql
-- Plan:       docs/architecture/coverage_group_phase_ra_schema_plan.md (§RA7, §7)
-- Depends on: RA1 (coverage_groups); live store-link tables.
-- ============================================================
-- Scope: RE-POINT columns only — additive, nullable. The store-link tables
--   are REUSED, not redefined: existing schema, triggers, and
--   roving_assignment_id are all preserved. RA only adds the nullable
--   coverage_group_id FK successor; R-C populates it during HR Emploc /
--   Plantilla footprint materialization.
--
--     • hr_emploc_store_links.coverage_group_id  → coverage_groups(id) ON DELETE SET NULL
--     • plantilla_store_links.coverage_group_id  → coverage_groups(id) ON DELETE SET NULL
--
--   FKs declared NOT VALID (large, actively-mutated tables; columns start
--   all-NULL so new rows are still checked).
--
-- Validation (run after apply):
--   V1  -- coverage_group_id exists, nullable, default NULL on both tables
--   V2  -- existing store-link rows untouched (all coverage_group_id IS NULL)
-- ============================================================

-- ── hr_emploc_store_links ────────────────────────────────────
ALTER TABLE public.hr_emploc_store_links
  ADD COLUMN IF NOT EXISTS coverage_group_id uuid;

ALTER TABLE public.hr_emploc_store_links
  DROP CONSTRAINT IF EXISTS hr_emploc_store_links_coverage_group_fkey,
  ADD  CONSTRAINT hr_emploc_store_links_coverage_group_fkey
    FOREIGN KEY (coverage_group_id) REFERENCES public.coverage_groups(id) ON DELETE SET NULL NOT VALID;

COMMENT ON COLUMN public.hr_emploc_store_links.coverage_group_id IS
  'Re-point successor to roving_assignment_id. Empty in RA; populated by R-C '
  'footprint materialization. Existing schema/triggers/roving_assignment_id preserved.';

-- ── plantilla_store_links ────────────────────────────────────
ALTER TABLE public.plantilla_store_links
  ADD COLUMN IF NOT EXISTS coverage_group_id uuid;

ALTER TABLE public.plantilla_store_links
  DROP CONSTRAINT IF EXISTS plantilla_store_links_coverage_group_fkey,
  ADD  CONSTRAINT plantilla_store_links_coverage_group_fkey
    FOREIGN KEY (coverage_group_id) REFERENCES public.coverage_groups(id) ON DELETE SET NULL NOT VALID;

COMMENT ON COLUMN public.plantilla_store_links.coverage_group_id IS
  'Re-point successor to roving_assignment_id. Empty in RA; populated by R-C '
  'footprint materialization. Existing schema/triggers/roving_assignment_id preserved.';
