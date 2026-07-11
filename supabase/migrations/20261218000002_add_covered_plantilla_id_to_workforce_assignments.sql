-- ============================================================
-- ohm#k3p8w6z1: Add covered_plantilla_id for Precise Coverage Closure
-- Migration: 20261218000002_add_covered_plantilla_id_to_workforce_assignments.sql
-- ============================================================
-- Sections:
--   §1  Add covered_plantilla_id to workforce_assignment_requests
--   §2  Add covered_plantilla_id to workforce_assignments
--   §3  Index on workforce_assignments.covered_plantilla_id
--   §4  Update v_workforce_store_temporary_coverage view
--   §5  Update request_reliever_coverage RPC (auto-detect covered employee)
--   §6  Update approve_reliever_coverage_request RPC (propagate covered_plantilla_id)
--   §7  Replace set_plantilla_active RPC (precise primary + guarded legacy fallback)
--   §8  Backfill existing unambiguous rows
--
-- Rollback notes:
--   §1-§2 columns are nullable — dropping them is safe:
--     ALTER TABLE workforce_assignment_requests DROP COLUMN IF EXISTS covered_plantilla_id;
--     ALTER TABLE workforce_assignments DROP COLUMN IF EXISTS covered_plantilla_id;
--   §5-§7 RPCs: old signatures are replaced in-place via CREATE OR REPLACE.
--     To restore, re-apply migration 20261215000003 and 20261218000001.
-- ============================================================


-- ============================================================
-- §1  Add covered_plantilla_id to workforce_assignment_requests
-- ============================================================
-- Records which On Leave plantilla employee triggered this coverage request.
-- Nullable: legacy requests and requests for stores without a specific on-leave
-- employee (e.g. roving coverage) may not have this set.

ALTER TABLE public.workforce_assignment_requests
  ADD COLUMN IF NOT EXISTS covered_plantilla_id uuid
    REFERENCES public.plantilla(id) ON DELETE SET NULL;

COMMENT ON COLUMN public.workforce_assignment_requests.covered_plantilla_id IS
  'ohm#k3p8w6z1: FK to the on-leave plantilla employee this coverage request is for. '
  'Nullable for legacy rows and roving coverage without a specific covered employee. '
  'Auto-populated by request_reliever_coverage when exactly one On Leave employee exists '
  'at the requested_store_id.';


-- ============================================================
-- §2  Add covered_plantilla_id to workforce_assignments
-- ============================================================
-- Propagated from the request at approval time. The authoritative link for
-- set_plantilla_active coverage closure and coverage card display.

ALTER TABLE public.workforce_assignments
  ADD COLUMN IF NOT EXISTS covered_plantilla_id uuid
    REFERENCES public.plantilla(id) ON DELETE SET NULL;

COMMENT ON COLUMN public.workforce_assignments.covered_plantilla_id IS
  'ohm#k3p8w6z1: FK to the on-leave plantilla employee this assignment covers. '
  'Propagated from workforce_assignment_requests.covered_plantilla_id at approval. '
  'Null for legacy assignments and non-on-leave coverage scenarios. '
  'Used by set_plantilla_active and v_workforce_store_temporary_coverage for precise matching.';


-- ============================================================
-- §3  Index on workforce_assignments.covered_plantilla_id
-- ============================================================
-- Supports the primary predicate in set_plantilla_active and view filters.

CREATE INDEX IF NOT EXISTS idx_wa_covered_plantilla_id
  ON public.workforce_assignments (covered_plantilla_id)
  WHERE covered_plantilla_id IS NOT NULL;


-- ============================================================
-- §4  Update v_workforce_store_temporary_coverage view
-- ============================================================
-- Add covered_plantilla_id to the view so Flutter can filter by it.
-- All other columns and JOINs are preserved exactly.

CREATE OR REPLACE VIEW public.v_workforce_store_temporary_coverage AS
SELECT
  wa.id                  AS assignment_id,
  wa.assigned_store_id   AS store_id,
  wa.assigned_account_id AS account_id,
  wa.assigned_group_id   AS group_id,
  wa.employee_id,
  p.employee_no          AS employee_number,
  p.employee_name,
  wpt.code               AS pool_type_code,
  wpt.name               AS pool_type_name,
  wa.deployment_type,
  wa.priority,
  wa.is_primary,
  wa.start_date,
  wa.end_date,
  wa.status,
  wa.approved_by,
  wa.approved_at,
  a.account_name,
  s.store_name,
  s.store_branch,
  g.group_name,
  wa.covered_plantilla_id       -- new: precise link to the on-leave employee
FROM public.workforce_assignments wa
JOIN  public.plantilla           p   ON (p.id = wa.employee_id AND p.is_deleted = false)
JOIN  public.workforce_pool_types wpt ON wpt.id = wa.pool_type_id
LEFT JOIN public.accounts          a   ON a.id = wa.assigned_account_id
LEFT JOIN public.stores             s   ON s.id = wa.assigned_store_id
LEFT JOIN public.groups             g   ON g.id = wa.assigned_group_id
WHERE wa.status = ANY (ARRAY['Active'::text, 'Approved'::text])
  AND (
    get_my_role_level() = ANY (ARRAY[100, 90, 30])
    OR public.i_have_full_access()
    OR (
      (wa.assigned_account_id::text = ANY (public.get_my_allowed_accounts()))
      AND public.can_view_pool_employee(wa.employee_id)
    )
  );

GRANT SELECT ON public.v_workforce_store_temporary_coverage TO authenticated;
REVOKE ALL  ON public.v_workforce_store_temporary_coverage FROM anon;

COMMENT ON VIEW public.v_workforce_store_temporary_coverage IS
  'ohm#k3p8w6z1: Active/Approved workforce assignments with covered_plantilla_id column added. '
  'employee_id = the reliever/commando. covered_plantilla_id = the on-leave employee being covered.';


-- ============================================================
-- §5  Update request_reliever_coverage RPC
-- ============================================================
-- Adds optional p_covered_plantilla_id (nullable).
-- If not supplied, auto-detects: when exactly one On Leave employee exists
-- at p_requested_store_id, that employee's id is used. If zero or multiple
-- On Leave employees exist, covered_plantilla_id remains null.
-- Backward-compatible: existing callers without the new param work unchanged.

-- Drop old 10-param overload to avoid ambiguity with the new 11-param version.
DROP FUNCTION IF EXISTS public.request_reliever_coverage(uuid, uuid, uuid, uuid, uuid, date, date, text, text, text);

CREATE OR REPLACE FUNCTION public.request_reliever_coverage(
  p_employee_id           uuid,
  p_pool_type_id          uuid,
  p_requested_account_id  uuid    DEFAULT NULL::uuid,
  p_requested_group_id    uuid    DEFAULT NULL::uuid,
  p_requested_store_id    uuid    DEFAULT NULL::uuid,
  p_start_date            date    DEFAULT CURRENT_DATE,
  p_end_date              date    DEFAULT CURRENT_DATE,
  p_priority              text    DEFAULT 'Normal'::text,
  p_reason                text    DEFAULT NULL::text,
  p_requested_position    text    DEFAULT NULL::text,
  p_covered_plantilla_id  uuid    DEFAULT NULL::uuid
)
RETURNS TABLE (
  request_id  uuid,
  employee_id uuid,
  status      text,
  message     text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_actor          uuid := auth.uid();
  v_actor_name     text := public.get_my_full_name();
  v_employee       public.plantilla%rowtype;
  v_request_id     uuid;
  v_covered_id     uuid;
  v_on_leave_count integer;
  v_dup_message    constant text :=
    'A pending coverage request already exists for this reliever.';
BEGIN
  IF NOT (public.i_have_full_access() OR public.i_am_ops()) THEN
    RAISE EXCEPTION 'forbidden: Ops role required to request coverage'
      USING ERRCODE = '42501';
  END IF;

  IF p_employee_id IS NULL OR p_pool_type_id IS NULL THEN
    RAISE EXCEPTION 'employee and pool type are required'
      USING ERRCODE = '22023';
  END IF;

  IF p_requested_account_id IS NULL OR p_requested_store_id IS NULL THEN
    RAISE EXCEPTION 'requested account and store are required'
      USING ERRCODE = '22023';
  END IF;

  IF p_start_date IS NULL OR p_end_date IS NULL OR p_start_date > p_end_date THEN
    RAISE EXCEPTION 'start_date must be on or before end_date'
      USING ERRCODE = '22007';
  END IF;

  IF NOT public.fn_wf_account_in_scope(p_requested_account_id) THEN
    RAISE EXCEPTION 'forbidden: requested account outside user scope'
      USING ERRCODE = '42501';
  END IF;

  -- Serialize concurrent callers on the same reliever.
  SELECT * INTO v_employee
    FROM public.plantilla
   WHERE id = p_employee_id
   FOR UPDATE;

  IF NOT FOUND
     OR COALESCE(v_employee.is_deleted, false)
     OR COALESCE(v_employee.is_pool_employee, false) = false THEN
    RAISE EXCEPTION 'employee is not requestable'
      USING ERRCODE = '22023';
  END IF;

  IF v_employee.deactivated_at IS NOT NULL
     OR v_employee.status IS DISTINCT FROM 'Active' THEN
    RAISE EXCEPTION 'inactive employee cannot be requested for coverage'
      USING ERRCODE = '22023';
  END IF;

  IF EXISTS (
    SELECT 1
      FROM public.workforce_assignment_requests war
     WHERE war.employee_id = p_employee_id
       AND war.status = 'Pending'
  ) THEN
    RAISE EXCEPTION '%', v_dup_message
      USING ERRCODE = '23505';
  END IF;

  -- Resolve covered_plantilla_id.
  -- Caller may pass it explicitly. If not (NULL), auto-detect:
  -- when exactly one On Leave employee is at the requested store, link to them.
  IF p_covered_plantilla_id IS NOT NULL THEN
    v_covered_id := p_covered_plantilla_id;
  ELSIF p_requested_store_id IS NOT NULL THEN
    SELECT COUNT(*) INTO v_on_leave_count
      FROM public.plantilla p
     WHERE p.store_id = p_requested_store_id
       AND p.status = 'On Leave'
       AND COALESCE(p.is_deleted, false) = false;

    IF v_on_leave_count = 1 THEN
      SELECT p.id INTO v_covered_id
        FROM public.plantilla p
       WHERE p.store_id = p_requested_store_id
         AND p.status = 'On Leave'
         AND COALESCE(p.is_deleted, false) = false
       LIMIT 1;
    ELSE
      v_covered_id := NULL; -- zero or ambiguous (2+)
    END IF;
  ELSE
    v_covered_id := NULL;
  END IF;

  BEGIN
    INSERT INTO public.workforce_assignment_requests (
      employee_id,
      pool_type_id,
      requested_account_id,
      requested_group_id,
      requested_store_id,
      requested_position,
      requested_by,
      requested_by_id,
      start_date,
      end_date,
      priority,
      reason,
      covered_plantilla_id,
      status,
      created_at,
      updated_at
    )
    VALUES (
      p_employee_id,
      p_pool_type_id,
      p_requested_account_id,
      p_requested_group_id,
      p_requested_store_id,
      NULLIF(BTRIM(COALESCE(p_requested_position, '')), ''),
      v_actor_name,
      v_actor,
      p_start_date,
      p_end_date,
      COALESCE(NULLIF(BTRIM(p_priority), ''), 'Normal'),
      NULLIF(BTRIM(COALESCE(p_reason, '')), ''),
      v_covered_id,
      'Pending',
      NOW(),
      NOW()
    )
    RETURNING id INTO v_request_id;
  EXCEPTION
    WHEN unique_violation THEN
      RAISE EXCEPTION '%', v_dup_message
        USING ERRCODE = '23505';
  END;

  RETURN QUERY
  SELECT
    v_request_id,
    p_employee_id,
    'Pending'::text,
    'Coverage request submitted. Waiting for Data Team approval.'::text;
END;
$function$;

REVOKE ALL ON FUNCTION public.request_reliever_coverage(uuid, uuid, uuid, uuid, uuid, date, date, text, text, text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.request_reliever_coverage(uuid, uuid, uuid, uuid, uuid, date, date, text, text, text, uuid) TO authenticated;


-- ============================================================
-- §6  Update approve_reliever_coverage_request RPC
-- ============================================================
-- Propagates covered_plantilla_id from the request row into the new assignment.

CREATE OR REPLACE FUNCTION public.approve_reliever_coverage_request(
  p_request_id          uuid,
  p_assigned_employee_id uuid DEFAULT NULL::uuid,
  p_notes               text DEFAULT NULL::text
)
RETURNS TABLE(request_id uuid, assignment_id uuid, status text, message text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_req           RECORD;
  v_final_emp_id  UUID;
  v_new_assign_id UUID;
  v_caller_name   TEXT;
BEGIN
  IF NOT (
    get_my_role_level() = ANY (ARRAY[100, 90, 30])
    OR i_have_full_access()
  ) THEN
    RAISE EXCEPTION 'Access denied: Data Team or above required.';
  END IF;

  SELECT * INTO v_req
  FROM workforce_assignment_requests
  WHERE id = p_request_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Request not found.';
  END IF;
  IF v_req.status <> 'Pending' THEN
    RAISE EXCEPTION 'Only Pending requests can be approved. Current status: %', v_req.status;
  END IF;

  v_final_emp_id := COALESCE(p_assigned_employee_id, v_req.employee_id);

  IF NOT EXISTS (
    SELECT 1 FROM plantilla
    WHERE id = v_final_emp_id
      AND is_deleted = false
      AND deactivated_at IS NULL
      AND plantilla.status = 'Active'
  ) THEN
    RAISE EXCEPTION 'Assigned employee not found or inactive.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM workforce_pool_slots wps
    JOIN plantilla pt ON pt.vcode = wps.vcode
    WHERE pt.id = v_final_emp_id
      AND wps.is_active = true
      AND wps.deleted_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Assigned employee is not enrolled in workforce pool.';
  END IF;

  IF p_assigned_employee_id IS NOT NULL AND p_assigned_employee_id <> v_req.employee_id THEN
    IF NOT EXISTS (
      SELECT 1
      FROM workforce_pool_slots wps
      JOIN plantilla pt ON pt.vcode = wps.vcode
      WHERE pt.id = v_final_emp_id
        AND wps.is_active = true
        AND wps.deleted_at IS NULL
        AND (
          wps.group_id IS NULL
          OR wps.group_id = (
            SELECT wps2.group_id
            FROM workforce_pool_slots wps2
            JOIN plantilla pt2 ON pt2.vcode = wps2.vcode
            WHERE pt2.id = v_req.employee_id
              AND wps2.is_active = true
              AND wps2.deleted_at IS NULL
            LIMIT 1
          )
        )
    ) THEN
      RAISE EXCEPTION 'Override employee is not globally visible or not in the same group as the original request.';
    END IF;
  END IF;

  v_caller_name := get_my_full_name();

  INSERT INTO workforce_assignments (
    employee_id, pool_type_id,
    assigned_group_id, assigned_account_id, assigned_store_id,
    priority, start_date, end_date,
    status, requested_by, approved_by, approved_at,
    notes, covered_plantilla_id,
    created_at, created_by, updated_at, updated_by
  ) VALUES (
    v_final_emp_id, v_req.pool_type_id,
    v_req.requested_group_id, v_req.requested_account_id, v_req.requested_store_id,
    v_req.priority, v_req.start_date, v_req.end_date,
    'Approved', v_req.requested_by, v_caller_name, now(),
    COALESCE(p_notes, v_req.notes),
    v_req.covered_plantilla_id,         -- propagated from the request
    now(), v_caller_name, now(), v_caller_name
  )
  RETURNING id INTO v_new_assign_id;

  UPDATE workforce_assignment_requests
  SET
    status                  = 'Approved',
    converted_assignment_id = v_new_assign_id,
    reviewed_by             = v_caller_name,
    reviewed_at             = now(),
    notes                   = COALESCE(p_notes, notes),
    updated_at              = now()
  WHERE id = p_request_id;

  RETURN QUERY
  SELECT
    p_request_id,
    v_new_assign_id,
    'Approved'::TEXT,
    'Request approved. Workforce assignment created.'::TEXT;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.approve_reliever_coverage_request(uuid, uuid, text) TO authenticated;


-- ============================================================
-- §7  Replace set_plantilla_active RPC
-- ============================================================
-- Primary path: close assignments WHERE covered_plantilla_id = p_plantilla_id.
-- Fallback (legacy null rows): guarded store predicate — only when target employee
-- is the sole On Leave employee at their store.
-- Supersedes the version in migration 20261218000001.

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
  v_actor                uuid    := public.get_current_profile_id();
  v_assignment_id        uuid;
  v_assignments_closed   integer := 0;
  v_other_on_leave_count integer := 0;
  v_coverage_skipped     boolean := false;
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

  -- ── Primary path: precise match via covered_plantilla_id ─────────────────
  -- Close assignments that are explicitly linked to this on-leave employee.
  -- This handles all rows created after migration 20261218000002 was applied.
  FOR v_assignment_id IN
    SELECT id
      FROM public.workforce_assignments
     WHERE covered_plantilla_id = p_plantilla_id
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

  -- ── Fallback path: guarded store predicate for legacy rows ────────────────
  -- Only runs when no assignments were found via covered_plantilla_id.
  -- Targets null-covered_plantilla_id rows only (legacy coverage).
  -- Guard: only close when this is the sole On Leave employee at the store —
  -- cannot safely isolate assignments without the FK when others are on leave.
  IF v_assignments_closed = 0 AND v_row.store_id IS NOT NULL THEN
    SELECT COUNT(*) INTO v_other_on_leave_count
      FROM public.plantilla
     WHERE store_id = v_row.store_id
       AND status = 'On Leave'
       AND id <> p_plantilla_id
       AND COALESCE(is_deleted, false) = false;

    IF v_other_on_leave_count = 0 THEN
      FOR v_assignment_id IN
        SELECT id
          FROM public.workforce_assignments
         WHERE assigned_store_id = v_row.store_id
           AND covered_plantilla_id IS NULL   -- legacy rows only
           AND status IN ('Active', 'Approved')
      LOOP
        UPDATE public.workforce_assignments
           SET status       = 'Completed',
               completed_at = NOW(),
               notes        = CONCAT_WS(
                                E'\n',
                                NULLIF(notes, ''),
                                'Auto-closed (legacy): regular employee returned to Active'
                              ),
               updated_at   = NOW(),
               updated_by   = v_actor::text
         WHERE id = v_assignment_id;

        v_assignments_closed := v_assignments_closed + 1;
      END LOOP;
    ELSE
      v_coverage_skipped := true;
    END IF;
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
    'coverage_skipped',   v_coverage_skipped
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.set_plantilla_active(uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.set_plantilla_active(uuid) FROM anon;

COMMENT ON FUNCTION public.set_plantilla_active(uuid) IS
  'ohm#k3p8w6z1: Returns an On Leave plantilla employee to Active status. '
  'Primary: closes assignments WHERE covered_plantilla_id = p_plantilla_id. '
  'Fallback: guarded store predicate for legacy rows (covered_plantilla_id IS NULL) — '
  'only closes when employee is the sole On Leave employee at their store. '
  'RBAC: Ops or full access. No hard deletes. No vacancy created.';


-- ============================================================
-- §8  Backfill existing unambiguous rows
-- ============================================================
-- Populate covered_plantilla_id for existing requests and assignments where:
--   - It is currently null
--   - The store has EXACTLY one On Leave employee (unambiguous)
-- Skips rows where the store has 0 or 2+ On Leave employees.
-- Safe to run multiple times (idempotent via IS NULL check).
-- Note: backfill uses CURRENT On Leave status. Rows where the employee has
-- already returned to Active (e.g. via the old predicate) will be skipped.

-- Backfill workforce_assignment_requests (Pending or Approved only)
UPDATE public.workforce_assignment_requests war
   SET covered_plantilla_id = sub.plantilla_id
  FROM (
    SELECT
      war2.id AS request_id,
      (
        SELECT p.id
          FROM public.plantilla p
         WHERE p.store_id = war2.requested_store_id
           AND p.status   = 'On Leave'
           AND COALESCE(p.is_deleted, false) = false
         LIMIT 1
      ) AS plantilla_id
    FROM public.workforce_assignment_requests war2
   WHERE war2.covered_plantilla_id IS NULL
     AND war2.status IN ('Pending', 'Approved')
     AND war2.requested_store_id IS NOT NULL
     AND (
       SELECT COUNT(*)
         FROM public.plantilla p
        WHERE p.store_id = war2.requested_store_id
          AND p.status   = 'On Leave'
          AND COALESCE(p.is_deleted, false) = false
     ) = 1
  ) sub
 WHERE war.id = sub.request_id
   AND sub.plantilla_id IS NOT NULL;

-- Backfill workforce_assignments (Active or Approved only)
UPDATE public.workforce_assignments wa
   SET covered_plantilla_id = sub.plantilla_id
  FROM (
    SELECT
      wa2.id AS assignment_id,
      (
        SELECT p.id
          FROM public.plantilla p
         WHERE p.store_id = wa2.assigned_store_id
           AND p.status   = 'On Leave'
           AND COALESCE(p.is_deleted, false) = false
         LIMIT 1
      ) AS plantilla_id
    FROM public.workforce_assignments wa2
   WHERE wa2.covered_plantilla_id IS NULL
     AND wa2.status IN ('Active', 'Approved')
     AND wa2.assigned_store_id IS NOT NULL
     AND (
       SELECT COUNT(*)
         FROM public.plantilla p
        WHERE p.store_id = wa2.assigned_store_id
          AND p.status   = 'On Leave'
          AND COALESCE(p.is_deleted, false) = false
     ) = 1
  ) sub
 WHERE wa.id = sub.assignment_id
   AND sub.plantilla_id IS NOT NULL;
