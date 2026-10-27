-- Migration: 20261027170000_increase_plantilla_list_limit.sql
-- Description: Increase p_limit ceiling in public.list_web_plantilla_employees from 200 to 5000
-- to support full-roster fetching for accounts with 750+ personnel without client-side row truncation.

CREATE OR REPLACE FUNCTION public.list_web_plantilla_employees(
  p_search            text    DEFAULT NULL,
  p_account_id        uuid    DEFAULT NULL,
  p_group_id          uuid    DEFAULT NULL,
  p_store_id          uuid    DEFAULT NULL,
  p_employment_status text    DEFAULT NULL,
  p_deployment        text    DEFAULT NULL,
  p_active_state      text    DEFAULT NULL,
  p_limit             integer DEFAULT 50,
  p_offset            integer DEFAULT 0,
  p_sort_by           text    DEFAULT 'employee_name',
  p_sort_dir          text    DEFAULT 'asc'
)
RETURNS TABLE (
  plantilla_id            uuid,
  employee_name           text,
  employee_no             text,
  account_id              uuid,
  account_name            text,
  group_id                uuid,
  group_name              text,
  store_id                uuid,
  store_name              text,
  province_id             uuid,
  position_title          text,
  status                  text,
  deployment_type         text,
  is_roving               boolean,
  roving_store_count      integer,
  vcode                   text,
  hr_emploc_id            uuid,
  date_hired              date,
  tenure_months           integer,
  age                     integer,
  has_penalty             boolean,
  separation_status       text,
  date_of_separation      date,
  is_active               boolean,
  is_inactive             boolean,
  is_pending_deactivation boolean,
  is_deactivated          boolean,
  onboarding_linked       boolean,
  has_masked_fields       boolean,
  masked_fields           jsonb,
  deactivation_overlay    jsonb,
  row_capabilities        jsonb,
  total_count             bigint
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_auth_uid   uuid := auth.uid();
  v_profile_id uuid;
  v_role_name  text;
  v_role_level integer;
  v_sort_by    text := lower(coalesce(nullif(btrim(p_sort_by), ''), 'employee_name'));
  v_sort_dir   text := lower(coalesce(nullif(btrim(p_sort_dir), ''), 'asc'));
  v_limit      integer := least(greatest(coalesce(p_limit, 50), 1), 5000);
  v_offset     integer := greatest(coalesce(p_offset, 0), 0);
BEGIN
  IF v_auth_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated: web plantilla list requires a valid session'
      USING ERRCODE = '42501';
  END IF;

  SELECT up.id, r.role_name, r.role_level
  INTO v_profile_id, v_role_name, v_role_level
  FROM public.users_profile up
  JOIN public.roles r ON r.id = up.role_id
  WHERE up.auth_user_id = v_auth_uid
    AND up.is_active = TRUE
    AND up.archived_at IS NULL
  ORDER BY up.created_at DESC
  LIMIT 1;

  IF v_profile_id IS NULL OR coalesce(v_role_level, 0) <= 0 THEN
    RAISE EXCEPTION 'forbidden: web plantilla list caller is not allowed'
      USING ERRCODE = '42501';
  END IF;

  IF v_sort_by <> ALL (ARRAY[
    'employee_name', 'employee_no', 'account_name', 'group_name', 'store_name',
    'position_title', 'status', 'date_hired', 'tenure_months', 'created_at'
  ]) THEN
    RAISE EXCEPTION 'invalid sort field: %', p_sort_by USING ERRCODE = '22023';
  END IF;

  IF v_sort_dir <> ALL (ARRAY['asc', 'desc']) THEN
    RAISE EXCEPTION 'invalid sort direction: %', p_sort_dir USING ERRCODE = '22023';
  END IF;

  RETURN QUERY
  WITH scoped AS (
    SELECT
      p.id AS plantilla_id,
      p.employee_name,
      p.employee_no,
      p.account_id,
      a.account_name,
      a.group_id,
      g.group_name,
      p.store_id,
      p.store_name,
      p.province_id,
      p."position" AS position_title,
      p.status,
      p.deployment_type,
      (COALESCE(p.deployment_type, '') = 'Roving' OR p.roving_assignment_id IS NOT NULL) AS is_roving,
      COALESCE(p.roving_store_count, 0) AS roving_store_count,
      p.vcode,
      p.hr_emploc_id,
      p.date_hired,
      p.tenure_months,
      p.age,
      COALESCE(p.has_penalty, FALSE) AS has_penalty,
      p.separation_status,
      p.date_of_separation,
      p.created_at,
      p.deactivated_at,
      (
        p.deactivated_at IS NULL
        AND p.date_of_separation IS NULL
        AND lower(coalesce(nullif(btrim(p.status), ''), 'active')) NOT IN (
          'inactive', 'deactivated', 'resigned', 'separated', 'endo', 'terminated'
        )
        AND lower(coalesce(nullif(btrim(p.separation_status), ''), '')) NOT IN (
          'inactive', 'deactivated', 'resigned', 'separated', 'endo', 'terminated'
        )
      ) AS is_active,
      (
        p.deactivated_at IS NOT NULL
        OR p.date_of_separation IS NOT NULL
        OR lower(coalesce(nullif(btrim(p.status), ''), '')) IN (
          'inactive', 'deactivated', 'resigned', 'separated', 'endo', 'terminated'
        )
        OR lower(coalesce(nullif(btrim(p.separation_status), ''), '')) IN (
          'inactive', 'deactivated', 'resigned', 'separated', 'endo', 'terminated'
        )
      ) AS is_inactive,
      (p.status IN ('Pending Deactivation', 'For Deactivation')) AS is_pending_deactivation,
      (
        p.deactivated_at IS NOT NULL
        OR p.status = 'Deactivated'
        OR lower(coalesce(nullif(btrim(p.separation_status), ''), '')) = 'deactivated'
      ) AS is_deactivated,
      (p.hr_emploc_id IS NOT NULL) AS onboarding_linked,
      (p.sss_no IS NOT NULL OR p.philhealth_no IS NOT NULL
        OR p.pagibig_no IS NOT NULL OR p.atm_no_masked IS NOT NULL) AS has_masked_fields,
      (
        '[]'::jsonb
        || CASE WHEN p.atm_no_masked IS NOT NULL THEN '["atm_no"]'::jsonb ELSE '[]'::jsonb END
        || CASE WHEN p.sss_no IS NOT NULL THEN '["sss_no"]'::jsonb ELSE '[]'::jsonb END
        || CASE WHEN p.philhealth_no IS NOT NULL THEN '["philhealth_no"]'::jsonb ELSE '[]'::jsonb END
        || CASE WHEN p.pagibig_no IS NOT NULL THEN '["pagibig_no"]'::jsonb ELSE '[]'::jsonb END
      ) AS masked_fields,
      jsonb_build_object(
        'is_pending', (p.status IN ('Pending Deactivation', 'For Deactivation')),
        'is_rejected', (p.status = 'Rejected Deactivation'),
        'is_deactivated', (
          p.deactivated_at IS NOT NULL
          OR p.status = 'Deactivated'
          OR lower(coalesce(nullif(btrim(p.separation_status), ''), '')) = 'deactivated'
        ),
        'deactivated_at', p.deactivated_at,
        'deactivation_reason', p.deactivation_reason,
        'display_label', CASE
          WHEN p.status IN ('Pending Deactivation', 'For Deactivation', 'Pending') THEN 'Pending Deactivation'
          WHEN p.status IN ('Rejected Deactivation', 'Rejected') THEN 'Rejected Deactivation'
          WHEN p.deactivated_at IS NOT NULL OR p.status IN ('Deactivated', 'Approved') THEN 'Deactivated'
          ELSE NULL
        END
      ) AS deactivation_overlay,
      jsonb_build_object(
        'can_view_detail', TRUE,
        'can_request_deactivation', (
          p.deactivated_at IS NULL
          AND p.date_of_separation IS NULL
          AND p.status NOT IN ('Pending Deactivation', 'For Deactivation', 'Deactivated')
          AND (public.i_have_full_access() OR public.i_am_ops())
        ),
        'can_transfer', (
          p.deactivated_at IS NULL
          AND p.date_of_separation IS NULL
          AND lower(coalesce(nullif(btrim(p.status), ''), 'active')) NOT IN (
            'inactive', 'deactivated', 'resigned', 'separated', 'endo', 'terminated'
          )
          AND (public.i_have_full_access() OR v_role_name = 'Encoder' OR v_role_level = 30)
        ),
        'can_request_deletion', (
          p.deactivated_at IS NULL
          AND p.date_of_separation IS NULL
          AND lower(coalesce(nullif(btrim(p.status), ''), 'active')) NOT IN (
            'inactive', 'deactivated', 'resigned', 'separated', 'endo', 'terminated'
          )
          AND (public.i_have_full_access() OR public.i_am_ops())
        ),
        'can_update_employment_status', (
          p.deactivated_at IS NULL
          AND p.date_of_separation IS NULL
          AND lower(coalesce(nullif(btrim(p.status), ''), 'active')) NOT IN (
            'inactive', 'deactivated', 'resigned', 'separated', 'endo', 'terminated'
          )
          AND (public.i_have_full_access() OR v_role_name = 'Encoder' OR v_role_level = 30)
        ),
        'can_archive', (COALESCE(v_role_level, 0) >= 100)
      ) AS row_capabilities
    FROM public.v_plantilla_safe p
    LEFT JOIN public.accounts a ON a.id = p.account_id
    LEFT JOIN public.groups g ON g.id = a.group_id
    WHERE
      p.source_headcount_request_id IS NULL
      AND (
        COALESCE(v_role_level, 0) >= 90
        OR p.account = ANY (public.get_my_allowed_accounts())
        OR EXISTS (
          SELECT 1 FROM public.user_scopes us
          WHERE us.user_id = v_profile_id AND us.account_id = p.account_id
        )
        OR EXISTS (
          SELECT 1 FROM public.user_scopes us JOIN public.accounts ac ON ac.id = p.account_id
          WHERE us.user_id = v_profile_id AND us.account_id IS NULL AND us.group_id = ac.group_id
        )
        OR EXISTS (
          SELECT 1 FROM public.users_profile up_fb JOIN public.accounts ac ON ac.id = p.account_id
          WHERE up_fb.id = v_profile_id
            AND NOT EXISTS (
              SELECT 1 FROM public.user_scopes us_any
              WHERE us_any.user_id = v_profile_id
                AND (us_any.group_id IS NOT NULL OR us_any.account_id IS NOT NULL)
            )
            AND (up_fb.account_id = p.account_id OR up_fb.group_id = ac.group_id)
        )
      )
  ),
  filtered AS (
    SELECT s.*
    FROM scoped s
    WHERE
      (p_account_id IS NULL OR s.account_id = p_account_id)
      AND (p_group_id IS NULL OR s.group_id = p_group_id)
      AND (p_store_id IS NULL OR s.store_id = p_store_id)
      AND (p_employment_status IS NULL OR s.status = p_employment_status)
      AND (
        p_deployment IS NULL
        OR (lower(p_deployment) = 'roving' AND s.is_roving)
        OR (lower(p_deployment) = 'stationary' AND NOT s.is_roving)
      )
      AND (
        p_active_state IS NULL
        OR nullif(btrim(p_active_state), '') IS NULL
        OR lower(btrim(p_active_state)) = 'all'
        OR (lower(btrim(p_active_state)) = 'active' AND s.is_active)
        OR (lower(btrim(p_active_state)) = 'inactive' AND s.is_inactive)
      )
      AND (
        p_search IS NULL
        OR nullif(btrim(p_search), '') IS NULL
        OR s.employee_name ILIKE '%' || btrim(p_search) || '%'
        OR s.employee_no ILIKE '%' || btrim(p_search) || '%'
        OR s.vcode ILIKE '%' || btrim(p_search) || '%'
        OR s.position_title ILIKE '%' || btrim(p_search) || '%'
        OR s.store_name ILIKE '%' || btrim(p_search) || '%'
        OR s.account_name ILIKE '%' || btrim(p_search) || '%'
      )
  ),
  counted AS (
    SELECT f.*, count(*) OVER () AS total_count
    FROM filtered f
  )
  SELECT
    c.plantilla_id, c.employee_name, c.employee_no, c.account_id, c.account_name,
    c.group_id, c.group_name, c.store_id, c.store_name, c.province_id,
    c.position_title, c.status, c.deployment_type, c.is_roving, c.roving_store_count,
    c.vcode, c.hr_emploc_id, c.date_hired, c.tenure_months, c.age, c.has_penalty,
    c.separation_status, c.date_of_separation, c.is_active, c.is_inactive,
    c.is_pending_deactivation, c.is_deactivated, c.onboarding_linked,
    c.has_masked_fields, c.masked_fields, c.deactivation_overlay, c.row_capabilities,
    c.total_count
  FROM counted c
  ORDER BY
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'employee_name'  THEN c.employee_name END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'employee_name'  THEN c.employee_name END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'employee_no'    THEN c.employee_no END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'employee_no'    THEN c.employee_no END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'account_name'   THEN c.account_name END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'account_name'   THEN c.account_name END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'group_name'     THEN c.group_name END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'group_name'     THEN c.group_name END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'store_name'     THEN c.store_name END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'store_name'     THEN c.store_name END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'position_title' THEN c.position_title END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'position_title' THEN c.position_title END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'status'         THEN c.status END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'status'         THEN c.status END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'date_hired'     THEN c.date_hired END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'date_hired'     THEN c.date_hired END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'tenure_months'  THEN c.tenure_months END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'tenure_months'  THEN c.tenure_months END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'created_at'     THEN c.created_at END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'created_at'     THEN c.created_at END DESC NULLS LAST,
    c.employee_name ASC NULLS LAST
  LIMIT v_limit
  OFFSET v_offset;
END;
$$;

COMMENT ON FUNCTION public.list_web_plantilla_employees(
  text, uuid, uuid, uuid, text, text, text, integer, integer, text, text
) IS 'Lists plantilla employees with client filtering, role-scoped security, masking metadata, and pagination support up to 5000 rows.';
