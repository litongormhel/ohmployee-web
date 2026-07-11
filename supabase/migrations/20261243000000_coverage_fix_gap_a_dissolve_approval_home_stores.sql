-- ============================================================
-- ohm#6m1c4kp9 — Fix NEW GAP-A: Dissolve Approval Home-Store Update on Pending
-- Migration: 20261243000000_coverage_fix_gap_a_dissolve_approval_home_stores.sql
--
-- Root cause:
--   _showDissolveApprovalFlow() called update_coverage_request_draft() on a
--   request already in `pending` status.  That RPC hard-blocks non-draft rows
--   (ERRCODE 22023), so the approve() call that follows never ran.  Every
--   dissolve approval was silently broken.
--
-- Fix:
--   Extend approve_coverage_request() to accept p_employee_home_stores jsonb
--   DEFAULT NULL.  When provided for a dissolve_coverage_group request, the RPC
--   merges the value into coverage_requests.payload before delegating to
--   _review_coverage_request_phase3, which already has write authority over the
--   row.  For every other request type, or when the param is NULL, behaviour is
--   identical to the previous version.
--
--   update_coverage_request_draft is UNCHANGED — draft-only guard stays.
--
-- Scope:
--   §1 — approve_coverage_request (plpgsql rewrite; adds p_employee_home_stores)
--
-- RLS / RBAC:
--   No new grants.  The existing EXECUTE grant to `authenticated` on
--   approve_coverage_request(uuid, text) must be re-applied to the new
--   (uuid, text, jsonb) overload.  review_coverage_request() calls
--   approve_coverage_request with 2 args → still resolves to this function via
--   DEFAULT NULL on p_employee_home_stores.
--
-- Apply after: 20261242000000_coverage_fix_p0002_normalization_ordering.sql
-- ============================================================

-- §1. approve_coverage_request
-- ---------------------------------------------------------------
-- Previous signature (from 20261023000000):
--   approve_coverage_request(p_coverage_request_id uuid, p_reviewer_remarks text DEFAULT NULL)
-- New signature adds:
--   p_employee_home_stores jsonb DEFAULT NULL
-- ---------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.approve_coverage_request(
  p_coverage_request_id   uuid,
  p_reviewer_remarks      text  DEFAULT NULL,
  p_employee_home_stores  jsonb DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
BEGIN
  -- When the caller supplies employee_home_stores at approval time (dissolve
  -- flow), merge it into the request payload before _review_coverage_request_phase3
  -- reads the row.  The WHERE clause limits the UPDATE to dissolve requests only;
  -- for any other request_type or when p_employee_home_stores IS NULL this is a
  -- no-op.
  IF p_employee_home_stores IS NOT NULL THEN
    UPDATE public.coverage_requests
    SET    payload    = payload || jsonb_build_object('employee_home_stores', p_employee_home_stores),
           updated_at = now()
    WHERE  id           = p_coverage_request_id
      AND  request_type = 'dissolve_coverage_group'::public.request_type
      AND  archived_at  IS NULL;
  END IF;

  -- Delegate to the canonical phase-3/4 review function.
  -- It does its own SELECT FOR UPDATE and will see the merged payload above.
  RETURN public._review_coverage_request_phase3(
    p_coverage_request_id,
    'approved'::public.request_status,
    p_reviewer_remarks,
    NULL
  );
END;
$fn$;

COMMENT ON FUNCTION public.approve_coverage_request(uuid, text, jsonb) IS
  'ohm#6m1c4kp9 GAP-A fix: extends approve_coverage_request to accept '
  'p_employee_home_stores jsonb DEFAULT NULL.  When non-NULL for a '
  'dissolve_coverage_group request, merges employee_home_stores into payload '
  'before delegating to _review_coverage_request_phase3.  All other request '
  'types and NULL callers are unaffected.  HA/SA only (enforced inside '
  '_review_coverage_request_phase3).';

-- Re-apply EXECUTE grant to new overload.
-- The previous (uuid, text) overload from 20261023000000 remains in place;
-- the new (uuid, text, jsonb) overload is a separate pg function signature.
REVOKE EXECUTE ON FUNCTION public.approve_coverage_request(uuid, text, jsonb)
  FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.approve_coverage_request(uuid, text, jsonb)
  TO authenticated;

NOTIFY pgrst, 'reload schema';

-- ── Smoke-test queries (run manually after applying) ──────────────────────────
/*
  -- 1. Confirm both signatures exist and new overload is grantable
  SELECT proname, pronargs, proargnames
  FROM pg_proc
  WHERE proname = 'approve_coverage_request'
    AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public');

  -- 2. Regression test: non-dissolve approval (add_store / remove_store /
  --    convert_roving_to_stationary) — call with p_employee_home_stores NULL
  --    (default).  Expects normal approval, no 22023 error.
  SELECT approve_coverage_request('<pending_non_dissolve_uuid>', NULL, NULL);

  -- 3. Dissolve approval smoke test with employee_home_stores:
  --    a. Create a dissolve_coverage_group request and submit it.
  --    b. Approve it supplying employee_home_stores at approval time.
  SELECT approve_coverage_request(
    '<pending_dissolve_uuid>',
    NULL,
    '{"<plantilla_id>": "<store_id>"}'::jsonb
  );
  --    Expected: {"status":"ok","request_status":"approved", ...}
  --              No 22023 error.
  --    c. Confirm payload contains employee_home_stores.
  SELECT payload -> 'employee_home_stores'
  FROM coverage_requests
  WHERE id = '<pending_dissolve_uuid>';
  --    Expected: {"<plantilla_id>": "<store_id>"}

  -- 4. Dissolve approval smoke test with empty employees:
  SELECT approve_coverage_request('<pending_dissolve_uuid_2>', NULL, '{}'::jsonb);
  SELECT payload -> 'employee_home_stores' FROM coverage_requests WHERE id = '<pending_dissolve_uuid_2>';
  --    Expected: {}

  -- 5. GAP-02 guard still fires if a home store is missing for an active employee:
  --    Approve a dissolve request without providing a home store for an active employee.
  SELECT approve_coverage_request('<pending_dissolve_uuid_3>', NULL, '{}'::jsonb);
  --    Expected: ERRCODE 23514 — 'each active roving employee must have a home store'
  --    (or equivalent message from _execute_approved_coverage_request)
*/
