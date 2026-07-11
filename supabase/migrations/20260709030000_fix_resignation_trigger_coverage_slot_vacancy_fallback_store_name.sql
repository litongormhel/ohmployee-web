-- ============================================================================
-- Fix Resignation Trigger Gaps: Coverage Slot Not Released, Missing Vacancy
-- Fallback (IF EXISTS branch), Null store_name (ELSE branch)
-- Migration: 20260709030000_fix_resignation_trigger_coverage_slot_vacancy_fallback_store_name.sql
-- Task: ohm#5t8p2rvn
-- ============================================================================
-- PROBLEM (3 distinct bugs in fn_plantilla_separation_to_vacancy()):
--
--   BUG 1 — coverage_slots not released on resignation:
--     No logic updated coverage_slots when the separated employee occupied a
--     Roving/Coverage Group slot. Slot stayed 'active' with a stale
--     current_occupant_plantilla_id, so it never surfaced as an open
--     Coverage Group vacancy. Confirmed live: plantilla bcd8844b-e37e-43e9-
--     846b-7875a6ebeb70 (Lapid, Lito Lacson, 2023-2365) separated on
--     2026-07-09 with coverage_slot_id set, but coverage_slots row
--     4d4810b8-4469-4d30-a7ff-0d9634ab089f stayed slot_status='active',
--     current_occupant_plantilla_id still pointing at the separated employee.
--
--   BUG 2 — no Vacancy creation fallback in the IF EXISTS branch (roving
--     path, pre-existing plantilla_store_links): when a link's resolved
--     v_vac.id IS NULL (no vacancy_id on the link and no vacancy matches its
--     vcode), the branch fell through with no action — the vacancy UPDATE
--     was simply skipped, silently no-op'ing. Only the ELSE/ESA-fallback
--     branch had insert-if-missing logic. Confirmed live: both of Lapid's
--     plantilla_store_links rows (998eeeac.../890d4f68...) have
--     vacancy_id = NULL and no vacancies row exists for VCAG2_0021/0022 —
--     separation silently did nothing for either store.
--
--   BUG 3 — store_name omitted on the ELSE-branch plantilla_store_links
--     INSERT: the ESA-fallback INSERT INTO plantilla_store_links never
--     populated store_name, leaving it NULL and rendering "-" in the Past
--     Stores UI for any link created via that path.
--
-- FIX (surgical, layered onto the live 20260709023900 body — no other logic
--      touched):
--   1. New top-of-function block: IF NEW.coverage_slot_id IS NOT NULL, flips
--      the matching coverage_slots row to slot_status='open',
--      current_occupant_plantilla_id=NULL — guarded by
--      current_occupant_plantilla_id = NEW.id so a slot already reassigned
--      to someone else is never clobbered. Runs once per separating row,
--      before the roving/stationary branch split (coverage_slot_id is not
--      exclusive to the roving branch at the schema level).
--   2. IF EXISTS branch (roving, pre-existing links): added an ELSE to the
--      existing `IF v_vac.id IS NOT NULL THEN ... END IF;` block that
--      mirrors the ELSE branch's create-if-missing shape (position_id hard
--      guard, then INSERT a new Open vacancy) using v_link.vcode as the
--      vacancy vcode and a stores lookup by that vcode for store_id/
--      store_name/account_id. The new vacancy_id is written back onto the
--      plantilla_store_links row so future separations resolve it directly.
--      NOT a verbatim copy of the ELSE branch's INSERT: that branch's
--      column list references vacancies.is_roving, which does not exist on
--      public.vacancies (confirmed via pg_attribute) — copying it verbatim
--      would throw 42703 immediately. The new INSERT here omits the
--      nonexistent column; every other column matches the ELSE branch's
--      create-vacancy shape (status='Open', vacancy_type='Backfill',
--      source='plantilla'). See "Not Done" below — the ELSE branch's own
--      is_roving bug is pre-existing and out of scope for this pass.
--   3. ELSE branch (ESA-fallback): added store_name to the
--      INSERT INTO plantilla_store_links column list, sourced from
--      v_esa.store_name (employee_store_allocations already carries a
--      correct store_name for every active allocation row).
--
-- NOT DONE (discovered, pre-existing, out of scope — flagged, not fixed):
--   The ELSE/ESA-fallback branch's vacancy lookup/create block references
--   public.vacancies.is_roving twice (the SELECT ... WHERE is_roving = true
--   lookup, and the is_roving column in the INSERT list) — this column does
--   not exist on public.vacancies (confirmed via pg_attribute: no is_roving,
--   no coverage_group_id). This means the ELSE branch has never successfully
--   executed on staging; every ESA-fallback roving separation currently
--   fails with 42703 the moment it's reached. This is a distinct,
--   undiagnosed bug from the 3 confirmed root causes this migration fixes
--   and was not touched here per explicit task scope ("do not re-diagnose").
--   Needs its own follow-up fix.
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
  -- Hard guard for position_id validity before reopening or creating vacancy
  IF NOT EXISTS (
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
