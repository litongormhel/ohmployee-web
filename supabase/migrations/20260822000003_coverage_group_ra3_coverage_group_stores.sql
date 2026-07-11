-- ============================================================
-- OHM2026_0066 — Coverage Group Phase R-A — RA3 coverage_group_stores
-- Migration:  20260822000003_coverage_group_ra3_coverage_group_stores.sql
-- Plan:       docs/architecture/coverage_group_phase_ra_schema_plan.md (§RA3)
-- Model:      docs/architecture/coverage_group_data_model_plan.md (§2)
-- Depends on: RA1 (coverage_groups), live stores, users_profile.
-- ============================================================
-- Scope: Store-footprint membership — one row per group↔store edge.
--   Covered stores hold 0 HC (HC lives on the group). Archive-first:
--   a store leaves the footprint by archival, preserving coverage history.
--
--   Constraints encoded here (per plan §4):
--     • partial unique (coverage_group_id, store_id) WHERE archived_at IS NULL
--         → a store appears at most once in a group's active footprint
--     • partial unique (coverage_group_id) WHERE is_anchor AND archived_at IS NULL
--         → exactly one active anchor per group (operator-chosen)
--     • cross-account guard: store.account_id == group.account_id
--         (security defect if violated — enforced by BEFORE trigger)
--   Indexes:
--     • (coverage_group_id) WHERE archived_at IS NULL — active footprint
--     • (store_id)          WHERE archived_at IS NULL — "which groups cover X"
--
-- Validation (run after apply):
--   V1  SELECT to_regclass('public.coverage_group_stores');
--   V2  -- same store twice active in one group → rejected
--   V3  -- two active anchors in one group → rejected
--   V4  -- cross-account store (store.account_id <> group.account_id) → rejected
-- ============================================================

CREATE TABLE IF NOT EXISTS public.coverage_group_stores (
  id                 uuid        NOT NULL DEFAULT gen_random_uuid(),
  coverage_group_id  uuid        NOT NULL,
  store_id           uuid        NOT NULL,

  -- Home/base store; exactly one active true per group (operator-chosen).
  -- Drives card title/location + per-store reporting default. NOT "counts for HC".
  is_anchor          boolean     NOT NULL DEFAULT false,

  added_at           timestamptz NOT NULL DEFAULT now(),
  added_by           uuid,

  -- Archive-first footprint edit; a dropped store sets archived_at.
  archived_at        timestamptz,
  archived_by        uuid,

  CONSTRAINT coverage_group_stores_pkey
    PRIMARY KEY (id),

  -- RESTRICT, not CASCADE: archive-first forbids hard delete of a group,
  -- so a cascade delete must never be possible (FK is a safety net).
  CONSTRAINT coverage_group_stores_group_fkey
    FOREIGN KEY (coverage_group_id) REFERENCES public.coverage_groups(id) ON DELETE RESTRICT,
  CONSTRAINT coverage_group_stores_store_fkey
    FOREIGN KEY (store_id)          REFERENCES public.stores(id)          ON DELETE RESTRICT,
  CONSTRAINT coverage_group_stores_added_by_fkey
    FOREIGN KEY (added_by)          REFERENCES public.users_profile(id)   ON DELETE SET NULL,
  CONSTRAINT coverage_group_stores_archived_by_fkey
    FOREIGN KEY (archived_by)       REFERENCES public.users_profile(id)   ON DELETE SET NULL
);

COMMENT ON TABLE public.coverage_group_stores IS
  'Active footprint of a coverage group — one row per group↔store edge, 0 HC each. '
  'Replaces the implicit "distinct vcodes across store-link tables ∪ primary_vcode". '
  'Archive-first; a store leaves by archived_at, preserving coverage history.';
COMMENT ON COLUMN public.coverage_group_stores.is_anchor IS
  'Operator-chosen home/base store. Exactly one active true per group. Drives '
  'card title/location + reporting default; does NOT mean "counts for HC".';

-- One active edge per (group, store).
CREATE UNIQUE INDEX IF NOT EXISTS uq_coverage_group_stores_active_edge
  ON public.coverage_group_stores (coverage_group_id, store_id)
  WHERE archived_at IS NULL;

-- Exactly one active anchor per group.
CREATE UNIQUE INDEX IF NOT EXISTS uq_coverage_group_stores_active_anchor
  ON public.coverage_group_stores (coverage_group_id)
  WHERE is_anchor AND archived_at IS NULL;

-- Active footprint lookup.
CREATE INDEX IF NOT EXISTS idx_coverage_group_stores_group_active
  ON public.coverage_group_stores (coverage_group_id)
  WHERE archived_at IS NULL;

-- "Which groups cover store X" / coverage lens.
CREATE INDEX IF NOT EXISTS idx_coverage_group_stores_store_active
  ON public.coverage_group_stores (store_id)
  WHERE archived_at IS NULL;

-- ── Cross-account footprint guard (security defect if violated) ──
CREATE OR REPLACE FUNCTION public.fn_assert_coverage_store_same_account()
  RETURNS trigger
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
AS $guard$
DECLARE
  v_group_account uuid;
  v_store_account uuid;
BEGIN
  SELECT account_id INTO v_group_account
  FROM public.coverage_groups WHERE id = NEW.coverage_group_id;

  SELECT account_id INTO v_store_account
  FROM public.stores WHERE id = NEW.store_id;

  IF v_group_account IS NULL THEN
    RAISE EXCEPTION 'coverage group % not found', NEW.coverage_group_id;
  END IF;

  IF v_store_account IS DISTINCT FROM v_group_account THEN
    RAISE EXCEPTION
      'cross-account footprint rejected: store % (account %) does not belong to group % account %',
      NEW.store_id, v_store_account, NEW.coverage_group_id, v_group_account
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END
$guard$;

COMMENT ON FUNCTION public.fn_assert_coverage_store_same_account() IS
  'Enforces store.account_id == group.account_id on every footprint edge. '
  'Cross-account coverage is a security defect (plan §RA3, blocker #5).';

DROP TRIGGER IF EXISTS trg_assert_coverage_store_same_account ON public.coverage_group_stores;
CREATE TRIGGER trg_assert_coverage_store_same_account
  BEFORE INSERT OR UPDATE OF coverage_group_id, store_id
  ON public.coverage_group_stores
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_assert_coverage_store_same_account();

-- ── RLS: RPC-first, scope-filtered reads (via parent group) ───
ALTER TABLE public.coverage_group_stores ENABLE ROW LEVEL SECURITY;
REVOKE INSERT, UPDATE, DELETE ON public.coverage_group_stores FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.coverage_group_stores FROM anon;

CREATE POLICY coverage_group_stores_read_scoped
  ON public.coverage_group_stores
  FOR SELECT
  TO authenticated
  USING (
    public.i_have_full_access()
    OR EXISTS (
      SELECT 1 FROM public.coverage_groups cg
      WHERE cg.id = coverage_group_stores.coverage_group_id
        AND cg.account_id = ANY (public.get_my_allowed_account_ids())
    )
  );
