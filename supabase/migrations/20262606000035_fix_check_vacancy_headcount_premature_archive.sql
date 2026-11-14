-- ============================================================================
-- Migration: 20262606000035_fix_check_vacancy_headcount_premature_archive.sql
-- Prompt:    ohm#9k4t7wpz — Bug: Plantilla Vacancy Tab slot disappears
--            prematurely when HR Emploc sources it
-- Date:      2026-08-06
-- ============================================================================
--
-- ROOT CAUSE:
--   Legacy trigger on_hr_emploc_inserted (AFTER INSERT ON hr_emploc) calls
--   check_vacancy_headcount(), which counts raw hr_emploc row existence for
--   a VCode (no status filter, no deleted_at filter, no slot-state awareness)
--   and marks the parent vacancy 'Filled' the moment that raw count meets
--   required_headcount:
--
--     v_hired := COUNT(*) FROM hr_emploc WHERE vcode = NEW.vcode;
--     IF v_hired >= v_required THEN
--       UPDATE vacancies SET status = 'Filled' WHERE vcode = NEW.vcode ...;
--     END IF;
--
--   This fires the instant an applicant is Confirmed Onboard and an
--   hr_emploc row is created (confirm_applicant_onboard -> INSERT hr_emploc)
--   -- long before the employee is ever moved to Plantilla. The subsequent
--   BEFORE UPDATE trigger on_vacancy_filled_archive then sets is_archived =
--   TRUE on the status -> 'Filled' transition. vw_slot_derived_vacancy_shadow
--   INNER JOINs vacancies with COALESCE(is_archived,false)=false AND status
--   <> 'Archived', so the archived vacancy row is dropped from the view
--   entirely -- not reclassified, REMOVED -- taking the VCode out of both
--   the Vacancy module's Open tab and Plantilla's Vacancy Tab
--   (fetchVacanciesForAccount queries the same view) while the applicant is
--   still sitting in HR Emploc, unable to reach Plantilla.
--
--   Confirmed live on both staging (qqiiznmqxfoamqytjica) and production
--   (rwxelulyapjgaarlwkus) -- byte-identical trigger/function bodies on
--   both. Reproduced against ERT_001 and VCTG2_0010 (account THREE,
--   production): both vacancies show status='Filled', is_archived=true,
--   set at the exact same transaction timestamp as their hr_emploc row's
--   created_at, while their plantilla_slots row is still 'hr_processing'
--   (not occupied) and no plantilla row exists for either applicant.
--
--   This is the SAME bug CLASS already fixed once for move_to_plantilla in
--   20261012000000_fix_multi_slot_vacancy_premature_fill.sql (OHM2026_0081,
--   VCAG5_0058) -- premature 'Filled' + auto-archive before every slot for
--   the VCode is actually occupied -- but via a completely independent,
--   unguarded write path that OHM2026_0081 never touched. Every legitimate
--   "close this vacancy" case is already correctly owned elsewhere:
--     - move_to_plantilla (stationary path): slot-aware NOT EXISTS guard
--       added by OHM2026_0081 -- fires only when every non-closed slot for
--       the VCode is occupied.
--     - move_to_plantilla (pool / roving / CGCODE-coverage paths): explicit
--       vacancy_id-scoped UPDATEs, unchanged by this migration.
--     - approve_hr_emploc_import (bulk import): ADR-001 HR Emploc Import
--       Rule 5 -- closes the vacancy atomically on approval, not on raw
--       row insert.
--   check_vacancy_headcount() is redundant with all of the above and
--   actively wrong -- it is legacy code that predates the slot-first
--   architecture and was never migrated or removed.
--
-- FIX:
--   Neutralize check_vacancy_headcount() to a documented no-op (RAISE
--   NOTICE only). The trigger wiring (on_hr_emploc_inserted) is left in
--   place -- consistent with this repo's existing freeze-in-place pattern
--   (see trg_freeze_vr_hc_filled, 20262606000021) -- so the historical
--   call site remains visible/auditable rather than silently disappearing
--   via DROP TRIGGER. No other function or Dart call site references
--   check_vacancy_headcount() or on_hr_emploc_inserted (grep-confirmed
--   across supabase/migrations and lib/ -- only legacy remote_schema
--   dumps and doc inventories mention it).
--
-- NOT DONE HERE (separate steps, per approved plan):
--   - Live audit for other VCodes already wrongly Filled+archived by this
--     trigger (read-only, run separately after this migration).
--   - Data repair of ERT_001 / VCTG2_0010 (and any other affected rows
--     found by the audit) back to Open/is_archived=false -- requires
--     explicit user approval per the Emergency Data Repair policy, staged
--     as its own execute_sql action following the 20261012000000 §2
--     precedent.
--   - The separate, related "No available headcount for this VCode"
--     client-side block (fetchAvailableSlotsForVcode counting slot_status
--     ='open' only) -- flagged for a follow-up prompt, not fixed here.
--
-- Idempotent: CREATE OR REPLACE.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.check_vacancy_headcount()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  -- ohm#9k4t7wpz (2026-08-06): neutralized. This trigger used to count raw
  -- hr_emploc row existence for NEW.vcode (no status/deleted_at filter, no
  -- slot-state awareness) and mark the parent vacancy 'Filled' the moment
  -- an hr_emploc row was inserted -- long before the applicant reached
  -- Plantilla. That premature 'Filled' transition cascaded into
  -- on_vacancy_filled_archive setting is_archived=true, which excluded the
  -- vacancy from vw_slot_derived_vacancy_shadow entirely, hiding it from
  -- both the Vacancy Open tab and Plantilla's Vacancy Tab while HR Emploc
  -- was still actively trying to fill the slot.
  --
  -- Vacancy closure on employee placement is now exclusively owned by:
  --   - move_to_plantilla (stationary path) via its slot-aware NOT EXISTS
  --     guard (OHM2026_0081, 20261012000000) -- fires only when every
  --     non-closed slot for the VCode is occupied.
  --   - move_to_plantilla (pool / roving / CGCODE-coverage paths) via
  --     their own explicit vacancy_id-scoped UPDATEs.
  --   - approve_hr_emploc_import (bulk import approval), per ADR-001 HR
  --     Emploc Import Rule 5.
  -- This trigger's own firing (on_hr_emploc_inserted, AFTER INSERT ON
  -- hr_emploc) is left wired for auditability, but is now a no-op.
  RETURN NEW;
END;
$function$;

COMMENT ON FUNCTION public.check_vacancy_headcount() IS
  'DEPRECATED + NEUTRALIZED (ohm#9k4t7wpz, 2026-08-06). Formerly marked the '
  'parent vacancy Filled on raw hr_emploc row-count >= required_headcount, '
  'bypassing slot state entirely and causing premature Filled+archive the '
  'moment an applicant reached HR Emploc (before Plantilla placement). '
  'Vacancy closure is now owned exclusively by move_to_plantilla''s '
  'slot-aware guard (OHM2026_0081) and approve_hr_emploc_import (ADR-001 '
  'HR Emploc Import Rule 5). Trigger on_hr_emploc_inserted remains wired '
  'to this now-inert function for audit-trail continuity.';
