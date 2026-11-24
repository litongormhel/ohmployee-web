-- Migration: 20262606000180_fix_announcements_grants_and_creator_resolution.sql
-- Created: 2026-11-24T15:44:07.028Z
-- Description: Fix announcements table grants, auto-resolve creator, safe notification fan-out, and dedicated RPC

BEGIN;

-- 1. Explicit Table Permissions for PostgREST Authenticated and Service Roles
GRANT ALL ON TABLE public.announcements TO authenticated, service_role;
GRANT ALL ON TABLE public.announcement_acknowledgements TO authenticated, service_role;
GRANT SELECT ON TABLE public.announcements TO anon;

-- 2. Ensure Sequence / ID permissions if applicable
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO authenticated, service_role;

-- 3. Automatic Created By Profile Resolution Trigger
CREATE OR REPLACE FUNCTION public.fn_announcements_resolve_creator()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  -- If created_by is omitted, attempt resolving from current auth session
  IF NEW.created_by IS NULL THEN
    SELECT id INTO NEW.created_by
    FROM public.users_profile
    WHERE auth_user_id = auth.uid()
    LIMIT 1;
  END IF;

  -- Fallback to system admin profile if executing in background / unmapped service role
  IF NEW.created_by IS NULL THEN
    SELECT id INTO NEW.created_by
    FROM public.users_profile
    WHERE role IN ('Super Admin', 'Head Admin')
    LIMIT 1;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_announcements_before_insert ON public.announcements;
CREATE TRIGGER trg_announcements_before_insert
BEFORE INSERT ON public.announcements
FOR EACH ROW
EXECUTE FUNCTION public.fn_announcements_resolve_creator();

-- 4. Hardened Notification Dispatch Trigger (Safe Non-Blocking Fan-Out)
CREATE OR REPLACE FUNCTION public.trg_announcement_notify()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_role_row record;
  v_role_target text;
  v_clean_title text;
  v_clean_msg text;
BEGIN
  -- Trigger only when announcement becomes active
  IF (TG_OP = 'INSERT' AND NEW.status = 'active') OR
     (TG_OP = 'UPDATE' AND OLD.status != 'active' AND NEW.status = 'active') THEN
    
    v_clean_title := '📢 ' || NEW.title;
    v_clean_msg := substring(NEW.content, 1, 180);

    BEGIN
      IF NEW.target_roles IS NOT NULL AND cardinality(NEW.target_roles) > 0 THEN
        -- Fan out strictly to specified target roles
        FOREACH v_role_target IN ARRAY NEW.target_roles LOOP
          INSERT INTO public.notifications (
            recipient_role,
            title,
            message,
            notification_type,
            event_type,
            reference_type,
            reference_id,
            deep_link_route,
            is_read,
            is_archived
          ) VALUES (
            v_role_target,
            v_clean_title,
            v_clean_msg,
            'announcement',
            'announcement_published',
            'announcement',
            NEW.id::text,
            '/dashboard',
            FALSE,
            FALSE
          );
        END LOOP;
      ELSE
        -- Global broadcast: fan out to all active roles
        FOR v_role_row IN SELECT DISTINCT role_name FROM public.roles LOOP
          INSERT INTO public.notifications (
            recipient_role,
            title,
            message,
            notification_type,
            event_type,
            reference_type,
            reference_id,
            deep_link_route,
            is_read,
            is_archived
          ) VALUES (
            v_role_row.role_name,
            v_clean_title,
            v_clean_msg,
            'announcement',
            'announcement_published',
            'announcement',
            NEW.id::text,
            '/dashboard',
            FALSE,
            FALSE
          );
        END LOOP;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'trg_announcement_notify: Notification dispatch warning: %', SQLERRM;
    END;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_after_announcement_notify ON public.announcements;
CREATE TRIGGER trg_after_announcement_notify
AFTER INSERT OR UPDATE ON public.announcements
FOR EACH ROW
EXECUTE FUNCTION public.trg_announcement_notify();

-- 5. Dedicated High-Reliability Announcement Creation RPC
CREATE OR REPLACE FUNCTION public.create_announcement(
  p_title text,
  p_content text,
  p_priority text DEFAULT 'info',
  p_is_pinned boolean DEFAULT FALSE,
  p_target_roles text[] DEFAULT NULL,
  p_target_group_ids uuid[] DEFAULT NULL,
  p_expires_at timestamptz DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_creator_id uuid;
  v_row record;
BEGIN
  IF NOT public.i_have_full_access() THEN
    RAISE EXCEPTION 'Access denied: Super Admin or Head Admin required to publish announcements.'
      USING ERRCODE = '42501';
  END IF;

  SELECT id INTO v_creator_id
  FROM public.users_profile
  WHERE auth_user_id = auth.uid()
  LIMIT 1;

  IF v_creator_id IS NULL THEN
    SELECT id INTO v_creator_id
    FROM public.users_profile
    WHERE role IN ('Super Admin', 'Head Admin')
    LIMIT 1;
  END IF;

  INSERT INTO public.announcements (
    title,
    content,
    priority,
    is_pinned,
    status,
    target_roles,
    target_group_ids,
    expires_at,
    created_by
  ) VALUES (
    trim(p_title),
    trim(p_content),
    COALESCE(p_priority, 'info'),
    COALESCE(p_is_pinned, FALSE),
    'active',
    p_target_roles,
    p_target_group_ids,
    p_expires_at,
    v_creator_id
  ) RETURNING * INTO v_row;

  RETURN to_jsonb(v_row);
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_announcement(text, text, text, boolean, text[], uuid[], timestamptz) TO authenticated, service_role;

COMMIT;
