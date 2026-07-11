-- ============================================================
-- OHMployee — CENCOM Backend Phase 3
-- Scope: Snapshot generation RPC, weekly delta RPC, pg_cron job.
--
-- What this migration does:
--   1. fn_generate_cencom_weekly_snapshot(p_date) — idempotent
--      snapshot generator. Queries live tables directly (SECURITY
--      DEFINER) filtered to cencom_scope groups. Writes one
--      aggregate row + one row per Group 1–5 to
--      cencom_weekly_snapshots.
--   2. fn_cencom_weekly_delta(p_reference_date) — compares the
--      two most recent snapshots on or before p_reference_date.
--      Returns current vs previous Tuesday delta for aggregate
--      and per-group rows.
--   3. pg_cron job: Tuesday 06:00 PHT = Monday 22:00 UTC
--      (adjust if server timezone differs).
--
-- Rollback:
--   SELECT cron.unschedule('cencom-weekly-snapshot');
--   DROP FUNCTION IF EXISTS public.fn_cencom_weekly_delta(date);
--   DROP FUNCTION IF EXISTS public.fn_generate_cencom_weekly_snapshot(date);
--
-- Prerequisites:
--   Phase 1 (cencom_scope column + views) must be applied first.
--   Phase 2 (cencom_weekly_snapshots table) must be applied first.
-- ============================================================

-- ── fn_generate_cencom_weekly_snapshot ───────────────────────────────────────
-- Idempotent: deletes all rows for p_date then re-inserts.
-- Queries live tables directly — DOES NOT use security_invoker views
-- to avoid RLS conflicts when called by pg_cron as postgres.
-- cencom_scope filter applied at the groups JOIN level.

CREATE OR REPLACE FUNCTION public.fn_generate_cencom_weekly_snapshot(
  p_date date DEFAULT CURRENT_DATE
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_group_rows  int := 0;
  v_agg_row     int := 0;
  v_result      jsonb;
BEGIN
  RAISE LOG '[cencom_snapshot] Starting snapshot generation for date %', p_date;

  -- ── Idempotency: clear existing rows for this date ──────────────────────
  DELETE FROM public.cencom_weekly_snapshots
  WHERE  snapshot_date = p_date;

  -- ── Build the CENCOM scoped data and insert in a single CTE-backed statement ──
  --
  -- FIX (OHM2026_2004): A PostgreSQL WITH clause is scoped to exactly one SQL
  -- statement. The previous implementation defined all CTEs (including group_agg)
  -- in a single WITH block, then used two separate INSERT statements. After the
  -- first INSERT consumed the CTE block, group_agg was no longer in scope for
  -- the second INSERT, producing:
  --   ERROR: relation "group_agg" does not exist (SQLSTATE 42P01)
  --
  -- Fix: combine both inserts into a single INSERT ... SELECT ... UNION ALL
  -- statement so the full CTE block remains in scope for both result sets.
  -- A discriminator column (row_type) routes each row to its correct snapshot_type.
  -- ---------------------------------------------------------------------------
  INSERT INTO public.cencom_weekly_snapshots (
    snapshot_date, snapshot_type,
    group_id, group_name, group_code,
    actual_hc, pipeline_count, vacant_count, required_hc,
    mfr, projected_mfr, vacancy_rate, pipeline_coverage, health_status
  )
  WITH actual AS (
    SELECT
      pl.account_id,
      count(*) FILTER (WHERE pl.status = 'Active') AS actual_hc
    FROM   public.plantilla pl
    WHERE  NOT COALESCE(pl.is_deleted, false)
    GROUP  BY pl.account_id
  ),
  pipeline AS (
    SELECT
      he.account_id,
      count(*) AS pipeline_count
    FROM   public.hr_emploc he
    WHERE  he.status NOT IN ('Moved to Plantilla', 'Backout')
      AND  he.deleted_at IS NULL
    GROUP  BY he.account_id
  ),
  vacant AS (
    SELECT
      v.account_id,
      count(*) AS vacant_count
    FROM   public.vacancies v
    WHERE  v.status = 'Open'
      AND  NOT COALESCE(v.is_archived, false)
    GROUP  BY v.account_id
  ),
  account_base AS (
    SELECT
      a.id                                   AS account_id,
      a.group_id,
      g.group_name,
      g.group_code,
      COALESCE(ac.actual_hc, 0)              AS actual_hc,
      COALESCE(p.pipeline_count, 0)          AS pipeline_count,
      COALESCE(v.vacant_count, 0)            AS vacant_count,
      COALESCE(ac.actual_hc, 0)
        + COALESCE(p.pipeline_count, 0)
        + COALESCE(v.vacant_count, 0)        AS required_hc
    FROM   public.accounts a
    JOIN   public.groups g ON g.id = a.group_id AND g.cencom_scope = true
    LEFT JOIN actual   ac ON ac.account_id = a.id
    LEFT JOIN pipeline p  ON p.account_id  = a.id
    LEFT JOIN vacant   v  ON v.account_id  = a.id
    WHERE  a.is_active = true
  ),
  group_agg AS (
    SELECT
      group_id,
      group_name,
      group_code,
      sum(actual_hc)::bigint                                           AS actual_hc,
      sum(pipeline_count)::bigint                                      AS pipeline_count,
      sum(vacant_count)::bigint                                        AS vacant_count,
      sum(required_hc)::bigint                                         AS required_hc,
      CASE WHEN sum(required_hc) = 0 THEN 1.0
           ELSE round(sum(actual_hc)::numeric / sum(required_hc)::numeric, 4)
      END                                                              AS mfr,
      CASE WHEN sum(required_hc) = 0 THEN 1.0
           ELSE round((sum(actual_hc) + sum(pipeline_count))::numeric
                      / sum(required_hc)::numeric, 4)
      END                                                              AS projected_mfr,
      CASE WHEN sum(required_hc) = 0 THEN 0.0
           ELSE round(sum(vacant_count)::numeric / sum(required_hc)::numeric, 4)
      END                                                              AS vacancy_rate,
      CASE WHEN sum(required_hc) = 0 THEN 0.0
           ELSE round(sum(pipeline_count)::numeric / sum(required_hc)::numeric, 4)
      END                                                              AS pipeline_coverage,
      CASE WHEN sum(required_hc) = 0                           THEN 'healthy'
           WHEN sum(actual_hc)::numeric
                / sum(required_hc)::numeric >= 1.0              THEN 'healthy'
           WHEN sum(actual_hc)::numeric
                / sum(required_hc)::numeric >= 0.9              THEN 'at_risk'
           ELSE                                                       'critical'
      END                                                              AS health_status
    FROM account_base
    GROUP BY group_id, group_name, group_code
  ),
  total_agg AS (
    SELECT
      sum(actual_hc)::bigint                                           AS actual_hc,
      sum(pipeline_count)::bigint                                      AS pipeline_count,
      sum(vacant_count)::bigint                                        AS vacant_count,
      sum(required_hc)::bigint                                         AS required_hc,
      CASE WHEN sum(required_hc) = 0 THEN 1.0
           ELSE round(sum(actual_hc)::numeric / sum(required_hc)::numeric, 4)
      END                                                              AS mfr,
      CASE WHEN sum(required_hc) = 0 THEN 1.0
           ELSE round((sum(actual_hc) + sum(pipeline_count))::numeric
                      / sum(required_hc)::numeric, 4)
      END                                                              AS projected_mfr,
      CASE WHEN sum(required_hc) = 0 THEN 0.0
           ELSE round(sum(vacant_count)::numeric / sum(required_hc)::numeric, 4)
      END                                                              AS vacancy_rate,
      CASE WHEN sum(required_hc) = 0 THEN 0.0
           ELSE round(sum(pipeline_count)::numeric / sum(required_hc)::numeric, 4)
      END                                                              AS pipeline_coverage,
      CASE WHEN sum(required_hc) = 0                           THEN 'healthy'
           WHEN sum(actual_hc)::numeric
                / sum(required_hc)::numeric >= 1.0              THEN 'healthy'
           WHEN sum(actual_hc)::numeric
                / sum(required_hc)::numeric >= 0.9              THEN 'at_risk'
           ELSE                                                       'critical'
      END                                                              AS health_status
    FROM account_base
  )
  -- Aggregate row first (group_id NULL), then one row per cencom_scope group.
  -- Single INSERT keeps group_agg and total_agg in the same CTE scope.
  SELECT p_date, 'aggregate', NULL, 'ALL GROUPS', 'ALL',
         actual_hc, pipeline_count, vacant_count, required_hc,
         mfr, projected_mfr, vacancy_rate, pipeline_coverage, health_status
  FROM   total_agg
  UNION ALL
  SELECT p_date, 'group', group_id, group_name, group_code,
         actual_hc, pipeline_count, vacant_count, required_hc,
         mfr, projected_mfr, vacancy_rate, pipeline_coverage, health_status
  FROM   group_agg;

  GET DIAGNOSTICS v_group_rows = ROW_COUNT;
  -- v_group_rows now holds total rows inserted (1 aggregate + N group rows).
  -- Derive the two sub-counts for the result JSON.
  v_agg_row    := LEAST(v_group_rows, 1);        -- always 1 unless table was empty
  v_group_rows := GREATEST(v_group_rows - 1, 0); -- remainder = per-group rows

  v_result := jsonb_build_object(
    'snapshot_date',  p_date,
    'aggregate_rows', v_agg_row,
    'group_rows',     v_group_rows,
    'generated_at',   now()
  );

  RAISE LOG '[cencom_snapshot] Completed for date %: % aggregate row, % group rows',
    p_date, v_agg_row, v_group_rows;

  RETURN v_result;

EXCEPTION WHEN OTHERS THEN
  RAISE LOG '[cencom_snapshot] ERROR for date %: % %', p_date, SQLSTATE, SQLERRM;
  RAISE;
END;
$$;

ALTER FUNCTION public.fn_generate_cencom_weekly_snapshot(date) OWNER TO postgres;

COMMENT ON FUNCTION public.fn_generate_cencom_weekly_snapshot(date) IS
  'Idempotent CENCOM weekly snapshot generator. '
  'Freezes Group 1–5 operational state (HC, pipeline, vacancies, MFR) for p_date. '
  'Deletes and re-inserts all rows for p_date on each call. '
  'Returns JSON summary: {snapshot_date, aggregate_rows, group_rows, generated_at}. '
  'Called by pg_cron every Tuesday 06:00 PHT. Phase 3.';

GRANT EXECUTE ON FUNCTION public.fn_generate_cencom_weekly_snapshot(date) TO service_role;
-- Intentionally NOT granted to authenticated — superAdmin/headAdmin may call via service_role only.


-- ── fn_cencom_weekly_delta ────────────────────────────────────────────────────
-- Compares the two most recent snapshots on or before p_reference_date.
-- Returns NULL previous_* columns if only one snapshot exists (first week).
-- Flutter receives current + previous + delta for MFR, HC, pipeline, vacancies.

CREATE OR REPLACE FUNCTION public.fn_cencom_weekly_delta(
  p_reference_date date DEFAULT CURRENT_DATE
)
RETURNS TABLE (
  current_snapshot_date   date,
  previous_snapshot_date  date,
  snapshot_type           text,
  group_id                uuid,
  group_name              text,
  group_code              text,

  current_hc              bigint,
  previous_hc             bigint,
  hc_delta                bigint,

  current_mfr             numeric,
  previous_mfr            numeric,
  mfr_delta               numeric,

  current_pipeline        bigint,
  previous_pipeline       bigint,
  pipeline_delta          bigint,

  current_vacant          bigint,
  previous_vacant         bigint,
  vacant_delta            bigint,

  current_required        bigint,
  previous_required       bigint,
  required_delta          bigint,

  current_health_status   text,
  previous_health_status  text,
  health_changed          boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  WITH ordered_dates AS (
    SELECT DISTINCT snapshot_date
    FROM   public.cencom_weekly_snapshots
    WHERE  snapshot_date <= p_reference_date
    ORDER  BY snapshot_date DESC
    LIMIT  2
  ),
  latest_date   AS (SELECT MAX(snapshot_date) AS d FROM ordered_dates),
  previous_date AS (SELECT MIN(snapshot_date) AS d FROM ordered_dates),
  current_snap  AS (
    SELECT * FROM public.cencom_weekly_snapshots
    WHERE  snapshot_date = (SELECT d FROM latest_date)
  ),
  previous_snap AS (
    SELECT * FROM public.cencom_weekly_snapshots
    WHERE  snapshot_date = (SELECT d FROM previous_date)
      AND  snapshot_date < (SELECT d FROM latest_date) -- guard: only if truly different
  )
  SELECT
    (SELECT d FROM latest_date)::date          AS current_snapshot_date,
    (SELECT d FROM previous_date
      WHERE d < (SELECT d FROM latest_date))::date AS previous_snapshot_date,

    c.snapshot_type,
    c.group_id,
    c.group_name,
    c.group_code,

    c.actual_hc                                AS current_hc,
    p.actual_hc                                AS previous_hc,
    c.actual_hc - COALESCE(p.actual_hc, 0)    AS hc_delta,

    c.mfr                                      AS current_mfr,
    p.mfr                                      AS previous_mfr,
    c.mfr - COALESCE(p.mfr, 0)                AS mfr_delta,

    c.pipeline_count                           AS current_pipeline,
    p.pipeline_count                           AS previous_pipeline,
    c.pipeline_count - COALESCE(p.pipeline_count, 0) AS pipeline_delta,

    c.vacant_count                             AS current_vacant,
    p.vacant_count                             AS previous_vacant,
    c.vacant_count - COALESCE(p.vacant_count, 0) AS vacant_delta,

    c.required_hc                              AS current_required,
    p.required_hc                              AS previous_required,
    c.required_hc - COALESCE(p.required_hc, 0) AS required_delta,

    c.health_status                            AS current_health_status,
    p.health_status                            AS previous_health_status,
    (c.health_status IS DISTINCT FROM p.health_status) AS health_changed

  FROM current_snap c
  LEFT JOIN previous_snap p
    ON p.group_id IS NOT DISTINCT FROM c.group_id
   AND p.snapshot_type = c.snapshot_type
  ORDER BY
    c.snapshot_type DESC,  -- 'group' before 'aggregate'? keep aggregate first
    c.group_code NULLS FIRST;
$$;

ALTER FUNCTION public.fn_cencom_weekly_delta(date) OWNER TO postgres;

COMMENT ON FUNCTION public.fn_cencom_weekly_delta(date) IS
  'Returns current vs previous CENCOM weekly snapshot delta. '
  'Covers aggregate + per-group rows. p_reference_date defaults to today. '
  'previous_* columns are NULL if fewer than 2 snapshots exist (first week). '
  'hc_delta / mfr_delta positive = improvement; negative = decline. '
  'Phase 3.';

GRANT EXECUTE ON FUNCTION public.fn_cencom_weekly_delta(date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_cencom_weekly_delta(date) TO service_role;


-- ── pg_cron: Tuesday 06:00 PHT (Monday 22:00 UTC) ────────────────────────────
-- Job name: cencom-weekly-snapshot
-- Cron: '0 22 * * 1'  → runs Monday 22:00 UTC = Tuesday 06:00 UTC+8 (PHT)
--
-- ⚠ TIMEZONE NOTE:
--   If your Supabase project uses a different server timezone, adjust the cron
--   expression accordingly:
--     UTC+8 (PHT) → use '0 22 * * 1'   (Monday 22:00 UTC)
--     UTC+7       → use '0 23 * * 1'   (Monday 23:00 UTC)
--     UTC         → use '0 6  * * 2'   (Tuesday 06:00 UTC)
--   Verify in Supabase Dashboard → Database → Extensions → pg_cron.
--
-- Idempotent: unschedules stale job by name before re-creating.
-- Silent if pg_cron is not enabled (functions still available for manual call).

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_extension WHERE extname = 'pg_cron'
  ) THEN
    RAISE WARNING '[cencom_cron] pg_cron not found — skipping job registration. '
                  'Enable pg_cron in Supabase Dashboard → Database → Extensions, '
                  'then re-run or schedule manually via: '
                  'SELECT cron.schedule(''cencom-weekly-snapshot'', ''0 22 * * 1'', '
                  '''SELECT public.fn_generate_cencom_weekly_snapshot(CURRENT_DATE)'');';
    RETURN;
  END IF;

  -- Remove stale registration (no-op if absent).
  DELETE FROM cron.job WHERE jobname = 'cencom-weekly-snapshot';

  -- Tuesday 06:00 PHT = Monday 22:00 UTC.
  PERFORM cron.schedule(
    'cencom-weekly-snapshot',
    '0 22 * * 1',
    'SELECT public.fn_generate_cencom_weekly_snapshot(CURRENT_DATE)'
  );

  RAISE LOG '[cencom_cron] Registered cencom-weekly-snapshot at Monday 22:00 UTC (Tuesday 06:00 PHT).';

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING '[cencom_cron] Failed to register cron job: % %', SQLSTATE, SQLERRM;
END;
$$;
