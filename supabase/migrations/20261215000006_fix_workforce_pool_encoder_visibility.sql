-- Migration: 20261215000006_fix_workforce_pool_encoder_visibility.sql
-- Goal: Fix Encoder (Data Team) visibility regression on Workforce Pool data

DROP POLICY IF EXISTS "plantilla_read_scoped" ON public.plantilla;

CREATE POLICY "plantilla_read_scoped" ON "public"."plantilla"
FOR SELECT TO authenticated
USING (
  public.i_can_view_plantilla()
  AND (
    public.i_have_full_access()
    OR (account = ANY (public.get_my_allowed_accounts()))
    OR (
      is_pool_employee = true
      AND (
        public.get_my_role_level() = 20
        OR public.get_my_role_level() = 30
        OR public.get_my_role_level() >= 90
      )
    )
  )
  AND (COALESCE(is_deleted, false) = false)
  AND ((deactivated_visible_until IS NULL) OR (deactivated_visible_until > now()))
);
