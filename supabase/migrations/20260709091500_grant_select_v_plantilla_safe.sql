-- Migration: 20260709091500_grant_select_v_plantilla_safe.sql
-- Purpose: Restore SELECT permissions on public.v_plantilla_safe view after drop/recreate CASCADE.

GRANT SELECT ON public.v_plantilla_safe TO authenticated, service_role, anon;
