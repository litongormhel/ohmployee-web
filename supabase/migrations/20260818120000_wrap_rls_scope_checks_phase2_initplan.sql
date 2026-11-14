-- ============================================================
-- ohm#5n8wq3vt — RLS InitPlan-wrapping fix, Phase 2 (31 tables)
-- Migration: 20260818120000_wrap_rls_scope_checks_phase2_initplan.sql
-- ============================================================
-- Context
-- -------
-- Continuation of ohm#3xk7m2wq Phase 1 (5 highest-risk tables:
-- stores, plantilla, plantilla_slots, slot_history, vacancies — now
-- LIVE on both staging and production, verified byte-identical).
--
-- Phase 1's own header estimated "~35 lower-risk tables" remaining
-- from the original Part B inventory. Re-pulled live via pg_policies
-- for this prompt (per standing instruction: never assume a stale
-- inventory) and found the real remaining surface is 92 tables / ~135
-- policies, not ~35 — Part B undercounted or new tables/policies were
-- added since 2026-08-17. Given the scale, this phase covers the top
-- 30 remaining tables by live row count (31 tables — two tied at 37
-- rows, both included): plantilla_import_rows (10,055) down through
-- new_store_requests/sla_breach_logs (37). The remaining ~61 tables
-- (mostly 0-20 rows: QA/ops scaffolding, deactivation stubs, empty
-- staging tables) are deferred to a future Phase 3.
--
-- Scope of the change, precisely
-- -------------------------------
-- Same 4-function scope as Phase 1, re-confirmed STABLE + 0-arg live
-- via pg_proc.provolatile immediately before drafting this migration:
-- i_have_full_access(), get_my_allowed_accounts() (returns text[]),
-- get_my_allowed_account_ids() (returns uuid[]), get_my_role()
-- (returns text). Every bare (unwrapped) call to these 4 functions in
-- the 40 policies below is rewritten as `(select fn())`.
--
-- ANY(fn()) cast gotcha (same fix as Phase 1): `col = ANY(fn())` is
-- rewritten as `col = ANY((select fn())::text[])` /
-- `::uuid[]` — a bare `(select ...)` immediately inside `ANY(...)` is
-- parsed as the scalar-subquery form of ANY, not the array form, and
-- throws `operator does not exist: type = type[]`. Does NOT apply to
-- `get_my_role() = ANY (ARRAY['Super Admin', ...])` sites
-- (sla_breach_read, vacancy_edit_lock_audit's SA/HA read policy) —
-- there the array is a literal on the right-hand side of `= ANY`, not
-- a function-returning-array as the direct ANY() argument, so no cast
-- is needed; only the scalar `get_my_role()` call itself is wrapped.
--
-- RESTRICTIVE-policy gotcha (same defect class Phase 1 caught and
-- fixed): hr_emploc_hide_deleted is the only RESTRICTIVE policy in
-- this batch (confirmed live via pg_policies.permissive =
-- 'RESTRICTIVE' before drafting this migration). Postgres has no
-- CREATE OR REPLACE POLICY; a bare CREATE POLICY after DROP defaults
-- to PERMISSIVE. This migration's CREATE POLICY for
-- hr_emploc_hide_deleted carries `AS RESTRICTIVE` explicitly to avoid
-- silently flipping it PERMISSIVE (which would OR-broaden instead of
-- AND-narrow visibility of soft-deleted rows to non-full-access
-- roles). Verified via explicit live `pg_policies.permissive` check
-- both before and after apply (not folded into the general row-set
-- diff — see correctness-equivalence report, ohm#5n8wq3vt).
--
-- Explicitly NOT wrapped, by design (out of authorized function
-- scope for this migration family, same exclusion rule as Phase 1):
--   - get_my_role_level(), i_am_ops(), i_am_recruitment(),
--     get_current_profile_id(), get_my_scoped_vcodes(),
--     get_my_full_name(), get_my_profile_id(), is_super_admin(),
--     auth.uid(), auth.role() all appear bare in one or more of these
--     policies too, but are outside this migration's authorized
--     function scope — untouched.
--   - No row-correlated calls (e.g. i_am_assigned_to_vacancy(id)-
--     style) were found among the 4 eligible functions in this batch
--     — nothing excluded on that basis this phase.
--
-- This is a text-only rewrite of policy qual/with_check expressions.
-- No function body is touched. No semantic/authorization change once
-- fn() is confirmed STABLE (re-verified live for this phase) and the
-- ANY-over-array cast + RESTRICTIVE-flag gotchas above are respected.
-- Only latency should change.
--
-- Correctness-equivalence verification performed BEFORE this
-- migration is applied (see .ai/handoff.md, ohm#5n8wq3vt): rolled-
-- back-transaction row-id-set diffs for SA/OM/HRCO test identities
-- across all 31 tables (93 comparisons), WITH CHECK accept/reject
-- parity for the 5 policies that carry one (applicants_insert_ops_
-- only, hcreq_insert_ops_scoped, qa_findings_write,
-- wps_write_data_team), and an explicit RESTRICTIVE-flag assertion on
-- hr_emploc_hide_deleted.
--
-- Migration mechanism matches Phase 1 and this codebase's existing
-- convention for RLS-policy-only changes: DROP POLICY IF EXISTS +
-- CREATE POLICY, preserving each policy's FOR/TO/roles exactly as
-- currently defined. Postgres has no CREATE OR REPLACE POLICY.
-- ============================================================

-- ── account_positions ───────────────────────────────────────────

DROP POLICY IF EXISTS "account_positions_read_scoped" ON public.account_positions;
CREATE POLICY "account_positions_read_scoped" ON public.account_positions
FOR SELECT TO authenticated
USING (
  (select i_have_full_access())
  OR (account_id IN (
    SELECT accounts.id FROM public.accounts
    WHERE (accounts.account_code = ANY ((select get_my_allowed_accounts())::text[]))
  ))
);

-- ── accounts ─────────────────────────────────────────────────────

DROP POLICY IF EXISTS "accounts_write_admin" ON public.accounts;
CREATE POLICY "accounts_write_admin" ON public.accounts
FOR ALL TO public
USING ((select i_have_full_access()));

-- ── activity_log ─────────────────────────────────────────────────

DROP POLICY IF EXISTS "audit_log_select" ON public.activity_log;
CREATE POLICY "audit_log_select" ON public.activity_log
FOR SELECT TO public
USING ((select i_have_full_access()));

-- ── applicant_status_history ────────────────────────────────────

DROP POLICY IF EXISTS "ash_read_scoped" ON public.applicant_status_history;
CREATE POLICY "ash_read_scoped" ON public.applicant_status_history
FOR SELECT TO authenticated
USING (
  (select i_have_full_access())
  OR (get_my_role_level() = 30)
  OR (EXISTS (
    SELECT 1 FROM public.applicants a
    JOIN public.vacancies v ON (v.vcode = a.vacancy_vcode)
    WHERE (a.id = applicant_status_history.applicant_id)
      AND (v.account = ANY ((select get_my_allowed_accounts())::text[]))
      AND (v.deleted_at IS NULL)
  ))
);

-- ── applicants ───────────────────────────────────────────────────

DROP POLICY IF EXISTS "applicants_insert_ops_only" ON public.applicants;
CREATE POLICY "applicants_insert_ops_only" ON public.applicants
FOR INSERT TO public
WITH CHECK (
  (
    (select i_have_full_access())
    OR (i_am_recruitment() AND (EXISTS (
      SELECT 1 FROM public.vacancies v
      WHERE (v.vcode = applicants.vacancy_vcode) AND (v.is_pool_vacancy = true) AND (v.deleted_at IS NULL)
    )))
    OR ((i_am_ops() OR i_am_recruitment()) AND (vacancy_vcode IN (
      SELECT v.vcode FROM public.vacancies v
      WHERE (v.account = ANY ((select get_my_allowed_accounts())::text[]))
        AND (v.deleted_at IS NULL)
        AND (NOT COALESCE(v.is_pool_vacancy, false))
    )))
    OR (i_am_ops() AND (EXISTS (
      SELECT 1 FROM public.vacancies v
      WHERE (v.vcode = applicants.vacancy_vcode)
        AND (v.is_pool_vacancy = true)
        AND (COALESCE(v.is_ops_request, false) = true)
        AND (v.account = ANY ((select get_my_allowed_accounts())::text[]))
        AND (v.deleted_at IS NULL)
    )))
  )
  AND (NOT (EXISTS (
    SELECT 1 FROM public.vacancies v
    WHERE (v.vcode = applicants.vacancy_vcode) AND (v.has_pending_closure = true) AND (v.deleted_at IS NULL)
  )))
);

DROP POLICY IF EXISTS "applicants_read_scoped" ON public.applicants;
CREATE POLICY "applicants_read_scoped" ON public.applicants
FOR SELECT TO public
USING (
  (select i_have_full_access())
  OR (vacancy_vcode = ANY (get_my_scoped_vcodes()))
  OR (
    (EXISTS (
      SELECT 1 FROM public.vacancies v
      WHERE (v.vcode = applicants.vacancy_vcode) AND (v.is_pool_vacancy = true) AND (v.deleted_at IS NULL)
    ))
    AND ((get_my_role_level() = 20) OR (get_my_role_level() = 30) OR (get_my_role_level() >= 90))
  )
);

DROP POLICY IF EXISTS "applicants_update_ops_recruitment" ON public.applicants;
CREATE POLICY "applicants_update_ops_recruitment" ON public.applicants
FOR UPDATE TO public
USING (
  (select i_have_full_access())
  OR (i_am_recruitment() AND (EXISTS (
    SELECT 1 FROM public.vacancies v
    WHERE (v.vcode = applicants.vacancy_vcode) AND (v.is_pool_vacancy = true) AND (v.deleted_at IS NULL)
  )))
  OR ((i_am_ops() OR i_am_recruitment()) AND (vacancy_vcode IN (
    SELECT v.vcode FROM public.vacancies v
    WHERE (v.account = ANY ((select get_my_allowed_accounts())::text[]))
      AND (v.deleted_at IS NULL)
      AND (NOT COALESCE(v.is_pool_vacancy, false))
  )))
);

-- ── audit_logs ───────────────────────────────────────────────────

DROP POLICY IF EXISTS "pol_audit_admin_read" ON public.audit_logs;
CREATE POLICY "pol_audit_admin_read" ON public.audit_logs
FOR SELECT TO authenticated
USING ((select i_have_full_access()));

-- ── coverage_group_stores ───────────────────────────────────────

DROP POLICY IF EXISTS "coverage_group_stores_read_scoped" ON public.coverage_group_stores;
CREATE POLICY "coverage_group_stores_read_scoped" ON public.coverage_group_stores
FOR SELECT TO authenticated
USING (
  (select i_have_full_access())
  OR (EXISTS (
    SELECT 1 FROM public.coverage_groups cg
    WHERE (cg.id = coverage_group_stores.coverage_group_id)
      AND (cg.account_id = ANY ((select get_my_allowed_account_ids())::uuid[]))
  ))
);

-- ── coverage_request_history ────────────────────────────────────

DROP POLICY IF EXISTS "coverage_request_history_read_scoped" ON public.coverage_request_history;
CREATE POLICY "coverage_request_history_read_scoped" ON public.coverage_request_history
FOR SELECT TO authenticated
USING (
  ((select i_have_full_access()) OR ((select get_my_role()) = 'Encoder'::text))
  AND (EXISTS (
    SELECT 1 FROM public.coverage_requests cr
    WHERE (cr.id = coverage_request_history.coverage_request_id)
  ))
);

-- ── coverage_requests ────────────────────────────────────────────

DROP POLICY IF EXISTS "coverage_requests_read_scoped" ON public.coverage_requests;
CREATE POLICY "coverage_requests_read_scoped" ON public.coverage_requests
FOR SELECT TO authenticated
USING (
  ((select i_have_full_access()) OR ((select get_my_role()) = 'Encoder'::text))
  AND (
    (select i_have_full_access())
    OR (requested_by = get_current_profile_id())
    OR (account_id = ANY ((select get_my_allowed_account_ids())::uuid[]))
    OR (EXISTS (
      SELECT 1 FROM public.coverage_groups cg
      WHERE (cg.id = ANY (ARRAY[coverage_requests.target_coverage_group_id, coverage_requests.source_coverage_group_id, coverage_requests.destination_coverage_group_id]))
        AND (cg.account_id = ANY ((select get_my_allowed_account_ids())::uuid[]))
    ))
  )
);

-- ── employee_activity_log ───────────────────────────────────────

DROP POLICY IF EXISTS "activity_log_read_scoped" ON public.employee_activity_log;
CREATE POLICY "activity_log_read_scoped" ON public.employee_activity_log
FOR SELECT TO public
USING (
  (select i_have_full_access())
  OR (vcode IN (
    SELECT v.vcode FROM public.vacancies v
    WHERE (v.account = ANY ((select get_my_allowed_accounts())::text[]))
  ))
);

-- ── employee_store_allocations ──────────────────────────────────

DROP POLICY IF EXISTS "esa_select" ON public.employee_store_allocations;
CREATE POLICY "esa_select" ON public.employee_store_allocations
FOR SELECT TO authenticated
USING (
  (select i_have_full_access())
  OR (account_id = ANY ((select get_my_allowed_account_ids())::uuid[]))
);

-- ── headcount_requests ───────────────────────────────────────────

DROP POLICY IF EXISTS "hcreq_insert_ops_scoped" ON public.headcount_requests;
CREATE POLICY "hcreq_insert_ops_scoped" ON public.headcount_requests
FOR INSERT TO public
WITH CHECK (
  (select i_have_full_access())
  OR (i_am_ops() AND (account_name_snapshot = ANY ((select get_my_allowed_accounts())::text[])))
);

DROP POLICY IF EXISTS "hcreq_select_scoped" ON public.headcount_requests;
CREATE POLICY "hcreq_select_scoped" ON public.headcount_requests
FOR SELECT TO public
USING (
  (select i_have_full_access())
  OR (account_name_snapshot = ANY ((select get_my_allowed_accounts())::text[]))
  OR (requested_by_user_id = get_current_profile_id())
);

-- ── hr_emploc ────────────────────────────────────────────────────

DROP POLICY IF EXISTS "hr_emploc_hide_deleted" ON public.hr_emploc;
CREATE POLICY "hr_emploc_hide_deleted" ON public.hr_emploc
AS RESTRICTIVE
FOR SELECT TO authenticated
USING ((deleted_at IS NULL) OR (select i_have_full_access()));

DROP POLICY IF EXISTS "hr_emploc_read_scoped" ON public.hr_emploc;
CREATE POLICY "hr_emploc_read_scoped" ON public.hr_emploc
FOR SELECT TO public
USING (
  (select i_have_full_access())
  OR (account = ANY ((select get_my_allowed_accounts())::text[]))
);

DROP POLICY IF EXISTS "hr_emploc_write_scoped" ON public.hr_emploc;
CREATE POLICY "hr_emploc_write_scoped" ON public.hr_emploc
FOR ALL TO public
USING (
  (select i_have_full_access())
  OR (account = ANY ((select get_my_allowed_accounts())::text[]))
);

-- ── hr_emploc_import_rows ───────────────────────────────────────

DROP POLICY IF EXISTS "hr_emploc_import_rows_select" ON public.hr_emploc_import_rows;
CREATE POLICY "hr_emploc_import_rows_select" ON public.hr_emploc_import_rows
FOR SELECT TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.hr_emploc_import_batches b
    WHERE (b.id = hr_emploc_import_rows.batch_id)
      AND (b.deleted_at IS NULL)
      AND (
        (select i_have_full_access())
        OR (b.group_id IN (
          SELECT DISTINCT a.group_id FROM public.accounts a
          WHERE ((a.id)::text = ANY ((select get_my_allowed_accounts())::text[]))
        ))
      )
  )
);

-- ── import_roving_groups ────────────────────────────────────────

DROP POLICY IF EXISTS "irg_select" ON public.import_roving_groups;
CREATE POLICY "irg_select" ON public.import_roving_groups
FOR SELECT TO authenticated
USING (
  (select i_have_full_access())
  OR (account_id = ANY ((select get_my_allowed_account_ids())::uuid[]))
);

-- ── mika_import_rows ────────────────────────────────────────────

DROP POLICY IF EXISTS "mika_rows_read_scoped" ON public.mika_import_rows;
CREATE POLICY "mika_rows_read_scoped" ON public.mika_import_rows
FOR SELECT TO authenticated
USING (
  (select i_have_full_access())
  OR (account = ANY ((select get_my_allowed_accounts())::text[]))
);

DROP POLICY IF EXISTS "mika_rows_write_admin" ON public.mika_import_rows;
CREATE POLICY "mika_rows_write_admin" ON public.mika_import_rows
FOR ALL TO authenticated
USING ((select i_have_full_access()));

-- ── new_store_requests ──────────────────────────────────────────

DROP POLICY IF EXISTS "nsr_select" ON public.new_store_requests;
CREATE POLICY "nsr_select" ON public.new_store_requests
FOR SELECT TO authenticated
USING (
  (select i_have_full_access())
  OR (requested_by = get_current_profile_id())
);

-- ── notifications ────────────────────────────────────────────────

DROP POLICY IF EXISTS "notif_select_own" ON public.notifications;
CREATE POLICY "notif_select_own" ON public.notifications
FOR SELECT TO public
USING (
  (recipient_user_id = auth.uid())
  OR (select i_have_full_access())
);

-- ── plantilla_import_batches ────────────────────────────────────

DROP POLICY IF EXISTS "pib_select" ON public.plantilla_import_batches;
CREATE POLICY "pib_select" ON public.plantilla_import_batches
FOR SELECT TO authenticated
USING (
  (select i_have_full_access())
  OR (uploaded_by = auth.uid())
);

-- ── plantilla_import_commit_snapshots ───────────────────────────

DROP POLICY IF EXISTS "pics_select" ON public.plantilla_import_commit_snapshots;
CREATE POLICY "pics_select" ON public.plantilla_import_commit_snapshots
FOR SELECT TO authenticated
USING (
  (select i_have_full_access())
  OR (EXISTS (
    SELECT 1 FROM public.plantilla_import_batches b
    WHERE (b.id = plantilla_import_commit_snapshots.batch_id) AND (b.uploaded_by = auth.uid())
  ))
);

-- ── plantilla_import_rows ───────────────────────────────────────

DROP POLICY IF EXISTS "pir_select" ON public.plantilla_import_rows;
CREATE POLICY "pir_select" ON public.plantilla_import_rows
FOR SELECT TO authenticated
USING (
  (select i_have_full_access())
  OR (EXISTS (
    SELECT 1 FROM public.plantilla_import_batches b
    WHERE (b.id = plantilla_import_rows.batch_id) AND (b.uploaded_by = auth.uid())
  ))
);

-- ── plantilla_store_links ───────────────────────────────────────

DROP POLICY IF EXISTS "plantilla_store_links_select_scoped" ON public.plantilla_store_links;
CREATE POLICY "plantilla_store_links_select_scoped" ON public.plantilla_store_links
FOR SELECT TO authenticated
USING (
  (select i_have_full_access())
  OR (EXISTS (
    SELECT 1 FROM public.plantilla p
    WHERE (p.id = plantilla_store_links.plantilla_id)
      AND ((p.account_id)::text = ANY ((select get_my_allowed_accounts())::text[]))
  ))
);

-- ── positions ────────────────────────────────────────────────────

DROP POLICY IF EXISTS "positions_write_admin" ON public.positions;
CREATE POLICY "positions_write_admin" ON public.positions
FOR ALL TO public
USING ((select i_have_full_access()));

-- ── possible_ghost_employees ────────────────────────────────────

DROP POLICY IF EXISTS "ghost_employees_read_ops_scoped" ON public.possible_ghost_employees;
CREATE POLICY "ghost_employees_read_ops_scoped" ON public.possible_ghost_employees
FOR SELECT TO public
USING (
  (select i_have_full_access())
  OR (i_am_ops() AND (account = ANY ((select get_my_allowed_accounts())::text[])))
);

DROP POLICY IF EXISTS "ghost_employees_write_admin" ON public.possible_ghost_employees;
CREATE POLICY "ghost_employees_write_admin" ON public.possible_ghost_employees
FOR ALL TO public
USING (
  (select i_have_full_access())
  OR ((get_my_role_level() = 30) AND (account = ANY ((select get_my_allowed_accounts())::text[])))
);

-- ── qa_agent_findings ────────────────────────────────────────────

DROP POLICY IF EXISTS "qa_findings_read" ON public.qa_agent_findings;
CREATE POLICY "qa_findings_read" ON public.qa_agent_findings
FOR SELECT TO public
USING (
  (select i_have_full_access())
  OR (get_my_role_level() >= 90)
);

DROP POLICY IF EXISTS "qa_findings_write" ON public.qa_agent_findings;
CREATE POLICY "qa_findings_write" ON public.qa_agent_findings
FOR ALL TO public
USING (
  (select i_have_full_access())
  OR (get_my_role_level() >= 90)
)
WITH CHECK (
  (select i_have_full_access())
  OR (get_my_role_level() >= 90)
);

-- ── sla_breach_logs ──────────────────────────────────────────────

DROP POLICY IF EXISTS "sla_breach_read" ON public.sla_breach_logs;
CREATE POLICY "sla_breach_read" ON public.sla_breach_logs
FOR SELECT TO public
USING ((select get_my_role()) = ANY (ARRAY['Super Admin'::text, 'Head Admin'::text, 'OM'::text]));

-- ── user_scopes ──────────────────────────────────────────────────

DROP POLICY IF EXISTS "user_scopes_read_own" ON public.user_scopes;
CREATE POLICY "user_scopes_read_own" ON public.user_scopes
FOR SELECT TO public
USING (
  (user_id = get_my_profile_id())
  OR (select i_have_full_access())
);

DROP POLICY IF EXISTS "user_scopes_write_admin" ON public.user_scopes;
CREATE POLICY "user_scopes_write_admin" ON public.user_scopes
FOR ALL TO public
USING ((select i_have_full_access()));

-- ── vacancy_edit_lock_audit ──────────────────────────────────────

DROP POLICY IF EXISTS "Allow SA and HA to read vacancy_edit_lock_audit" ON public.vacancy_edit_lock_audit;
CREATE POLICY "Allow SA and HA to read vacancy_edit_lock_audit" ON public.vacancy_edit_lock_audit
FOR SELECT TO authenticated
USING ((select get_my_role()) = ANY (ARRAY['Super Admin'::text, 'Head Admin'::text]));

-- ── vacancy_import_batches ──────────────────────────────────────

DROP POLICY IF EXISTS "vib_select" ON public.vacancy_import_batches;
CREATE POLICY "vib_select" ON public.vacancy_import_batches
FOR SELECT TO authenticated
USING (
  (select i_have_full_access())
  OR (uploaded_by = auth.uid())
);

-- ── vacancy_import_rows ──────────────────────────────────────────

DROP POLICY IF EXISTS "vir_select" ON public.vacancy_import_rows;
CREATE POLICY "vir_select" ON public.vacancy_import_rows
FOR SELECT TO authenticated
USING (
  (select i_have_full_access())
  OR (EXISTS (
    SELECT 1 FROM public.vacancy_import_batches b
    WHERE (b.id = vacancy_import_rows.batch_id) AND (b.uploaded_by = auth.uid())
  ))
);

-- ── workforce_pool_slots ────────────────────────────────────────

DROP POLICY IF EXISTS "wps_read_data_team_or_scoped" ON public.workforce_pool_slots;
CREATE POLICY "wps_read_data_team_or_scoped" ON public.workforce_pool_slots
FOR SELECT TO authenticated
USING (
  (deleted_at IS NULL)
  AND (
    (get_my_role_level() = ANY (ARRAY[100, 90, 30]))
    OR (select i_have_full_access())
    OR (account = ANY ((select get_my_allowed_accounts())::text[]))
  )
);

DROP POLICY IF EXISTS "wps_write_data_team" ON public.workforce_pool_slots;
CREATE POLICY "wps_write_data_team" ON public.workforce_pool_slots
FOR ALL TO authenticated
USING (
  (get_my_role_level() = ANY (ARRAY[100, 90, 30]))
  OR (select i_have_full_access())
)
WITH CHECK (
  (get_my_role_level() = ANY (ARRAY[100, 90, 30]))
  OR (select i_have_full_access())
);
