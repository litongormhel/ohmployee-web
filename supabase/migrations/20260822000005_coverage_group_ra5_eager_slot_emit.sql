-- ============================================================
-- OHM2026_0066 — Coverage Group Phase R-A — RA5 eager slot-emit
-- Migration:  20260822000005_coverage_group_ra5_eager_slot_emit.sql
-- Plan:       docs/architecture/coverage_group_phase_ra_schema_plan.md (§RA5, §6)
-- Depends on: RA4 (coverage_slots), RA1 (coverage_groups).
-- ============================================================
-- Scope: Eager slot-emit. An AFTER INSERT trigger on coverage_groups emits
--   exactly required_headcount coverage_slots, ordinals 1..N, all 'open'.
--   Chosen as a TRIGGER (not folded into a create RPC) so eager-emit holds
--   for ANY insert path — RPC, R-F migration backfill, or manual service-role
--   insert. Reconciliation (Σ slot statuses == required_headcount) then holds
--   the instant a group row exists. Closes the OHM2026_0070 "no group until
--   applicant" gap by construction.
--
--   No lifecycle wiring beyond emit — slots are born 'open'. Transitions are
--   R-B/R-C and are not implemented here.
--
-- Validation (run after apply):
--   V1  -- INSERT a group with required_headcount = N → exactly N 'open' slots,
--          ordinals 1..N; reconciliation holds at creation.
-- ============================================================

CREATE OR REPLACE FUNCTION public.fn_emit_coverage_slots()
  RETURNS trigger
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
AS $emit$
BEGIN
  INSERT INTO public.coverage_slots (coverage_group_id, slot_ordinal, slot_status)
  SELECT NEW.id, gs.ord, 'open'
  FROM generate_series(1, NEW.required_headcount) AS gs(ord);

  RETURN NULL;  -- AFTER trigger; return value ignored
END
$emit$;

COMMENT ON FUNCTION public.fn_emit_coverage_slots() IS
  'Eager slot-emit: on group INSERT, creates required_headcount open slots '
  '(ordinals 1..N). Makes the reconciliation invariant true by construction '
  'for every insert path (RPC, R-F backfill, manual). Plan §RA5/§6.';

DROP TRIGGER IF EXISTS trg_emit_coverage_slots ON public.coverage_groups;
CREATE TRIGGER trg_emit_coverage_slots
  AFTER INSERT
  ON public.coverage_groups
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_emit_coverage_slots();
