-- ============================================================
-- Migration: 20262606000088_on_leave_edr_lapse_sla_notifications.sql
-- On-Leave Expected Date of Return (EDR) Lapse & SLA Breach Notifications
-- ============================================================
-- Business Rules:
--   1. If an employee is On Leave and the Expected Date of Return (EDR)
--      has lapsed (CURRENT_DATE > EDR):
--      - Days 1 to 2 (v_days_lapsed < 3): Notify assigned HRCO that action
--        is required to update employment status or return employee to Active.
--      - Day 3+ (v_days_lapsed >= 3): If no action from HRCO, escalate and
--        notify Operations Manager (OM) that the SLA has breached.
--   2. Prevents daily notification spam via same-day reference deduplication.
--   3. Scheduled via pg_cron daily at 06:00 PHT (22:00 UTC).
-- ============================================================

CREATE OR REPLACE FUNCTION public.check_on_leave_edr_sla()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  rec                  RECORD;
  v_edr                date;
  v_days_lapsed        integer;
  v_hrco_auth_id       uuid;
  v_om_auth_id         uuid;
  v_hrco_notified      integer := 0;
  v_om_breached        integer := 0;
  v_total_scanned      integer := 0;
  v_today              date := CURRENT_DATE;
BEGIN
  -- Iterate through all active on-leave plantilla records
  FOR rec IN
    SELECT
      p.id,
      p.employee_name,
      p.employee_no,
      p.account,
      p.account_id,
      p.store_id,
      p.store_name,
      p.hrco_name,
      p.hrco_user_id_snapshot,
      p.om_user_id_snapshot,
      p.remarks,
      s.hrco_user_id AS store_hrco_user_id,
      s.om_user_id   AS store_om_user_id,
      a.om_user_id   AS account_om_user_id
    FROM public.plantilla p
    LEFT JOIN public.stores   s ON s.id = p.store_id
    LEFT JOIN public.accounts a ON a.id = p.account_id
    WHERE p.status = 'On Leave'
      AND COALESCE(p.is_deleted, false) = false
  LOOP
    v_total_scanned := v_total_scanned + 1;
    v_edr := NULL;

    -- 1. Try to resolve EDR from active temporary coverage assignment
    SELECT wa.end_date INTO v_edr
    FROM public.workforce_assignments wa
    WHERE wa.covered_plantilla_id = rec.id
      AND wa.status IN ('Active', 'Approved')
      AND wa.end_date IS NOT NULL
    ORDER BY wa.end_date DESC
    LIMIT 1;

    -- 2. Fallback: Parse EDR from plantilla remarks (e.g., "EDR: 2026-11-30")
    IF v_edr IS NULL AND rec.remarks IS NOT NULL THEN
      BEGIN
        v_edr := (regexp_match(rec.remarks, 'EDR:\s*([0-9]{4}-[0-9]{2}-[0-9]{2})'))[1]::date;
      EXCEPTION WHEN OTHERS THEN
        v_edr := NULL;
      END;
    END IF;

    -- Check if EDR exists and has lapsed
    IF v_edr IS NOT NULL AND v_today > v_edr THEN
      v_days_lapsed := (v_today - v_edr)::integer;

      -- Phase 1: Days 1 to 2 past EDR -> Notify HRCO
      IF v_days_lapsed >= 1 AND v_days_lapsed < 3 THEN
        -- Resolve HRCO auth user ID
        SELECT up.auth_user_id INTO v_hrco_auth_id
        FROM public.users_profile up
        WHERE up.id = COALESCE(rec.hrco_user_id_snapshot, rec.store_hrco_user_id)
           OR up.auth_user_id = COALESCE(rec.hrco_user_id_snapshot, rec.store_hrco_user_id)
        LIMIT 1;

        -- Guard: avoid duplicate notification for same employee on the same calendar day
        IF NOT EXISTS (
          SELECT 1 FROM public.notifications n
          WHERE n.reference_type = 'plantilla_edr_lapse'
            AND n.reference_id = rec.id::text
            AND n.created_at >= v_today::timestamptz
        ) THEN
          PERFORM public.notify_user(
            p_recipient_user_id => v_hrco_auth_id,
            p_recipient_role    => 'HRCO',
            p_title             => '⚠️ EDR Lapsed: Return to Active or Update Status',
            p_message           => 'Employee ' || rec.employee_name || ' (' || rec.employee_no || ') at '
                                   || COALESCE(rec.store_name, rec.account) || ' reached Expected Date of Return ('
                                   || to_char(v_edr, 'Mon DD, YYYY') || '). Please update employment status or return to Active.',
            p_notification_type => 'immediate',
            p_event_type        => 'edr_lapsed',
            p_reference_type    => 'plantilla_edr_lapse',
            p_reference_id      => rec.id::text,
            p_deep_link_route   => '/plantilla/' || rec.id::text,
            p_sla_level         => 0::smallint
          );
          v_hrco_notified := v_hrco_notified + 1;
        END IF;

      -- Phase 2: Day 3+ past EDR -> Escalate to OM as SLA Breach
      ELSIF v_days_lapsed >= 3 THEN
        -- Resolve OM auth user ID
        SELECT up.auth_user_id INTO v_om_auth_id
        FROM public.users_profile up
        WHERE up.id = COALESCE(rec.om_user_id_snapshot, rec.store_om_user_id, rec.account_om_user_id)
           OR up.auth_user_id = COALESCE(rec.om_user_id_snapshot, rec.store_om_user_id, rec.account_om_user_id)
        LIMIT 1;

        -- Guard: avoid duplicate breach notification for same employee on the same calendar day
        IF NOT EXISTS (
          SELECT 1 FROM public.notifications n
          WHERE n.reference_type = 'plantilla_edr_breach'
            AND n.reference_id = rec.id::text
            AND n.created_at >= v_today::timestamptz
        ) THEN
          PERFORM public.notify_user(
            p_recipient_user_id => v_om_auth_id,
            p_recipient_role    => 'Operations Manager',
            p_title             => '🚨 SLA BREACH: On-Leave Employee Overdue (' || v_days_lapsed || 'd Lapsed)',
            p_message           => 'SLA Breach: Employee ' || rec.employee_name || ' (' || rec.employee_no || ') at '
                                   || COALESCE(rec.store_name, rec.account) || ' is ' || v_days_lapsed || ' days past EDR ('
                                   || to_char(v_edr, 'Mon DD, YYYY') || ') without action taken by HRCO. Immediate review required.',
            p_notification_type => 'immediate',
            p_event_type        => 'edr_breached',
            p_reference_type    => 'plantilla_edr_breach',
            p_reference_id      => rec.id::text,
            p_deep_link_route   => '/plantilla/' || rec.id::text,
            p_sla_level         => 1::smallint
          );

          -- Log to activity_log if available
          BEGIN
            INSERT INTO public.activity_log (
              actor_id, actor_name, actor_role, action, target_table, target_id, target_name, new_value
            ) VALUES (
              NULL, 'System SLA Monitor', 'System',
              'ON_LEAVE_EDR_BREACH_ESCALATED', 'plantilla', rec.id,
              rec.employee_name,
              jsonb_build_object(
                'edr', v_edr,
                'days_lapsed', v_days_lapsed,
                'escalated_to_om', v_om_auth_id
              )
            );
          EXCEPTION WHEN OTHERS THEN
            NULL;
          END;

          v_om_breached := v_om_breached + 1;
        END IF;
      END IF;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'scanned',         v_total_scanned,
    'hrco_notified',   v_hrco_notified,
    'om_breached',     v_om_breached,
    'run_at',          now()
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.check_on_leave_edr_sla() TO authenticated, service_role;
COMMENT ON FUNCTION public.check_on_leave_edr_sla() IS
  'Daily SLA sweep: notifies HRCO when an On-Leave employee reaches EDR (Days 1-2). '
  'Escalates to Operations Manager (OM) as an SLA breach if no action is taken after 3 days.';

-- Register pg_cron daily job at 06:00 PHT (22:00 UTC) if pg_cron is enabled
DO $$
BEGIN
  IF to_regclass('cron.job') IS NOT NULL THEN
    PERFORM cron.unschedule(jobid)
    FROM cron.job
    WHERE jobname = 'check_on_leave_edr_sla';

    PERFORM cron.schedule(
      'check_on_leave_edr_sla',
      '0 22 * * *',
      'SELECT public.check_on_leave_edr_sla();'
    );
  END IF;
EXCEPTION WHEN OTHERS THEN
  NULL;
END $$;
