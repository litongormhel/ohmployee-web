-- Migration: 20260708160000_hybrid_requirement_stabilization
-- Prompt ID: ohm#9f3d2a7c (Hybrid Stabilization — Deterministic Routing, Guardrails, Drift Visibility)
--
-- Logic-layer stabilization on top of ohm#c7a9f2d1 (Phase 1 Hardening). No schema rewrite,
-- no NOT NULL, no heuristic removal, no pool/roving/coverage behavior change.
--
-- Depends on:
--   20260708012728_add_vacancy_requirements_normalization.sql (vacancy_requirements table)
--   20260708140000_assignment_hc_sync.sql (confirm_applicant_onboard 13-arg signature)
--   20260708150000_vacancy_requirement_hardening_phase1.sql (nullable FK linkage,
--     move_to_plantilla carries FK forward, fn_plantilla_separation_to_vacancy §5A/§5B inline split)
--
-- SCOPE NOTE — deviation from the originating prompt's literal example SQL:
--   The prompt's `resolve_requirement_for_separation` example resolves the fallback heuristic
--   by `vacancy_id` (`vr.vacancy_id = p_vacancy_id ORDER BY hc_filled DESC`). That does not match
--   production: `plantilla.vacancy_id` is populated on only ~19/376 active rows (ohm#c7a9f2d1
--   finding), so a vacancy_id-keyed heuristic would silently stop matching for the vast majority
--   of stationary separations. The LIVE heuristic already in `fn_plantilla_separation_to_vacancy`
--   (from ohm#91c5af4e / ohm#c7a9f2d1) is keyed by `store_id` + `account_id` instead — that is the
--   heuristic actually exercised in production today. `resolve_requirement_for_separation` below
--   is therefore signed `(p_vacancy_requirement_id, p_store_id, p_account_id)` and reproduces that
--   exact store/account heuristic byte-for-byte, not the prompt's vacancy_id-keyed example. This
--   centralizes the branching (Task 1's actual goal) without changing which rows match (Hard Rule:
--   "DO NOT remove heuristic logic").
--
-- Validation queries at bottom of file.

-- ============================================================
-- TASK 1 — Centralized Hybrid Routing (single source of truth)
-- ============================================================
-- Deterministic path: p_vacancy_requirement_id, when provided, always wins.
-- Heuristic fallback: unchanged store/account most-filled-requirement lookup,
-- reproduced verbatim from the live fn_plantilla_separation_to_vacancy body.

CREATE OR REPLACE FUNCTION public.resolve_requirement_for_separation(
  p_vacancy_requirement_id uuid,
  p_store_id uuid,
  p_account_id uuid
)
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

  -- Fallback heuristic (existing production logic preserved, unchanged since
  -- ohm#91c5af4e / ohm#c7a9f2d1): most-filled requirement for a vacancy at the
  -- same store + account as the separating employee.
  SELECT vr.id INTO resolved_id
    FROM public.vacancy_requirements vr
    JOIN public.vacancies v ON v.id = vr.vacancy_id
   WHERE v.store_id   = p_store_id
     AND v.account_id = p_account_id
     AND vr.hc_filled > 0
     AND v.deleted_at IS NULL
   ORDER BY vr.hc_filled DESC
   LIMIT 1;

  RETURN resolved_id;
END;
$function$;

COMMENT ON FUNCTION public.resolve_requirement_for_separation(uuid, uuid, uuid) IS
  'ohm#9f3d2a7c — Single source of truth for FK-vs-heuristic separation routing. '
  'Deterministic when p_vacancy_requirement_id is set; falls back to the unchanged '
  'store+account most-filled-requirement heuristic otherwise. No inline heuristic '
  'branching is permitted anywhere else — fn_plantilla_separation_to_vacancy calls '
  'this exclusively for the stationary decrement.';

-- ============================================================
-- §2  Patch fn_plantilla_separation_to_vacancy — route stationary decrement
--     through resolve_requirement_for_separation exclusively
-- ============================================================
-- Byte-identical to the live 20260708150000 body except §5A/§5B's inline
-- IF/ELSE is replaced by a single call to the centralized resolver above.
-- Roving path (untouched, does not use vacancy_requirements at all) and every
-- other line are reproduced verbatim.

CREATE OR REPLACE FUNCTION public.fn_plantilla_separation_to_vacancy()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_link        RECORD;
  v_vac         public.vacancies%ROWTYPE;
  v_esa         RECORD;
  v_new_link_id uuid;
  v_hc          numeric;
  v_resolved_requirement_id uuid;
BEGIN
  IF OLD.status NOT IN ('Active', 'On Leave', 'For Deactivation')
    OR NEW.status NOT IN ('Resigned', 'AWOL', 'Endo', 'Terminated', 'Others',
                          'Inactive', 'Floating', 'For Deactivation')
    OR OLD.status = NEW.status THEN
    RETURN NEW;
  END IF;

  -- ── Roving employee path ─────────────────────────────────────────────────
  IF COALESCE(NEW.is_roving, false) THEN

    IF EXISTS (
      SELECT 1 FROM public.plantilla_store_links
       WHERE plantilla_id = NEW.id AND is_active = true
    ) THEN
      FOR v_link IN
        SELECT * FROM public.plantilla_store_links
         WHERE plantilla_id = NEW.id AND is_active = true
      LOOP
        SELECT COALESCE(esa.filled_hc, 1)::numeric INTO v_hc
          FROM public.employee_store_allocations esa
         WHERE esa.plantilla_id        = NEW.id
           AND esa.store_id            = v_link.store_id
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
        END IF;

        UPDATE public.plantilla_store_links
           SET is_active   = false,
               deactivated_at = NOW()
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
            NEW.position,
            NEW.position_id,
            'Open',
            'Backfill',
            true,
            GREATEST(v_hc, 1),
            'plantilla',
            NOW(),
            NOW()
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

        INSERT INTO public.plantilla_store_links (
          plantilla_id, store_id, vcode, vacancy_id, is_active
        )
        SELECT NEW.id, v_esa.store_id,
               COALESCE(v_vac.vcode, v_esa.store_id::text),
               v_vac.id, false
         WHERE NOT EXISTS (
           SELECT 1 FROM public.plantilla_store_links psl
            WHERE psl.plantilla_id = NEW.id
              AND psl.store_id     = v_esa.store_id
         )
        RETURNING id INTO v_new_link_id;

        IF v_new_link_id IS NOT NULL THEN
          UPDATE public.plantilla_store_links
             SET deactivated_at = NOW()
           WHERE id = (
             SELECT id FROM public.plantilla_store_links
              WHERE plantilla_id = NEW.id
                AND store_id     = v_esa.store_id
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
  PERFORM public.reopen_or_create_vacancy_for_plantilla(
    NEW.id,
    NEW.date_of_separation,
    'Backfill'
  );

  -- ohm#9f3d2a7c — Task 1: centralized resolver replaces the prior inline
  -- §5A/§5B IF/ELSE. No behavior change: deterministic when the FK is set,
  -- otherwise the identical store+account heuristic as before.
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
$fn$;

COMMENT ON FUNCTION public.fn_plantilla_separation_to_vacancy() IS
  'ohm#9f3d2a7c — Stationary decrement now routes exclusively through '
  'resolve_requirement_for_separation() (Task 1 centralized routing). No inline '
  'FK-vs-heuristic branching remains in this function. Roving path unchanged '
  '(does not use vacancy_requirements).';

-- ============================================================
-- TASK 4 — Drift Visibility Layer
-- ============================================================
-- Wraps the existing vw_requirement_reconciliation view (ohm#c7a9f2d1). Read-only
-- — no auto-correction, per Hard Rules.

CREATE OR REPLACE FUNCTION public.detect_requirement_drift()
RETURNS TABLE (
  requirement_id uuid,
  vacancy_id uuid,
  delta int
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT
    id,
    vacancy_id,
    delta
  FROM public.vw_requirement_reconciliation
  WHERE delta != 0;
$function$;

COMMENT ON FUNCTION public.detect_requirement_drift() IS
  'ohm#9f3d2a7c — Task 4 drift alert helper. Read-only; surfaces vw_requirement_reconciliation '
  'rows where hc_filled has drifted from the actual linked-plantilla count. Never auto-corrects.';

GRANT EXECUTE ON FUNCTION public.detect_requirement_drift() TO authenticated;

-- ============================================================
-- TASK 2 — Write Guardrail (FORWARD DATA ONLY)
-- ============================================================
-- HARD RULE compliance note: the originating prompt's example trigger enforces
-- "vacancy has requirements -> vacancy_requirement_id required" keyed purely on
-- NEW.vacancy_id. That is unsafe as written: pool, CGCODE-coverage, and (in some
-- historical rows) even stationary INSERTs into plantilla come from several
-- other functions (baseline CSV import approval, additional-store approval,
-- coverage-group execution) that were not all audited/updated as part of this
-- pass, and per Task 5's own flow classification, pool/roving/coverage rows
-- must NEVER be required to carry vacancy_requirement_id. This version adds
-- explicit exclusions for those three flows (mirrors move_to_plantilla's own
-- branch discriminators: is_pool_employee, deployment_type = 'Roving' — used
-- for BOTH the pure-roving and the CGCODE-coverage sub-path, and
-- coverage_slot_id) so the guard only ever applies to structured/stationary
-- assignment inserts, per Hard Rule "DO NOT modify pool / roving / coverage
-- flows to force requirements".

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
    RAISE EXCEPTION 'vacancy_requirement_id is required for this vacancy'
      USING ERRCODE = '23514',
            HINT = 'This vacancy has structured requirements (vacancy_requirements). '
                   'Select a specific requirement during onboarding before assigning to plantilla.';
  END IF;

  RETURN NEW;
END;
$function$;

COMMENT ON FUNCTION public.enforce_requirement_on_assignment() IS
  'ohm#9f3d2a7c — Task 2 write guardrail. Applies ONLY to new plantilla INSERTs '
  '(BEFORE INSERT trigger — never re-evaluates existing rows). Explicitly excludes '
  'pool (is_pool_employee), roving/coverage (deployment_type = ''Roving'' covers both '
  'the pure-roving and CGCODE-coverage move_to_plantilla branches), and '
  'coverage_slot_id IS NOT NULL rows, matching Task 5''s flow classification. '
  'Rows with NEW.vacancy_id IS NULL (still the majority of stationary inserts, per '
  'ohm#c7a9f2d1''s live data finding) are also skipped — this guard only fires once a '
  'vacancy_id is actually populated on the insert.';

DROP TRIGGER IF EXISTS trg_enforce_requirement_on_assignment ON public.plantilla;
CREATE TRIGGER trg_enforce_requirement_on_assignment
BEFORE INSERT ON public.plantilla
FOR EACH ROW
EXECUTE FUNCTION public.enforce_requirement_on_assignment();

-- ============================================================
-- §6  Validation queries (run manually after applying)
-- ============================================================
--
-- V1 — resolver parity: confirm the resolver reproduces the exact rows the
--   old inline heuristic used to match (rollback after):
--   BEGIN;
--     SELECT public.resolve_requirement_for_separation(NULL, store_id, account_id)
--       FROM public.plantilla WHERE id = '<some active stationary plantilla id>';
--   ROLLBACK;
--
-- V2 — detect_requirement_drift returns the same rows as the raw view query:
--   SELECT * FROM public.detect_requirement_drift();
--   SELECT * FROM public.vw_requirement_reconciliation WHERE delta != 0;
--   -- Expected: identical row sets
--
-- V3 — guardrail does not block pool/roving/coverage (rollback after):
--   BEGIN;
--     INSERT INTO public.plantilla (..., is_pool_employee, vacancy_id, vacancy_requirement_id, ...)
--       VALUES (..., true, '<vacancy with requirements>', NULL, ...);
--     -- expect: succeeds (pool exclusion)
--   ROLLBACK;
--
-- V4 — guardrail blocks stationary insert with a requirement-bearing vacancy_id
--   and no vacancy_requirement_id (rollback after):
--   BEGIN;
--     INSERT INTO public.plantilla (..., vacancy_id, vacancy_requirement_id, ...)
--       VALUES (..., '<vacancy with requirements>', NULL, ...);
--     -- expect exception: vacancy_requirement_id is required for this vacancy
--   ROLLBACK;
