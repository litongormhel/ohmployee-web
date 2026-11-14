-- Migration: 20262606000116_dashboard_announcements_system.sql
-- Description: Unified Dashboard Announcements System with Realtime Broadcast and Push Notifications
-- Supports broadcast and targeted announcements, urgent acknowledgements, and multi-repo parity.

-- 1. Create announcements table
CREATE TABLE IF NOT EXISTS public.announcements (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title            text NOT NULL,
  content          text NOT NULL,
  priority         text NOT NULL DEFAULT 'info' CHECK (priority IN ('info', 'important', 'urgent')),
  is_pinned        boolean NOT NULL DEFAULT FALSE,
  status           text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'archived')),
  target_roles     text[] DEFAULT NULL,
  target_group_ids uuid[] DEFAULT NULL,
  expires_at       timestamptz DEFAULT NULL,
  created_by       uuid NOT NULL REFERENCES public.users_profile(id) ON DELETE CASCADE,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now()
);

-- Indexing for performance
CREATE INDEX IF NOT EXISTS idx_announcements_status_expires 
  ON public.announcements (status, expires_at);

CREATE INDEX IF NOT EXISTS idx_announcements_pinned_created 
  ON public.announcements (is_pinned DESC, created_at DESC);

-- 2. Create announcement acknowledgements table (one-time acknowledgement for urgent notices)
CREATE TABLE IF NOT EXISTS public.announcement_acknowledgements (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  announcement_id uuid NOT NULL REFERENCES public.announcements(id) ON DELETE CASCADE,
  user_id         uuid NOT NULL REFERENCES public.users_profile(id) ON DELETE CASCADE,
  acknowledged_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_announcement_user_ack UNIQUE (announcement_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_announcement_ack_lookup 
  ON public.announcement_acknowledgements (announcement_id, user_id);

-- 3. Enable Row Level Security (RLS)
ALTER TABLE public.announcements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.announcement_acknowledgements ENABLE ROW LEVEL SECURITY;

-- Announcements RLS Policies
DROP POLICY IF EXISTS pol_announcements_select ON public.announcements;
CREATE POLICY pol_announcements_select ON public.announcements
FOR SELECT TO authenticated
USING (
  public.i_have_full_access()
  OR (
    status = 'active'
    AND (expires_at IS NULL OR expires_at > now())
    AND (
      -- Role targeting (global if null/empty, or matches user's current role)
      (target_roles IS NULL OR cardinality(target_roles) = 0 OR public.get_my_role() = ANY(target_roles))
      -- Group targeting (global if null/empty, or matches user's group scopes)
      AND (
        target_group_ids IS NULL 
        OR cardinality(target_group_ids) = 0 
        OR EXISTS (
          SELECT 1 FROM public.user_scopes us 
          WHERE us.user_id = (SELECT up.id FROM public.users_profile up WHERE up.auth_user_id = auth.uid() LIMIT 1)
            AND us.group_id = ANY(target_group_ids)
        )
        OR EXISTS (
          SELECT 1 FROM public.users_profile up
          WHERE up.auth_user_id = auth.uid()
            AND up.group_id = ANY(target_group_ids)
        )
      )
    )
  )
);

DROP POLICY IF EXISTS pol_announcements_admin_mutations ON public.announcements;
CREATE POLICY pol_announcements_admin_mutations ON public.announcements
FOR ALL TO authenticated
USING (public.i_have_full_access())
WITH CHECK (public.i_have_full_access());

-- Acknowledgements RLS Policies
DROP POLICY IF EXISTS pol_announcement_ack_select ON public.announcement_acknowledgements;
CREATE POLICY pol_announcement_ack_select ON public.announcement_acknowledgements
FOR SELECT TO authenticated
USING (
  public.i_have_full_access()
  OR user_id = (SELECT up.id FROM public.users_profile up WHERE up.auth_user_id = auth.uid() LIMIT 1)
);

DROP POLICY IF EXISTS pol_announcement_ack_insert ON public.announcement_acknowledgements;
CREATE POLICY pol_announcement_ack_insert ON public.announcement_acknowledgements
FOR INSERT TO authenticated
WITH CHECK (
  user_id = (SELECT up.id FROM public.users_profile up WHERE up.auth_user_id = auth.uid() LIMIT 1)
);

-- 4. Automatic In-App & Mobile Push Notification Dispatch on Announcement Publication
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
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_after_announcement_notify ON public.announcements;
CREATE TRIGGER trg_after_announcement_notify
AFTER INSERT OR UPDATE ON public.announcements
FOR EACH ROW
EXECUTE FUNCTION public.trg_announcement_notify();

-- 5. Add to Supabase Realtime publication
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' 
      AND schemaname = 'public' 
      AND tablename = 'announcements'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.announcements;
  END IF;
END $$;
