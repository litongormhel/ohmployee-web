-- ============================================================================
-- OHM2026_0071 — Normalize Roving Vacancy Creation HC Flags (follow-up to 0070)
-- ============================================================================
-- ADDITIVE migration. Does NOT modify or drop any existing migration. Does NOT
-- delete vacancy rows, hide satellite stores, touch Import Plantilla / rollback,
-- modify CENCOM UI, or modify the legacy COUNT views. No DROP CASCADE. Existing
-- RLS / RBAC unchanged.
--
-- BACKGROUND (OHM2026_0070):
--   0070 made EXISTING roving groups manpower-aware via affects_required_hc /
--   affects_mfr and shipped two idempotent helpers:
--     fn_apply_roving_vacancy_hc_flags(roving_assignment_id)  — per-group
--     fn_backfill_roving_vacancy_hc_flags()                   — all groups
--   It also documented one limitation: a roving footprint that has just been
--   created / re-materialized keeps affects_required_hc = true on every store
--   row until something re-runs the helper, so a 5-store roving footprint can
--   momentarily inflate Open HC to 5 instead of 1.
--
-- WHY A TRIGGER (creation-path investigation result):
--   There is NO single "create a 5-row roving footprint" RPC. A roving footprint
--   is assembled / re-materialized incrementally, and every such path writes a
--   roving store-link row carrying roving_assignment_id:
--     • confirm_applicant_onboard  → INSERTs plantilla_store_links (+ creates the
--                                     roving_assignment) as each store is onboarded
--     • merge_as_roving_emploc     → re-parents hr_emploc_store_links
--     • resign_roving_employee     → reopens the satellite vacancies and flips the
--                                     plantilla_store_links to 'Resigned'
--     • HR Emploc store-link flows → INSERT hr_emploc_store_links during pipeline
--   Patching each giant RPC inline is high-risk transcription churn. Instead we
--   normalize at the one invariant point all of them share: the roving store-link
--   write. An AFTER trigger on the two store-link tables calls the existing 0070
--   helper for the affected group, so exactly one VCODE stays primary
--   (affects_required_hc = true / affects_mfr = true) and the rest become
--   satellites (false). Idempotent, so repeated firings are harmless.
--
-- PRIMARY / SATELLITE STRATEGY (unchanged from 0070):
--   Primary = roving_assignments.primary_vcode, else min(member vcode). Members =
--   distinct vcodes from hr_emploc_store_links + plantilla_store_links (+ primary).
--   Pool vacancies are never touched. Stationary vacancies are never touched
--   (they have no roving_assignment_id and never reach this trigger).
--
-- EDIT-LOCK SAFETY:
--   The helper UPDATEs public.vacancies, which fires trg_assert_vacancy_edit_allowed.
--   On the deployment path (confirm / resign) the surrounding RPC already mutates
--   vacancies, so there is no NEW lock exposure. To avoid regressing the pipeline
--   path (HR Emploc store-link writes that would otherwise not touch vacancies),
--   the trigger SKIPS normalization while the vacancy module is edit-locked for a
--   non-full-access caller; the periodic backfill or the next unlocked store-link
--   write re-normalizes. No onboarding flow is broken during the lock window.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- §1  Trigger function: normalize a roving group's HC flags from a store-link
-- ----------------------------------------------------------------------------
-- Fires AFTER a roving store-link row is created/updated. Delegates to the 0070
-- helper for the group identified by NEW.roving_assignment_id. SECURITY DEFINER
-- so the helper's vacancy UPDATE runs with the same authority as 0070's backfill.
CREATE OR REPLACE FUNCTION public.fn_trg_normalize_roving_vacancy_hc()
  RETURNS trigger
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.roving_assignment_id IS NOT NULL THEN
    -- Edit-lock safety: don't force a vacancies UPDATE during the freeze window
    -- for a caller that can't override it (would roll back the store-link write).
    IF public.i_have_full_access() OR NOT public.is_vacancy_edit_locked() THEN
      PERFORM public.fn_apply_roving_vacancy_hc_flags(NEW.roving_assignment_id);
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

COMMENT ON FUNCTION public.fn_trg_normalize_roving_vacancy_hc() IS
  'AFTER-trigger glue (OHM2026_0071): on a roving store-link write, calls '
  'fn_apply_roving_vacancy_hc_flags(roving_assignment_id) so a freshly created/'
  're-materialized roving footprint marks one primary VCODE (1 HC) and the rest '
  'as satellites (0 HC). Skips while the vacancy module is edit-locked for a '
  'non-full-access caller. Idempotent.';

REVOKE ALL ON FUNCTION public.fn_trg_normalize_roving_vacancy_hc() FROM PUBLIC, anon;

-- ----------------------------------------------------------------------------
-- §2  Attach the trigger to both roving store-link tables
-- ----------------------------------------------------------------------------
-- plantilla_store_links: deployment-stage footprint (confirm onboard / resign /
-- reassignment). hr_emploc_store_links: pipeline-stage footprint (HR Emploc).
-- WHEN guard keeps the trigger inert for any non-roving row (defensive — both
-- columns are NOT NULL today, but stays correct if that ever changes).
DROP TRIGGER IF EXISTS trg_normalize_roving_hc_on_plantilla_link ON public.plantilla_store_links;
CREATE TRIGGER trg_normalize_roving_hc_on_plantilla_link
  AFTER INSERT OR UPDATE ON public.plantilla_store_links
  FOR EACH ROW
  WHEN (NEW.roving_assignment_id IS NOT NULL)
  EXECUTE FUNCTION public.fn_trg_normalize_roving_vacancy_hc();

DROP TRIGGER IF EXISTS trg_normalize_roving_hc_on_hr_emploc_link ON public.hr_emploc_store_links;
CREATE TRIGGER trg_normalize_roving_hc_on_hr_emploc_link
  AFTER INSERT OR UPDATE ON public.hr_emploc_store_links
  FOR EACH ROW
  WHEN (NEW.roving_assignment_id IS NOT NULL)
  EXECUTE FUNCTION public.fn_trg_normalize_roving_vacancy_hc();

-- ----------------------------------------------------------------------------
-- §3  One-time re-normalization of any footprints created since 0070's backfill
-- ----------------------------------------------------------------------------
-- Idempotent. The vacancy edit-lock trigger would block this UPDATE if the
-- migration happens to run inside the lock window; disable only that named
-- trigger for the backfill, then re-enable (same pattern as 0070 §3).
ALTER TABLE public.vacancies DISABLE TRIGGER trg_assert_vacancy_edit_allowed;

SELECT public.fn_backfill_roving_vacancy_hc_flags();

ALTER TABLE public.vacancies ENABLE TRIGGER trg_assert_vacancy_edit_allowed;

COMMIT;
