-- Migration: 20260707100000_hrco_scope_isolation_plantilla
-- Created: 2026-07-07
-- Prompt: ohm#k8d2x7qf (implements approved ADR addition in
--   .ai/architecture_locks/adr_001_coverage_architecture_v2.md — "HRCO Employee-Level
--   Scope Isolation (Plantilla)"; design ref: docs/architecture/hrco_scope_isolation_design_draft.md)
-- Purpose: Close a Plantilla RLS scope leak where any HRCO on an account could see
--   every employee in that account regardless of who actually handles them. Introduces
--   a new employee-level assignment table (modeled on employee_store_allocations'
--   active/history pattern), narrows plantilla_read_scoped for the HRCO role only, and
--   adds the RPCs needed to assign/reassign/search/count. Backfill: Option A (clean
--   start) — no data migration; all existing employees begin unassigned.
--
-- Scope: Plantilla only. Vacancy/HR Emploc RLS untouched. plantilla_insert_scoped /
--   plantilla_update_scoped untouched (write narrowing enforced at RPC layer only).
--
-- Smoke Tests (run after apply, capture real output before COMPLETE):
-- S1: BEGIN; SELECT assign_hrco_to_plantilla(<plantilla_id>, <hrco_auth_uid>);
--     SELECT assign_hrco_to_plantilla(<same plantilla_id>, <other_hrco_auth_uid>);
--     SELECT plantilla_id, hrco_user_id, is_active, effective_end FROM plantilla_hrco_assignments
--       WHERE plantilla_id = <plantilla_id> ORDER BY created_at; ROLLBACK;
--     -- expect: first row is_active=false w/ effective_end set, second row is_active=true
-- S2: attempt two concurrent active rows for same plantilla_id -> unique violation on
--     uq_hrco_assignment_active_per_plantilla
-- S3: as HRCO test user, SELECT count(*) FROM plantilla; -- only assigned rows returned
-- S4: as Head Admin/Super Admin, SELECT count(*) FROM plantilla; -- unchanged from baseline

BEGIN;

-- ── New table ──────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.plantilla_hrco_assignments (
  id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  plantilla_id            uuid NOT NULL REFERENCES public.plantilla(id),
  employee_no             text NOT NULL,
  account_id              uuid NOT NULL,
  hrco_user_id            uuid NOT NULL,              -- auth.users.id of the assigned HRCO
  hrco_email_snapshot     text NOT NULL,               -- point-in-time snapshot, survives email changes
  hrco_name_snapshot      text,
  is_active               boolean NOT NULL DEFAULT true,
  effective_start         timestamptz NOT NULL DEFAULT now(),
  effective_end           timestamptz,                 -- NULL = currently active
  assigned_by             uuid NOT NULL,               -- profile id of Encoder/HA/SA who made the change
  assignment_source       text NOT NULL DEFAULT 'manual' CHECK (assignment_source IN ('manual', 'csv_import')),
  source_import_batch_id  uuid REFERENCES public.plantilla_import_batches(id),
  created_at              timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.plantilla_hrco_assignments ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON public.plantilla_hrco_assignments TO authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.plantilla_hrco_assignments FROM authenticated, anon;

-- Exactly one active assignment per employee — the actual data-layer enforcement point
CREATE UNIQUE INDEX IF NOT EXISTS uq_hrco_assignment_active_per_plantilla
  ON public.plantilla_hrco_assignments (plantilla_id)
  WHERE is_active;

CREATE INDEX IF NOT EXISTS idx_hrco_assignment_hrco_active
  ON public.plantilla_hrco_assignments (hrco_user_id)
  WHERE is_active;

CREATE INDEX IF NOT EXISTS idx_hrco_assignment_plantilla
  ON public.plantilla_hrco_assignments (plantilla_id);

-- ── Helper functions ─────────────────────────────────────────────────────────

-- Data Team helper — Encoder + Head Admin + Super Admin (narrower than i_have_full_access())
CREATE OR REPLACE FUNCTION public.i_am_data_team()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $$
  SELECT public.get_effective_role() IN ('Encoder', 'Head Admin', 'Super Admin');
$$;

-- Exact-role check, gates the RLS narrowing branch
CREATE OR REPLACE FUNCTION public.i_am_hrco_only()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $$
  SELECT public.get_effective_role() = 'HRCO';
$$;

-- Shared validation: is this candidate user an active HRCO on this account's roster?
-- Used by BOTH the CSV import validator and the Assign/Reassign RPC (single code path).
CREATE OR REPLACE FUNCTION public.fn_is_valid_hrco_for_account(p_user_id uuid, p_account_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.users_profile up
    JOIN public.roles r ON r.id = up.role_id
    WHERE up.auth_user_id = p_user_id
      AND COALESCE(up.is_active, true)
      AND r.role_name = 'HRCO'
      AND EXISTS (
        SELECT 1 FROM public.user_scopes us
        WHERE us.user_id = up.id
          AND (
            us.account_id = p_account_id
            OR us.group_id = (SELECT group_id FROM public.accounts WHERE id = p_account_id)
          )
      )
  );
$$;

CREATE OR REPLACE FUNCTION public.fn_can_assign_hrco()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $$
  SELECT public.get_effective_role() IN ('Encoder', 'Head Admin', 'Super Admin');
$$;

-- ── RPC: Assign / Reassign (single code path) ───────────────────────────────
CREATE OR REPLACE FUNCTION public.assign_hrco_to_plantilla(
  p_plantilla_id uuid,
  p_hrco_user_id uuid,
  p_reason text DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $$
DECLARE
  v_account_id  uuid;
  v_employee_no text;
  v_new_id      uuid;
BEGIN
  IF NOT public.fn_can_assign_hrco() THEN
    RAISE EXCEPTION 'forbidden: Encoder, Head Admin, or Super Admin required' USING ERRCODE = '42501';
  END IF;

  SELECT account_id, employee_no INTO v_account_id, v_employee_no
    FROM public.plantilla
   WHERE id = p_plantilla_id AND NOT is_deleted
   FOR UPDATE;

  IF v_account_id IS NULL THEN
    RAISE EXCEPTION 'plantilla_not_found' USING ERRCODE = 'P0002';
  END IF;

  IF NOT public.fn_is_valid_hrco_for_account(p_hrco_user_id, v_account_id) THEN
    RAISE EXCEPTION 'invalid_hrco: not an HRCO on this account roster' USING ERRCODE = '22023';
  END IF;

  -- Deactivate any existing active assignment (no-op if unassigned — this IS the
  -- "unassigned -> assigned" first-assignment case)
  UPDATE public.plantilla_hrco_assignments
     SET is_active = false, effective_end = now()
   WHERE plantilla_id = p_plantilla_id AND is_active;

  INSERT INTO public.plantilla_hrco_assignments (
    plantilla_id, employee_no, account_id, hrco_user_id,
    hrco_email_snapshot, hrco_name_snapshot,
    assigned_by, assignment_source
  )
  SELECT p_plantilla_id, v_employee_no, v_account_id, p_hrco_user_id,
         up.email, up.full_name,
         public.get_current_profile_id(), 'manual'
    FROM public.users_profile up
   WHERE up.auth_user_id = p_hrco_user_id
   RETURNING id INTO v_new_id;

  RETURN v_new_id;
END;
$$;

-- ── RPC: Needs HRCO tab badge count (Data Team only) ────────────────────────
CREATE OR REPLACE FUNCTION public.get_plantilla_unassigned_hrco_count(p_account_id uuid)
RETURNS integer
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $$
  SELECT CASE WHEN public.i_am_data_team() OR public.i_have_full_access() THEN (
    SELECT count(*)::int
      FROM public.plantilla p
     WHERE p.account_id = p_account_id
       AND p.is_deleted = false
       AND p.status IN ('Active', 'For Deactivation', 'On Leave')
       AND NOT EXISTS (
         SELECT 1 FROM public.plantilla_hrco_assignments a
          WHERE a.plantilla_id = p.id AND a.is_active
       )
  ) ELSE 0 END;
$$;

-- ── RPC: Assign/Reassign search sheet — scoped candidate list ───────────────
CREATE OR REPLACE FUNCTION public.search_account_hrcos(p_account_id uuid, p_query text DEFAULT NULL)
RETURNS TABLE(user_id uuid, full_name text, email text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $$
  SELECT up.auth_user_id, up.full_name, up.email
    FROM public.users_profile up
    JOIN public.roles r ON r.id = up.role_id
   WHERE public.fn_can_assign_hrco()
     AND r.role_name = 'HRCO'
     AND COALESCE(up.is_active, true)
     AND EXISTS (
       SELECT 1 FROM public.user_scopes us
        WHERE us.user_id = up.id
          AND (
            us.account_id = p_account_id
            OR us.group_id = (SELECT group_id FROM public.accounts WHERE id = p_account_id)
          )
     )
     AND (
       p_query IS NULL OR trim(p_query) = ''
       OR up.full_name ILIKE '%' || p_query || '%'
       OR up.email ILIKE '%' || p_query || '%'
     )
   ORDER BY up.full_name;
$$;

-- ── RLS: new table ───────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "hrco_assignments_read_scoped" ON public.plantilla_hrco_assignments;
CREATE POLICY "hrco_assignments_read_scoped" ON public.plantilla_hrco_assignments FOR SELECT USING (
  public.i_have_full_access()
  OR public.i_am_data_team()
  OR (public.i_am_hrco_only() AND hrco_user_id = auth.uid())
);
-- No INSERT/UPDATE/DELETE policies — grants revoked entirely; all writes via
-- SECURITY DEFINER RPC (bypasses RLS by design, same as employee_store_allocations).

-- ── RLS: plantilla_read_scoped narrowing (HRCO role only; every other branch
--   is preserved byte-for-byte, including the existing pool-employee branch) ─
DROP POLICY IF EXISTS "plantilla_read_scoped" ON public.plantilla;
CREATE POLICY "plantilla_read_scoped" ON public.plantilla FOR SELECT USING (
  i_can_view_plantilla()
  AND (
    i_have_full_access()
    OR (
      NOT i_am_hrco_only()
      AND (
        account = ANY (get_my_allowed_accounts())
        OR (
          (is_pool_employee = true)
          AND (
            (get_my_role_level() = 20)
            OR (get_my_role_level() = 30)
            OR (get_my_role_level() >= 90)
            OR ((get_my_role_level() >= 40) AND (get_my_role_level() <= 70))
          )
        )
      )
    )
    OR (
      i_am_hrco_only()
      AND EXISTS (
        SELECT 1 FROM public.plantilla_hrco_assignments pha
         WHERE pha.plantilla_id = plantilla.id
           AND pha.hrco_user_id = auth.uid()
           AND pha.is_active
      )
    )
  )
  AND (COALESCE(is_deleted, false) = false)
  AND ((deactivated_visible_until IS NULL) OR (deactivated_visible_until > now()))
);

COMMIT;
