-- RLS InitPlan wrap — Plantilla module, full pass (ohm#7n3wk8qm).
-- Wraps bare scope-check function calls as (select fn()) so Postgres caches one
-- evaluation per query instead of re-evaluating per row. Same category as Phase 1/2
-- (ohm#3xk7m2wq / ohm#5n8wq3vt) but covers functions never in scope before: i_am_ops,
-- i_am_recruitment, i_am_data_team, i_am_hrco_only, get_my_scoped_vcodes,
-- get_my_full_name, get_my_profile_id, get_my_role, get_my_role_level.
-- All wrapped functions confirmed STABLE via pg_proc.provolatile before this migration.
-- Text/logic identical to the live bare policies except for the wrap. Verified on
-- staging via rolled-back-transaction row-count+md5 fingerprint A/B across Head
-- Admin/OM/HRCO (93/93 combinations byte-identical across the qual-bearing policies
-- below) before this file was authored. WITH CHECK-only (INSERT) policies were
-- verified by mechanical equivalence instead of row-level testing: wrapping a 0-arg
-- STABLE function call in (select fn()) is provably value-identical to the bare call
-- within one statement/snapshot — this is a Postgres STABLE-volatility guarantee, not
-- an empirical claim — so no separate insert-side fingerprint test was run.
--
-- Functions intentionally left bare (out of this prompt's audited-function scope,
-- not verified STABLE this session): i_am_encoder, i_am_hr_dept, i_am_backoffice,
-- i_can_act_on_plantilla, get_current_profile_id, i_am_assigned_to_vacancy.
--
-- Deviation found vs. this prompt's original table list (live pg_policies is
-- authoritative, per the mandated methodology): account_request_account_scopes and
-- account_request_group_scopes have RLS ENABLED but ZERO policies defined on staging
-- (default-deny for all non-superuser roles) — the prompt's named policies
-- "aras_select_admin_only" / "args_select_admin_only" do not exist. Nothing to wrap;
-- flagged to Ohm rather than fabricating new policies (out of this prompt's scope).

-- plantilla_insert_scoped: PERMISSIVE, INSERT, public (i_am_hr_dept() left bare — out of scope)
DROP POLICY IF EXISTS plantilla_insert_scoped ON public.plantilla;
CREATE POLICY plantilla_insert_scoped ON public.plantilla
FOR INSERT
TO public
WITH CHECK (
  (select i_have_full_access())
  OR (
    (NOT (select i_am_recruitment()))
    AND (NOT i_am_hr_dept())
    AND (account = ANY ((select get_my_allowed_accounts())::text[]))
  )
);

-- approvals_insert_admin: PERMISSIVE, INSERT, public
DROP POLICY IF EXISTS approvals_insert_admin ON public.plantilla_approvals;
CREATE POLICY approvals_insert_admin ON public.plantilla_approvals
FOR INSERT
TO public
WITH CHECK ((select i_have_full_access()));

-- approvals_read_admin: PERMISSIVE, SELECT, public
DROP POLICY IF EXISTS approvals_read_admin ON public.plantilla_approvals;
CREATE POLICY approvals_read_admin ON public.plantilla_approvals
FOR SELECT
TO public
USING ((select i_have_full_access()));

-- approvals_update_admin: PERMISSIVE, UPDATE, public
DROP POLICY IF EXISTS approvals_update_admin ON public.plantilla_approvals;
CREATE POLICY approvals_update_admin ON public.plantilla_approvals
FOR UPDATE
TO public
USING ((select i_have_full_access()));

-- hrco_assignments_read_scoped: PERMISSIVE, SELECT, public
DROP POLICY IF EXISTS hrco_assignments_read_scoped ON public.plantilla_hrco_assignments;
CREATE POLICY hrco_assignments_read_scoped ON public.plantilla_hrco_assignments
FOR SELECT
TO public
USING (
  (select i_have_full_access())
  OR (select i_am_data_team())
  OR ((select i_am_hrco_only()) AND (hrco_user_id = auth.uid()))
);

-- employees_read_scoped: PERMISSIVE, SELECT, authenticated
DROP POLICY IF EXISTS employees_read_scoped ON public.employees;
CREATE POLICY employees_read_scoped ON public.employees
FOR SELECT
TO authenticated
USING (
  (select i_have_full_access())
  OR (account = ANY ((select get_my_allowed_accounts())::text[]))
);

-- employees_write_scoped: PERMISSIVE, ALL, authenticated
DROP POLICY IF EXISTS employees_write_scoped ON public.employees;
CREATE POLICY employees_write_scoped ON public.employees
FOR ALL
TO authenticated
USING (
  (select i_have_full_access())
  OR (account = ANY ((select get_my_allowed_accounts())::text[]))
);

-- activity_log_insert_auth: PERMISSIVE, INSERT, authenticated
DROP POLICY IF EXISTS activity_log_insert_auth ON public.employee_activity_log;
CREATE POLICY activity_log_insert_auth ON public.employee_activity_log
FOR INSERT
TO authenticated
WITH CHECK (performed_by = (select get_my_full_name()));

-- deact_audit_v2_read: PERMISSIVE, SELECT, authenticated (i_am_backoffice() left bare — out of scope)
DROP POLICY IF EXISTS deact_audit_v2_read ON public.employee_deactivation_audit_log;
CREATE POLICY deact_audit_v2_read ON public.employee_deactivation_audit_log
FOR SELECT
TO authenticated
USING (
  (select i_have_full_access())
  OR i_am_backoffice()
);

-- deact_req_v2_read_scoped: PERMISSIVE, SELECT, authenticated (i_am_backoffice()/get_current_profile_id() left bare — out of scope)
DROP POLICY IF EXISTS deact_req_v2_read_scoped ON public.employee_deactivation_requests;
CREATE POLICY deact_req_v2_read_scoped ON public.employee_deactivation_requests
FOR SELECT
TO authenticated
USING (
  (select i_have_full_access())
  OR i_am_backoffice()
  OR ((select i_am_ops()) AND (requestor_profile_id = get_current_profile_id()))
);

-- deployments_read_scoped: PERMISSIVE, SELECT, authenticated
DROP POLICY IF EXISTS deployments_read_scoped ON public.employee_deployments;
CREATE POLICY deployments_read_scoped ON public.employee_deployments
FOR SELECT
TO authenticated
USING (
  (select i_have_full_access())
  OR (account = ANY ((select get_my_allowed_accounts())::text[]))
);

-- deployments_write_admin: PERMISSIVE, ALL, authenticated
DROP POLICY IF EXISTS deployments_write_admin ON public.employee_deployments;
CREATE POLICY deployments_write_admin ON public.employee_deployments
FOR ALL
TO authenticated
USING ((select i_have_full_access()));

-- pol_transfer_encoder_only_insert: RESTRICTIVE, INSERT, authenticated — preserve AS RESTRICTIVE
DROP POLICY IF EXISTS pol_transfer_encoder_only_insert ON public.employee_transfers;
CREATE POLICY pol_transfer_encoder_only_insert ON public.employee_transfers
AS RESTRICTIVE
FOR INSERT
TO authenticated
WITH CHECK (
  (select get_my_role()) = ANY (ARRAY['Encoder'::text, 'Super Admin'::text, 'Head Admin'::text, 'OM'::text, 'HRCO'::text, 'Recruitment'::text])
);

-- transfers_insert_scoped: PERMISSIVE, INSERT, public
DROP POLICY IF EXISTS transfers_insert_scoped ON public.employee_transfers;
CREATE POLICY transfers_insert_scoped ON public.employee_transfers
FOR INSERT
TO public
WITH CHECK (
  (select i_have_full_access())
  OR (requested_by = (select get_my_full_name()))
);

-- transfers_read_scoped: PERMISSIVE, SELECT, authenticated
DROP POLICY IF EXISTS transfers_read_scoped ON public.employee_transfers;
CREATE POLICY transfers_read_scoped ON public.employee_transfers
FOR SELECT
TO authenticated
USING (
  (select i_have_full_access())
  OR (requested_by = (select get_my_full_name()))
);

-- deact_audit_insert_auth: PERMISSIVE, INSERT, authenticated
DROP POLICY IF EXISTS deact_audit_insert_auth ON public.deactivation_audit_log;
CREATE POLICY deact_audit_insert_auth ON public.deactivation_audit_log
FOR INSERT
TO authenticated
WITH CHECK (performed_by = (select get_my_full_name()));

-- deact_audit_read_admin: PERMISSIVE, SELECT, authenticated
DROP POLICY IF EXISTS deact_audit_read_admin ON public.deactivation_audit_log;
CREATE POLICY deact_audit_read_admin ON public.deactivation_audit_log
FOR SELECT
TO authenticated
USING ((select i_have_full_access()));

-- deact_batches_read_scoped: PERMISSIVE, SELECT, authenticated
DROP POLICY IF EXISTS deact_batches_read_scoped ON public.deactivation_batches;
CREATE POLICY deact_batches_read_scoped ON public.deactivation_batches
FOR SELECT
TO authenticated
USING (
  (select i_have_full_access())
  OR (created_by = (select get_my_full_name()))
);

-- deact_batches_write_admin: PERMISSIVE, ALL, authenticated
DROP POLICY IF EXISTS deact_batches_write_admin ON public.deactivation_batches;
CREATE POLICY deact_batches_write_admin ON public.deactivation_batches
FOR ALL
TO authenticated
USING ((select i_have_full_access()));

-- deact_items_read_scoped: PERMISSIVE, SELECT, authenticated
DROP POLICY IF EXISTS deact_items_read_scoped ON public.deactivation_items;
CREATE POLICY deact_items_read_scoped ON public.deactivation_items
FOR SELECT
TO authenticated
USING (
  (select i_have_full_access())
  OR (account = ANY ((select get_my_allowed_accounts())::text[]))
);

-- deact_items_write_admin: PERMISSIVE, ALL, authenticated
DROP POLICY IF EXISTS deact_items_write_admin ON public.deactivation_items;
CREATE POLICY deact_items_write_admin ON public.deactivation_items
FOR ALL
TO authenticated
USING ((select i_have_full_access()));

-- deact_req_insert_ops_only: PERMISSIVE, INSERT, public
DROP POLICY IF EXISTS deact_req_insert_ops_only ON public.deactivation_requests;
CREATE POLICY deact_req_insert_ops_only ON public.deactivation_requests
FOR INSERT
TO public
WITH CHECK (
  (select i_have_full_access())
  OR ((select i_am_ops()) AND (requested_by = (select get_my_full_name())))
);

-- deact_requests_read_scoped: PERMISSIVE, SELECT, authenticated
DROP POLICY IF EXISTS deact_requests_read_scoped ON public.deactivation_requests;
CREATE POLICY deact_requests_read_scoped ON public.deactivation_requests
FOR SELECT
TO authenticated
USING (
  (select i_have_full_access())
  OR (requested_by = (select get_my_full_name()))
);

-- account_positions_write_data_team: PERMISSIVE, ALL, authenticated
DROP POLICY IF EXISTS account_positions_write_data_team ON public.account_positions;
CREATE POLICY account_positions_write_data_team ON public.account_positions
FOR ALL
TO authenticated
USING ((select get_my_role_level()) >= 30)
WITH CHECK ((select get_my_role_level()) >= 30);

-- agt_history_select: PERMISSIVE, SELECT, authenticated
DROP POLICY IF EXISTS agt_history_select ON public.account_group_transfer_request_history;
CREATE POLICY agt_history_select ON public.account_group_transfer_request_history
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM account_group_transfer_requests r
    WHERE (r.id = account_group_transfer_request_history.request_id)
      AND ((select i_have_full_access()) OR ((select get_my_role_level()) >= 90))
  )
);

-- agt_select_scoped: PERMISSIVE, SELECT, authenticated
DROP POLICY IF EXISTS agt_select_scoped ON public.account_group_transfer_requests;
CREATE POLICY agt_select_scoped ON public.account_group_transfer_requests
FOR SELECT
TO authenticated
USING (
  (select i_have_full_access())
  OR ((select get_my_role_level()) >= 90)
);

-- roving_assignments_insert: PERMISSIVE, INSERT, authenticated
DROP POLICY IF EXISTS roving_assignments_insert ON public.roving_assignments;
CREATE POLICY roving_assignments_insert ON public.roving_assignments
FOR INSERT
TO authenticated
WITH CHECK (
  (select i_have_full_access())
  OR (account = ANY ((select get_my_allowed_accounts())::text[]))
);

-- roving_assignments_select: PERMISSIVE, SELECT, authenticated
DROP POLICY IF EXISTS roving_assignments_select ON public.roving_assignments;
CREATE POLICY roving_assignments_select ON public.roving_assignments
FOR SELECT
TO authenticated
USING (
  (select i_have_full_access())
  OR (account = ANY ((select get_my_allowed_accounts())::text[]))
);

-- roving_assignments_update: PERMISSIVE, UPDATE, authenticated
DROP POLICY IF EXISTS roving_assignments_update ON public.roving_assignments;
CREATE POLICY roving_assignments_update ON public.roving_assignments
FOR UPDATE
TO authenticated
USING (
  (select i_have_full_access())
  OR (account = ANY ((select get_my_allowed_accounts())::text[]))
)
WITH CHECK (
  (select i_have_full_access())
  OR (account = ANY ((select get_my_allowed_accounts())::text[]))
);

-- ghost_employees_read_ops_scoped: PERMISSIVE, SELECT, public
DROP POLICY IF EXISTS ghost_employees_read_ops_scoped ON public.possible_ghost_employees;
CREATE POLICY ghost_employees_read_ops_scoped ON public.possible_ghost_employees
FOR SELECT
TO public
USING (
  (select i_have_full_access())
  OR ((select i_am_ops()) AND (account = ANY ((select get_my_allowed_accounts())::text[])))
);

-- ghost_employees_write_admin: PERMISSIVE, ALL, public
DROP POLICY IF EXISTS ghost_employees_write_admin ON public.possible_ghost_employees;
CREATE POLICY ghost_employees_write_admin ON public.possible_ghost_employees
FOR ALL
TO public
USING (
  (select i_have_full_access())
  OR (((select get_my_role_level()) = 30) AND (account = ANY ((select get_my_allowed_accounts())::text[])))
);

-- ash_read_scoped: PERMISSIVE, SELECT, authenticated
DROP POLICY IF EXISTS ash_read_scoped ON public.applicant_status_history;
CREATE POLICY ash_read_scoped ON public.applicant_status_history
FOR SELECT
TO authenticated
USING (
  (select i_have_full_access())
  OR ((select get_my_role_level()) = 30)
  OR (EXISTS (
    SELECT 1 FROM applicants a JOIN vacancies v ON (v.vcode = a.vacancy_vcode)
    WHERE (a.id = applicant_status_history.applicant_id)
      AND (v.account = ANY ((select get_my_allowed_accounts())::text[]))
      AND (v.deleted_at IS NULL)
  ))
);

-- amr_select_own: PERMISSIVE, SELECT, public
DROP POLICY IF EXISTS amr_select_own ON public.applicant_movement_requests;
CREATE POLICY amr_select_own ON public.applicant_movement_requests
FOR SELECT
TO public
USING (
  (requested_by = (SELECT users_profile.id FROM users_profile WHERE users_profile.auth_user_id = auth.uid()))
  OR (select i_have_full_access())
  OR ((select get_my_role_level()) >= 30)
);

-- amr_history_select: PERMISSIVE, SELECT, public
DROP POLICY IF EXISTS amr_history_select ON public.applicant_movement_request_history;
CREATE POLICY amr_history_select ON public.applicant_movement_request_history
FOR SELECT
TO public
USING (
  EXISTS (
    SELECT 1 FROM applicant_movement_requests r
    WHERE (r.id = applicant_movement_request_history.request_id)
      AND (
        (r.requested_by = (SELECT users_profile.id FROM users_profile WHERE users_profile.auth_user_id = auth.uid()))
        OR (select i_have_full_access())
        OR ((select get_my_role_level()) >= 30)
      )
  )
);

-- apch_read_scoped: PERMISSIVE, SELECT, authenticated
DROP POLICY IF EXISTS apch_read_scoped ON public.applicant_profile_change_history;
CREATE POLICY apch_read_scoped ON public.applicant_profile_change_history
FOR SELECT
TO authenticated
USING (
  (select i_have_full_access())
  OR ((select get_my_role_level()) = 30)
  OR (EXISTS (
    SELECT 1 FROM applicants a JOIN vacancies v ON (v.vcode = a.vacancy_vcode)
    WHERE (a.id = applicant_profile_change_history.applicant_id)
      AND (v.account = ANY ((select get_my_allowed_accounts())::text[]))
  ))
);

-- apeh_select_scoped: PERMISSIVE, SELECT, authenticated
DROP POLICY IF EXISTS apeh_select_scoped ON public.applicant_profile_edit_history;
CREATE POLICY apeh_select_scoped ON public.applicant_profile_edit_history
FOR SELECT
TO authenticated
USING (
  (select i_have_full_access())
  OR ((select get_my_role_level()) = 30)
  OR (EXISTS (
    SELECT 1 FROM applicants a JOIN vacancies v ON (v.vcode = a.vacancy_vcode)
    WHERE (a.id = applicant_profile_edit_history.applicant_id)
      AND (v.account = ANY ((select get_my_allowed_accounts())::text[]))
      AND (v.deleted_at IS NULL)
  ))
);

-- aper_read_scoped: PERMISSIVE, SELECT, authenticated
DROP POLICY IF EXISTS aper_read_scoped ON public.applicant_profile_edit_requests;
CREATE POLICY aper_read_scoped ON public.applicant_profile_edit_requests
FOR SELECT
TO authenticated
USING (
  (select i_have_full_access())
  OR ((select get_my_role_level()) = 30)
  OR (requested_by = (select get_my_profile_id()))
  OR (EXISTS (
    SELECT 1 FROM applicants a JOIN vacancies v ON (v.vcode = a.vacancy_vcode)
    WHERE (a.id = applicant_profile_edit_requests.applicant_id)
      AND (v.account = ANY ((select get_my_allowed_accounts())::text[]))
  ))
);

-- applicants_insert_ops_only: PERMISSIVE, INSERT, public
DROP POLICY IF EXISTS applicants_insert_ops_only ON public.applicants;
CREATE POLICY applicants_insert_ops_only ON public.applicants
FOR INSERT
TO public
WITH CHECK (
  (
    (select i_have_full_access())
    OR (
      (select i_am_recruitment())
      AND EXISTS (
        SELECT 1 FROM vacancies v
        WHERE (v.vcode = applicants.vacancy_vcode) AND (v.is_pool_vacancy = true) AND (v.deleted_at IS NULL)
      )
    )
    OR (
      ((select i_am_ops()) OR (select i_am_recruitment()))
      AND (vacancy_vcode IN (
        SELECT v.vcode FROM vacancies v
        WHERE (v.account = ANY ((select get_my_allowed_accounts())::text[]))
          AND (v.deleted_at IS NULL)
          AND (NOT COALESCE(v.is_pool_vacancy, false))
      ))
    )
    OR (
      (select i_am_ops())
      AND EXISTS (
        SELECT 1 FROM vacancies v
        WHERE (v.vcode = applicants.vacancy_vcode)
          AND (v.is_pool_vacancy = true)
          AND (COALESCE(v.is_ops_request, false) = true)
          AND (v.account = ANY ((select get_my_allowed_accounts())::text[]))
          AND (v.deleted_at IS NULL)
      )
    )
  )
  AND NOT EXISTS (
    SELECT 1 FROM vacancies v
    WHERE (v.vcode = applicants.vacancy_vcode) AND (v.has_pending_closure = true) AND (v.deleted_at IS NULL)
  )
);

-- applicants_read_scoped: PERMISSIVE, SELECT, public
DROP POLICY IF EXISTS applicants_read_scoped ON public.applicants;
CREATE POLICY applicants_read_scoped ON public.applicants
FOR SELECT
TO public
USING (
  (select i_have_full_access())
  OR (vacancy_vcode = ANY ((select get_my_scoped_vcodes())::text[]))
  OR (
    EXISTS (
      SELECT 1 FROM vacancies v
      WHERE (v.vcode = applicants.vacancy_vcode) AND (v.is_pool_vacancy = true) AND (v.deleted_at IS NULL)
    )
    AND (
      ((select get_my_role_level()) = 20)
      OR ((select get_my_role_level()) = 30)
      OR ((select get_my_role_level()) >= 90)
    )
  )
);

-- applicants_update_ops_recruitment: PERMISSIVE, UPDATE, public
DROP POLICY IF EXISTS applicants_update_ops_recruitment ON public.applicants;
CREATE POLICY applicants_update_ops_recruitment ON public.applicants
FOR UPDATE
TO public
USING (
  (select i_have_full_access())
  OR (
    (select i_am_recruitment())
    AND EXISTS (
      SELECT 1 FROM vacancies v
      WHERE (v.vcode = applicants.vacancy_vcode) AND (v.is_pool_vacancy = true) AND (v.deleted_at IS NULL)
    )
  )
  OR (
    ((select i_am_ops()) OR (select i_am_recruitment()))
    AND (vacancy_vcode IN (
      SELECT v.vcode FROM vacancies v
      WHERE (v.account = ANY ((select get_my_allowed_accounts())::text[]))
        AND (v.deleted_at IS NULL)
        AND (NOT COALESCE(v.is_pool_vacancy, false))
    ))
  )
);
