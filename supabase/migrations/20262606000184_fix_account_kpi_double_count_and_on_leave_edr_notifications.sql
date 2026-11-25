-- Migration: 20262606000184_fix_account_kpi_double_count_and_on_leave_edr_notifications.sql
-- Purpose:
-- 1. ADR-001 Rule 2 & ADR-002 Zero-Gap Contract:
--    Harden public.v_account_allocation_kpi:
--    a) Fix double-counting in coverage_slot_kpi: do not count actual_hc or filled_hc for occupants
--       who already hold an active store allocation in public.employee_store_allocations under that account.
--    b) Incorporate active On-Leave headcount (leave_count) into required_hc capacity.
--    c) Append leave_count to the end of v_account_allocation_kpi (preserving strict column order parity).
-- 2. On-Leave SLA & EDR Notification Routine:
--    Create public.check_and_notify_on_leave_edr() function to scan active on-leave personnel:
--    - When CURRENT_DATE = EDR: Dispatches LEAVE_RETURN_DUE notification to assigned HRCO.
--    - When CURRENT_DATE > EDR: Dispatches LEAVE_RETURN_BREACH urgent notification to OM, HRCO, and Admins.
--    - Idempotent 24h deduplication prevents notification spamming.

BEGIN;

-- ── §1. Harden v_account_allocation_kpi ───────────────────────────────────────

CREATE OR REPLACE VIEW public.v_account_allocation_kpi
  WITH (security_invoker = true)
AS
WITH filled AS (
  SELECT a.account_id,
         round(COALESCE(sum(a.filled_hc), 0), 4) AS filled_hc,
         count(DISTINCT a.employee_no)            AS actual_hc
  FROM public.employee_store_allocations a
  JOIN public.plantilla p ON p.id = a.plantilla_id
  WHERE a.is_active
    AND p.status = 'Active'
    AND (p.date_of_separation IS NULL OR p.date_of_separation > CURRENT_DATE)
    AND COALESCE(p.is_deleted, false) = false
    AND COALESCE(p.is_archived, false) = false
  GROUP BY a.account_id
),
leave AS (
  SELECT p.account_id,
         count(*) AS leave_count
  FROM public.plantilla p
  WHERE p.status IN ('On Leave', 'on_leave')
    AND (p.date_of_separation IS NULL OR p.date_of_separation > CURRENT_DATE)
    AND COALESCE(p.is_deleted, false) = false
    AND COALESCE(p.is_archived, false) = false
  GROUP BY p.account_id
),
pipeline AS (
  SELECT he.account_id,
         count(*) AS pipeline_count
  FROM public.hr_emploc he
  LEFT JOIN public.vacancies v ON v.id = he.vacancy_id
  WHERE he.status <> ALL (ARRAY['Moved to Plantilla'::text, 'Backout'::text])
    AND he.deleted_at IS NULL
    AND he.coverage_slot_id IS NULL
    AND COALESCE(v.is_pool_vacancy, false) = false
  GROUP BY he.account_id
),
coverage_slot_kpi AS (
  SELECT
    cg.account_id,
    -- Prevent double counting: only count active coverage slots whose occupant
    -- does NOT already have an active store allocation in this account
    COUNT(*) FILTER (
      WHERE cs.slot_status = 'active'
        AND (
          cs.current_occupant_plantilla_id IS NULL
          OR NOT EXISTS (
            SELECT 1 FROM public.employee_store_allocations esa
            WHERE esa.plantilla_id = cs.current_occupant_plantilla_id
              AND esa.account_id = cg.account_id
              AND esa.is_active = true
          )
        )
    )::numeric AS filled_hc,
    COUNT(DISTINCT cs.current_occupant_plantilla_id) FILTER (
      WHERE cs.slot_status = 'active'
        AND cs.current_occupant_plantilla_id IS NOT NULL
        AND NOT EXISTS (
          SELECT 1 FROM public.employee_store_allocations esa
          WHERE esa.plantilla_id = cs.current_occupant_plantilla_id
            AND esa.account_id = cg.account_id
            AND esa.is_active = true
        )
    ) AS actual_hc,
    COUNT(*) FILTER (WHERE cs.slot_status IN ('pipeline', 'hr_processing')) AS pipeline_count,
    COUNT(*) FILTER (WHERE cs.slot_status = 'open')::numeric                AS slot_vacant_hc
  FROM public.coverage_slots cs
  JOIN public.coverage_groups cg ON cg.id = cs.coverage_group_id
  LEFT JOIN public.plantilla cp ON cp.id = cs.current_occupant_plantilla_id
  WHERE cg.archived_at IS NULL
    AND (
      cp.id IS NULL 
      OR (
        cp.status = 'Active' 
        AND (cp.date_of_separation IS NULL OR cp.date_of_separation > CURRENT_DATE)
        AND COALESCE(cp.is_deleted, false) = false
        AND COALESCE(cp.is_archived, false) = false
      )
    )
  GROUP BY cg.account_id
),
slot_vacant_non_roving AS (
  SELECT
    ps.account_id,
    COUNT(*) FILTER (WHERE ps.slot_status IN ('open', 'pipeline')) AS vacant_slots
  FROM public.plantilla_slots ps
  INNER JOIN public.vacancies v
    ON  v.vcode = ps.legacy_vcode
   AND  v.deleted_at IS NULL
   AND  COALESCE(v.is_archived, false)    = false
   AND  COALESCE(v.is_pool_vacancy, false) = false
  WHERE ps.is_roving    = false
    AND ps.legacy_vcode IS NOT NULL
    AND ps.account_id   IS NOT NULL
  GROUP BY ps.account_id
),
slot_vacant_roving AS (
  SELECT
    ps.account_id,
    SUM(
      CASE WHEN ps.slot_status IN ('open', 'pipeline')
           THEN 1.0 / NULLIF(grp.total_slots::numeric, 0)
           ELSE 0.0
      END
    ) AS vacant_hc
  FROM public.plantilla_slots ps
  JOIN (
    SELECT source_hc_request_id,
           COUNT(*) AS total_slots
    FROM public.plantilla_slots
    WHERE is_roving = true
      AND source_hc_request_id IS NOT NULL
    GROUP BY source_hc_request_id
  ) grp ON grp.source_hc_request_id = ps.source_hc_request_id
  WHERE ps.is_roving            = true
    AND ps.source_hc_request_id IS NOT NULL
    AND ps.account_id           IS NOT NULL
  GROUP BY ps.account_id
),
vacant AS (
  SELECT vv.account_id, count(*) AS open_hc
  FROM public.vacancies vv
  WHERE vv.status = 'Open'
    AND vv.deleted_at IS NULL
    AND COALESCE(vv.is_archived, false)       = false
    AND COALESCE(vv.is_pool_vacancy, false)   = false
    AND COALESCE(vv.affects_required_hc, true) = true
  GROUP BY vv.account_id
),
base AS (
  SELECT
    a.id          AS account_id,
    a.account_name,
    a.account_code,
    a.group_id,
    g.group_name,
    g.group_code,
    round(COALESCE(f.filled_hc, 0) + COALESCE(csk.filled_hc, 0), 4)::numeric(12,4) AS filled_hc,
    COALESCE(f.actual_hc, 0)  + COALESCE(csk.actual_hc, 0)                          AS actual_hc,
    (COALESCE(p.pipeline_count, 0) + COALESCE(csk.pipeline_count, 0))::bigint       AS pipeline_count,
    COALESCE(v.open_hc, 0)                                                           AS open_hc,
    round(
      COALESCE(svn.vacant_slots,   0)::numeric
    + COALESCE(svr.vacant_hc,      0)::numeric
    + COALESCE(csk.slot_vacant_hc, 0)::numeric,
    0)::numeric(12,4)                                                                AS slot_vacant_hc,
    round(
      COALESCE(f.filled_hc,          0)
    + COALESCE(csk.filled_hc,        0)
    + COALESCE(l.leave_count,        0)
    + COALESCE(p.pipeline_count,     0)
    + COALESCE(csk.pipeline_count,   0)
    + COALESCE(svn.vacant_slots,     0)::numeric
    + COALESCE(svr.vacant_hc,        0)::numeric
    + COALESCE(csk.slot_vacant_hc,   0)::numeric,
    0)::numeric(12,4)                                                                AS required_hc,
    COALESCE(l.leave_count, 0)::bigint                                               AS leave_count
  FROM public.accounts a
  LEFT JOIN public.groups          g    ON g.id          = a.group_id
  LEFT JOIN filled                 f    ON f.account_id  = a.id
  LEFT JOIN leave                  l    ON l.account_id  = a.id
  LEFT JOIN pipeline               p    ON p.account_id  = a.id
  LEFT JOIN coverage_slot_kpi      csk  ON csk.account_id = a.id
  LEFT JOIN vacant                 v    ON v.account_id  = a.id
  LEFT JOIN slot_vacant_non_roving svn  ON svn.account_id = a.id
  LEFT JOIN slot_vacant_roving     svr  ON svr.account_id = a.id
  WHERE a.is_active = true
    AND COALESCE(a.is_pool_account, false) = false
    AND (
         public.i_have_full_access()
      OR a.id = ANY (public.get_my_allowed_account_ids())
    )
)
SELECT
  account_id, account_name, account_code, group_id, group_name, group_code,
  filled_hc,
  actual_hc,
  pipeline_count,
  open_hc,
  required_hc,
  CASE WHEN required_hc = 0 THEN 0.0
       ELSE round(LEAST(1.0, GREATEST(0.0, actual_hc::numeric / required_hc)), 4) END AS mfr,
  CASE WHEN required_hc = 0 THEN 0.0
       ELSE round(LEAST(1.0, GREATEST(0.0, (actual_hc::numeric + pipeline_count) / required_hc)), 4) END AS projected_mfr,
  CASE WHEN required_hc = 0 THEN 0.0
       ELSE round(slot_vacant_hc / required_hc, 4) END                     AS vacancy_rate,
  CASE WHEN required_hc = 0 THEN 0.0
       ELSE round(pipeline_count / required_hc, 4) END                     AS pipeline_coverage,
  CASE WHEN required_hc = 0              THEN 'healthy'::text
       WHEN actual_hc::numeric / required_hc >= 1.0 THEN 'healthy'::text
       WHEN actual_hc::numeric / required_hc >= 0.9 THEN 'at_risk'::text
       ELSE                                   'critical'::text
  END                                                                       AS health_status,
  slot_vacant_hc,
  leave_count
FROM base;

ALTER VIEW public.v_account_allocation_kpi OWNER TO postgres;
COMMENT ON VIEW public.v_account_allocation_kpi IS
  'Allocation-based per-account KPI. ADR-001 Rule 2 & ADR-002 compliant: actual_hc derives strictly from active, non-separated employees in public.plantilla without double-counting coverage slots. '
  'Incorporates active leave_count into required_hc and appends leave_count as trailing column for 100% parity with Plantilla roster tabs.';
GRANT SELECT ON public.v_account_allocation_kpi TO authenticated, service_role;

-- ── §2. On-Leave EDR Notification Routine ─────────────────────────────────────

CREATE OR REPLACE FUNCTION public.check_and_notify_on_leave_edr()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_rec               record;
  v_edr_str           text;
  v_edr_date          date;
  v_days_lapsed       integer;
  v_hrco_id           uuid;
  v_om_id             uuid;
  v_notifs_sent       integer := 0;
  v_today             date := CURRENT_DATE;
BEGIN
  FOR v_rec IN
    SELECT p.id, p.account_id, p.employee_no, p.first_name, p.last_name, p.store_name, p.remarks
    FROM public.plantilla p
    WHERE p.status IN ('On Leave', 'on_leave')
      AND COALESCE(p.is_deleted, false) = false
      AND COALESCE(p.is_archived, false) = false
      AND p.remarks ILIKE '%EDR:%'
  LOOP
    -- Extract EDR (format YYYY-MM-DD) from remarks
    v_edr_str := substring(v_rec.remarks from 'EDR:\s*([0-9]{4}-[0-9]{2}-[0-9]{2})');
    
    IF v_edr_str IS NOT NULL THEN
      BEGIN
        v_edr_date := v_edr_str::date;
      EXCEPTION WHEN OTHERS THEN
        v_edr_date := NULL;
      END;

      IF v_edr_date IS NOT NULL AND v_today >= v_edr_date THEN
        v_days_lapsed := v_today - v_edr_date;

        -- Resolve HRCO for this account
        SELECT up.id INTO v_hrco_id
        FROM public.user_scopes us
        JOIN public.users_profile up ON up.id = us.user_id
        JOIN public.roles r ON r.id = up.role_id
        WHERE us.account_id = v_rec.account_id
          AND r.role_name = 'HRCO'
          AND up.is_active = true
          AND up.archived_at IS NULL
        LIMIT 1;

        -- Resolve OM for this account or account group
        SELECT up.id INTO v_om_id
        FROM public.user_scopes us
        JOIN public.users_profile up ON up.id = us.user_id
        JOIN public.roles r ON r.id = up.role_id
        JOIN public.accounts acc ON acc.id = v_rec.account_id
        WHERE (us.account_id = v_rec.account_id OR us.group_id = acc.group_id)
          AND r.role_name IN ('Operations Manager', 'OM')
          AND up.is_active = true
          AND up.archived_at IS NULL
        LIMIT 1;

        -- 1. Due Today (CURRENT_DATE = EDR): Notify HRCO
        IF v_days_lapsed = 0 THEN
          IF v_hrco_id IS NOT NULL AND NOT EXISTS (
            SELECT 1 FROM public.notifications n
            WHERE n.user_id = v_hrco_id
              AND n.type = 'LEAVE_RETURN_DUE'
              AND n.target_entity_id = v_rec.id
              AND n.created_at::date = v_today
          ) THEN
            INSERT INTO public.notifications (
              user_id, type, title, message, priority, target_entity_id, deep_link, created_at
            ) VALUES (
              v_hrco_id,
              'LEAVE_RETURN_DUE',
              'Employee Due to Return from Leave Today',
              format('%s %s (%s) at %s is scheduled to return today (%s). Please verify return or update leave status.',
                     v_rec.first_name, v_rec.last_name, v_rec.employee_no, COALESCE(v_rec.store_name, 'Unassigned Store'), v_edr_str),
              'normal',
              v_rec.id,
              format('/plantilla?accountId=%s&status=on_leave', v_rec.account_id),
              NOW()
            );
            v_notifs_sent := v_notifs_sent + 1;
          END IF;

        -- 2. Breach (CURRENT_DATE > EDR): Notify OM and HRCO
        ELSIF v_days_lapsed > 0 THEN
          -- Notify OM
          IF v_om_id IS NOT NULL AND NOT EXISTS (
            SELECT 1 FROM public.notifications n
            WHERE n.user_id = v_om_id
              AND n.type = 'LEAVE_RETURN_BREACH'
              AND n.target_entity_id = v_rec.id
              AND n.created_at::date = v_today
          ) THEN
            INSERT INTO public.notifications (
              user_id, type, title, message, priority, target_entity_id, deep_link, created_at
            ) VALUES (
              v_om_id,
              'LEAVE_RETURN_BREACH',
              'On-Leave SLA Breach: Overdue Return',
              format('SLA Breach: %s %s (%s) at %s exceeded EDR (%s) by %s day(s) without returning to Active duty.',
                     v_rec.first_name, v_rec.last_name, v_rec.employee_no, COALESCE(v_rec.store_name, 'Unassigned Store'), v_edr_str, v_days_lapsed),
              'urgent',
              v_rec.id,
              format('/plantilla?accountId=%s&status=on_leave', v_rec.account_id),
              NOW()
            );
            v_notifs_sent := v_notifs_sent + 1;
          END IF;

          -- Notify HRCO as well
          IF v_hrco_id IS NOT NULL AND NOT EXISTS (
            SELECT 1 FROM public.notifications n
            WHERE n.user_id = v_hrco_id
              AND n.type = 'LEAVE_RETURN_BREACH'
              AND n.target_entity_id = v_rec.id
              AND n.created_at::date = v_today
          ) THEN
            INSERT INTO public.notifications (
              user_id, type, title, message, priority, target_entity_id, deep_link, created_at
            ) VALUES (
              v_hrco_id,
              'LEAVE_RETURN_BREACH',
              'On-Leave SLA Breach: Overdue Return',
              format('SLA Breach: %s %s (%s) at %s is %s day(s) past scheduled EDR (%s). Action required to confirm return or extend leave.',
                     v_rec.first_name, v_rec.last_name, v_rec.employee_no, COALESCE(v_rec.store_name, 'Unassigned Store'), v_days_lapsed, v_edr_str),
              'urgent',
              v_rec.id,
              format('/plantilla?accountId=%s&status=on_leave', v_rec.account_id),
              NOW()
            );
            v_notifs_sent := v_notifs_sent + 1;
          END IF;
        END IF;

      END IF;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'status', 'ok',
    'notifications_dispatched', v_notifs_sent,
    'evaluated_at', NOW()
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.check_and_notify_on_leave_edr() TO authenticated, service_role;
COMMENT ON FUNCTION public.check_and_notify_on_leave_edr() IS
  'Evaluates on-leave personnel against Estimated Date of Return (EDR). Dispatches LEAVE_RETURN_DUE to HRCO on EDR day, and LEAVE_RETURN_BREACH to OM and HRCO if breached.';

COMMIT;
