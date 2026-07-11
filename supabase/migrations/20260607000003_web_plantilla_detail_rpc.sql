-- Migration: 20260607000003_web_plantilla_detail_rpc.sql
-- Ticket: OHM2026_1101 - Web Plantilla detail presentation RPC
--
-- Purpose:
--   Safe, read-only presentation contract for a single Plantilla employee record
--   on the OHMployee Web Dashboard detail drawer.
--
-- Security invariants:
--   - Caller identity is derived strictly from auth.uid(). No caller-supplied IDs.
--   - Unauthenticated, profile-less, inactive, archived, and out-of-scope callers
--     fail closed (ERRCODE 42501). No cross-scope leakage.
--   - Scope check runs against v_plantilla_safe, which already excludes deleted,
--     archived, and expired visibility-window rows.
--   - PII is excluded from the contract: no ATM numbers, no SSS/PhilHealth/Pag-IBIG
--     raw values, no payroll rate, no exact birthdate, no coordinator/contact details,
--     no raw notes or remarks. Only safe/derived presentation fields are exposed:
--     age (integer years), tenure_months, and masked field indicators.
--   - row_capabilities are UI hints only; action RPCs, triggers, and RLS remain authority.
--   - Execution is granted only to authenticated. PUBLIC and anon are revoked.
--
-- Assumptions (documented):
--   - Reads v_plantilla_safe for scoped base data; JOINs raw plantilla table for
--     additional columns not projected by the view (name parts, transfer fields,
--     inactive/for-deactivation timestamps, onboarding snapshots).
--   - Transfer overlay includes transferred_from_store_id UUID and the resolved store
--     name from the stores table. Frontend must treat the name as informational.
--   - Deactivation overlay is derived purely from v_plantilla_safe columns (status,
--     deactivated_at, deactivation_reason). It does NOT join employee_deactivation_requests
--     (deactivation v2 migrations marked APPLY PENDING) to avoid an apply-order dependency.
--     A follow-up migration may enrich the overlay once v2 tables are confirmed applied.
--   - HC placeholder slots (source_headcount_request_id IS NOT NULL) are not excluded
--     from detail access — a direct plantilla_id lookup should still resolve them.

-- ============================================================================
-- get_web_plantilla_detail(p_employee_id uuid)
-- ============================================================================

DROP FUNCTION IF EXISTS public.get_web_plantilla_detail(uuid);

CREATE OR REPLACE FUNCTION public.get_web_plantilla_detail(p_employee_id uuid)
RETURNS TABLE (
  -- Identity
  plantilla_id                uuid,
  employee_name               text,
  employee_no                 text,
  last_name                   text,
  first_name                  text,
  middle_name                 text,
  emploc_no                   text,

  -- Assignment
  account_id                  uuid,
  account_name                text,
  group_id                    uuid,
  group_name                  text,
  store_id                    uuid,
  store_name                  text,
  area                        text,
  province_id                 uuid,
  chain_id                    uuid,

  -- Position / Deployment
  position_title              text,
  position_id                 uuid,
  deployment_type             text,
  is_roving                   boolean,
  roving_assignment_id        uuid,
  roving_store_count          integer,
  roving_stores               jsonb,
  schedule                    text,
  rest_day                    text,

  -- Employment / Lifecycle Status
  status                      text,
  is_active                   boolean,
  is_inactive                 boolean,
  is_pending_deactivation     boolean,
  is_deactivated              boolean,
  date_hired                  date,
  tenure_months               integer,
  age                         integer,
  separation_status           text,
  date_of_separation          date,
  over_headcount              boolean,

  -- Onboarding Linkage
  hr_emploc_id                uuid,
  onboarding_linked           boolean,
  vcode                       text,
  vacancy_id                  uuid,
  vacancy_code_snapshot       text,
  employee_name_snapshot      text,
  hrco_user_id_snapshot       uuid,
  hrco_name                   text,

  -- Deactivation Overlay
  deactivation_overlay        jsonb,
  inactive_at                 timestamp with time zone,
  for_deactivation_at         timestamp with time zone,
  deactivated_at              timestamp with time zone,

  -- Transfer Overlay
  transfer_overlay            jsonb,

  -- Staffing / HC Linkage
  source_headcount_request_id uuid,
  is_hc_placeholder           boolean,

  -- Masked Indicators
  has_masked_fields           boolean,
  masked_fields               jsonb,
  has_penalty                 boolean,

  -- Capability Hints
  row_capabilities            jsonb,

  -- Audit / Timeline Summaries
  created_at                  timestamp with time zone,
  updated_at                  timestamp with time zone,
  moved_by_user_id            uuid,
  last_mika_synced_at         timestamp with time zone,
  last_mika_synced_by         uuid
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
BEGIN
  IF v_auth_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated: web plantilla detail requires a valid session'
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
    RAISE EXCEPTION 'forbidden: web plantilla detail caller is not allowed'
      USING ERRCODE = '42501';
  END IF;

  -- Validate record exists in v_plantilla_safe (respects deletion, archival,
  -- and expired visibility windows) and is within the caller's scope.
  IF NOT EXISTS (
    SELECT 1 FROM public.v_plantilla_safe p
    WHERE p.id = p_employee_id
      AND (
        COALESCE(v_role_level, 0) >= 90
        OR p.account = ANY (public.get_my_allowed_accounts())
        OR EXISTS (
          SELECT 1 FROM public.user_scopes us
          WHERE us.user_id = v_profile_id AND us.account_id = p.account_id
        )
        OR EXISTS (
          SELECT 1 FROM public.user_scopes us
          JOIN public.accounts ac ON ac.id = p.account_id
          WHERE us.user_id = v_profile_id
            AND us.account_id IS NULL
            AND us.group_id = ac.group_id
        )
        OR EXISTS (
          SELECT 1 FROM public.users_profile up_fb
          JOIN public.accounts ac ON ac.id = p.account_id
          WHERE up_fb.id = v_profile_id
            AND NOT EXISTS (
              SELECT 1 FROM public.user_scopes us_any
              WHERE us_any.user_id = v_profile_id
                AND (us_any.group_id IS NOT NULL OR us_any.account_id IS NOT NULL)
            )
            AND (up_fb.account_id = p.account_id OR up_fb.group_id = ac.group_id)
        )
      )
  ) THEN
    RAISE EXCEPTION 'forbidden: web plantilla detail record is not found or caller has insufficient access'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    -- Identity
    p.id                                                                       AS plantilla_id,
    p.employee_name,
    p.employee_no,
    pl.last_name,
    pl.first_name,
    pl.middle_name,
    pl.emploc_no,

    -- Assignment
    p.account_id,
    a.account_name,
    a.group_id,
    g.group_name,
    p.store_id,
    p.store_name,
    p.area,
    p.province_id,
    p.chain_id,

    -- Position / Deployment
    p."position"                                                               AS position_title,
    p.position_id,
    p.deployment_type,
    (COALESCE(p.deployment_type, '') = 'Roving'
      OR p.roving_assignment_id IS NOT NULL)                                   AS is_roving,
    p.roving_assignment_id,
    COALESCE(p.roving_store_count, 0)                                          AS roving_store_count,
    COALESCE(p.roving_stores, '[]'::jsonb)                                     AS roving_stores,
    p.schedule,
    pl.rest_day,

    -- Employment / Lifecycle Status
    p.status,
    (p.status = 'Active')                                                      AS is_active,
    (p.status <> 'Active')                                                     AS is_inactive,
    (p.status IN ('Pending Deactivation', 'For Deactivation'))                 AS is_pending_deactivation,
    (p.status = 'Deactivated')                                                 AS is_deactivated,
    p.date_hired,
    p.tenure_months,
    p.age,
    p.separation_status,
    p.date_of_separation,
    COALESCE(p.over_headcount, FALSE)                                          AS over_headcount,

    -- Onboarding Linkage
    p.hr_emploc_id,
    (p.hr_emploc_id IS NOT NULL)                                               AS onboarding_linked,
    p.vcode,
    pl.vacancy_id,
    pl.vacancy_code_snapshot,
    pl.employee_name_snapshot,
    pl.hrco_user_id_snapshot,
    p.hrco_name,

    -- Deactivation Overlay (derived from v_plantilla_safe columns only)
    jsonb_build_object(
      'is_pending',         (p.status IN ('Pending Deactivation', 'For Deactivation')),
      'is_rejected',        (p.status = 'Rejected Deactivation'),
      'is_deactivated',     (p.status = 'Deactivated'),
      'deactivated_at',     p.deactivated_at,
      'deactivation_reason', p.deactivation_reason,
      'display_label', CASE
        WHEN p.status IN ('Pending Deactivation', 'For Deactivation', 'Pending')
          THEN 'Pending Deactivation'
        WHEN p.status IN ('Rejected Deactivation', 'Rejected')
          THEN 'Rejected Deactivation'
        WHEN p.status IN ('Deactivated', 'Approved')
          THEN 'Deactivated'
        ELSE NULL
      END
    )                                                                          AS deactivation_overlay,
    pl.inactive_at,
    pl.for_deactivation_at,
    p.deactivated_at,

    -- Transfer Overlay
    jsonb_build_object(
      'has_transfer_history',      (pl.transferred_from_store_id IS NOT NULL),
      'transferred_from_store_id', pl.transferred_from_store_id,
      'transferred_from_store_name', ts.store_name,
      'last_transfer_at',          pl.last_transfer_at
    )                                                                          AS transfer_overlay,

    -- Staffing / HC Linkage
    p.source_headcount_request_id,
    (p.source_headcount_request_id IS NOT NULL)                                AS is_hc_placeholder,

    -- Masked Indicators
    (
      p.sss_no IS NOT NULL
      OR p.philhealth_no IS NOT NULL
      OR p.pagibig_no IS NOT NULL
      OR p.atm_no_masked IS NOT NULL
    )                                                                          AS has_masked_fields,
    (
      '[]'::jsonb
      || CASE WHEN p.atm_no_masked   IS NOT NULL THEN '["atm_no"]'::jsonb      ELSE '[]'::jsonb END
      || CASE WHEN p.sss_no          IS NOT NULL THEN '["sss_no"]'::jsonb      ELSE '[]'::jsonb END
      || CASE WHEN p.philhealth_no   IS NOT NULL THEN '["philhealth_no"]'::jsonb ELSE '[]'::jsonb END
      || CASE WHEN p.pagibig_no      IS NOT NULL THEN '["pagibig_no"]'::jsonb   ELSE '[]'::jsonb END
    )                                                                          AS masked_fields,
    COALESCE(p.has_penalty, FALSE)                                             AS has_penalty,

    -- Capability Hints (UI presentation only — action RPCs remain authority)
    jsonb_build_object(
      'can_view_detail',              TRUE,
      'can_request_deactivation',     (
        p.status NOT IN ('Pending Deactivation', 'For Deactivation', 'Deactivated')
        AND (public.i_have_full_access() OR public.i_am_ops())
      ),
      'can_resubmit_deactivation',    (
        p.status = 'Rejected Deactivation'
        AND (public.i_have_full_access() OR public.i_am_ops())
      ),
      'can_transfer',                 (
        p.status = 'Active'
        AND (public.i_have_full_access() OR v_role_name = 'Encoder' OR v_role_level = 30)
      ),
      'can_request_deletion',         (
        p.status = 'Active'
        AND (public.i_have_full_access() OR public.i_am_ops())
      ),
      'can_update_employment_status', (
        p.status = 'Active'
        AND (public.i_have_full_access() OR v_role_name = 'Encoder' OR v_role_level = 30)
      ),
      'can_archive',                  (COALESCE(v_role_level, 0) >= 100)
    )                                                                          AS row_capabilities,

    -- Audit / Timeline Summaries
    p.created_at,
    p.updated_at,
    pl.moved_by_user_id,
    p.last_mika_synced_at,
    p.last_mika_synced_by

  FROM public.v_plantilla_safe p
  JOIN public.plantilla pl ON pl.id = p.id
  LEFT JOIN public.accounts a ON a.id = p.account_id
  LEFT JOIN public.groups g ON g.id = a.group_id
  LEFT JOIN public.stores ts ON ts.id = pl.transferred_from_store_id
  WHERE p.id = p_employee_id;
END;
$$;

COMMENT ON FUNCTION public.get_web_plantilla_detail(uuid) IS
  'OHM2026_1101 - Web presentation detail contract only. Returns safe detail fields for a '
  'single Plantilla employee record by plantilla_id. Reads through v_plantilla_safe '
  '(respects deletion, archival, visibility windows). ATM, gov IDs, payroll rate, exact '
  'birthdate, coordinator, and raw notes are never exposed. RLS/action RPCs remain authority.';


-- ============================================================================
-- Grants
-- ============================================================================

REVOKE ALL ON FUNCTION public.get_web_plantilla_detail(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_web_plantilla_detail(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_web_plantilla_detail(uuid) TO authenticated;


-- ============================================================================
-- Validation notes (run in staging/dev with representative JWT sessions):
--
-- 1. Unauthenticated / anon blocked:
--    anon has no execute grant; direct SQL with auth.uid() NULL raises 42501.
--
-- 2. Out-of-scope caller blocked:
--    SELECT * FROM public.get_web_plantilla_detail('<plantilla_id_outside_scope>');
--    Expected: raises 42501 (record not found or insufficient access).
--
-- 3. Deleted / archived / expired-visibility record blocked:
--    Rows excluded by v_plantilla_safe (is_deleted, is_archived, expired windows)
--    will fail the EXISTS scope check and raise 42501.
--
-- 4. PII safety:
--    The returned contract exposes only age, tenure_months, and masked field
--    indicators. ATM (raw), SSS, PhilHealth, Pag-IBIG, rate, exact date_of_birth,
--    coordinator, remarks are never selected.
--
-- 5. Super Admin / Head Admin global access:
--    role_level >= 90 bypasses account/group scope gates.
--
-- 6. Scoped role access:
--    Caller with account-level scope sees their assigned account rows only.
--    Group-level scope resolves accounts via user_scopes.group_id + accounts.group_id.
--    Legacy users_profile fallback (no scope rows at all) applies where applicable.
--
-- 7. Transfer overlay:
--    transferred_from_store_name resolves via stores JOIN; null when no prior transfer.
--
-- 8. HC placeholder slots:
--    source_headcount_request_id IS NOT NULL flags HC-created inactive slots.
--    These are still accessible by direct plantilla_id (not excluded from detail).
-- ============================================================================
