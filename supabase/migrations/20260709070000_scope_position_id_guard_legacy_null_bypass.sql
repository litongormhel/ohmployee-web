-- ============================================================================
-- Scope position_id Separation Guard: hard-block only post-import-fix
-- records, bypass legacy null rows.
-- Migration: 20260709070000_scope_position_id_guard_legacy_null_bypass.sql
-- Task: ohm#5qwm9btr
-- ============================================================================
-- DECISION (Ohm, explicit): do NOT backfill the remaining 263 legacy
-- Active/Stationary plantilla rows with position_id IS NULL (179 clean-match
-- + 82 no-match + 2 unrecoverable incl. ZZTEST -- see docs/state/
-- plantilla_state.md and .ai/handoff.md). These will be handled via a future
-- archive/cleanup pass instead. Until then, the hard position_id guard in
-- fn_plantilla_separation_to_vacancy() (stationary path, originally added in
-- 20260708220000-era work and carried forward unchanged through
-- 20260709030000) unconditionally blocks separation for every one of these
-- rows with `Invalid position_id: <NULL>` (P0001) -- even though the data is
-- known-dirty legacy data, not a live bug, and the employee genuinely needs
-- to be separated.
--
-- ROOT CAUSE OF THE NULLS (already fixed forward-only, not touched here):
-- approve_plantilla_import_batch() did not resolve plantilla.position_id
-- from the POSITION text column until ohm#4dh6y1sc's fix. That fix is
-- registered in supabase_migrations.schema_migrations as version
-- 20260709060355 (name 20260709040000_fix_plantilla_import_position_id_
-- resolution -- the version differs from the intended filename timestamp
-- because it was originally applied via the now-permanently-banned
-- Supabase MCP apply_migration tool, which stamps the wall-clock time of
-- invocation as the version; see docs/audit/migration_drift_root_cause_
-- 2026-07-03.md). That wall-clock version IS the exact moment the fix went
-- live: 2026-07-09 06:03:55 UTC (confirmed via `SHOW timezone` = UTC on this
-- project, and `now()` returning a +00 offset). Live query confirms every
-- one of the 263 remaining NULL rows has plantilla.created_at strictly
-- before this cutoff (0 rows after) -- so created_at vs this literal cutoff
-- is a reliable, verified signal, not a guess.
--
-- FIX (surgical -- only the stationary-path position_id guard changes; every
-- other line of fn_plantilla_separation_to_vacancy() is byte-identical to
-- the live 20260709030000 body):
--   - NEW.position_id NOT NULL but references no row in public.positions:
--     ALWAYS hard-blocks, regardless of created_at. This is a distinct,
--     always-invalid state (a dangling/corrupt FK) -- none of the known 263
--     legacy rows are in this state (they are all NULL, not a bad non-null
--     FK), so this case is not part of the legacy-data exception and must
--     keep failing fast.
--   - NEW.position_id IS NULL AND NEW.created_at >= 2026-07-09 06:03:55 UTC:
--     hard-blocks (RAISE EXCEPTION, same P0001 message as before). Any row
--     created after the import-path fix went live should have had
--     position_id resolved (or the import would have failed fast with
--     POSITION_NOT_FOUND) -- a NULL here means something new and different
--     went wrong. Real regression, not legacy dirty data. Keep blocking.
--   - NEW.position_id IS NULL AND NEW.created_at < 2026-07-09 06:03:55 UTC
--     (or NEW.created_at IS NULL, defensively treated as "unknown" and
--     routed through the same COALESCE-to-now() path as the block branch
--     rather than silently allowed): known legacy dirty data pending future
--     archive/cleanup, not a live bug. Skip the check entirely -- proceed
--     with separation normally.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_plantilla_separation_to_vacancy()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_link        RECORD;
  v_vac         public.vacancies%ROWTYPE;
  v_esa         RECORD;
  v_new_link_id uuid;
  v_hc          numeric;
  v_resolved_requirement_id uuid;
  v_link_status text;
  v_link_vcode  text;
BEGIN
  -- Trigger filter logic
  IF OLD.status NOT IN ('Active', 'On Leave', 'For Deactivation')
    OR NEW.status NOT IN ('Resigned', 'AWOL', 'Endo', 'Terminated', 'Others',
                          'Inactive', 'Floating', 'For Deactivation')
    OR OLD.status = NEW.status THEN
    RETURN NEW;
  END IF;

  -- BUG 1 FIX: release the Coverage Group slot this employee occupied, if any.
  -- Guarded by current_occupant_plantilla_id = NEW.id so a slot already
  -- reassigned to a different employee is never clobbered.
  IF NEW.coverage_slot_id IS NOT NULL THEN
    UPDATE public.coverage_slots
       SET slot_status = 'open',
           current_occupant_plantilla_id = NULL,
           updated_at = NOW()
     WHERE id = NEW.coverage_slot_id
       AND current_occupant_plantilla_id = NEW.id;
  END IF;

  -- ── Roving employee path ─────────────────────────────────────────────────
  IF COALESCE(NEW.deployment_type, '') = 'Roving' THEN

    v_link_status := CASE
      WHEN NEW.separation_status IN ('AWOL','Resigned','Terminated','End of Contract','Endo','Others')
        THEN 'Resigned'
      ELSE 'Backed Out'
    END;

    IF EXISTS (
      SELECT 1 FROM public.plantilla_store_links
       WHERE plantilla_id = NEW.id AND status = 'Active'
    ) THEN
      FOR v_link IN
        SELECT * FROM public.plantilla_store_links
         WHERE plantilla_id = NEW.id AND status = 'Active'
      LOOP
        SELECT COALESCE(esa.filled_hc, 1)::numeric INTO v_hc
          FROM public.employee_store_allocations esa
         WHERE esa.plantilla_id        = NEW.id
           AND esa.vcode               = v_link.vcode
           AND esa.is_active           = true
         LIMIT 1;

        v_hc := COALESCE(v_hc, 1);

        IF v_link.vacancy_id IS NOT NULL THEN
          SELECT * INTO v_vac FROM public.vacancies
           WHERE id = v_link.vacancy_id AND deleted_at IS NULL LIMIT 1;
        ELSE
          SELECT * INTO v_vac FROM public.vacancies
           WHERE vcode = v_link.vcode AND deleted_at IS NULL LIMIT 1;
        END IF;

        IF v_vac.id IS NOT NULL THEN
          IF v_vac.status IN ('Filled', 'Closed') THEN
            UPDATE public.vacancies
               SET status         = 'Open',
                   is_archived    = false,
                   archived_at    = NULL,
                   archived_by    = NULL,
                   required_headcount = GREATEST(
                                         COALESCE(required_headcount, 0) + v_hc,
                                         1
                                       ),
                   updated_at     = NOW()
             WHERE id = v_vac.id;
          ELSE
            UPDATE public.vacancies
               SET required_headcount = GREATEST(
                                         COALESCE(required_headcount, 0) + v_hc,
                                         1
                                       ),
                   updated_at = NOW()
             WHERE id = v_vac.id;
          END IF;
        ELSE
          -- BUG 2 FIX: mirror the ELSE branch's create-if-missing logic.
          -- No vacancy_id on the link and no vacancy matches its vcode —
          -- create one instead of silently no-op'ing.
          IF NOT EXISTS (
            SELECT 1 FROM public.positions WHERE id = NEW.position_id
          ) THEN
            RAISE EXCEPTION 'Invalid position_id: %', NEW.position_id;
          END IF;

          INSERT INTO public.vacancies (
            vcode, account, account_id, store_id, store_name, position, position_id,
            status, vacancy_type, required_headcount,
            source, created_at, updated_at
          )
          SELECT
            v_link.vcode,
            NEW.account,
            NEW.account_id,
            s.id,
            s.store_name,
            p.position_name,
            p.id,
            'Open',
            'Backfill',
            GREATEST(v_hc, 1),
            'plantilla',
            NOW(),
            NOW()
          FROM public.positions p
          LEFT JOIN public.stores s ON s.vcode = v_link.vcode
          WHERE p.id = NEW.position_id
          RETURNING * INTO v_vac;

          UPDATE public.plantilla_store_links
             SET vacancy_id = v_vac.id
           WHERE id = v_link.id;
        END IF;

        UPDATE public.plantilla_store_links
           SET status      = v_link_status,
               unlinked_at = NOW()
         WHERE id = v_link.id;

      END LOOP;

    ELSE
      FOR v_esa IN
        SELECT * FROM public.employee_store_allocations
         WHERE plantilla_id = NEW.id AND is_active = true
      LOOP
        v_hc := COALESCE(v_esa.filled_hc, 1)::numeric;

        SELECT * INTO v_vac FROM public.vacancies
         WHERE store_id    = v_esa.store_id
           AND account_id  = NEW.account_id
           AND is_roving   = true
           AND deleted_at  IS NULL
           AND status NOT IN ('Filled', 'Closed', 'Cancelled')
         LIMIT 1;

        IF NOT FOUND THEN
          -- Hard guard for position_id validity
          IF NOT EXISTS (
            SELECT 1 FROM public.positions WHERE id = NEW.position_id
          ) THEN
            RAISE EXCEPTION 'Invalid position_id: %', NEW.position_id;
          END IF;

          INSERT INTO public.vacancies (
            vcode, account, account_id, store_id, position, position_id,
            status, vacancy_type, is_roving, required_headcount,
            source, created_at, updated_at
          )
          SELECT
            v_esa.store_id::text,
            NEW.account,
            NEW.account_id,
            v_esa.store_id,
            p.position_name,
            p.id,
            'Open',
            'Backfill',
            true,
            GREATEST(v_hc, 1),
            'plantilla',
            NOW(),
            NOW()
          FROM public.positions p
          WHERE p.id = NEW.position_id
          RETURNING * INTO v_vac;
        ELSE
          UPDATE public.vacancies
             SET required_headcount = GREATEST(
                                       COALESCE(required_headcount, 0) + v_hc,
                                       1
                                     ),
                 status    = CASE
                               WHEN status IN ('Filled', 'Closed') THEN 'Open'
                               ELSE status
                             END,
                 is_archived = false,
                 archived_at = NULL,
                 archived_by = NULL,
                 updated_at  = NOW()
           WHERE id = v_vac.id
          RETURNING * INTO v_vac;
        END IF;

        v_link_vcode := COALESCE(v_vac.vcode, v_esa.vcode, v_esa.store_id::text);

        -- BUG 3 FIX: populate store_name from the ESA row (already correct
        -- there) instead of leaving it NULL.
        INSERT INTO public.plantilla_store_links (
          plantilla_id, account, vcode, store_name, vacancy_id, status
        )
        SELECT NEW.id, NEW.account, v_link_vcode, v_esa.store_name, v_vac.id, v_link_status
         WHERE NOT EXISTS (
           SELECT 1 FROM public.plantilla_store_links psl
            WHERE psl.plantilla_id = NEW.id
              AND psl.vcode        = v_link_vcode
         )
        RETURNING id INTO v_new_link_id;

        IF v_new_link_id IS NOT NULL THEN
          UPDATE public.plantilla_store_links
             SET unlinked_at = NOW()
           WHERE id = (
             SELECT id FROM public.plantilla_store_links
              WHERE plantilla_id = NEW.id
                AND vcode        = v_link_vcode
              ORDER BY created_at DESC
              LIMIT 1
           );
        END IF;
      END LOOP;
    END IF;

    UPDATE public.employee_store_allocations
       SET is_active     = false,
           effective_end = COALESCE(NEW.date_of_separation, CURRENT_DATE)
     WHERE plantilla_id = NEW.id
       AND is_active    = true;

    RETURN NEW;
  END IF;

  -- ── Stationary employee path ─────────────────────────────────────────────
  -- ohm#5qwm9btr: position_id guard, now time-scoped.
  --
  -- Non-null position_id that doesn't resolve to a real positions row is
  -- always invalid data corruption -- keep hard-blocking regardless of when
  -- the row was created; none of the known legacy-null rows are in this
  -- state, so this branch is not part of the legacy-data exception below.
  --
  -- Null position_id: only hard-block when the row was created AFTER the
  -- approve_plantilla_import_batch() import-path fix (ohm#4dh6y1sc) went
  -- live -- 2026-07-09 06:03:55 UTC, the exact wall-clock version recorded
  -- for that migration in supabase_migrations.schema_migrations (verified:
  -- every one of the 263 remaining NULL Active/Stationary rows on staging
  -- has created_at strictly before this cutoff; 0 rows after). A NULL
  -- position_id on a row created after that cutoff means the insert path
  -- SHOULD have resolved it but didn't -- a genuine new regression, not
  -- legacy dirty data -- so it still hard-blocks. A NULL position_id on a
  -- row created before the cutoff is known dirty legacy data pending future
  -- archive/cleanup (explicit decision -- not backfilled, see
  -- docs/state/plantilla_state.md) -- skip the check entirely and let
  -- separation proceed normally. NEW.created_at IS NULL is treated the same
  -- as "now" (i.e. still blocks) rather than silently falling into the
  -- legacy bypass, since no legitimate row is expected to have a null
  -- created_at.
  IF NEW.position_id IS NULL THEN
    IF COALESCE(NEW.created_at, NOW()) >= TIMESTAMPTZ '2026-07-09 06:03:55+00' THEN
      RAISE EXCEPTION 'Invalid position_id: %', NEW.position_id;
    END IF;
  ELSIF NOT EXISTS (
    SELECT 1 FROM public.positions WHERE id = NEW.position_id
  ) THEN
    RAISE EXCEPTION 'Invalid position_id: %', NEW.position_id;
  END IF;

  PERFORM public.reopen_or_create_vacancy_for_plantilla(
    NEW.id,
    NEW.date_of_separation,
    'Backfill'
  );

  v_resolved_requirement_id := public.resolve_requirement_for_separation(
    NEW.vacancy_requirement_id,
    NEW.store_id,
    NEW.account_id
  );

  IF v_resolved_requirement_id IS NOT NULL THEN
    UPDATE public.vacancy_requirements
       SET hc_filled = GREATEST(0, hc_filled - 1)
     WHERE id = v_resolved_requirement_id;
  END IF;

  UPDATE public.employee_store_allocations
     SET is_active     = false,
         effective_end = COALESCE(NEW.date_of_separation, CURRENT_DATE)
   WHERE plantilla_id = NEW.id
     AND is_active    = true;

  RETURN NEW;
END;
$function$
;
