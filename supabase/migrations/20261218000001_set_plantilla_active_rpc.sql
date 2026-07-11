-- ============================================================
-- ohm#v6n9k3p8 + ohm#b7q4m8x2: Return On Leave Employee to Active + Close Coverage
-- Migration: 20261218000001_set_plantilla_active_rpc.sql
-- ============================================================
-- New RPC: set_plantilla_active(p_plantilla_id uuid) → jsonb
--
-- Atomically:
--   1. Validates employee is 'On Leave'
--   2. Conditionally closes active/approved workforce_assignments for the store
--      (only when the target employee is the sole On Leave employee at that store)
--   3. Sets plantilla.status = 'Active'
--   4. Returns closure summary
--
-- RBAC: i_have_full_access() OR i_am_ops() (mirrors set_plantilla_on_leave)
-- Safety: SECURITY DEFINER closes coverage without requiring Data Team role
-- No hard deletes. No vacancy created. Store-employee allocation preserved.
--
-- Coverage closure safety rule (ohm#b7q4m8x2):
--   workforce_assignments has NO FK to the on-leave employee — employee_id
--   in that table is the RELIEVER being deployed, not the employee being covered.
--   The only store-based match is assigned_store_id = plantilla.store_id.
--   If multiple On Leave employees exist at the same store, each may have their
--   own coverage assignment and we cannot distinguish them without a schema change.
--   Guard: skip closure when other On Leave employees are present at the same store.
--   The activated employee's coverage card disappears regardless (Flutter-side
--   _loadCoverage gates on _isOnLeaveStatus, which returns false after activation).
--
-- Rollback notes:
--   If rollback needed, drop this function:
--     DROP FUNCTION IF EXISTS public.set_plantilla_active(uuid);
--   No table schema changes were made — rollback is safe.
-- ============================================================

CREATE OR REPLACE FUNCTION public.set_plantilla_active(
  p_plantilla_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_row                  public.plantilla;
  v_actor                uuid := public.get_current_profile_id();
  v_assignments_closed   integer := 0;
  v_assignment_id        uuid;
  v_other_on_leave_count integer := 0;
BEGIN
  -- RBAC guard: same as set_plantilla_on_leave
  IF NOT (public.i_have_full_access() OR public.i_am_ops()) THEN
    RAISE EXCEPTION 'forbidden: Ops role required for employment status update'
      USING ERRCODE = '42501';
  END IF;

  -- Lock and fetch the plantilla row
  SELECT * INTO v_row
    FROM public.plantilla
   WHERE id = p_plantilla_id
     AND COALESCE(is_deleted, false) = false
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'plantilla record not found: %', p_plantilla_id;
  END IF;

  -- Scope guard for non-admin callers
  IF NOT public.i_have_full_access()
     AND NOT (v_row.account = ANY(public.get_my_allowed_accounts())) THEN
    RAISE EXCEPTION 'forbidden: account out of scope' USING ERRCODE = '42501';
  END IF;

  -- Employee must be On Leave to return to Active
  IF v_row.status <> 'On Leave' THEN
    RAISE EXCEPTION 'employee is not On Leave (current status: %)', v_row.status;
  END IF;

  -- Coverage closure safety check.
  --
  -- workforce_assignments.employee_id = the RELIEVER (pool employee being deployed).
  -- There is no FK from workforce_assignments to the on-leave employee being covered.
  -- The only available match key is assigned_store_id = plantilla.store_id.
  --
  -- If multiple On Leave employees exist at the same store, each may have their own
  -- coverage assignment sharing the same assigned_store_id. Closing all of them when
  -- only one employee returns to Active would incorrectly end the remaining employees'
  -- coverage.
  --
  -- Guard: only close assignments when the target employee is the SOLE On Leave
  -- employee at that store. If others are on leave there, skip closure — the other
  -- assignments must remain active for them.
  IF v_row.store_id IS NOT NULL THEN
    SELECT COUNT(*) INTO v_other_on_leave_count
      FROM public.plantilla
     WHERE store_id = v_row.store_id
       AND status = 'On Leave'
       AND id <> p_plantilla_id
       AND COALESCE(is_deleted, false) = false;

    IF v_other_on_leave_count = 0 THEN
      -- Safe: target employee is the only On Leave employee at this store.
      -- Close all active/approved assignments at the store — they must all be covering
      -- for this one employee.
      FOR v_assignment_id IN
        SELECT id
          FROM public.workforce_assignments
         WHERE assigned_store_id = v_row.store_id
           AND status IN ('Active', 'Approved')
      LOOP
        UPDATE public.workforce_assignments
           SET status       = 'Completed',
               completed_at = NOW(),
               notes        = CONCAT_WS(
                                E'\n',
                                NULLIF(notes, ''),
                                'Auto-closed: regular employee returned to Active'
                              ),
               updated_at   = NOW(),
               updated_by   = v_actor::text
         WHERE id = v_assignment_id;

        v_assignments_closed := v_assignments_closed + 1;
      END LOOP;
    END IF;
    -- If v_other_on_leave_count > 0: skip closure.
    -- The activated employee's coverage card disappears in Flutter because
    -- _loadCoverage gates on _isOnLeaveStatus(status), which returns false
    -- after this RPC sets status = 'Active'.
  END IF;

  -- Return plantilla to Active status
  UPDATE public.plantilla
     SET status     = 'Active',
         updated_by = auth.uid(),
         updated_at = NOW()
   WHERE id = p_plantilla_id
  RETURNING * INTO v_row;

  RETURN jsonb_build_object(
    'plantilla_id',       v_row.id,
    'employee_no',        v_row.employee_no,
    'status',             v_row.status,
    'coverage_closed',    v_assignments_closed > 0,
    'assignments_closed', v_assignments_closed,
    'coverage_skipped',   v_other_on_leave_count > 0
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.set_plantilla_active(uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.set_plantilla_active(uuid) FROM anon;

COMMENT ON FUNCTION public.set_plantilla_active(uuid) IS
  'ohm#v6n9k3p8 + ohm#b7q4m8x2: Returns an On Leave plantilla employee to Active status. '
  'Closes active/approved workforce_assignments at the store ONLY when the target employee '
  'is the sole On Leave employee there (guards against closing unrelated coverage when '
  'multiple employees are on leave at the same store). '
  'Coverage card disappears in Flutter regardless (status-gated). '
  'RBAC: Ops or full access. No hard deletes. No vacancy created.';
