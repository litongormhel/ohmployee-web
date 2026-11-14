-- Migration: 20260817000003_backfill_vacancies_store_id_from_import_batch
-- Created: 2026-08-17
-- Purpose: One-time backfill of vacancies.store_id for existing rows created by
--   the Import Vacancy pipeline (source_vacancy_import_batch_id IS NOT NULL)
--   whose store_id was never populated (the bug fixed prospectively in
--   20260817000002 for new/re-imported rows). Same two-tier match: unambiguous
--   stores.vcode first, then store_name + account_id + group_id fallback.
--   Rows with more than one fallback candidate, zero candidates, or a
--   defensive unique-index collision are SKIPPED and left store_id = NULL —
--   never fabricated. A single row's skip never aborts the batch.
--
--   Note (verified against the live function definition before writing this
--   migration): vacancies.position_id is never set anywhere on the Import
--   Vacancy path, so the composite unique index uniq_vacancies_open_per_slot
--   (store_id, position_id) — which only fires when BOTH columns are
--   non-null — cannot actually be violated by this backfill today. The
--   collision check below is kept anyway as a defensive guard in case that
--   changes, and is expected to skip zero rows.
--
--   Dry-run finding against staging (qqiiznmqxfoamqytjica, 2026-08-17): the
--   "one VCode per store" invariant is NOT enforced by a DB constraint on
--   stores.vcode — 5 existing vcodes (VMRIZG1_0019..0023) each match 3
--   distinct stores rows. The vcode tier is ambiguity-checked exactly like
--   the name-fallback tier for this reason (see inline comment below).
--
-- Smoke Tests:
-- S1 (dry run, staging, inside BEGIN/ROLLBACK): run this file, note the
--    RAISE NOTICE summary (resolved via vcode / resolved via name / skipped
--    ambiguous / skipped no-match / skipped collision), then ROLLBACK and
--    confirm vacancies.store_id is unchanged for every row.
-- S2: every row resolved via vcode tier has vacancies.store_id equal to the
--     stores row whose vcode matches (case-insensitive).
-- S3: every row resolved via the name fallback has exactly one candidate
--     stores row for (store_name, account_id, group_id).
-- S4: rows with >1 fallback candidates, or 0 candidates in both tiers, still
--     have store_id IS NULL after the migration runs for real.
-- S5: audit_logs gains one 'UPDATE' row per vacancy actually backfilled,
--     tagged with the resolution tier; no audit_logs rows are written for
--     skipped candidates (skip detail is surfaced via RAISE NOTICE only,
--     matching this repo's existing convention for documented-but-unrepaired
--     data — see 20260629040000_repair_remaining_orphan_plantilla_slots.sql).

BEGIN;

DO $$
DECLARE
  v_resolved_vcode    int := 0;
  v_resolved_name     int := 0;
  v_skipped_ambiguous int := 0;
  v_skipped_no_match  int := 0;
  v_skipped_collision int := 0;
  v_row               record;
BEGIN
  -- Build a one-shot resolution plan for every candidate row.
  CREATE TEMP TABLE _store_id_backfill_plan (
    vacancy_id   uuid PRIMARY KEY,
    vcode        text,
    tier         text,       -- 'vcode' | 'name' | 'ambiguous' | 'no_match'
    store_id     uuid,       -- resolved store id, NULL when unresolved
    would_collide boolean NOT NULL DEFAULT false
  ) ON COMMIT DROP;

  -- NOTE: "one VCode per store" is NOT enforced by a DB constraint on
  -- stores.vcode. Dry-run against staging found 5 vcodes (VMRIZG1_0019..0023)
  -- that each match 3 distinct stores rows. The vcode tier is therefore
  -- ambiguity-checked exactly like the name-fallback tier below — an
  -- ambiguous vcode match stays NULL and does NOT fall through to the name
  -- tier (an ambiguous authoritative match is a data-quality signal, not
  -- "no data").
  WITH candidates AS (
    SELECT v.id, v.vcode, v.store_name, v.account_id, v.group_id, v.position_id
      FROM public.vacancies v
     WHERE v.store_id IS NULL
       AND v.source_vacancy_import_batch_id IS NOT NULL
  ),
  vcode_match AS (
    SELECT c.id AS vacancy_id, c.vcode, s.id AS store_id,
           count(*) OVER (PARTITION BY c.id) AS match_count
      FROM candidates c
      JOIN public.stores s ON upper(s.vcode) = upper(c.vcode)
  ),
  vcode_resolved AS (
    SELECT vacancy_id, vcode, store_id
      FROM vcode_match
     WHERE match_count = 1
  ),
  vcode_ambiguous AS (
    SELECT DISTINCT vacancy_id, vcode
      FROM vcode_match
     WHERE match_count > 1
  ),
  name_candidates AS (
    SELECT c.id AS vacancy_id, c.vcode
      FROM candidates c
     WHERE c.id NOT IN (SELECT vacancy_id FROM vcode_match)
  ),
  name_match AS (
    SELECT nc.vacancy_id, nc.vcode, s.id AS store_id,
           count(*) OVER (PARTITION BY nc.vacancy_id) AS match_count
      FROM name_candidates nc
      JOIN candidates c ON c.id = nc.vacancy_id
      JOIN public.stores s
        ON s.store_name = c.store_name
       AND s.account_id = c.account_id
       AND s.group_id   = c.group_id
  ),
  name_resolved AS (
    SELECT vacancy_id, vcode, store_id
      FROM name_match
     WHERE match_count = 1
  ),
  name_ambiguous AS (
    SELECT DISTINCT vacancy_id, vcode
      FROM name_match
     WHERE match_count > 1
  ),
  no_match AS (
    SELECT nc.vacancy_id, nc.vcode
      FROM name_candidates nc
     WHERE nc.vacancy_id NOT IN (SELECT vacancy_id FROM name_match)
  )
  INSERT INTO _store_id_backfill_plan (vacancy_id, vcode, tier, store_id)
  SELECT vacancy_id, vcode, 'vcode', store_id FROM vcode_resolved
  UNION ALL
  SELECT vacancy_id, vcode, 'name', store_id FROM name_resolved
  UNION ALL
  SELECT vacancy_id, vcode, 'ambiguous', NULL FROM vcode_ambiguous
  UNION ALL
  SELECT vacancy_id, vcode, 'ambiguous', NULL FROM name_ambiguous
  UNION ALL
  SELECT vacancy_id, vcode, 'no_match', NULL FROM no_match;

  -- Defensive collision check against uniq_vacancies_open_per_slot
  -- (store_id, position_id) for Open/non-archived/non-hc_request rows.
  -- Expected to affect zero rows today (position_id is always NULL on the
  -- Import Vacancy path) but evaluated for real, not assumed.
  UPDATE _store_id_backfill_plan p
     SET would_collide = true
    FROM public.vacancies c
    WHERE c.id = p.vacancy_id
      AND p.store_id IS NOT NULL
      AND c.position_id IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM public.vacancies existing
         WHERE existing.id <> c.id
           AND existing.store_id = p.store_id
           AND existing.position_id = c.position_id
           AND existing.status = 'Open'
           AND COALESCE(existing.is_archived, false) = false
           AND existing.deleted_at IS NULL
           AND COALESCE(existing.source, '') <> 'hc_request'
      );

  -- Apply the backfill for every resolved, non-colliding row.
  UPDATE public.vacancies v
     SET store_id   = p.store_id,
         updated_at = now()
    FROM _store_id_backfill_plan p
   WHERE v.id = p.vacancy_id
     AND p.store_id IS NOT NULL
     AND p.would_collide = false;

  -- Per-row audit trail for what actually changed.
  INSERT INTO public.audit_logs (actor_id, module, action, record_id, new_data)
  SELECT NULL, 'vacancies', 'UPDATE', p.vacancy_id,
         jsonb_build_object(
           'event',    'store_id_backfill',
           'migration','20260817000003',
           'vcode',    p.vcode,
           'tier',     p.tier,
           'store_id', p.store_id
         )
    FROM _store_id_backfill_plan p
   WHERE p.store_id IS NOT NULL
     AND p.would_collide = false;

  SELECT count(*) FILTER (WHERE tier = 'vcode' AND store_id IS NOT NULL AND NOT would_collide),
         count(*) FILTER (WHERE tier = 'name'  AND store_id IS NOT NULL AND NOT would_collide),
         count(*) FILTER (WHERE tier = 'ambiguous'),
         count(*) FILTER (WHERE tier = 'no_match'),
         count(*) FILTER (WHERE would_collide)
    INTO v_resolved_vcode, v_resolved_name, v_skipped_ambiguous, v_skipped_no_match, v_skipped_collision
    FROM _store_id_backfill_plan;

  RAISE NOTICE 'store_id backfill: resolved_via_vcode=%, resolved_via_name=%, skipped_ambiguous=%, skipped_no_match=%, skipped_index_collision=%',
    v_resolved_vcode, v_resolved_name, v_skipped_ambiguous, v_skipped_no_match, v_skipped_collision;

  IF v_skipped_ambiguous > 0 THEN
    RAISE NOTICE 'Ambiguous (skipped, store_id left NULL) vcodes: %',
      (SELECT string_agg(vcode, ', ') FROM _store_id_backfill_plan WHERE tier = 'ambiguous');
  END IF;

  IF v_skipped_no_match > 0 THEN
    RAISE NOTICE 'No candidate store (skipped, store_id left NULL) vcodes: %',
      (SELECT string_agg(vcode, ', ') FROM _store_id_backfill_plan WHERE tier = 'no_match');
  END IF;

  IF v_skipped_collision > 0 THEN
    RAISE NOTICE 'Unique-index collision (skipped, store_id left NULL) vcodes: %',
      (SELECT string_agg(vcode, ', ') FROM _store_id_backfill_plan WHERE would_collide);
  END IF;
END $$;

COMMIT;
