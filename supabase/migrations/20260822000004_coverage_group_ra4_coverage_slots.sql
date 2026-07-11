-- ============================================================
-- OHM2026_0066 — Coverage Group Phase R-A — RA4 coverage_slots
-- Migration:  20260822000004_coverage_group_ra4_coverage_slots.sql
-- Plan:       docs/architecture/coverage_group_phase_ra_schema_plan.md (§RA4)
-- Model:      docs/architecture/coverage_group_data_model_plan.md (§3)
-- Lifecycle:  docs/architecture/coverage_slot_lifecycle_plan.md (LOCKED rec #2)
-- Depends on: RA1 (coverage_groups).
-- ============================================================
-- Scope: One coverage slot = one unit of roving HC. N slots per group,
--   N = required_headcount. The roving peer of plantilla_slots.
--
--   FILLED TOKEN = 'active' (LOCKED — OHM2026_0064). 'occupied' is
--   reserved exclusively for stationary plantilla_slots; the two models
--   run side by side with disjoint filled tokens. UI label = "Filled" for
--   both. This CHECK is the data-layer resolution of OHM2026_0063 Risk #1.
--
--   Constraints encoded here (per plan §4):
--     • CHECK (slot_status IN ('open','pipeline','hr_processing','active','closed'))
--     • CHECK (slot_ordinal >= 1)
--     • unique (coverage_group_id, slot_ordinal)   — stable ordinal identity
--   Index:
--     • (coverage_group_id, slot_status) — count strips + claim-lowest-open
--
-- Reconciliation invariant (R-B+, asserted by RA5 eager-emit at creation):
--   open + pipeline + hr_processing + active + closed == required_headcount.
--
-- Validation (run after apply):
--   V1  SELECT to_regclass('public.coverage_slots');
--   V2  -- slot_status = 'occupied' rejected; 'active' accepted
--   V3  -- slot_ordinal = 0 rejected
--   V4  -- duplicate (coverage_group_id, slot_ordinal) rejected
-- ============================================================

CREATE TABLE IF NOT EXISTS public.coverage_slots (
  id                 uuid        NOT NULL DEFAULT gen_random_uuid(),
  coverage_group_id  uuid        NOT NULL,

  -- 1..N within the group; stable identity for reopen-on-same-ordinal.
  slot_ordinal       integer     NOT NULL,

  -- Filled token is 'active' (NOT 'occupied' — that is stationary-only).
  slot_status        text        NOT NULL DEFAULT 'open',

  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT coverage_slots_pkey
    PRIMARY KEY (id),

  CONSTRAINT coverage_slots_status_check
    CHECK (slot_status IN ('open', 'pipeline', 'hr_processing', 'active', 'closed')),
  CONSTRAINT coverage_slots_ordinal_check
    CHECK (slot_ordinal >= 1),

  -- RESTRICT, not CASCADE: archive-first forbids hard delete of a group.
  CONSTRAINT coverage_slots_group_fkey
    FOREIGN KEY (coverage_group_id) REFERENCES public.coverage_groups(id) ON DELETE RESTRICT
);

COMMENT ON TABLE public.coverage_slots IS
  'One coverage slot = one unit of roving HC. N slots per group (N = '
  'required_headcount). Roving peer of plantilla_slots. Filled token = '
  '"active" (occupied = stationary only; UI label "Filled" for both).';
COMMENT ON COLUMN public.coverage_slots.slot_ordinal IS
  '1..N within the group. Claim takes the lowest-ordinal open slot; '
  'separation reopens the exact same ordinal (active → open). Stable for '
  'the group life — required_headcount is create-time-fixed in V1.';
COMMENT ON COLUMN public.coverage_slots.slot_status IS
  'open | pipeline | hr_processing | active | closed. Filled = "active" '
  '(LOCKED OHM2026_0064). "closed" is the archive-first terminal state.';

-- Stable ordinal identity per group (peer of uq_plantilla_slots_legacy_vcode_ordinal).
CREATE UNIQUE INDEX IF NOT EXISTS uq_coverage_slots_group_ordinal
  ON public.coverage_slots (coverage_group_id, slot_ordinal);

-- Count-strip aggregation + R-B FOR UPDATE SKIP LOCKED lowest-open claim.
CREATE INDEX IF NOT EXISTS idx_coverage_slots_group_status
  ON public.coverage_slots (coverage_group_id, slot_status);

-- ── RLS: RPC-first, scope-filtered reads (via parent group) ───
ALTER TABLE public.coverage_slots ENABLE ROW LEVEL SECURITY;
REVOKE INSERT, UPDATE, DELETE ON public.coverage_slots FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.coverage_slots FROM anon;

CREATE POLICY coverage_slots_read_scoped
  ON public.coverage_slots
  FOR SELECT
  TO authenticated
  USING (
    public.i_have_full_access()
    OR EXISTS (
      SELECT 1 FROM public.coverage_groups cg
      WHERE cg.id = coverage_slots.coverage_group_id
        AND cg.account_id = ANY (public.get_my_allowed_account_ids())
    )
  );
