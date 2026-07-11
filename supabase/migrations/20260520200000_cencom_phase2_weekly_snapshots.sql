-- ============================================================
-- OHMployee — CENCOM Backend Phase 2
-- Scope: Weekly snapshot table architecture.
--
-- What this migration does:
--   1. Creates `cencom_weekly_snapshots` table to store frozen
--      Tuesday 6:00 AM operational state for Group 1–5.
--   2. Enables RLS — snapshot data readable by authenticated users;
--      writes only via SECURITY DEFINER snapshot function.
--   3. Adds uniqueness constraints and safe indexes.
--   4. Adds `fn_cencom_snapshot_scope()` helper RPC for Flutter.
--
-- Rollback:
--   DROP TABLE IF EXISTS public.cencom_weekly_snapshots CASCADE;
--
-- Data model:
--   group_id IS NULL     → aggregate row (all Group 1–5 combined)
--   group_id IS NOT NULL → per-group row
--   snapshot_date        → always the Tuesday the job ran
--   snapshot_type        → 'aggregate' | 'group'
-- ============================================================

-- ── Table ─────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.cencom_weekly_snapshots (
  id                 uuid        NOT NULL DEFAULT gen_random_uuid(),
  snapshot_date      date        NOT NULL,
  snapshot_type      text        NOT NULL DEFAULT 'aggregate'
                                 CHECK (snapshot_type IN ('aggregate','group')),
  group_id           uuid        REFERENCES public.groups(id) ON DELETE SET NULL,
  group_name         text,
  group_code         text,

  -- Raw counts (frozen at snapshot time — never back-computed from live tables)
  actual_hc          bigint      NOT NULL DEFAULT 0,
  pipeline_count     bigint      NOT NULL DEFAULT 0,
  vacant_count       bigint      NOT NULL DEFAULT 0,
  required_hc        bigint      NOT NULL DEFAULT 0,

  -- Rates (stored as computed percentages at snapshot time)
  mfr                numeric(8,4) NOT NULL DEFAULT 0,
  projected_mfr      numeric(8,4) NOT NULL DEFAULT 0,
  vacancy_rate       numeric(8,4) NOT NULL DEFAULT 0,
  pipeline_coverage  numeric(8,4) NOT NULL DEFAULT 0,
  health_status      text        NOT NULL DEFAULT 'healthy'
                                 CHECK (health_status IN ('healthy','at_risk','critical')),

  created_at         timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT cencom_weekly_snapshots_pkey PRIMARY KEY (id)
);

ALTER TABLE public.cencom_weekly_snapshots OWNER TO postgres;

COMMENT ON TABLE public.cencom_weekly_snapshots IS
  'Frozen weekly operational state for CENCOM Group 1–5. '
  'Populated every Tuesday 06:00 PHT (22:00 UTC Monday) by fn_generate_cencom_weekly_snapshot(). '
  'Never modified after insert — historical record only. '
  'Phase 2 — Weekly snapshot architecture.';

COMMENT ON COLUMN public.cencom_weekly_snapshots.snapshot_date IS
  'The Tuesday calendar date this snapshot represents.';
COMMENT ON COLUMN public.cencom_weekly_snapshots.snapshot_type IS
  '"aggregate" = all Group 1–5 combined; "group" = single operational group.';
COMMENT ON COLUMN public.cencom_weekly_snapshots.group_id IS
  'NULL for aggregate rows; references groups.id for per-group rows.';

-- ── Uniqueness constraints ────────────────────────────────────────────────────
-- Aggregate: exactly one aggregate row per snapshot date.
CREATE UNIQUE INDEX IF NOT EXISTS cencom_weekly_snapshots_unique_agg
  ON public.cencom_weekly_snapshots (snapshot_date)
  WHERE group_id IS NULL AND snapshot_type = 'aggregate';

-- Per-group: exactly one row per group per snapshot date.
CREATE UNIQUE INDEX IF NOT EXISTS cencom_weekly_snapshots_unique_group
  ON public.cencom_weekly_snapshots (snapshot_date, group_id)
  WHERE group_id IS NOT NULL AND snapshot_type = 'group';

-- ── Performance indexes ───────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_cencom_snapshots_date
  ON public.cencom_weekly_snapshots (snapshot_date DESC);

CREATE INDEX IF NOT EXISTS idx_cencom_snapshots_group_date
  ON public.cencom_weekly_snapshots (group_id, snapshot_date DESC);

-- ── RLS ──────────────────────────────────────────────────────────────────────
ALTER TABLE public.cencom_weekly_snapshots ENABLE ROW LEVEL SECURITY;

-- Authenticated users can read snapshot data.
-- (Snapshot is pre-aggregated — no per-row PII. Access mirrors CENCOM module access.)
CREATE POLICY "cencom_snapshots_read_authenticated"
  ON public.cencom_weekly_snapshots
  FOR SELECT
  USING (auth.role() = 'authenticated');

-- No INSERT/UPDATE/DELETE policy — all writes go through SECURITY DEFINER function only.
-- Direct table writes from authenticated clients are blocked by the absence of write policies.

-- ── Grants ───────────────────────────────────────────────────────────────────
GRANT SELECT ON public.cencom_weekly_snapshots TO authenticated;
GRANT ALL    ON public.cencom_weekly_snapshots TO service_role;

-- ── Helper RPC: fn_cencom_snapshot_scope ─────────────────────────────────────
-- Returns group IDs and names currently in cencom_scope.
-- Used by Flutter to build scope-aware UI without hardcoding group names.

CREATE OR REPLACE FUNCTION public.fn_cencom_snapshot_scope()
RETURNS TABLE (
  group_id    uuid,
  group_name  text,
  group_code  text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT id, group_name, group_code
  FROM   public.groups
  WHERE  cencom_scope = true
  ORDER  BY group_code;
$$;

ALTER FUNCTION public.fn_cencom_snapshot_scope() OWNER TO postgres;

COMMENT ON FUNCTION public.fn_cencom_snapshot_scope() IS
  'Returns all Group 1–5 operational group IDs and names (cencom_scope = true). '
  'Flutter CENCOM screen calls this to filter account/group queries to CENCOM scope. '
  'Phase 2 — Weekly snapshot architecture.';

GRANT EXECUTE ON FUNCTION public.fn_cencom_snapshot_scope() TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_cencom_snapshot_scope() TO service_role;
