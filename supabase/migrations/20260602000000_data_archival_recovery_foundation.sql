-- ============================================================
-- OHM2026_1052 — Data Archival & Recovery Backend Foundation
-- Migration:  20260602000000_data_archival_recovery_foundation.sql
-- Depends on: 20260524120000_deactivation_v2_data_migration.sql
-- ============================================================

-- ── §1. Archival Metadata Columns ──────────────────────────────────────────
-- Add standard metadata fields to public.plantilla and public.vacancies.
-- Using SAFE ADD COLUMN IF NOT EXISTS patterns.

-- Plantilla metadata columns
ALTER TABLE public.plantilla
  ADD COLUMN IF NOT EXISTS is_archived     boolean     NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS archived_at     timestamptz DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS archived_by     uuid        REFERENCES public.users_profile(id) ON DELETE SET NULL DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS archive_reason   text        DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS restored_at     timestamptz DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS restored_by     uuid        REFERENCES public.users_profile(id) ON DELETE SET NULL DEFAULT NULL;

-- Vacancies metadata columns (is_archived, archived_at, archived_by already exist)
ALTER TABLE public.vacancies
  ADD COLUMN IF NOT EXISTS archive_reason   text        DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS archived_by_id  uuid        REFERENCES public.users_profile(id) ON DELETE SET NULL DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS restored_at     timestamptz DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS restored_by     uuid        REFERENCES public.users_profile(id) ON DELETE SET NULL DEFAULT NULL;

-- Create indexes for performance on the new columns
CREATE INDEX IF NOT EXISTS idx_plantilla_is_archived ON public.plantilla(is_archived) WHERE (is_archived = true);
CREATE INDEX IF NOT EXISTS idx_plantilla_archived_by ON public.plantilla(archived_by);
CREATE INDEX IF NOT EXISTS idx_vacancies_archived_by_id ON public.vacancies(archived_by_id);


-- ── §2. Archive Audit Table ────────────────────────────────────────────────
-- Create public.archival_audit_logs to track all archival actions.

CREATE TABLE IF NOT EXISTS public.archival_audit_logs (
  id               uuid        NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  module           text        NOT NULL, -- 'plantilla' | 'vacancy'
  record_id        uuid        NOT NULL,
  action_type      text        NOT NULL, -- 'archive' | 'restore'
  archived_by      uuid        REFERENCES public.users_profile(id) ON DELETE SET NULL DEFAULT NULL,
  restored_by      uuid        REFERENCES public.users_profile(id) ON DELETE SET NULL DEFAULT NULL,
  reason           text        DEFAULT NULL,
  payload_snapshot jsonb       DEFAULT NULL,
  created_at       timestamptz NOT NULL DEFAULT now()
);

-- RLS Configuration for Audit Table
ALTER TABLE public.archival_audit_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS archival_audit_logs_select_super_admin ON public.archival_audit_logs;
CREATE POLICY archival_audit_logs_select_super_admin
  ON public.archival_audit_logs
  FOR SELECT
  TO authenticated
  USING (public.is_super_admin());


-- ── §3. Super Admin RPC Functions ──────────────────────────────────────────

-- 3.1. archive_plantilla_record
CREATE OR REPLACE FUNCTION public.archive_plantilla_record(
  p_plantilla_id uuid,
  p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_caller_id uuid;
  v_record record;
  v_snapshot jsonb;
BEGIN
  -- Super Admin check
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Access Denied: Super Admin only' USING ERRCODE = '42501';
  END IF;

  v_caller_id := public.get_current_profile_id();

  -- Get and lock record
  SELECT * INTO v_record
  FROM public.plantilla
  WHERE id = p_plantilla_id AND is_deleted = false
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Record not found or already deleted' USING ERRCODE = 'P0002';
  END IF;

  IF v_record.is_archived = true THEN
    RAISE EXCEPTION 'Record is already archived' USING ERRCODE = '23505';
  END IF;

  -- Create snapshot
  v_snapshot := to_jsonb(v_record);

  -- Update Plantilla record
  UPDATE public.plantilla
  SET is_archived = true,
      archived_at = now(),
      archived_by = v_caller_id,
      archive_reason = p_reason,
      updated_at = now(),
      updated_by = v_caller_id
  WHERE id = p_plantilla_id;

  -- Insert audit log
  INSERT INTO public.archival_audit_logs (
    module,
    record_id,
    action_type,
    archived_by,
    reason,
    payload_snapshot
  ) VALUES (
    'plantilla',
    p_plantilla_id,
    'archive',
    v_caller_id,
    p_reason,
    v_snapshot
  );

  RETURN jsonb_build_object(
    'success', true,
    'plantilla_id', p_plantilla_id,
    'archived_at', now()
  );
END;
$$;

-- 3.2. restore_plantilla_record
CREATE OR REPLACE FUNCTION public.restore_plantilla_record(
  p_plantilla_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_caller_id uuid;
  v_record record;
  v_snapshot jsonb;
  v_conflict_id uuid;
BEGIN
  -- Super Admin check
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Access Denied: Super Admin only' USING ERRCODE = '42501';
  END IF;

  v_caller_id := public.get_current_profile_id();

  -- Get and lock record
  SELECT * INTO v_record
  FROM public.plantilla
  WHERE id = p_plantilla_id AND is_deleted = false
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Record not found or already deleted' USING ERRCODE = 'P0002';
  END IF;

  IF v_record.is_archived = false THEN
    RAISE EXCEPTION 'Record is not currently archived' USING ERRCODE = '23505';
  END IF;

  -- Validation A: Active employee number conflict (uq_plantilla_employee_no_active)
  IF v_record.employee_no IS NOT NULL AND v_record.status = ANY(ARRAY['Active', 'Pending Deactivation', 'On Leave']) THEN
    SELECT id INTO v_conflict_id
    FROM public.plantilla
    WHERE employee_no = v_record.employee_no
      AND is_deleted = false
      AND is_archived = false
      AND status = ANY(ARRAY['Active', 'Pending Deactivation', 'On Leave'])
      AND id <> p_plantilla_id
    LIMIT 1;

    IF v_conflict_id IS NOT NULL THEN
      RAISE EXCEPTION 'Conflict: Employee Number % is already active on record %', v_record.employee_no, v_conflict_id USING ERRCODE = '23505';
    END IF;
  END IF;

  -- Validation B: Active hr_emploc_id conflict (uq_plantilla_hr_emploc_active)
  IF v_record.hr_emploc_id IS NOT NULL THEN
    SELECT id INTO v_conflict_id
    FROM public.plantilla
    WHERE hr_emploc_id = v_record.hr_emploc_id
      AND is_deleted = false
      AND is_archived = false
      AND id <> p_plantilla_id
    LIMIT 1;

    IF v_conflict_id IS NOT NULL THEN
      RAISE EXCEPTION 'Conflict: Emploc deployment record % is already active on plantilla record %', v_record.hr_emploc_id, v_conflict_id USING ERRCODE = '23505';
    END IF;
  END IF;

  -- Create snapshot
  v_snapshot := to_jsonb(v_record);

  -- Update Plantilla record to restore
  UPDATE public.plantilla
  SET is_archived = false,
      restored_at = now(),
      restored_by = v_caller_id,
      archived_at = null,
      archived_by = null,
      archive_reason = null,
      updated_at = now(),
      updated_by = v_caller_id
  WHERE id = p_plantilla_id;

  -- Insert audit log
  INSERT INTO public.archival_audit_logs (
    module,
    record_id,
    action_type,
    restored_by,
    payload_snapshot
  ) VALUES (
    'plantilla',
    p_plantilla_id,
    'restore',
    v_caller_id,
    v_snapshot
  );

  RETURN jsonb_build_object(
    'success', true,
    'plantilla_id', p_plantilla_id,
    'restored_at', now()
  );
END;
$$;

-- 3.3. archive_vacancy_record
CREATE OR REPLACE FUNCTION public.archive_vacancy_record(
  p_vacancy_id uuid,
  p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_caller_id uuid;
  v_caller_name text;
  v_record record;
  v_snapshot jsonb;
BEGIN
  -- Super Admin check
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Access Denied: Super Admin only' USING ERRCODE = '42501';
  END IF;

  v_caller_id := public.get_current_profile_id();
  v_caller_name := public.get_my_full_name();

  -- Get and lock record
  SELECT * INTO v_record
  FROM public.vacancies
  WHERE id = p_vacancy_id AND deleted_at IS NULL
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Record not found or already deleted' USING ERRCODE = 'P0002';
  END IF;

  IF v_record.is_archived = true THEN
    RAISE EXCEPTION 'Record is already archived' USING ERRCODE = '23505';
  END IF;

  -- Create snapshot
  v_snapshot := to_jsonb(v_record);

  -- Update Vacancy record
  UPDATE public.vacancies
  SET is_archived = true,
      archived_at = now(),
      archived_by_id = v_caller_id,
      archived_by = v_caller_name, -- synchronize legacy field
      archive_reason = p_reason,
      status = 'Archived', -- Maintain status for standard frontend sorting
      updated_at = now(),
      updated_by = v_caller_id
  WHERE id = p_vacancy_id;

  -- Insert audit log
  INSERT INTO public.archival_audit_logs (
    module,
    record_id,
    action_type,
    archived_by,
    reason,
    payload_snapshot
  ) VALUES (
    'vacancy',
    p_vacancy_id,
    'archive',
    v_caller_id,
    p_reason,
    v_snapshot
  );

  RETURN jsonb_build_object(
    'success', true,
    'vacancy_id', p_vacancy_id,
    'archived_at', now()
  );
END;
$$;

-- 3.4. restore_vacancy_record
CREATE OR REPLACE FUNCTION public.restore_vacancy_record(
  p_vacancy_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_caller_id uuid;
  v_record record;
  v_snapshot jsonb;
  v_conflict_id uuid;
  v_target_status text;
BEGIN
  -- Super Admin check
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Access Denied: Super Admin only' USING ERRCODE = '42501';
  END IF;

  v_caller_id := public.get_current_profile_id();

  -- Get and lock record
  SELECT * INTO v_record
  FROM public.vacancies
  WHERE id = p_vacancy_id AND deleted_at IS NULL
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Record not found or already deleted' USING ERRCODE = 'P0002';
  END IF;

  IF v_record.is_archived = false THEN
    RAISE EXCEPTION 'Record is not currently archived' USING ERRCODE = '23505';
  END IF;

  -- Resolve restoration target status safely (cannot restore into 'Archived')
  v_target_status := CASE WHEN v_record.status = 'Archived' THEN 'Open' ELSE COALESCE(v_record.status, 'Open') END;

  -- Validation: Slot conflict for Open vacancies (uniq_vacancies_open_per_slot)
  IF v_target_status = 'Open' AND COALESCE(v_record.source, '') IS DISTINCT FROM 'hc_request' THEN
    SELECT id INTO v_conflict_id
    FROM public.vacancies
    WHERE store_id = v_record.store_id
      AND position_id = v_record.position_id
      AND status = 'Open'
      AND COALESCE(is_archived, false) = false
      AND deleted_at IS NULL
      AND COALESCE(source, '') IS DISTINCT FROM 'hc_request'
      AND id <> p_vacancy_id
    LIMIT 1;

    IF v_conflict_id IS NOT NULL THEN
      RAISE EXCEPTION 'Conflict: There is already an active Open vacancy for this store and position slot (Vacancy ID: %)', v_conflict_id USING ERRCODE = '23505';
    END IF;
  END IF;

  -- Create snapshot
  v_snapshot := to_jsonb(v_record);

  -- Update Vacancy record to restore
  UPDATE public.vacancies
  SET is_archived = false,
      restored_at = now(),
      restored_by = v_caller_id,
      archived_at = null,
      archived_by_id = null,
      archived_by = null, -- clear legacy field
      archive_reason = null,
      status = v_target_status,
      updated_at = now(),
      updated_by = v_caller_id
  WHERE id = p_vacancy_id;

  -- Insert audit log
  INSERT INTO public.archival_audit_logs (
    module,
    record_id,
    action_type,
    restored_by,
    payload_snapshot
  ) VALUES (
    'vacancy',
    p_vacancy_id,
    'restore',
    v_caller_id,
    v_snapshot
  );

  RETURN jsonb_build_object(
    'success', true,
    'vacancy_id', p_vacancy_id,
    'restored_at', now()
  );
END;
$$;


-- ── §4. Redefining Operational Views ───────────────────────────────────────

-- 4.1. Redefining v_plantilla_safe to filter is_archived
CREATE OR REPLACE VIEW public.v_plantilla_safe AS
SELECT
  id,
  employee_name,
  employee_no,
  account,
  account_id,
  chain_id,
  store_id,
  province_id,
  "position",
  position_id,
  status,
  separation_status,
  date_of_separation,
  over_headcount,
  deactivated_at,
  deactivated_visible_until,
  deactivation_reason,
  deletion_requested_at,
  deletion_reason,
  sss_no,
  philhealth_no,
  pagibig_no,
  CASE
    WHEN atm_no IS NULL THEN NULL::text
    WHEN length(atm_no) <= 4 THEN '****'::text
    ELSE repeat('*', length(atm_no) - 4) || right(atm_no, 4)
  END AS atm_no_masked,
  civil_status,
  date_of_birth,
  CASE
    WHEN date_of_birth IS NOT NULL
      THEN EXTRACT(year FROM age(date_of_birth::timestamptz))::integer
    ELSE NULL::integer
  END AS age,
  CASE
    WHEN date_hired IS NOT NULL
      THEN (EXTRACT(epoch FROM age(now(), date_hired::timestamptz))
           / (60 * 60 * 24 * 30.4375))::integer
    ELSE NULL::integer
  END AS tenure_months,
  last_mika_synced_at,
  last_mika_synced_by,
  store_name,
  area,
  rate,
  schedule,
  deployment_type,
  has_penalty,
  date_hired,
  coordinator,
  hrco_name,
  vcode,
  hr_emploc_id,
  roving_assignment_id,
  created_at,
  updated_at,
  source_headcount_request_id,
  -- Computed columns
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
  inactive_visible_until
FROM public.plantilla p
WHERE
  COALESCE(is_deleted, false) = false
  AND (is_archived = false) -- EXCLUDE ARCHIVED RECORDS
  AND (deactivated_visible_until IS NULL OR deactivated_visible_until > NOW())
  AND (inactive_visible_until IS NULL OR inactive_visible_until > NOW());

COMMENT ON VIEW public.v_plantilla_safe IS
  'Safe read-only view over plantilla. Excludes deleted rows, '
  'archived rows, expired deactivated-visibility windows, and expired inactive-visibility windows. '
  'Updated in 20260602000000 to support standard data archival exclusions.';

-- 4.2. Redefining v_account_kpi to filter is_archived
CREATE OR REPLACE VIEW public.v_account_kpi AS
WITH actual AS (
    SELECT
        p.account_id,
        count(*) FILTER (
            WHERE p.status = 'Active'::text
        ) AS actual_hc
    FROM public.plantilla p
    WHERE
        COALESCE(p.is_deleted, false) = false
        AND COALESCE(p.is_archived, false) = false
        AND COALESCE(p.is_pool_employee, false) = false
    GROUP BY p.account_id
),
pipeline AS (
    SELECT
        he.account_id,
        count(*) AS pipeline_count
    FROM public.hr_emploc he
    LEFT JOIN public.vacancies v
        ON v.id = he.vacancy_id
    WHERE
        (
            he.status <> ALL (
                ARRAY[
                    'Moved to Plantilla'::text,
                    'Backout'::text
                ]
            )
        )
        AND he.deleted_at IS NULL
        AND COALESCE(v.is_archived, false) = false
        AND COALESCE(v.is_pool_vacancy, false) = false
    GROUP BY he.account_id
),
vacant AS (
    SELECT
        vacancies.account_id,
        count(*) AS vacant_count
    FROM public.vacancies
    WHERE
        vacancies.status = 'Open'::text
        AND COALESCE(vacancies.is_archived, false) = false
        AND COALESCE(vacancies.is_pool_vacancy, false) = false
    GROUP BY vacancies.account_id
),
base AS (
    SELECT
        a.id AS account_id,
        a.account_name,
        a.account_code,
        a.group_id,
        g.group_name,
        g.group_code,
        COALESCE(ac.actual_hc, 0::bigint) AS actual_hc,
        COALESCE(p.pipeline_count, 0::bigint) AS pipeline_count,
        COALESCE(v.vacant_count, 0::bigint) AS vacant_count,
        (
            COALESCE(ac.actual_hc, 0::bigint)
            + COALESCE(p.pipeline_count, 0::bigint)
            + COALESCE(v.vacant_count, 0::bigint)
        ) AS required_hc
    FROM public.accounts a
    LEFT JOIN public.groups g
        ON g.id = a.group_id
    LEFT JOIN actual ac
        ON ac.account_id = a.id
    LEFT JOIN pipeline p
        ON p.account_id = a.id
    LEFT JOIN vacant v
        ON v.account_id = a.id
    WHERE
        a.is_active = true
        AND COALESCE(a.is_pool_account, false) = false
        AND (
            public.i_have_full_access()
            OR (
                a.id::text = ANY (
                    public.get_my_allowed_accounts()
                )
            )
        )
)
SELECT
    account_id,
    account_name,
    account_code,
    group_id,
    group_name,
    group_code,
    actual_hc,
    pipeline_count,
    vacant_count,
    required_hc,
    CASE
        WHEN required_hc = 0 THEN 1.0
        ELSE round(
            actual_hc::numeric
            / required_hc::numeric,
            4
        )
    END AS mfr,
    CASE
        WHEN required_hc = 0 THEN 1.0
        ELSE round(
            (
                actual_hc + pipeline_count
            )::numeric
            / required_hc::numeric,
            4
        )
    END AS projected_mfr,
    CASE
        WHEN required_hc = 0 THEN 0.0
        ELSE round(
            vacant_count::numeric
            / required_hc::numeric,
            4
        )
    END AS vacancy_rate,
    CASE
        WHEN required_hc = 0 THEN 0.0
        ELSE round(
            pipeline_count::numeric
            / required_hc::numeric,
            4
        )
    END AS pipeline_coverage,
    CASE
        WHEN required_hc = 0 THEN 'healthy'::text
        WHEN (
            actual_hc::numeric
            / required_hc::numeric
        ) >= 1.0 THEN 'healthy'::text
        WHEN (
            actual_hc::numeric
            / required_hc::numeric
        ) >= 0.9 THEN 'at_risk'::text
        ELSE 'critical'::text
    END AS health_status
FROM base;

COMMENT ON VIEW public.v_account_kpi IS
  'Dashboard Accounts health KPI. Filters out archived vacancies and archived plantilla records. '
  'Updated in 20260602000000 to keep dashboards pristine.';

-- 4.3. Redefining vw_plantilla_status_counts to filter is_archived
CREATE OR REPLACE VIEW public.vw_plantilla_status_counts AS
 SELECT p.account_id,
    a.group_id,
    count(*) FILTER (WHERE (p.status = 'Active'::text)) AS active_count,
    count(*) FILTER (WHERE (p.status = 'On Leave'::text)) AS on_leave_count,
    count(*) FILTER (WHERE (p.status = 'Resigned'::text)) AS resigned_count
   FROM (public.plantilla p
     LEFT JOIN public.accounts a ON ((a.id = p.account_id)))
  WHERE (COALESCE(p.is_archived, false) = false) AND (COALESCE(p.is_deleted, false) = false)
  GROUP BY p.account_id, a.group_id;

COMMENT ON VIEW public.vw_plantilla_status_counts IS
  'Tabular/Status aggregate counts for active Plantilla. '
  'Excludes archived records to preserve tab/aggregate count precision.';


-- ── §5. Archive Observation Views ──────────────────────────────────────────

-- 5.1. vw_archived_plantilla
CREATE OR REPLACE VIEW public.vw_archived_plantilla AS
SELECT
  p.*,
  up_arc.full_name AS archived_by_name,
  up_rst.full_name AS restored_by_name
FROM public.plantilla p
LEFT JOIN public.users_profile up_arc ON up_arc.id = p.archived_by
LEFT JOIN public.users_profile up_rst ON up_rst.id = p.restored_by
WHERE p.is_archived = true;

COMMENT ON VIEW public.vw_archived_plantilla IS
  'Governance observation view for archived Plantilla records. Super Admin scoped.';

-- 5.2. vw_archived_vacancies
CREATE OR REPLACE VIEW public.vw_archived_vacancies AS
SELECT
  v.*,
  up_arc.full_name AS archived_by_name,
  up_rst.full_name AS restored_by_name
FROM public.vacancies v
LEFT JOIN public.users_profile up_arc ON up_arc.id = v.archived_by_id
LEFT JOIN public.users_profile up_rst ON up_rst.id = v.restored_by
WHERE v.is_archived = true;

COMMENT ON VIEW public.vw_archived_vacancies IS
  'Governance observation view for archived Vacancies records. Super Admin scoped.';
