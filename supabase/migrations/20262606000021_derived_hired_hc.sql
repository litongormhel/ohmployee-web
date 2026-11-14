-- ============================================================================
-- Migration: 20262606000021_derived_hired_hc.sql
-- Prompt:    ohm#7k2d9f4a (SA-2, HC Derivation — ADR-001 DB-level enforcement)
-- Date:      2026-08-03
--
-- Purpose:
--   vacancy_requirements.hc_filled is a falsifiable dual source of truth that
--   failed audit CASE 2 (SM TABUK / VCAG2_0025 phantom Hired=1). This
--   migration replaces it with derivation from plantilla.status = 'Active':
--
--   D2.1  New derived view public.vw_vacancy_requirements — every column of
--         vacancy_requirements, but hc_filled computed as the count of Active
--         (non-deleted) plantilla rows whose vacancy_requirement_id points at
--         the requirement. This is the ADR-001 read path going forward.
--   D2.2  Rewire every writer/reader of the stored counter:
--           - fn_plantilla_separation_to_vacancy(): decrement block removed
--             entirely (derived count drops automatically when a plantilla
--             row leaves 'Active'); everything else preserved verbatim.
--           - resolve_requirement_for_separation(): "most-filled requirement"
--             fallback now ranks by derived Active-plantilla count.
--           - confirm_applicant_onboard() [13-arg overload]: hc_filled sync
--             UPDATE removed; capacity reads (open-requirement resolution and
--             requirement_already_full guard) now derive from
--             GREATEST(Active plantilla linked, other Confirmed Onboard
--             applicants linked) so pre-plantilla pipeline capacity behavior
--             is preserved without any stored counter.
--           - enforce_requirement_on_assignment(): available-requirement pick
--             uses the same derived capacity expression.
--           - create_plantilla_slot_from_request(): NOT modified — its only
--             touch is INSERT ... hc_filled = 0, identical to the column
--             default and forced to 0 by the freeze trigger below.
--           - check_vr_capacity(): NOT modified — read-only validation of a
--             now-frozen value; permanently satisfied.
--           - vw_requirement_reconciliation: NOT modified — diagnostic view
--             comparing stored vs actual; still correct after the freeze.
--   D2.3  One-time reconciliation of the stored column to the derived value
--         (so any residual direct reader sees correct data at cutover), then
--         FREEZE: BEFORE INSERT/UPDATE trigger forces hc_filled = 0 on INSERT
--         and raises on any UPDATE that changes it. Physical removal of the
--         column is deferred to a later prompt (repo migration lint forbids
--         the required DDL token in this repo's automated pipeline).
--   D2.4  Repair public.vw_slot_derived_vacancy_shadow:
--           CASE 2: hired_count now derives strictly from Active plantilla
--                   rows per vcode (the applicant-based heuristics — including
--                   the unconditional "no plantilla rows exist" branch that
--                   produced SM TABUK's phantom Hired=1 — are removed).
--           CASE 3: vacancy_tab priority is now
--                   Closure > Pipeline > Open > Hired > Open(default), so a
--                   record with active pipeline can never classify as Open.
--
-- BEFORE-state snapshots (verbatim pg_get_functiondef / pg_get_viewdef, taken
-- from staging qqiiznmqxfoamqytjica on 2026-08-03) are archived in the task
-- scratchpad:
--   sa2_before_fn_plantilla_separation_to_vacancy.sql
--   sa2_before_confirm_applicant_onboard_13arg.sql
--   sa2_before_small_functions.sql   (check_vr_capacity,
--                                     resolve_requirement_for_separation,
--                                     enforce_requirement_on_assignment)
--   sa2_before_vw_slot_derived_vacancy_shadow.sql (+ vw_requirement_reconciliation)
--
-- NOTE (Flutter follow-up, NOT done here): Flutter currently reads
-- vacancy_requirements directly; repointing those reads to
-- vw_vacancy_requirements is flagged for a later Flutter prompt.
--
-- Idempotent: CREATE OR REPLACE throughout; DROP TRIGGER IF EXISTS before
-- CREATE TRIGGER; reconciliation UPDATE is a no-op when already in sync and
-- runs before the freeze trigger is (re)created.
-- ============================================================================

-- ────────────────────────────────────────────────────────────────────────────
-- D2.1  Derived read view: vw_vacancy_requirements
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW public.vw_vacancy_requirements
WITH (security_invoker = true) AS
SELECT
  vr.id,
  vr.vacancy_id,
  vr.position_id,
  vr.employment_type,
  vr.hc_needed,
  COALESCE(pc.active_count, 0)::integer AS hc_filled,
  vr.created_at,
  vr.source_headcount_request_id
FROM public.vacancy_requirements vr
LEFT JOIN (
  SELECT p.vacancy_requirement_id, count(*) AS active_count
  FROM public.plantilla p
  WHERE p.status = 'Active'
    AND COALESCE(p.is_deleted, false) = false
    AND p.vacancy_requirement_id IS NOT NULL
  GROUP BY p.vacancy_requirement_id
) pc ON pc.vacancy_requirement_id = vr.id;

COMMENT ON VIEW public.vw_vacancy_requirements IS
  'ohm#7k2d9f4a (ADR-001): vacancy_requirements with hc_filled DERIVED from '
  'Active plantilla rows linked via plantilla.vacancy_requirement_id. The '
  'stored vacancy_requirements.hc_filled column is frozen and deprecated — '
  'read this view instead.';

GRANT SELECT ON public.vw_vacancy_requirements TO authenticated;
GRANT SELECT ON public.vw_vacancy_requirements TO service_role;

-- ────────────────────────────────────────────────────────────────────────────
-- D2.2a  resolve_requirement_for_separation — derived-count fallback ranking
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.resolve_requirement_for_separation(p_vacancy_requirement_id uuid, p_store_id uuid, p_account_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  resolved_id uuid;
BEGIN
  IF p_vacancy_requirement_id IS NOT NULL THEN
    RETURN p_vacancy_requirement_id;
  END IF;

  -- Fallback heuristic (ohm#7k2d9f4a): "most-filled requirement" for a vacancy
  -- at the same store + account as the separating employee — now ranked by the
  -- DERIVED Active-plantilla count instead of the frozen stored counter.
  SELECT vr.id INTO resolved_id
    FROM public.vacancy_requirements vr
    JOIN public.vacancies v ON v.id = vr.vacancy_id
    CROSS JOIN LATERAL (
      SELECT count(*) AS active_cnt
        FROM public.plantilla p
       WHERE p.vacancy_requirement_id = vr.id
         AND p.status = 'Active'
         AND COALESCE(p.is_deleted, false) = false
    ) d
   WHERE v.store_id   = p_store_id
     AND v.account_id = p_account_id
     AND d.active_cnt > 0
     AND v.deleted_at IS NULL
   ORDER BY d.active_cnt DESC
   LIMIT 1;

  RETURN resolved_id;
END;
$function$;

-- ────────────────────────────────────────────────────────────────────────────
-- D2.2b  fn_plantilla_separation_to_vacancy — stored-counter decrement removed
--        (everything else preserved byte-for-byte from the live staging body;
--        see sa2_before_fn_plantilla_separation_to_vacancy.sql)
-- ────────────────────────────────────────────────────────────────────────────
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

  -- ohm#7k2d9f4a (ADR-001): the stored-counter decrement that used to live
  -- here is gone. Hired HC is now derived from plantilla.status = 'Active'
  -- (see vw_vacancy_requirements), so this separation is reflected in the
  -- derived counts automatically the moment NEW.status leaves 'Active' —
  -- zero manual sync required.

  UPDATE public.employee_store_allocations
     SET is_active     = false,
         effective_end = COALESCE(NEW.date_of_separation, CURRENT_DATE)
   WHERE plantilla_id = NEW.id
     AND is_active    = true;

  RETURN NEW;
END;
$function$;

-- ────────────────────────────────────────────────────────────────────────────
-- D2.2c  confirm_applicant_onboard (13-arg overload) — stored-counter sync
--        removed; capacity reads derived. The legacy 11-arg overload never
--        touched hc_filled and is left untouched.
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.confirm_applicant_onboard(p_applicant_id uuid, p_last_name text DEFAULT NULL::text, p_first_name text DEFAULT NULL::text, p_middle_name text DEFAULT NULL::text, p_full_name text DEFAULT NULL::text, p_contact_number text DEFAULT NULL::text, p_remarks text DEFAULT NULL::text, p_roving_assignment_id uuid DEFAULT NULL::uuid, p_hired_by_user_id uuid DEFAULT NULL::uuid, p_endorsed_by_deployer_id uuid DEFAULT NULL::uuid, p_endorsed_by_name text DEFAULT NULL::text, p_hired_date date DEFAULT NULL::date, p_vacancy_requirement_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_role        text    := public.get_my_role();
  v_role_level  int     := COALESCE(public.get_my_role_level(), 0);
  v_profile_id  uuid    := public.get_my_profile_id();
  v_actor_name  text    := public.get_my_full_name();
  v_app         public.applicants%ROWTYPE;
  v_vac         public.vacancies%ROWTYPE;
  v_hr          public.hr_emploc%ROWTYPE;
  v_full_name   text;
  v_hired_by_id uuid;
  v_is_roving   boolean;
  v_store_link_id uuid;
  v_late_result   jsonb;
  v_existing_plt      public.plantilla%ROWTYPE;
  v_roving_id         uuid;
  v_new_roving        boolean := false;
  v_plt_store_link_id uuid;
  v_existing_employee_no text;
  v_roving_hr_found   boolean := false;
  v_resolved_requirement_id uuid;
BEGIN
  IF NOT (
    public.i_have_full_access()
    OR v_role_level = 30
    OR v_role IN ('OM', 'HRCO', 'ATL', 'TL', 'Operations Manager')
  ) THEN
    RAISE EXCEPTION 'forbidden: Ops Team, Data Team, or Super Admin required'
      USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_app
    FROM public.applicants
   WHERE id = p_applicant_id
  FOR UPDATE;

  IF NOT FOUND OR COALESCE(v_app.is_archived, false) THEN
    RAISE EXCEPTION 'applicant % not found or archived', p_applicant_id
      USING ERRCODE = 'P0002';
  END IF;

  IF COALESCE(v_app.status, 'New') IN (
    'Failed', 'Backout', 'Did Not Report', 'Rejected by Ops'
  ) THEN
    RAISE EXCEPTION
      'applicant % has terminal status % — cannot onboard',
      p_applicant_id, v_app.status
      USING ERRCODE = 'P0002';
  END IF;

  SELECT * INTO v_vac
    FROM public.vacancies
   WHERE vcode = v_app.vacancy_vcode
     AND deleted_at IS NULL
   LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'vacancy % not found', v_app.vacancy_vcode
      USING ERRCODE = 'P0002';
  END IF;

  v_is_roving := COALESCE(p_roving_assignment_id, v_app.roving_assignment_id) IS NOT NULL;

  -- ── Idempotent Guard ──
  -- Re-onboarding the same applicant must be a no-op (ADR-001: no stored
  -- counter exists to double-increment anymore, but the early return is kept)
  IF v_app.status = 'Confirmed Onboard' THEN
    IF v_is_roving THEN
      SELECT * INTO v_hr
        FROM public.hr_emploc
       WHERE roving_assignment_id = COALESCE(p_roving_assignment_id, v_app.roving_assignment_id)
         AND assignment_type = 'Roving'
         AND deleted_at IS NULL
       ORDER BY created_at ASC LIMIT 1;
    ELSE
      SELECT * INTO v_hr
        FROM public.hr_emploc
       WHERE deleted_at IS NULL
         AND (
           applicant_id = v_app.id
           OR (applicant_name = v_app.full_name AND vcode = v_app.vacancy_vcode)
         )
       ORDER BY created_at DESC LIMIT 1;
    END IF;

    RETURN jsonb_build_object(
      'ok',               true,
      'applicant_id',     v_app.id,
      'applicant_status', v_app.status,
      'hr_emploc_id',     v_hr.id,
      'vcode',            v_app.vacancy_vcode,
      'idempotent',       true
    );
  END IF;

  -- Resolve requirement ID (prefer caller param, then applicant linkage, then
  -- open requirement). ohm#7k2d9f4a: "open" is now judged by DERIVED occupancy
  -- — GREATEST(Active plantilla linked, Confirmed Onboard applicants linked,
  -- excluding this applicant) — instead of the frozen stored counter. This
  -- preserves the pre-existing pipeline-capacity semantics (the old counter
  -- was synced from Confirmed Onboard applicant counts) while also honoring
  -- plantilla truth.
  v_resolved_requirement_id := COALESCE(p_vacancy_requirement_id, v_app.vacancy_requirement_id);

  IF v_resolved_requirement_id IS NULL AND NOT v_is_roving THEN
    SELECT vr.id INTO v_resolved_requirement_id
      FROM public.vacancy_requirements vr
     WHERE vr.vacancy_id = v_vac.id
       AND GREATEST(
             (SELECT count(*) FROM public.plantilla p
               WHERE p.vacancy_requirement_id = vr.id
                 AND p.status = 'Active'
                 AND COALESCE(p.is_deleted, false) = false),
             (SELECT count(*) FROM public.applicants a
               WHERE a.vacancy_requirement_id = vr.id
                 AND a.status = 'Confirmed Onboard'
                 AND COALESCE(a.is_archived, false) = false
                 AND a.id <> p_applicant_id)
           ) < vr.hc_needed
     ORDER BY vr.created_at
     LIMIT 1;

    -- If all are filled, fall back to the first requirement
    IF v_resolved_requirement_id IS NULL THEN
      SELECT id INTO v_resolved_requirement_id
        FROM public.vacancy_requirements
       WHERE vacancy_id = v_vac.id
       ORDER BY created_at
       LIMIT 1;
    END IF;
  END IF;

  IF p_hired_by_user_id IS NOT NULL THEN
    v_hired_by_id := p_hired_by_user_id;
  ELSE
    v_hired_by_id := public.get_my_auth_uid();
  END IF;

  UPDATE public.applicants
     SET status               = 'Confirmed Onboard',
         last_name            = COALESCE(p_last_name,      last_name),
         first_name           = COALESCE(p_first_name,     first_name),
         middle_name          = COALESCE(p_middle_name,    middle_name),
         full_name            = COALESCE(p_full_name,      full_name),
         contact_number       = COALESCE(p_contact_number, contact_number),
         remarks              = COALESCE(p_remarks,        remarks),
         hired_date           = COALESCE(p_hired_date,     hired_date),
         hired_by             = v_hired_by_id::text,
         roving_assignment_id = COALESCE(
                                  p_roving_assignment_id,
                                  roving_assignment_id
                                ),
         vacancy_requirement_id = COALESCE(
                                    v_resolved_requirement_id,
                                    vacancy_requirement_id
                                  ),
         last_activity_at     = NOW(),
         last_activity_by     = v_profile_id,
         updated_at           = NOW()
   WHERE id = p_applicant_id;

  SELECT * INTO v_app FROM public.applicants WHERE id = p_applicant_id;

  IF v_is_roving AND p_roving_assignment_id IS NULL THEN
    SELECT ra.id INTO v_roving_id
      FROM public.plantilla plt
      JOIN public.roving_assignments ra
        ON ra.plantilla_id = plt.id AND ra.is_active = true
     WHERE plt.employee_no = v_app.full_name
       AND plt.account = v_vac.account
     LIMIT 1;

    IF v_roving_id IS NULL THEN
      v_new_roving := true;
    END IF;
  ELSE
    v_roving_id := p_roving_assignment_id;
  END IF;

  SELECT plt.* INTO v_existing_plt
    FROM public.plantilla plt
   WHERE plt.account = v_vac.account
     AND (
       plt.employee_no ILIKE v_app.full_name
       OR plt.employee_name ILIKE v_app.full_name
     )
     AND plt.status IN ('Active', 'On Leave')
     AND NOT COALESCE(plt.is_deleted, false)
     AND NOT COALESCE(plt.is_archived, false)
   LIMIT 1;

  IF v_existing_plt.id IS NOT NULL THEN
    v_late_result := public.link_late_store_to_plantilla(
      p_plantilla_id      => v_existing_plt.id,
      p_vcode             => v_vac.vcode,
      p_vacancy_id        => v_vac.id,
      p_applicant_id      => v_app.id,
      p_performed_by      => v_profile_id
    );
  END IF;

  SELECT * INTO v_hr
    FROM public.hr_emploc
   WHERE applicant_id = p_applicant_id
   LIMIT 1;

  IF v_hr.id IS NOT NULL THEN
    UPDATE public.hr_emploc
       SET hr_status              = COALESCE(hr_status, 'Pending'),
           vacancy_requirement_id = COALESCE(vacancy_requirement_id, v_resolved_requirement_id),
           updated_at             = NOW()
      WHERE id = v_hr.id
     RETURNING * INTO v_hr;
  ELSE
    IF NOT v_is_roving THEN
      INSERT INTO public.hr_emploc (
        applicant_name, applicant_name_snapshot, applicant_id,
        vcode, vacancy_id, vacancy_code_snapshot,
        account, account_id, chain_id, store_id, province_id,
        area_name_snapshot, hrco_user_id_snapshot, om_user_id_snapshot,
        atl_user_id_snapshot, position_id_snapshot, position,
        store_name, hrco_name, status, hr_status, hired_date,
        deployed_by_user_id, created_by, updated_by, date_requested,
        assignment_type, roving_assignment_id, covered_stores,
        vacancy_requirement_id
      ) VALUES (
        v_app.full_name, v_app.full_name, v_app.id,
        v_vac.vcode, v_vac.id, v_vac.vcode,
        v_vac.account, v_vac.account_id, v_vac.chain_id, v_vac.store_id, v_vac.province_id,
        v_vac.area_name, v_vac.hrco_user_id, v_vac.om_user_id,
        v_vac.atl_user_id, v_vac.position_id, v_vac.position,
        v_vac.store_name, v_vac.hrco_name, 'Pending Emploc', 'Pending', v_app.hired_date,
        v_profile_id, v_profile_id, v_profile_id, NOW(),
        'Stationary'::public.hr_emploc_assignment_type,
        NULL, '[]'::jsonb,
        v_resolved_requirement_id
      )
      RETURNING * INTO v_hr;
    END IF;
  END IF;

  INSERT INTO public.employee_activity_log (
    emploc_no, vcode, activity_type, description, performed_by, metadata
  ) VALUES (
    COALESCE(v_hr.emploc_no, v_app.full_name),
    v_vac.vcode,
    'confirmed_onboard',
    'Applicant confirmed onboard and moved to HR Emploc for ' || v_vac.vcode,
    v_actor_name,
    jsonb_build_object(
      'applicant_id',               v_app.id,
      'hr_emploc_id',               v_hr.id,
      'vacancy_id',                 v_vac.id,
      'role',                       v_role,
      'hired_by_user_id',           v_hired_by_id,
      'endorsed_by_deployer_id',    p_endorsed_by_deployer_id,
      'endorsed_by_name',           p_endorsed_by_name,
      'is_roving',                  v_is_roving,
      'hired_date',                 v_app.hired_date,
      'late_store_linked',          v_late_result IS NOT NULL,
      'vacancy_requirement_id',     v_resolved_requirement_id,
      'movement_at',                NOW()
    )
  );

  -- ohm#7k2d9f4a (ADR-001): the stored-counter sync that used to live here is
  -- gone — hired HC is derived (vw_vacancy_requirements). Only the concurrency
  -- guard remains, now judged by derived occupancy (excluding this applicant,
  -- whose status was already flipped above).
  IF v_resolved_requirement_id IS NOT NULL THEN
    IF p_vacancy_requirement_id IS NOT NULL THEN
      IF EXISTS (
        SELECT 1 FROM public.vacancy_requirements vr
         WHERE vr.id = p_vacancy_requirement_id
           AND GREATEST(
                 (SELECT count(*) FROM public.plantilla p
                   WHERE p.vacancy_requirement_id = vr.id
                     AND p.status = 'Active'
                     AND COALESCE(p.is_deleted, false) = false),
                 (SELECT count(*) FROM public.applicants a
                   WHERE a.vacancy_requirement_id = vr.id
                     AND a.status = 'Confirmed Onboard'
                     AND COALESCE(a.is_archived, false) = false
                     AND a.id <> p_applicant_id)
               ) >= vr.hc_needed
      ) THEN
        RAISE EXCEPTION 'requirement_already_full'
          USING MESSAGE = 'The selected position requirement has no remaining headcount. Another hire may have filled it concurrently.',
                HINT    = 'Refresh the vacancy and select a different requirement.';
      END IF;
    END IF;
  END IF;

  IF NOT v_is_roving THEN
    PERFORM public.fn_sync_slot_to_hr_processing(
      p_vcode        => v_vac.vcode,
      p_applicant_id => v_app.id,
      p_performed_by => v_profile_id,
      p_source_fn    => 'confirm_applicant_onboard'
    );
  END IF;

  RETURN jsonb_build_object(
    'ok',                       true,
    'applicant_id',             v_app.id,
    'applicant_status',         v_app.status,
    'hr_emploc_id',             v_hr.id,
    'vcode',                    v_vac.vcode,
    'hired_by_user_id',         v_hired_by_id,
    'hired_date',               v_app.hired_date,
    'is_roving',                v_is_roving,
    'late_store_linked',        v_late_result,
    'vacancy_requirement_id',   v_resolved_requirement_id
  );
END;
$function$;

-- ────────────────────────────────────────────────────────────────────────────
-- D2.2d  enforce_requirement_on_assignment — derived-capacity requirement pick
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.enforce_requirement_on_assignment()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  has_requirements boolean;
BEGIN
  -- Non-requirement flows (ADR-001 / Task 5 classification) are never gated.
  IF COALESCE(NEW.is_pool_employee, false)
     OR NEW.deployment_type = 'Roving'
     OR NEW.coverage_slot_id IS NOT NULL
     OR NEW.vacancy_id IS NULL
  THEN
    RETURN NEW;
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.vacancy_requirements
    WHERE vacancy_id = NEW.vacancy_id
  ) INTO has_requirements;

  IF has_requirements AND NEW.vacancy_requirement_id IS NULL THEN
    -- Try to resolve vacancy_requirement_id from vacancy_id.
    -- ohm#7k2d9f4a: "available" is now judged by DERIVED occupancy —
    -- GREATEST(Active plantilla linked, Confirmed Onboard applicants linked)
    -- < hc_needed — instead of the frozen stored counter.
    SELECT vr.id INTO NEW.vacancy_requirement_id
      FROM public.vacancy_requirements vr
     WHERE vr.vacancy_id = NEW.vacancy_id
       AND GREATEST(
             (SELECT count(*) FROM public.plantilla p
               WHERE p.vacancy_requirement_id = vr.id
                 AND p.status = 'Active'
                 AND COALESCE(p.is_deleted, false) = false),
             (SELECT count(*) FROM public.applicants a
               WHERE a.vacancy_requirement_id = vr.id
                 AND a.status = 'Confirmed Onboard'
                 AND COALESCE(a.is_archived, false) = false)
           ) < vr.hc_needed
     ORDER BY vr.created_at
     LIMIT 1;

    -- If none found (all are full), fall back to the first requirement by created_at.
    IF NEW.vacancy_requirement_id IS NULL THEN
      SELECT id INTO NEW.vacancy_requirement_id
        FROM public.vacancy_requirements
       WHERE vacancy_id = NEW.vacancy_id
       ORDER BY created_at
       LIMIT 1;
    END IF;

    -- If still NULL (should not happen if has_requirements is true), raise exception.
    IF NEW.vacancy_requirement_id IS NULL THEN
      RAISE EXCEPTION 'vacancy_requirement_id is required for this vacancy'
        USING ERRCODE = '23514',
              HINT = 'This vacancy has structured requirements (vacancy_requirements). '
                     'Select a specific requirement during onboarding before assigning to plantilla.';
    END IF;
  END IF;

  RETURN NEW;
END;
$function$;

-- ────────────────────────────────────────────────────────────────────────────
-- D2.3  One-time reconciliation, then freeze the stored column
-- ────────────────────────────────────────────────────────────────────────────
-- Ensure re-runs of this file can still reconcile before the freeze re-arms.
DROP TRIGGER IF EXISTS trg_freeze_vr_hc_filled ON public.vacancy_requirements;

-- One-time reconciliation: sync the stored value to the derived Active count
-- so any residual direct reader sees correct data at cutover. LEAST() guard
-- keeps trg_check_vr_capacity satisfied even if a requirement is over-linked.
-- (Verified drift on staging 2026-08-03: exactly 2 rows — VCAG2_0024 stored 0
-- vs derived 1, and VCAG2_0025 stored 1 vs derived 0, the audit CASE 2 row.)
DROP TRIGGER IF EXISTS trg_freeze_vr_hc_filled ON public.vacancy_requirements;

UPDATE public.vacancy_requirements vr
   SET hc_filled = LEAST(
         vr.hc_needed,
         (SELECT count(*) FROM public.plantilla p
           WHERE p.vacancy_requirement_id = vr.id
             AND p.status = 'Active'
             AND COALESCE(p.is_deleted, false) = false)
       )
 WHERE vr.hc_filled IS DISTINCT FROM LEAST(
         vr.hc_needed,
         (SELECT count(*) FROM public.plantilla p
           WHERE p.vacancy_requirement_id = vr.id
             AND p.status = 'Active'
             AND COALESCE(p.is_deleted, false) = false)
       );

-- Freeze trigger: INSERT always lands at 0; any UPDATE that changes the value
-- is rejected. This blocks all future drift of the deprecated counter.
CREATE OR REPLACE FUNCTION public.fn_freeze_vr_hc_filled()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.hc_filled := 0;
    RETURN NEW;
  END IF;

  IF NEW.hc_filled IS DISTINCT FROM OLD.hc_filled THEN
    RAISE EXCEPTION
      'vacancy_requirements.hc_filled is frozen (ohm#7k2d9f4a, ADR-001): the column is deprecated; hired HC is derived from Active plantilla rows — read public.vw_vacancy_requirements instead'
      USING ERRCODE = '55000';
  END IF;

  RETURN NEW;
END;
$function$;

CREATE TRIGGER trg_freeze_vr_hc_filled
BEFORE INSERT OR UPDATE ON public.vacancy_requirements
FOR EACH ROW EXECUTE FUNCTION public.fn_freeze_vr_hc_filled();

COMMENT ON COLUMN public.vacancy_requirements.hc_filled IS
  'DEPRECATED + FROZEN (ohm#7k2d9f4a, 2026-08-03, ADR-001). Do not read or '
  'write. Hired HC is derived from plantilla.status = ''Active'' via '
  'public.vw_vacancy_requirements. Writes are blocked by '
  'trg_freeze_vr_hc_filled; physical removal of the column is deferred to a '
  'later prompt.';

-- ────────────────────────────────────────────────────────────────────────────
-- D2.4  Repair vw_slot_derived_vacancy_shadow
--       CASE 2: hired_count strictly from Active plantilla per vcode.
--       CASE 3: tab priority Closure > Pipeline > Open > Hired > Open.
--       Output column list is unchanged (names, order, types).
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW public.vw_slot_derived_vacancy_shadow
WITH (security_invoker = true) AS
 WITH aging_basis AS (
         SELECT DISTINCT ON (sh.slot_id) sh.slot_id,
            sh.created_at AS open_episode_start
           FROM slot_history sh
          WHERE sh.new_value = 'open'::text
          ORDER BY sh.slot_id, sh.created_at DESC
        ), pending_closure AS (
         SELECT DISTINCT vcr.vacancy_vcode
           FROM vacancy_closure_requests vcr
             JOIN vacancies v_1 ON v_1.vcode = vcr.vacancy_vcode AND v_1.deleted_at IS NULL AND COALESCE(v_1.is_archived, false) = false
          WHERE vcr.status = 'Pending'::text
        ), applicant_counts AS (
         SELECT a_1.vacancy_vcode,
            count(DISTINCT a_1.id) FILTER (WHERE COALESCE(a_1.is_archived, false) = false AND fn_is_active_vacancy_applicant_status(a_1.status)) AS pipeline_count
           FROM applicants a_1
          WHERE a_1.vacancy_vcode IS NOT NULL
          GROUP BY a_1.vacancy_vcode
        ), plantilla_counts AS (
         SELECT p.vcode,
            count(DISTINCT p.id) FILTER (WHERE COALESCE(p.is_deleted, false) = false AND p.status = 'Active'::text) AS active_emp_count
           FROM plantilla p
          WHERE p.vcode IS NOT NULL
          GROUP BY p.vcode
        ), req_counts AS (
         SELECT vr.vacancy_id,
            sum(vr.hc_needed) AS req_hc_needed
           FROM vacancy_requirements vr
          GROUP BY vr.vacancy_id
        )
 SELECT ps.legacy_vcode,
    ps.legacy_vcode AS vacancy_id,
    v.id AS legacy_vacancy_id,
    v.store_name,
    v.area_city,
    v.province,
    v.area_name,
    v.required_headcount,
    (array_agg(ps.store_id ORDER BY ps.created_at, (ps.id::text)))[1] AS store_id,
    min(st.store_branch) AS store_branch,
    (array_agg(ps.account_id ORDER BY ps.created_at, (ps.id::text)))[1] AS account_id,
    min(a.account_name) AS account_name,
    (array_agg(ps.group_id ORDER BY ps.created_at, (ps.id::text)))[1] AS group_id,
    min(g.group_name) AS group_name,
    min(ps."position") AS "position",
    min(ps.employment_type) AS employment_type,
    false AS is_roving,
    count(*) AS required_hc,
    COALESCE(rc.req_hc_needed, count(*)) AS hc_needed,
    COALESCE(max(ac.pipeline_count), 0::bigint) AS pipeline_count,
    -- ohm#7k2d9f4a CASE 2 fix: Hired = Active plantilla rows on this vcode,
    -- nothing else. The former applicant-based heuristics (including the
    -- unconditional "no plantilla rows on vcode" branch that produced the
    -- SM TABUK phantom Hired=1) are removed per ADR-001.
    COALESCE(max(plc.active_emp_count), 0::bigint) AS hired_count,
        CASE
            WHEN (EXISTS ( SELECT 1
               FROM plantilla_slots ps_closed
              WHERE ps_closed.legacy_vcode = ps.legacy_vcode AND ps_closed.slot_status = 'closed'::text)) THEN 0::bigint
            ELSE GREATEST(0::bigint, COALESCE(rc.req_hc_needed, count(*)) - COALESCE(max(plc.active_emp_count), 0::bigint))
        END AS open_count,
    count(*) FILTER (WHERE ps.slot_status = 'hr_processing'::text) AS hr_processing_count,
    count(*) FILTER (WHERE ps.slot_status = 'occupied'::text) AS occupied_count,
    count(*) FILTER (WHERE ps.slot_status = 'closed'::text) AS closed_count,
    COALESCE(max(ac.pipeline_count), 0::bigint) AS active_applicant_count,
    bool_or(pc.vacancy_vcode IS NOT NULL) AS has_pending_closure,
    -- ohm#7k2d9f4a CASE 3 fix: classification priority is
    -- Closure > Pipeline > Open > Hired > Open(default) — Pipeline now
    -- overrides Open so one record can never classify as both.
        CASE
            WHEN bool_or(pc.vacancy_vcode IS NOT NULL) OR (EXISTS ( SELECT 1
               FROM plantilla_slots ps_closed
              WHERE ps_closed.legacy_vcode = ps.legacy_vcode AND ps_closed.slot_status = 'closed'::text)) THEN 'Closure'::text
            WHEN COALESCE(max(ac.pipeline_count), 0::bigint) > 0 THEN 'Pipeline'::text
            WHEN GREATEST(0::bigint, COALESCE(rc.req_hc_needed, count(*)) - COALESCE(max(plc.active_emp_count), 0::bigint)) > 0 THEN 'Open'::text
            WHEN COALESCE(max(plc.active_emp_count), 0::bigint) >= COALESCE(rc.req_hc_needed, count(*)) THEN 'Hired'::text
            ELSE 'Open'::text
        END AS vacancy_tab,
    min(COALESCE(ab.open_episode_start, ps.created_at)) FILTER (WHERE ps.slot_status = 'open'::text) AS aging_start_at,
        CASE
            WHEN GREATEST(0::bigint, COALESCE(rc.req_hc_needed, count(*)) - COALESCE(max(plc.active_emp_count), 0::bigint)) = 0 THEN NULL::integer
            WHEN min(COALESCE(ab.open_episode_start, ps.created_at)) FILTER (WHERE ps.slot_status = 'open'::text)::date > CURRENT_DATE THEN NULL::integer
            ELSE CURRENT_DATE - min(COALESCE(ab.open_episode_start, ps.created_at)) FILTER (WHERE ps.slot_status = 'open'::text)::date
        END AS aging_days,
    min(ps.created_at) AS created_at,
    max(ps.updated_at) AS updated_at,
    max(ps.closed_at) AS closed_at,
    (array_agg(ps.source_hc_request_id ORDER BY ps.created_at, (ps.id::text)))[1] AS source_hc_request_id,
    v.urgency_level,
    v.hrco_name,
    v.hrco_user_id,
    v.target_fill_date,
    v.triggered_by_user_id,
    v.triggered_by_name
   FROM plantilla_slots ps
     LEFT JOIN aging_basis ab ON ab.slot_id = ps.id
     LEFT JOIN stores st ON st.id = ps.store_id
     LEFT JOIN accounts a ON a.id = ps.account_id
     LEFT JOIN groups g ON g.id = ps.group_id
     LEFT JOIN pending_closure pc ON pc.vacancy_vcode = ps.legacy_vcode
     LEFT JOIN applicant_counts ac ON ac.vacancy_vcode = ps.legacy_vcode
     LEFT JOIN plantilla_counts plc ON plc.vcode = ps.legacy_vcode
     JOIN vacancies v ON v.vcode = ps.legacy_vcode AND v.deleted_at IS NULL AND COALESCE(v.is_archived, false) = false AND v.status <> 'Archived'::text
     LEFT JOIN req_counts rc ON rc.vacancy_id = v.id
  WHERE ps.legacy_vcode IS NOT NULL AND ps.is_roving = false AND NOT (EXISTS ( SELECT 1
           FROM coverage_group_stores cgs
             JOIN coverage_groups cg ON cg.id = cgs.coverage_group_id
          WHERE cgs.store_id = ps.store_id AND cgs.archived_at IS NULL AND cg.archived_at IS NULL))
  GROUP BY ps.legacy_vcode, v.id, rc.req_hc_needed;
