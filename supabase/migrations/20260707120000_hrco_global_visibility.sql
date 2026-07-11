-- Migration: 20260707120000_hrco_global_visibility
-- Created: 2026-07-07
-- Prompt: ohm#7gk2d9xq — Implement HRCO Global Visibility (User-Level Access Control)
-- Purpose: Adds a per-user "global visibility" override for the HRCO role so a
--   Data Team admin can grant a specific HRCO account visibility into every
--   Active/For Deactivation/On Leave employee within their allowed accounts,
--   bypassing the per-employee assignment narrowing introduced in
--   20260707100000_hrco_scope_isolation_plantilla.sql. Maps the ohm#7gk2d9xq
--   prompt's generic "users.global_visibility" ask onto this repo's actual
--   architecture: users_profile (not a bare "users" table) and the existing
--   plantilla_hrco_assignments / plantilla_read_scoped mechanism (not a new
--   "employee_assignments" table).
--
-- Scope: HRCO role visibility only. Every other RLS branch on plantilla is
--   preserved byte-for-byte. No changes to Vacancy / HR Emploc / Coverage.
--   Account-scoping invariant preserved: global visibility still filters by
--   get_my_allowed_accounts(); it never crosses account_id boundaries.
--
-- Smoke Tests (run after apply, capture real output before COMPLETE):
-- S1 (Scoped, unchanged): as HRCO user with hrco_global_visibility=false and
--     5 active plantilla_hrco_assignments -> SELECT count(*) FROM plantilla
--     returns 5.
-- S2 (Global): SELECT set_hrco_global_visibility(<hrco_profile_id>, true) as
--     Data Team/SA; as that HRCO user -> SELECT count(*) FROM plantilla
--     returns every Active/For Deactivation/On Leave row for their allowed
--     accounts (e.g. 1300), NOT rows from a different account.
-- S3 (Cross-account protection): as a global-visibility HRCO scoped only to
--     Account A -> SELECT count(*) FROM plantilla WHERE account_id = <Account B>
--     returns 0.

BEGIN;

-- ── Column ───────────────────────────────────────────────────────────────────
ALTER TABLE public.users_profile
  ADD COLUMN IF NOT EXISTS hrco_global_visibility boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.users_profile.hrco_global_visibility IS
  'ohm#7gk2d9xq: HRCO-only override. When true, bypasses plantilla_hrco_assignments '
  'narrowing and grants the HRCO visibility into all employees within their allowed '
  'accounts (still account-scoped via get_my_allowed_accounts()). No effect for any '
  'other role.';

-- ── Helper: live per-request lookup, no relogin required ────────────────────
CREATE OR REPLACE FUNCTION public.i_have_hrco_global_visibility()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $$
  SELECT COALESCE(up.hrco_global_visibility, false)
    FROM public.users_profile up
   WHERE up.auth_user_id = auth.uid();
$$;

-- ── RLS: plantilla_read_scoped — HRCO branch gains a global-visibility
--   bypass; every other branch (full access, non-HRCO scoped, pool-employee)
--   is preserved byte-for-byte from 20260707100000. ──────────────────────────
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
      AND (
        (
          public.i_have_hrco_global_visibility()
          AND account = ANY (get_my_allowed_accounts())
        )
        OR EXISTS (
          SELECT 1 FROM public.plantilla_hrco_assignments pha
           WHERE pha.plantilla_id = plantilla.id
             AND pha.hrco_user_id = auth.uid()
             AND pha.is_active
        )
      )
    )
  )
  AND (COALESCE(is_deleted, false) = false)
  AND ((deactivated_visible_until IS NULL) OR (deactivated_visible_until > now()))
);

-- ── RPC: set_hrco_global_visibility (Data Team + Super Admin only) ──────────
CREATE OR REPLACE FUNCTION public.set_hrco_global_visibility(
  p_profile_id uuid,
  p_enabled boolean
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $$
DECLARE
  v_target_role text;
  v_old_value   boolean;
BEGIN
  IF NOT (public.i_am_data_team() OR public.i_have_full_access()) THEN
    RAISE EXCEPTION 'forbidden: Encoder, Head Admin, or Super Admin required' USING ERRCODE = '42501';
  END IF;

  SELECT r.role_name, up.hrco_global_visibility
    INTO v_target_role, v_old_value
    FROM public.users_profile up
    JOIN public.roles r ON r.id = up.role_id
   WHERE up.id = p_profile_id;

  IF v_target_role IS NULL THEN
    RAISE EXCEPTION 'user profile not found: %', p_profile_id USING ERRCODE = 'P0002';
  END IF;

  IF v_target_role <> 'HRCO' THEN
    RAISE EXCEPTION 'hrco_global_visibility only applies to the HRCO role' USING ERRCODE = '22023';
  END IF;

  UPDATE public.users_profile
     SET hrco_global_visibility = p_enabled,
         updated_at = now()
   WHERE id = p_profile_id;

  INSERT INTO public.audit_logs (actor_id, module, action, record_id, old_data, new_data)
  VALUES (
    auth.uid(),
    'User Management',
    'UPDATE_USER_ROLE'::audit_action,
    p_profile_id,
    jsonb_build_object('hrco_global_visibility', v_old_value),
    jsonb_build_object('hrco_global_visibility', p_enabled)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.set_hrco_global_visibility(uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_hrco_global_visibility(uuid, boolean) TO authenticated;

COMMIT;
