-- Migration: 20260819210000_fix_plantilla_scope_menu_encoder_group_branch.sql
-- Module: Vacancy Import / Plantilla Import (Store Import) group dropdown
-- Prompt: ohm#3wv7n2kx (BUG-01)
--
-- Root cause: get_plantilla_scope_menu() branches by role name. Only
-- i_have_full_access() (SA/HA) and v_role IN ('OM','Operations Manager')
-- return scope_type='group'. Every other role — including Encoder — falls
-- into the "all other roles" branch, which only ever returns
-- scope_type='account', whether the caller's user_scopes row has account_id
-- set directly or only group_id (in which case it derives and returns the
-- accounts under that group). Confirmed live: Encoder users on staging with
-- only group_id set (no account_id) still resolve through the account-
-- derivation path today, so Import Vacancy / Import Plantilla show Account
-- names instead of Group names for Encoder.
--
-- Fix (per Ohm's decision, ohm#3wv7n2kx): group_id presence on a user_scopes
-- row is the authoritative signal for group scope for Encoder, regardless of
-- whether that Encoder also has separate account_id-scoped rows elsewhere.
-- Add a new Encoder branch, structurally identical to the existing OM branch
-- (same query shape, same can_manage/can_view_only tuple — Encoder's Data
-- Team standing is intended to be at or above OM's for this screen), inserted
-- after the OM branch and before the "all other roles" fallback. An Encoder
-- with zero group_id rows (account_id-only scope, if any exist) still falls
-- through unchanged to the existing account-derivation logic below — this is
-- a new branch, not a merge into the OM role-name list, specifically to avoid
-- ever short-circuiting a genuinely account-only Encoder into an empty result.
--
-- All other branches (SA/HA, OM, Recruitment/HR Dept no-access, and the
-- "all other roles" fallback for HRCO/ATL/TL/Viewer/Back Office) are
-- byte-identical to the live function (verified via pg_get_functiondef
-- before writing this file). No schema/RLS/table changes.
--
-- Consumers: vacancy_import_service.dart (Import Vacancy) and
-- store_import_service.dart (Import Plantilla / Store Import) both call
-- get_plantilla_scope_menu() directly and are the only Flutter callers
-- (confirmed via grep) — both screens are fixed by this one function change.

CREATE OR REPLACE FUNCTION public.get_plantilla_scope_menu()
 RETURNS TABLE(scope_type text, scope_id uuid, label text, sort_order integer, can_view boolean, can_manage boolean, can_view_only boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_role          text := public.get_my_role();
  v_profile_id    uuid := public.get_current_profile_id();
  v_acct_count    int;
  v_can_manage    boolean;
  v_can_view_only boolean;
BEGIN
  v_can_manage    := v_role IN ('Super Admin','Head Admin','HRCO','ATL','TL','Operations Manager','OM');
  v_can_view_only := NOT v_can_manage
                     AND v_role NOT IN ('Recruitment','Recruitment Team','HR Dept','HR Department','HR Personnel');

  -- Super Admin / Head Admin
  IF public.i_have_full_access() THEN
    RETURN QUERY
      SELECT 'group'::text, g.id, g.group_name,
             ROW_NUMBER() OVER (ORDER BY g.group_code)::int,
             true, true, false
      FROM public.groups g ORDER BY g.group_code;
    RETURN;
  END IF;

  -- Recruitment / HR Dept: no access
  IF public.i_am_recruitment() OR public.i_am_hr_dept() THEN
    RETURN;
  END IF;

  -- OM / Operations Manager: scoped groups
  IF v_role IN ('OM','Operations Manager') THEN
    RETURN QUERY
      SELECT 'group'::text, g.id, g.group_name,
             ROW_NUMBER() OVER (ORDER BY g.group_code)::int,
             true, true, false
      FROM public.user_scopes us
      JOIN public.groups g ON g.id = us.group_id
      WHERE us.user_id = v_profile_id AND us.group_id IS NOT NULL
      ORDER BY g.group_code;
    RETURN;
  END IF;

  -- Encoder: group_id presence is the authoritative signal for group scope
  -- (ohm#3wv7n2kx / BUG-01). Mirrors the OM branch exactly, including the
  -- can_manage/can_view_only tuple. Falls through to the account branch
  -- below only if this Encoder has no group_id-scoped row at all.
  IF v_role = 'Encoder' AND EXISTS (
    SELECT 1 FROM public.user_scopes us2
    WHERE us2.user_id = v_profile_id AND us2.group_id IS NOT NULL
  ) THEN
    RETURN QUERY
      SELECT 'group'::text, g.id, g.group_name,
             ROW_NUMBER() OVER (ORDER BY g.group_code)::int,
             true, true, false
      FROM public.user_scopes us
      JOIN public.groups g ON g.id = us.group_id
      WHERE us.user_id = v_profile_id AND us.group_id IS NOT NULL
      ORDER BY g.group_code;
    RETURN;
  END IF;

  -- All other roles (Encoder w/ account-only scope, HRCO/ATL/TL scoped, Viewer, Back Office)
  SELECT COUNT(*) INTO v_acct_count
  FROM public.user_scopes
  WHERE user_id = v_profile_id AND account_id IS NOT NULL;

  IF v_acct_count > 0 THEN
    RETURN QUERY
      SELECT 'account'::text, a.id, a.account_name,
             ROW_NUMBER() OVER (ORDER BY a.account_name)::int,
             true, v_can_manage, v_can_view_only
      FROM public.user_scopes us
      JOIN public.accounts a ON a.id = us.account_id
      WHERE us.user_id = v_profile_id AND us.account_id IS NOT NULL AND a.is_active = true
      ORDER BY a.account_name;
  ELSE
    RETURN QUERY
      SELECT 'account'::text, a.id, a.account_name,
             ROW_NUMBER() OVER (ORDER BY a.account_name)::int,
             true, v_can_manage, v_can_view_only
      FROM public.user_scopes us
      JOIN public.accounts a ON a.group_id = us.group_id
      WHERE us.user_id = v_profile_id AND us.group_id IS NOT NULL
        AND us.account_id IS NULL AND a.is_active = true
      ORDER BY a.account_name;
  END IF;
END;
$function$
;
