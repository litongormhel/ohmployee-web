-- ============================================================
-- OHM2026_0066 — Coverage Group Phase R-A — RA1 coverage_groups
-- Migration:  20260822000001_coverage_group_ra1_coverage_groups.sql
-- Plan:       docs/architecture/coverage_group_phase_ra_schema_plan.md (§RA1)
-- Model:      docs/architecture/coverage_group_data_model_plan.md (§1)
-- Depends on: RA0 preflight; live accounts, positions, users_profile.
-- ============================================================
-- Scope: Create the CGCODE root table — the roving peer of a stationary
--   VCODE. Owns the CGCODE identity and required_headcount (the HC anchor).
--   Additive only. Touches nothing stationary.
--
--   Constraints encoded here (per plan §4):
--     • CHECK (required_headcount >= 1)
--     • CHECK (coverage_code LIKE 'CG-%')        — disjoint namespace prefix
--     • partial unique (account_id, coverage_code) WHERE archived_at IS NULL
--   Indexes:
--     • (account_id) WHERE archived_at IS NULL   — scope-filtered list
--     • (position_id)                            — position rollups
--
-- Validation (run after apply):
--   V1  SELECT to_regclass('public.coverage_groups');           -- not null
--   V2  -- per-account active CGCODE uniqueness (expect 2nd insert to fail)
--   V3  -- CHECK coverage_code LIKE 'CG-%' rejects a bare code
--   V4  -- CHECK required_headcount >= 1 rejects 0
-- ============================================================

CREATE TABLE IF NOT EXISTS public.coverage_groups (
  id                  uuid        NOT NULL DEFAULT gen_random_uuid(),

  -- Identity (CGCODE) — minted by fn_generate_cgcode_for_account (RA2)
  coverage_code       text        NOT NULL,

  -- Scope: exactly one account; cross-account footprint prohibited
  account_id          uuid        NOT NULL,
  position_id         uuid        NOT NULL,
  employment_type     text        NOT NULL,

  -- HC anchor — number of rovers the footprint needs. Independent of
  -- store count. N coverage_slots are emitted from this value (RA5).
  required_headcount  integer     NOT NULL DEFAULT 1,

  -- Cached/derived group status for list queries; authoritative status
  -- is computed from slot counts (R-D). Not CHECK-constrained in RA.
  status              text        NOT NULL DEFAULT 'open',

  area_name           text,

  created_at          timestamptz NOT NULL DEFAULT now(),
  created_by          uuid,

  -- Archive-first: a group leaves the system by archival, never delete.
  archived_at         timestamptz,
  archived_by         uuid,
  archive_reason      text,

  CONSTRAINT coverage_groups_pkey
    PRIMARY KEY (id),

  CONSTRAINT coverage_groups_required_hc_check
    CHECK (required_headcount >= 1),
  CONSTRAINT coverage_groups_code_prefix_check
    CHECK (coverage_code LIKE 'CG-%'),

  CONSTRAINT coverage_groups_account_fkey
    FOREIGN KEY (account_id)  REFERENCES public.accounts(id)       ON DELETE RESTRICT,
  CONSTRAINT coverage_groups_position_fkey
    FOREIGN KEY (position_id) REFERENCES public.positions(id)      ON DELETE RESTRICT,
  CONSTRAINT coverage_groups_created_by_fkey
    FOREIGN KEY (created_by)  REFERENCES public.users_profile(id)  ON DELETE SET NULL,
  CONSTRAINT coverage_groups_archived_by_fkey
    FOREIGN KEY (archived_by) REFERENCES public.users_profile(id)  ON DELETE SET NULL
);

COMMENT ON TABLE public.coverage_groups IS
  'CGCODE root — the roving peer of a stationary VCODE. Owns the coverage '
  'identity, position/emp type, and required_headcount (the HC anchor). '
  'HC lives HERE, never on member stores. Archive-first; never hard-deleted. '
  'Carved out of vw_slot_derived_vacancy_shadow (separate roving shadow, R-D).';
COMMENT ON COLUMN public.coverage_groups.coverage_code IS
  'CGCODE. Unique per active account. CG- prefix enforces disjointness from VCODE.';
COMMENT ON COLUMN public.coverage_groups.required_headcount IS
  'Number of rovers the footprint needs. Drives the N eager coverage_slots (RA5). '
  'Independent of store count: adding/removing a store never changes HC.';
COMMENT ON COLUMN public.coverage_groups.status IS
  'Cached group status (open/pipeline/hr_processing/partially_filled/filled/closed). '
  'Authoritative status is slot-count-derived (R-D); this is a list-query cache.';

-- Per-account CGCODE uniqueness (active only) — mirrors the VCODE invariant.
-- Archived codes may repeat.
CREATE UNIQUE INDEX IF NOT EXISTS uq_coverage_groups_account_code_active
  ON public.coverage_groups (account_id, coverage_code)
  WHERE archived_at IS NULL;

-- Scope-filtered active list (non-admin user_scopes path).
CREATE INDEX IF NOT EXISTS idx_coverage_groups_account_active
  ON public.coverage_groups (account_id)
  WHERE archived_at IS NULL;

-- Position rollups.
CREATE INDEX IF NOT EXISTS idx_coverage_groups_position
  ON public.coverage_groups (position_id);

-- ── RLS: RPC-first, scope-filtered reads (backend-enforced) ───
ALTER TABLE public.coverage_groups ENABLE ROW LEVEL SECURITY;
REVOKE INSERT, UPDATE, DELETE ON public.coverage_groups FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.coverage_groups FROM anon;

CREATE POLICY coverage_groups_read_scoped
  ON public.coverage_groups
  FOR SELECT
  TO authenticated
  USING (
    public.i_have_full_access()
    OR account_id = ANY (public.get_my_allowed_account_ids())
  );
