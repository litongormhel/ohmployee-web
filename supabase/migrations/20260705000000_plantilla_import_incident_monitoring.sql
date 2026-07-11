-- ============================================================
-- OHM2026_0081 — Plantilla Import Operational Notifications
--               and Incident Monitoring
-- Migration: 20260705000000_plantilla_import_incident_monitoring.sql
-- Depends on: 20260704000000_plantilla_import_operational_safeguards.sql
-- ============================================================
-- Purpose
--   Adds structured incident event logging and an operational
--   notification queue for Import Plantilla failure visibility,
--   incident monitoring, and admin alerting.
--
-- Sections
--   §1  plantilla_import_incidents table + RLS
--   §2  plantilla_import_notifications queue table + RLS
--   §3  fn_auto_import_incident_on_status_change trigger function
--   §4  trg_import_incident trigger on plantilla_import_batches
--   §5  get_plantilla_import_incidents() SA/HA read RPC
--   §6  dismiss_plantilla_import_notification() SA/HA dismiss RPC
--
-- Severity mapping (canonical)
--   commit_failed                → critical
--   rollback_failed              → critical
--   rollback_safety_rejection    → warning   (ROLLBACK_UNSAFE error path)
--   stale_batch_rejection        → warning   (batch transitioned to expired)
--   approval_concurrency_conflict → warning  (manually logged — no RPC change)
--   rollback_concurrency_conflict → warning  (manually logged — no RPC change)
--   superseded_batch_rejection   → info      (manually logged — no RPC change)
--
-- Auto-incident generation (trigger-based, transactional-safe)
--   Fires AFTER UPDATE OF status on plantilla_import_batches.
--   Covers:  commit_failed, rollback_failed, expired.
--   Does NOT modify approval/rollback RPCs — trigger only.
--
-- Replay safety
--   Tables use CREATE TABLE IF NOT EXISTS.
--   All functions use CREATE OR REPLACE.
--   Trigger is DROP-IF-EXISTS before re-create.
--   No DROP CASCADE anywhere.
--
-- What is NOT changed
--   - approve_plantilla_import_batch
--   - rollback_plantilla_import_batch
--   - mark_expired_plantilla_import_batches
--   - get_plantilla_import_operational_health
--   - Allocation formulas / diff preview / CENCOM / HR Emploc
--   - Existing audit_logs usage
-- ============================================================


-- ============================================================
-- §1  plantilla_import_incidents
-- ============================================================

CREATE TABLE IF NOT EXISTS public.plantilla_import_incidents (
  id              uuid        NOT NULL DEFAULT gen_random_uuid(),
  batch_id        uuid            REFERENCES public.plantilla_import_batches(id),
  severity        text        NOT NULL,
  incident_type   text        NOT NULL,
  message         text        NOT NULL,
  actor           uuid,
  is_resolved     boolean     NOT NULL DEFAULT false,
  resolved_at     timestamptz,
  resolved_by     uuid,
  metadata        jsonb,
  created_at      timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT pii_pk PRIMARY KEY (id),
  CONSTRAINT pii_severity_check
    CHECK (severity IN ('info', 'warning', 'critical')),
  CONSTRAINT pii_type_check
    CHECK (incident_type IN (
      'commit_failed',
      'rollback_failed',
      'rollback_safety_rejection',
      'stale_batch_rejection',
      'approval_concurrency_conflict',
      'rollback_concurrency_conflict',
      'superseded_batch_rejection'
    ))
);

COMMENT ON TABLE public.plantilla_import_incidents IS
  'Structured incident records for Import Plantilla operational failures. '
  'Rows are inserted by the trg_import_incident trigger on batch status changes. '
  'Additive only — no modifications to audit_logs.';

COMMENT ON COLUMN public.plantilla_import_incidents.incident_type IS
  'commit_failed | rollback_failed | rollback_safety_rejection | '
  'stale_batch_rejection | approval_concurrency_conflict | '
  'rollback_concurrency_conflict | superseded_batch_rejection';

COMMENT ON COLUMN public.plantilla_import_incidents.severity IS
  'info | warning | critical';

CREATE INDEX IF NOT EXISTS idx_pii_batch_id
  ON public.plantilla_import_incidents(batch_id);

CREATE INDEX IF NOT EXISTS idx_pii_severity_created
  ON public.plantilla_import_incidents(severity, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_pii_unresolved
  ON public.plantilla_import_incidents(is_resolved, created_at DESC)
  WHERE is_resolved = false;

ALTER TABLE public.plantilla_import_incidents ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pii_sa_ha_select ON public.plantilla_import_incidents;
CREATE POLICY pii_sa_ha_select
  ON public.plantilla_import_incidents
  FOR SELECT
  TO authenticated
  USING (public.fn_can_approve_plantilla_import());


-- ============================================================
-- §2  plantilla_import_notifications
-- ============================================================

CREATE TABLE IF NOT EXISTS public.plantilla_import_notifications (
  id                uuid        NOT NULL DEFAULT gen_random_uuid(),
  batch_id          uuid            REFERENCES public.plantilla_import_batches(id),
  incident_id       uuid            REFERENCES public.plantilla_import_incidents(id),
  notification_type text        NOT NULL,
  title             text        NOT NULL,
  message           text        NOT NULL,
  status            text        NOT NULL DEFAULT 'pending',
  dismissed_by      uuid,
  dismissed_at      timestamptz,
  created_at        timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT pin_pk PRIMARY KEY (id),
  CONSTRAINT pin_status_check
    CHECK (status IN ('pending', 'sent', 'dismissed'))
);

COMMENT ON TABLE public.plantilla_import_notifications IS
  'Lightweight operational notification queue for Import Plantilla failures. '
  'No real-time push provider wired yet — queue only. '
  'Dismissed via dismiss_plantilla_import_notification() RPC (SA/HA).';

COMMENT ON COLUMN public.plantilla_import_notifications.status IS
  'pending | sent | dismissed';

CREATE INDEX IF NOT EXISTS idx_pin_batch_id
  ON public.plantilla_import_notifications(batch_id);

CREATE INDEX IF NOT EXISTS idx_pin_status_created
  ON public.plantilla_import_notifications(status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_pin_pending
  ON public.plantilla_import_notifications(created_at DESC)
  WHERE status = 'pending';

ALTER TABLE public.plantilla_import_notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pin_sa_ha_select ON public.plantilla_import_notifications;
CREATE POLICY pin_sa_ha_select
  ON public.plantilla_import_notifications
  FOR SELECT
  TO authenticated
  USING (public.fn_can_approve_plantilla_import());


-- ============================================================
-- §3  fn_auto_import_incident_on_status_change
-- ============================================================
-- Trigger function that auto-generates incident + notification
-- rows when plantilla_import_batches.status transitions to a
-- failure or expiration state.
--
-- Covered transitions:
--   pending_approval / approved  → commit_failed     → critical incident
--   approved                     → rollback_failed   → critical | warning incident
--                                                      (warning if ROLLBACK_UNSAFE)
--   pending_approval             → expired           → warning incident
--
-- Transactional-safe: EXCEPTION block ensures the trigger
-- never prevents the originating DML from completing.
--
-- RBAC: SECURITY DEFINER — runs with elevated privileges so
-- the trigger can insert into the two incident tables even
-- though the caller's RLS policies do not grant INSERT.

CREATE OR REPLACE FUNCTION public.fn_auto_import_incident_on_status_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
DECLARE
  v_incident_type text;
  v_severity      text;
  v_message       text;
  v_actor         uuid;
  v_incident_id   uuid;
  v_notif_title   text;
BEGIN
  -- Skip if status did not change
  IF NEW.status IS NOT DISTINCT FROM OLD.status THEN
    RETURN NEW;
  END IF;

  -- Map status transition to incident type + severity
  CASE NEW.status

    WHEN 'commit_failed' THEN
      v_incident_type := 'commit_failed';
      v_severity      := 'critical';
      v_message       := COALESCE(
        'Import commit failed: ' || NEW.commit_error_detail,
        'Import batch commit failed.'
      );
      v_actor         := auth.uid();
      v_notif_title   := '[Critical] Import Commit Failed';

    WHEN 'rollback_failed' THEN
      -- ROLLBACK_UNSAFE errors ([40001]) are safety rejections, not hard failures
      IF NEW.rollback_error_detail ILIKE '%ROLLBACK_UNSAFE%'
         OR NEW.rollback_error_detail ILIKE '%[40001]%'
      THEN
        v_incident_type := 'rollback_safety_rejection';
        v_severity      := 'warning';
        v_message       := COALESCE(
          'Rollback blocked by safety guard: ' || NEW.rollback_error_detail,
          'Rollback blocked by safety constraint.'
        );
        v_notif_title   := '[Warning] Rollback Safety Rejection';
      ELSE
        v_incident_type := 'rollback_failed';
        v_severity      := 'critical';
        v_message       := COALESCE(
          'Rollback failed: ' || NEW.rollback_error_detail,
          'Import batch rollback failed.'
        );
        v_notif_title   := '[Critical] Import Rollback Failed';
      END IF;
      v_actor := auth.uid();

    WHEN 'expired' THEN
      v_incident_type := 'stale_batch_rejection';
      v_severity      := 'warning';
      v_message       := 'Batch expired without approval after 72+ hours of pending.';
      v_actor         := auth.uid();
      v_notif_title   := '[Warning] Import Batch Expired';

    ELSE
      -- No incident for other status transitions
      RETURN NEW;
  END CASE;

  BEGIN
    -- Insert incident record
    INSERT INTO public.plantilla_import_incidents (
      batch_id,
      severity,
      incident_type,
      message,
      actor,
      metadata
    ) VALUES (
      NEW.id,
      v_severity,
      v_incident_type,
      v_message,
      v_actor,
      jsonb_build_object(
        'file_name',           NEW.file_name,
        'selected_group_id',   NEW.selected_group_id,
        'selected_account_id', NEW.selected_account_id,
        'from_status',         OLD.status,
        'to_status',           NEW.status
      )
    ) RETURNING id INTO v_incident_id;

    -- Insert notification queue entry
    INSERT INTO public.plantilla_import_notifications (
      batch_id,
      incident_id,
      notification_type,
      title,
      message
    ) VALUES (
      NEW.id,
      v_incident_id,
      v_incident_type,
      v_notif_title,
      v_message
    );

  EXCEPTION WHEN OTHERS THEN
    -- Never block the originating DML — silently swallow
    NULL;
  END;

  RETURN NEW;
END$func$;

REVOKE ALL ON FUNCTION public.fn_auto_import_incident_on_status_change() FROM PUBLIC, anon;

COMMENT ON FUNCTION public.fn_auto_import_incident_on_status_change() IS
  'Trigger function: auto-generates plantilla_import_incidents + '
  'plantilla_import_notifications rows on batch status transitions to '
  'commit_failed, rollback_failed, or expired. '
  'Transactional-safe (inner exception block prevents blocking the originating DML). '
  'Does NOT modify approve/rollback RPCs.';


-- ============================================================
-- §4  trg_import_incident trigger
-- ============================================================

DROP TRIGGER IF EXISTS trg_import_incident
  ON public.plantilla_import_batches;

CREATE TRIGGER trg_import_incident
  AFTER UPDATE OF status
  ON public.plantilla_import_batches
  FOR EACH ROW
  WHEN (OLD.status IS DISTINCT FROM NEW.status)
  EXECUTE FUNCTION public.fn_auto_import_incident_on_status_change();

COMMENT ON TRIGGER trg_import_incident ON public.plantilla_import_batches IS
  'Fires AFTER UPDATE OF status when status changes. '
  'Delegates to fn_auto_import_incident_on_status_change to create '
  'incident + notification records for failure/expiration transitions.';


-- ============================================================
-- §5  get_plantilla_import_incidents
-- ============================================================
-- SA/HA read-only feed of recent incidents.
-- Returns incidents grouped by severity (critical → warning → info),
-- unresolved first, newest within group, over the last p_days days.

CREATE OR REPLACE FUNCTION public.get_plantilla_import_incidents(
  p_days int DEFAULT 7
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
DECLARE
  v_result jsonb;
BEGIN
  IF NOT public.fn_can_approve_plantilla_import() THEN
    RAISE EXCEPTION 'forbidden: Head Admin or Super Admin required'
      USING ERRCODE = '42501';
  END IF;

  IF p_days < 1 THEN
    RAISE EXCEPTION 'INVALID_INPUT: p_days must be >= 1'
      USING ERRCODE = '22023';
  END IF;

  SELECT jsonb_build_object(
    'generated_at', now(),
    'window_days',  p_days,
    'total',        count(*),
    'critical',     count(*) FILTER (WHERE i.severity = 'critical'),
    'warning',      count(*) FILTER (WHERE i.severity = 'warning'),
    'info',         count(*) FILTER (WHERE i.severity = 'info'),
    'unresolved',   count(*) FILTER (WHERE i.is_resolved = false),
    'incidents',    COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'id',            i.id,
          'batch_id',      i.batch_id,
          'severity',      i.severity,
          'incident_type', i.incident_type,
          'message',       i.message,
          'is_resolved',   i.is_resolved,
          'resolved_at',   i.resolved_at,
          'created_at',    i.created_at,
          'metadata',      i.metadata
        )
        ORDER BY
          i.is_resolved ASC,
          CASE i.severity WHEN 'critical' THEN 1 WHEN 'warning' THEN 2 ELSE 3 END ASC,
          i.created_at DESC
      ),
      '[]'::jsonb
    )
  ) INTO v_result
  FROM public.plantilla_import_incidents i
  WHERE i.created_at > now() - (p_days || ' days')::interval;

  RETURN v_result;
END$func$;

REVOKE ALL ON FUNCTION public.get_plantilla_import_incidents(int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_plantilla_import_incidents(int) TO authenticated;

COMMENT ON FUNCTION public.get_plantilla_import_incidents(int) IS
  'Returns structured Import Plantilla incident records for the last p_days days '
  '(default 7). Incidents ordered: unresolved first, then by severity '
  '(critical→warning→info), newest within group. '
  'Includes summary counts (total, critical, warning, info, unresolved). '
  'Zero DML — STABLE, safe to poll. '
  'RBAC: Head Admin / Super Admin only.';


-- ============================================================
-- §6  dismiss_plantilla_import_notification
-- ============================================================
-- SA/HA only. Soft dismiss — sets status = dismissed.
-- Does not hard-delete the notification row.

CREATE OR REPLACE FUNCTION public.dismiss_plantilla_import_notification(
  p_notification_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
DECLARE
  v_uid   uuid := auth.uid();
  v_actor uuid := public.get_current_profile_id();
BEGIN
  IF NOT public.fn_can_approve_plantilla_import() THEN
    RAISE EXCEPTION 'forbidden: Head Admin or Super Admin required'
      USING ERRCODE = '42501';
  END IF;

  UPDATE public.plantilla_import_notifications
     SET status       = 'dismissed',
         dismissed_by = v_actor,
         dismissed_at = now()
   WHERE id = p_notification_id
     AND status <> 'dismissed';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'NOTIFICATION_NOT_FOUND_OR_ALREADY_DISMISSED'
      USING ERRCODE = 'P0002';
  END IF;

  INSERT INTO public.audit_logs(actor_id, module, action, record_id, new_data)
  VALUES (v_uid, 'plantilla_import_notifications', 'UPDATE', p_notification_id,
    jsonb_build_object('status', 'dismissed', 'dismissed_by', v_actor));

  RETURN jsonb_build_object(
    'dismissed',         true,
    'notification_id',   p_notification_id
  );
END$func$;

REVOKE ALL ON FUNCTION public.dismiss_plantilla_import_notification(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.dismiss_plantilla_import_notification(uuid) TO authenticated;

COMMENT ON FUNCTION public.dismiss_plantilla_import_notification(uuid) IS
  'Soft-dismisses one pending Import Plantilla notification. '
  'Sets status = dismissed; row is preserved for audit. '
  'Raises P0002 if the notification does not exist or is already dismissed. '
  'RBAC: Head Admin / Super Admin only.';


-- ============================================================
-- Validation SQL checklist (run after applying)
-- ============================================================
--
-- V1: Tables exist
--   SELECT table_name FROM information_schema.tables
--    WHERE table_name IN (
--      'plantilla_import_incidents',
--      'plantilla_import_notifications'
--    );
--
-- V2: Trigger exists on plantilla_import_batches
--   SELECT tgname FROM pg_trigger
--    WHERE tgname = 'trg_import_incident'
--      AND tgrelid = 'public.plantilla_import_batches'::regclass;
--
-- V3: RPCs exist
--   SELECT proname FROM pg_proc
--    WHERE proname IN (
--      'fn_auto_import_incident_on_status_change',
--      'get_plantilla_import_incidents',
--      'dismiss_plantilla_import_notification'
--    );
--
-- V4: Incident generation (commit_failed path)
--   UPDATE public.plantilla_import_batches
--      SET status = 'commit_failed',
--          commit_error_detail = '[TEST] manual test trigger'
--    WHERE id = '<your-test-batch-id>';
--   SELECT * FROM public.plantilla_import_incidents
--    WHERE incident_type = 'commit_failed'
--    ORDER BY created_at DESC LIMIT 1;
--   SELECT * FROM public.plantilla_import_notifications
--    WHERE notification_type = 'commit_failed'
--    ORDER BY created_at DESC LIMIT 1;
--
-- V5: Incident generation (expired path)
--   UPDATE public.plantilla_import_batches
--      SET status = 'expired', is_expired = true
--    WHERE id = '<your-test-batch-id>';
--   SELECT incident_type, severity FROM public.plantilla_import_incidents
--    WHERE incident_type = 'stale_batch_rejection'
--    ORDER BY created_at DESC LIMIT 1;
--
-- V6: Incident feed RPC
--   SELECT get_plantilla_import_incidents(7);
--   -- Verify: total, critical, warning, info, unresolved counts correct.
--   -- Verify: incidents array ordered unresolved-first, critical-first.
--
-- V7: Notification dismissal
--   SELECT dismiss_plantilla_import_notification('<notification-id>');
--   SELECT status FROM public.plantilla_import_notifications
--    WHERE id = '<notification-id>';
--   -- Expect: status = 'dismissed'
--
-- V8: Severity grouping
--   SELECT severity, count(*) FROM public.plantilla_import_incidents
--    GROUP BY severity ORDER BY 1;
--
-- V9: Rollback safety rejection (ROLLBACK_UNSAFE path)
--   UPDATE public.plantilla_import_batches
--      SET status = 'rollback_failed',
--          rollback_error_detail = '[40001] ROLLBACK_UNSAFE: ...'
--    WHERE id = '<your-test-batch-id>';
--   SELECT incident_type FROM public.plantilla_import_incidents
--    WHERE batch_id = '<your-test-batch-id>'
--    ORDER BY created_at DESC LIMIT 1;
--   -- Expect: rollback_safety_rejection (not rollback_failed)
--
-- V10: Double-transition idempotency
--   Re-run the same status update — trigger should not create a second
--   incident because WHEN (OLD.status IS DISTINCT FROM NEW.status)
--   is false on re-apply.
-- ============================================================
