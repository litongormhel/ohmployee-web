-- ============================================================
-- OHM2026_0078: On-Leave / Floating Employment Status + Derived E.Type
-- Migration: 20261007000001_on_leave_floating_status.sql
-- ============================================================
-- Sections:
--   §1  Expand plantilla_status_check — add 'On Leave'
--   §2  Update uq_plantilla_employee_no_active — include 'On Leave'
--   §3  Update v_plantilla_safe — add derived_employment_type column
--   §4  Patch get_plantilla_employees — On Leave in active filter + derived type
--   §5  New RPC set_plantilla_on_leave
--   §6  New RPC set_plantilla_floating
--   §7  Store deactivation trigger — release slots when store goes inactive
-- ============================================================


-- ============================================================
-- §1  Expand plantilla_status_check to include 'On Leave'
-- ============================================================
-- The 20260526114431 remote schema removed 'On Leave' from the constraint.
-- Re-add it so the set_plantilla_on_leave RPC can write this status.

ALTER TABLE public.plantilla
  DROP CONSTRAINT IF EXISTS plantilla_status_check;

ALTER TABLE public.plantilla
  ADD CONSTRAINT plantilla_status_check
  CHECK (status = ANY (ARRAY[
    'Active'::text,
    'Inactive'::text,
    'Pending Deactivation'::text,
    'Rejected Deactivation'::text,
    'Deactivated'::text,
    'On Leave'::text
  ])) NOT VALID;


-- ============================================================
-- §2  Update uq_plantilla_employee_no_active unique index
-- ============================================================
-- Include 'On Leave' alongside 'Active' and 'Pending Deactivation'
-- so an On-Leave employee still blocks a duplicate employee_no insert.

DROP INDEX IF EXISTS public.uq_plantilla_employee_no_active;

CREATE UNIQUE INDEX uq_plantilla_employee_no_active
  ON public.plantilla (employee_no)
  WHERE is_deleted = false
    AND status = ANY (ARRAY[
      'Active'::text,
      'Pending Deactivation'::text,
      'On Leave'::text
    ]);


-- ============================================================
-- §3  Update v_plantilla_safe — add derived_employment_type
-- ============================================================
-- derived_employment_type is computed from active plantilla_store_links count:
--   >1 active links → 'Roving'
--   ≤1 active links → COALESCE(stored deployment_type, 'Stationary')
--
-- This replaces the stored deployment_type for display purposes and ensures
-- an employee with 2+ active assigned stores is shown as Roving even if the
-- stored field is stale.

CREATE OR REPLACE VIEW public.v_plantilla_safe AS
SELECT
  p.id,
  p.employee_name,
  p.employee_no,
  p.account,
  p.account_id,
  p.chain_id,
  p.store_id,
  p.province_id,
  p."position",
  p.position_id,
  p.status,
  p.separation_status,
  p.date_of_separation,
  p.over_headcount,
  p.deactivated_at,
  p.deactivated_visible_until,
  p.deactivation_reason,
  p.deletion_requested_at,
  p.deletion_reason,
  p.sss_no,
  p.philhealth_no,
  p.pagibig_no,
  CASE
    WHEN p.atm_no IS NULL THEN NULL::text
    WHEN length(p.atm_no) <= 4 THEN '****'::text
    ELSE repeat('*', length(p.atm_no) - 4) || right(p.atm_no, 4)
  END AS atm_no_masked,
  p.civil_status,
  p.date_of_birth,
  CASE
    WHEN p.date_of_birth IS NOT NULL
      THEN EXTRACT(year FROM age(p.date_of_birth::timestamptz))::integer
    ELSE NULL::integer
  END AS age,
  CASE
    WHEN p.date_hired IS NOT NULL
      THEN (EXTRACT(epoch FROM age(now(), p.date_hired::timestamptz))
           / (60 * 60 * 24 * 30.4375))::integer
    ELSE NULL::integer
  END AS tenure_months,
  p.last_mika_synced_at,
  p.last_mika_synced_by,
  p.store_name,
  p.area,
  p.rate,
  p.schedule,
  p.deployment_type,
  p.has_penalty,
  p.date_hired,
  p.coordinator,
  p.hrco_name,
  p.vcode,
  p.hr_emploc_id,
  p.roving_assignment_id,
  p.created_at,
  p.updated_at,
  p.source_headcount_request_id,
  -- Computed: roving store count and store-link snapshot
  COALESCE((
    SELECT COUNT(*)
      FROM public.plantilla_store_links psl
     WHERE psl.plantilla_id = p.id
       AND psl.deleted_at IS NULL
       AND psl.status = 'Active'
  ), 0)::integer AS roving_store_count,
  (
    SELECT jsonb_agg(
      jsonb_build_object(
        'vcode',     psl.vcode,
        'store_name',psl.store_name,
        'account',   psl.account,
        'status',    psl.status,
        'linked_at', psl.linked_at
      ) ORDER BY psl.vcode
    )
      FROM public.plantilla_store_links psl
     WHERE psl.plantilla_id = p.id
       AND psl.deleted_at IS NULL
  ) AS roving_stores,
  p.inactive_visible_until,
  s.area_city                           AS area_city,
  COALESCE(s.area_province, s.province) AS area_province,
  CASE
    WHEN (
      SELECT COUNT(*)
        FROM public.plantilla_store_links psl
       WHERE psl.plantilla_id = p.id
         AND psl.deleted_at IS NULL
         AND psl.status = 'Active'
    ) > 1
    THEN 'Roving'
    ELSE COALESCE(p.deployment_type, 'Stationary')
  END AS derived_employment_type
FROM public.plantilla p
LEFT JOIN public.stores s ON s.id = p.store_id
WHERE
  COALESCE(p.is_deleted, false) = false
  AND (p.is_archived = false)
  AND (p.deactivated_visible_until IS NULL OR p.deactivated_visible_until > NOW())
  AND (p.inactive_visible_until IS NULL OR p.inactive_visible_until > NOW());

COMMENT ON VIEW public.v_plantilla_safe IS
  'Safe read-only view over plantilla. Excludes deleted, archived, expired deactivated-visibility, '
  'and expired inactive-visibility rows. LEFT JOIN stores exposes area_city and area_province. '
  'Adds append-only derived_employment_type from active store link count.';


-- ============================================================
-- §4  Patch get_plantilla_employees
-- ============================================================
-- Changes:
--   1. Add derived_employment_type to RETURNS TABLE after existing columns.
--   2. Return derived_employment_type in SELECT (CASE from store link count).
--   3. Include 'On Leave' in the 'active' status filter bucket.
--   4. Allow can_resign / can_endo / can_separate / can_reassign for On Leave.

DROP FUNCTION IF EXISTS public.get_plantilla_employees(uuid, text);

CREATE OR REPLACE FUNCTION public.get_plantilla_employees(
  p_store_id      uuid,
  p_status_filter text DEFAULT 'all'::text
)
RETURNS TABLE(
  id                        uuid,
  employee_name             text,
  employee_no               text,
  emploc_no                 text,
  vcode                     text,
  position_name             text,
  deployment_type           text,
  account                   text,
  store_name                text,
  status                    text,
  separation_status         text,
  inactive_at               timestamp with time zone,
  for_deactivation_at       timestamp with time zone,
  deactivated_at            timestamp with time zone,
  deactivated_visible_until timestamp with time zone,
  sla_status                text,
  sla_due_date              date,
  can_reassign_store        boolean,
  can_resign                boolean,
  can_endo                  boolean,
  can_separate              boolean,
  can_request_deactivation  boolean,
  can_complete_deactivation boolean,
  can_view_benefits         boolean,
  can_sync_mika             boolean,
  can_reveal_benefits       boolean,
  area_city                 text,
  area_province             text,
  derived_employment_type   text
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_role          text    := public.get_my_role();
  v_is_ops        boolean := public.i_am_ops();
  v_is_full       boolean := public.i_have_full_access();
  v_is_backoffice boolean := v_role IN ('Back Office', 'Backoffice');
BEGIN
  RETURN QUERY
  SELECT
    p.id,
    p.employee_name,
    p.employee_no,
    p.emploc_no,
    p.vcode,
    p.position::text,
    p.deployment_type,
    p.account,
    p.store_name,
    p.status,
    p.separation_status,
    p.inactive_at,
    p.for_deactivation_at,
    p.deactivated_at,
    p.deactivated_visible_until,
    -- SLA status
    CASE
      WHEN p.status = 'Inactive' AND p.inactive_at < NOW() - INTERVAL '3 days'
        THEN 'breach_inactive_no_request'
      WHEN p.status = 'For Deactivation' AND p.for_deactivation_at < NOW() - INTERVAL '3 days'
        THEN 'breach_deactivation_overdue'
      WHEN p.status IN ('Inactive', 'For Deactivation') THEN 'within_sla'
      ELSE NULL
    END,
    -- SLA due date
    CASE
      WHEN p.status = 'Inactive'         THEN (p.inactive_at + INTERVAL '3 days')::date
      WHEN p.status = 'For Deactivation' THEN (p.for_deactivation_at + INTERVAL '3 days')::date
      ELSE NULL
    END,
    -- can_reassign_store: Active and On Leave employees
    (v_is_full OR (v_is_ops AND p.status IN ('Active', 'On Leave'))),
    -- can_resign
    (v_is_full OR (v_is_ops AND p.status IN ('Active', 'On Leave'))),
    -- can_endo
    (v_is_full OR (v_is_ops AND p.status IN ('Active', 'On Leave'))),
    -- can_separate
    (v_is_full OR (v_is_ops AND p.status IN ('Active', 'On Leave'))),
    -- can_request_deactivation: Inactive employees
    (v_is_full OR (v_is_ops AND p.status = 'Inactive')),
    -- can_complete_deactivation: Backoffice for For Deactivation
    ((v_is_backoffice OR v_is_full) AND p.status = 'For Deactivation'),
    true,
    (v_is_full OR v_is_ops OR v_is_backoffice),
    (v_is_full OR v_is_ops OR v_is_backoffice),
    s.area_city::text,
    COALESCE(s.area_province, s.province)::text,
    CASE
      WHEN (
        SELECT COUNT(*)
          FROM public.plantilla_store_links psl
         WHERE psl.plantilla_id = p.id
           AND psl.deleted_at IS NULL
           AND psl.status = 'Active'
      ) > 1
      THEN 'Roving'
      ELSE COALESCE(p.deployment_type, 'Stationary')
    END AS derived_employment_type
  FROM public.plantilla p
  LEFT JOIN public.stores s ON s.id = p.store_id
  WHERE p.store_id = p_store_id
    AND (
      v_is_full
      OR p.account = ANY (public.get_my_allowed_accounts())
    )
    AND (
      CASE LOWER(p_status_filter)
        WHEN 'all'              THEN p.status IN ('Active', 'On Leave', 'Inactive', 'For Deactivation', 'Deactivated')
                                     AND (p.status <> 'Deactivated'
                                          OR p.deactivated_visible_until > NOW())
        WHEN 'active'           THEN p.status IN ('Active', 'On Leave')
        WHEN 'inactive'         THEN p.status IN ('Inactive', 'Floating')
                                     AND p.source_headcount_request_id IS NULL
        WHEN 'for_deactivation' THEN p.status = 'For Deactivation'
        WHEN 'deactivated'      THEN p.status = 'Deactivated'
                                     AND p.deactivated_visible_until > NOW()
        ELSE true
      END
    )
  ORDER BY
    CASE p.status
      WHEN 'Active'             THEN 1
      WHEN 'On Leave'           THEN 2
      WHEN 'Inactive'           THEN 3
      WHEN 'For Deactivation'   THEN 4
      WHEN 'Deactivated'        THEN 5
      ELSE 6
    END,
    p.employee_name;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.get_plantilla_employees(uuid, text) TO authenticated;


-- ============================================================
-- §5  New RPC: set_plantilla_on_leave
-- ============================================================
-- Sets plantilla.status = 'On Leave' for an active employee.
-- On-Leave employees remain visible in the Active tab with a yellow indicator.
-- RBAC: Ops role or full access. Employee must currently be 'Active'.

CREATE OR REPLACE FUNCTION public.set_plantilla_on_leave(
  p_plantilla_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_row    public.plantilla;
  v_actor  uuid := public.get_current_profile_id();
BEGIN
  -- RBAC guard
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

  -- Employee must be Active to go On Leave
  IF v_row.status <> 'Active' THEN
    RAISE EXCEPTION 'employee is not Active (current status: %)', v_row.status;
  END IF;

  -- Update status
  UPDATE public.plantilla
  SET status     = 'On Leave',
      updated_by = auth.uid(),
      updated_at = NOW()
  WHERE id = p_plantilla_id
  RETURNING * INTO v_row;

  RETURN jsonb_build_object(
    'plantilla_id', v_row.id,
    'status',       v_row.status,
    'employee_no',  v_row.employee_no
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.set_plantilla_on_leave(uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.set_plantilla_on_leave(uuid) FROM anon;


-- ============================================================
-- §6  New RPC: set_plantilla_floating
-- ============================================================
-- Sets plantilla.status = 'Inactive' with separation_status = 'Floating'.
-- Floating employees appear in the Inactive tab. This triggers the normal
-- deactivation request flow (Ops must then call create_deactivation_request).
-- RBAC: Ops role or full access. Employee must currently be 'Active' or 'On Leave'.

CREATE OR REPLACE FUNCTION public.set_plantilla_floating(
  p_plantilla_id uuid,
  p_remarks      text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_row    public.plantilla;
  v_actor  uuid := public.get_current_profile_id();
BEGIN
  -- RBAC guard
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

  -- Employee must be Active or On Leave to go Floating
  IF v_row.status NOT IN ('Active', 'On Leave') THEN
    RAISE EXCEPTION 'employee must be Active or On Leave to set Floating (current status: %)', v_row.status;
  END IF;

  -- Update status to Inactive with Floating separation type
  UPDATE public.plantilla
  SET status            = 'Inactive',
      separation_status = 'Floating',
      inactive_at       = NOW(),
      remarks           = COALESCE(p_remarks, remarks),
      updated_by        = auth.uid(),
      updated_at        = NOW()
  WHERE id = p_plantilla_id
  RETURNING * INTO v_row;

  -- Release the employee's slot (non-blocking — same pattern as other separations)
  PERFORM public.fn_sync_slot_to_open(
    p_plantilla_id => p_plantilla_id,
    p_reason_code  => 'RESIGNED',
    p_performed_by => v_actor,
    p_source_fn    => 'set_plantilla_floating'
  );

  RETURN jsonb_build_object(
    'plantilla_id',      v_row.id,
    'status',            v_row.status,
    'separation_status', v_row.separation_status,
    'employee_no',       v_row.employee_no
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.set_plantilla_floating(uuid, text) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.set_plantilla_floating(uuid, text) FROM anon;


-- ============================================================
-- §7  Store deactivation → slot release trigger
-- ============================================================
-- When stores.is_active changes from true to false, release the
-- plantilla slots for all Active employees deployed at that store.
-- Calls fn_sync_slot_to_open for each affected plantilla row.
-- Non-blocking: errors are logged via RAISE NOTICE, not re-raised.

CREATE OR REPLACE FUNCTION public.fn_trg_store_deactivation_release_slots()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_plantilla RECORD;
  v_actor     uuid;
BEGIN
  -- Only fire when is_active transitions true → false
  IF OLD.is_active IS NOT DISTINCT FROM false THEN
    RETURN NEW;
  END IF;
  IF NEW.is_active <> false THEN
    RETURN NEW;
  END IF;

  -- Resolve actor (system context — service role or trigger auth.uid may be null)
  BEGIN
    v_actor := public.get_current_profile_id();
  EXCEPTION WHEN OTHERS THEN
    v_actor := NULL;
  END;

  -- Release slots for all Active plantilla employees at this store
  FOR v_plantilla IN
    SELECT p.id AS plantilla_id, p.employee_no
      FROM public.plantilla p
     WHERE p.store_id = NEW.id
       AND p.status IN ('Active', 'On Leave')
       AND COALESCE(p.is_deleted, false) = false
  LOOP
    BEGIN
      PERFORM public.fn_sync_slot_to_open(
        p_plantilla_id => v_plantilla.plantilla_id,
        p_reason_code  => 'RESIGNED',
        p_performed_by => v_actor,
        p_source_fn    => 'fn_trg_store_deactivation_release_slots'
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE
        'fn_trg_store_deactivation_release_slots: slot release failed for plantilla_id=% employee_no=% store_id=% err=%',
        v_plantilla.plantilla_id, v_plantilla.employee_no, NEW.id, SQLERRM;
    END;
  END LOOP;

  RETURN NEW;
END;
$function$;

-- Drop existing trigger if any, then create fresh
DROP TRIGGER IF EXISTS trg_store_deactivation_release_slots ON public.stores;

CREATE TRIGGER trg_store_deactivation_release_slots
  AFTER UPDATE OF is_active ON public.stores
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_trg_store_deactivation_release_slots();

COMMENT ON FUNCTION public.fn_trg_store_deactivation_release_slots() IS
  'OHM2026_0078: Releases plantilla slots when a store is deactivated (is_active → false). '
  'Non-blocking — slot release errors do not roll back the store update.';
