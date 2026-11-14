-- Phase 1.6: wrap remaining bare scope-check calls in plantilla_read_scoped
-- (i_can_view_plantilla, i_am_hrco_only, i_have_hrco_global_visibility, get_my_role_level)
-- confirmed the dominant cost (~4.8s of 5.5s) in the live OM/BANKO shadow-view query.
-- All 4 functions confirmed STABLE via pg_proc.provolatile before this migration.
-- Structure/logic unchanged — text-identical except each bare call wrapped as (select ...).

DROP POLICY IF EXISTS plantilla_read_scoped ON public.plantilla;
CREATE POLICY plantilla_read_scoped ON public.plantilla
FOR SELECT
TO public
USING (
  (select i_can_view_plantilla())
  AND (
    (select i_have_full_access())
    OR (
      (NOT (select i_am_hrco_only()))
      AND (
        (account = ANY ((select get_my_allowed_accounts())::text[]))
        OR (
          (is_pool_employee = true)
          AND (
            ((select get_my_role_level()) = 20)
            OR ((select get_my_role_level()) = 30)
            OR ((select get_my_role_level()) >= 90)
            OR (((select get_my_role_level()) >= 40) AND ((select get_my_role_level()) <= 70))
          )
        )
      )
    )
    OR (
      (select i_am_hrco_only())
      AND (
        (
          (select i_have_hrco_global_visibility())
          AND (account = ANY ((select get_my_allowed_accounts())::text[]))
        )
        OR (
          EXISTS (
            SELECT 1 FROM plantilla_hrco_assignments pha
            WHERE (pha.plantilla_id = plantilla.id)
              AND (pha.hrco_user_id = auth.uid())
              AND pha.is_active
          )
        )
      )
    )
  )
  AND (COALESCE(is_deleted, false) = false)
  AND ((deactivated_visible_until IS NULL) OR (deactivated_visible_until > now()))
);
