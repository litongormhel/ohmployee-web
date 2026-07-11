-- ============================================================
-- OHM2026_0065 — Security Advisor Phase 1 (Low-Risk Objects Only)
-- DRAFT — DO NOT APPLY WITHOUT REVIEW
-- ============================================================
--
-- Prompt ID : OHM2026_0066 (revised from OHM2026_0065 draft)
-- Date       : 2026-06-03
-- Author     : Claude (revised per OHM2026_0066 instruction)
-- Predecessor: OHM2026_0063 (audit), OHM2026_0064 (dependency matrix)
-- Status     : DRAFT — awaiting product + engineering approval before apply
--
-- Revision note (OHM2026_0066):
--   vw_open_vacancies_by_store removed from Phase 1. Consumer confirmation
--   is pending and the view queries the vacancies table (active recruitment
--   surface). Per OHM2026_0066 instruction it must not be touched in Phase 1.
--
-- Purpose:
--   Enable RLS on two admin-only account-request scope tables and add
--   security_invoker=true to four confirmed-unused/admin-only views.
--   All objects in this migration are classified "safe to fix first" per
--   OHM2026_0064 Deliverable 3 Group 1.
--
-- Workflow-safety guarantee:
--   No object in this migration is queried by any live Flutter screen,
--   and all mutation paths on the two tables use SECURITY DEFINER RPCs
--   which bypass RLS entirely. This migration changes security surface
--   only — no visible app behaviour changes.
--
-- Objects included:
--   TABLES (RLS enable + SA/HA SELECT + no direct writes):
--     1. account_request_account_scopes
--     2. account_request_group_scopes
--   VIEWS (add security_invoker=true, body verbatim from authoritative migration):
--     3. v_qa_notifications          (admin QA tooling — base RLS already HA/SA-only)
--     4. v_qa_health_metrics         (admin QA tooling — base RLS already HA/SA-only)
--     5. v_qa_detection_run_summary  (admin QA tooling — initiated_by scoped by base RLS)
--     6. v_store_fractional_hc       (not yet wired into live MFR; esa_select base RLS enforced)
--
-- Objects EXCLUDED (workflow-sensitive — do NOT touch in Phase 1):
--   vw_open_vacancies_by_store  — removed from Phase 1 (OHM2026_0066); consumer confirmation pending;
--                                  queries vacancies table (active recruitment surface); defer to later phase
--   vw_vacancy_list             — primary Flutter vacancy surface (CRITICAL blast radius)
--   transfer_requests           — live Flutter INSERT+SELECT; product confirmation pending
--   vw_ready_to_plantilla       — HR Emploc Ready tab; consumer confirmation pending
--   vw_plantilla_status_counts  — dashboard KPI; consumer confirmation pending
--   team_performance_summary    — reclassified LIVE by OHM2026_0064 (live perf dashboard)
--   hr_emploc_store_links       — v_hr_emploc_sla_flags (security_invoker) depends on it; policy design required
--   plantilla_store_links       — direct Flutter query plantilla_screen.dart:5107; policy design required
--   v_hr_emploc_sla_flags       — already security_invoker=true; do not touch
--   Any Vacancy/Plantilla/HR Emploc/Transfer/Team Directory/Dashboard workflow object
--
-- Idempotency:
--   ALTER TABLE ... ENABLE ROW LEVEL SECURITY is idempotent (PostgreSQL no-ops if already enabled).
--   ALTER TABLE ... FORCE ROW LEVEL SECURITY is idempotent.
--   Policies use DROP POLICY IF EXISTS before CREATE POLICY for safe re-runs.
--   CREATE OR REPLACE VIEW is idempotent.
--
-- ============================================================


-- ──────────────────────────────────────────────────────────────
-- §1  account_request_account_scopes — Enable RLS
-- ──────────────────────────────────────────────────────────────
--
-- WHY SAFE FOR PHASE 1:
--   • No Flutter or web screen queries this table directly (confirmed OHM2026_0063/0064).
--   • All reads and writes go through SECURITY DEFINER RPCs:
--       fn_enrich_account_request, approve_account_request_v2, get_approval_queue
--     SECURITY DEFINER functions run as the function owner (postgres) and bypass RLS,
--     so enabling RLS here does not break any existing workflow call.
--   • The dependent view v_approval_queue is security DEFINER — it also bypasses RLS,
--     so row visibility through that view is unchanged.
--   • Only direct PostgREST selects from non-admin users are blocked (the security gap
--     being remediated).
--
-- WORKFLOW PROTECTED:
--   HC / Account Request approval workflow (SA/HA submits → get_approval_queue →
--   approve_account_request_v2). All steps use DEFINER RPCs — unaffected by RLS.
--
-- WHAT CHANGES:
--   Any authenticated user who was previously able to SELECT all account scope
--   assignments via PostgREST is now blocked unless they are SA/HA.

ALTER TABLE public.account_request_account_scopes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.account_request_account_scopes FORCE ROW LEVEL SECURITY;

-- Allow SA/HA direct read (e.g. admin tooling, SQL editor sessions running as authenticated).
DROP POLICY IF EXISTS "aras_select_admin_only" ON public.account_request_account_scopes;
CREATE POLICY "aras_select_admin_only"
  ON public.account_request_account_scopes
  FOR SELECT
  TO authenticated
  USING (public.i_have_full_access());

-- Block direct client writes. All mutations are via SECURITY DEFINER RPCs which bypass RLS.
-- service_role also bypasses RLS — backend triggers/functions unaffected.
DROP POLICY IF EXISTS "aras_no_direct_write" ON public.account_request_account_scopes;
CREATE POLICY "aras_no_direct_write"
  ON public.account_request_account_scopes
  FOR ALL
  TO authenticated
  USING (false)
  WITH CHECK (false);


-- ──────────────────────────────────────────────────────────────
-- §2  account_request_group_scopes — Enable RLS
-- ──────────────────────────────────────────────────────────────
--
-- WHY SAFE FOR PHASE 1:
--   Identical profile to account_request_account_scopes (see §1). Same DEFINER RPC
--   consumers, same v_approval_queue (definer) dependency, no direct Flutter query.
--
-- WORKFLOW PROTECTED:
--   Same HC / Account Request approval workflow as §1. Group-scope rows are read and
--   written only by the same SECURITY DEFINER RPCs. Enabling RLS does not affect them.
--
-- WHAT CHANGES:
--   Direct PostgREST selects of group scope assignments are restricted to SA/HA only.

ALTER TABLE public.account_request_group_scopes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.account_request_group_scopes FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "args_select_admin_only" ON public.account_request_group_scopes;
CREATE POLICY "args_select_admin_only"
  ON public.account_request_group_scopes
  FOR SELECT
  TO authenticated
  USING (public.i_have_full_access());

DROP POLICY IF EXISTS "args_no_direct_write" ON public.account_request_group_scopes;
CREATE POLICY "args_no_direct_write"
  ON public.account_request_group_scopes
  FOR ALL
  TO authenticated
  USING (false)
  WITH CHECK (false);


-- ──────────────────────────────────────────────────────────────
-- §3  v_qa_notifications — Add security_invoker
-- ──────────────────────────────────────────────────────────────
--
-- WHY SAFE FOR PHASE 1:
--   • Admin/QA tooling only. No Flutter mobile screen queries this view (OHM2026_0064).
--   • Underlying table qa_notifications has RLS policy restricting reads to
--     i_have_full_access() OR role_level >= 90. Adding security_invoker enforces this
--     existing RLS; it does not change who can see data — it removes the definer bypass.
--   • No workflow objects depend on this view.
--
-- WORKFLOW PROTECTED:
--   QA admin dashboard — SA/HA access is preserved (their role satisfies the base RLS policy).
--
-- BODY SOURCE: 20260521062543_remote_schema.sql (authoritative; verbatim copy).

CREATE OR REPLACE VIEW public.v_qa_notifications
  WITH (security_invoker = true)
AS
SELECT
    id,
    notification_type,
    severity,
    title,
    message,
    reference_type,
    reference_id,
    target_role,
    is_read,
    read_at,
    created_at,
    archived_at,
    metadata
FROM public.qa_notifications
WHERE archived_at IS NULL
ORDER BY created_at DESC;


-- ──────────────────────────────────────────────────────────────
-- §4  v_qa_health_metrics — Add security_invoker
-- ──────────────────────────────────────────────────────────────
--
-- WHY SAFE FOR PHASE 1:
--   • Admin/QA tooling only. No mobile consumer (OHM2026_0064).
--   • Underlying qa_health_metrics RLS policy: role_level >= 90 (HA/SA only).
--     Adding security_invoker enforces existing RLS — no behavior change for SA/HA.
--
-- WORKFLOW PROTECTED:
--   QA health metrics dashboard — SA/HA access preserved.
--
-- BODY SOURCE: 20260521062543_remote_schema.sql (authoritative; verbatim copy).

CREATE OR REPLACE VIEW public.v_qa_health_metrics
  WITH (security_invoker = true)
AS
SELECT
    id,
    metric_date,
    environment,
    metric_name,
    metric_value,
    metric_status,
    metadata,
    created_at
FROM public.qa_health_metrics
ORDER BY metric_date DESC, created_at DESC;


-- ──────────────────────────────────────────────────────────────
-- §5  v_qa_detection_run_summary — Add security_invoker
-- ──────────────────────────────────────────────────────────────
--
-- WHY SAFE FOR PHASE 1:
--   • Admin/QA tooling only. No mobile consumer (OHM2026_0064).
--   • Underlying qa_agent_runs RLS policy: i_have_full_access() OR
--     initiated_by = get_current_profile_id(). Adding security_invoker enforces
--     this scoping — users only see their own runs (or all if SA/HA).
--   • Today the view leaks all users' run summaries to any authenticated caller.
--     This fix is intentional tightening with no live mobile blast radius.
--
-- WORKFLOW PROTECTED:
--   QA detection run history — SA/HA see all; other users see own runs only (correct behavior).
--
-- BODY SOURCE: 20260521062543_remote_schema.sql (authoritative; verbatim copy).

CREATE OR REPLACE VIEW public.v_qa_detection_run_summary
  WITH (security_invoker = true)
AS
SELECT
    r.id,
    r.agent_name,
    r.execution_type,
    r.status,
    r.target_module,
    r.initiated_by,
    r.started_at,
    r.completed_at,
    r.summary,
    count(f.id)                                         AS finding_count,
    count(f.id) FILTER (WHERE f.severity = 'critical')  AS critical_count,
    count(f.id) FILTER (WHERE f.severity = 'high')      AS high_count,
    count(f.id) FILTER (WHERE f.severity = 'medium')    AS medium_count,
    count(f.id) FILTER (WHERE f.severity = 'low')       AS low_count
FROM public.qa_agent_runs r
LEFT JOIN public.qa_agent_findings f ON f.run_id = r.id
GROUP BY r.id;


-- ──────────────────────────────────────────────────────────────
-- §6  v_store_fractional_hc — Add security_invoker
-- ──────────────────────────────────────────────────────────────
--
-- WHY SAFE FOR PHASE 1:
--   • Not yet integrated into live MFR views or any mobile dashboard (OHM2026_0063/0064).
--     Comment in 20260603010000_plantilla_import_dry_run_v1.sql §13 explicitly states:
--     "Not wired into v_workforce_health_summary / v_account_kpi in V1 (next-step integration)."
--   • The newer v_store_allocation_hc (created in 20260628000000) already uses
--     security_invoker=true — this view was missed.
--   • Underlying employee_store_allocations has RLS policy esa_select (scoped by account_id).
--     Adding security_invoker enforces existing RLS — scoped users see only their accounts' links.
--   • No Flutter screen or RPC reads this view in the current build.
--
-- WORKFLOW PROTECTED:
--   N/A — no live consumer. Roving Plantilla / MFR workflow uses v_store_allocation_hc
--   (already security_invoker=true) and DEFINER RPCs — both unaffected by this change.
--
-- BODY SOURCE: 20260603010000_plantilla_import_dry_run_v1.sql §13 line 1060 (authoritative; verbatim copy).

CREATE OR REPLACE VIEW public.v_store_fractional_hc
  WITH (security_invoker = true)
AS
SELECT
    a.store_id,
    a.vcode,
    a.store_name,
    a.account_id,
    a.group_id,
    count(DISTINCT a.plantilla_id)                              AS employee_count,
    round(sum(a.filled_hc), 4)                                  AS filled_hc,
    count(*) FILTER (WHERE a.roving_group_id IS NOT NULL)       AS roving_allocations
FROM public.employee_store_allocations a
WHERE a.is_active
GROUP BY a.store_id, a.vcode, a.store_name, a.account_id, a.group_id;


-- ============================================================
-- VALIDATION QUERIES (COMMENTS ONLY — run manually after apply)
-- ============================================================
--
-- V1 — Confirm RLS enabled on both account_request scope tables:
--
-- SELECT relname, relrowsecurity, relforcerowsecurity
-- FROM pg_class
-- WHERE relname IN (
--   'account_request_account_scopes',
--   'account_request_group_scopes'
-- );
-- Expected: relrowsecurity = true, relforcerowsecurity = true for both.
--
--
-- V2 — Confirm RLS policies exist on both tables:
--
-- SELECT tablename, policyname, cmd, roles, qual
-- FROM pg_policies
-- WHERE tablename IN (
--   'account_request_account_scopes',
--   'account_request_group_scopes'
-- )
-- ORDER BY tablename, policyname;
-- Expected: 2 policies per table — aras_select_admin_only + aras_no_direct_write
--           (and args_* equivalents).
--
--
-- V3 — Confirm security_invoker on the four views:
--
-- SELECT relname, reloptions
-- FROM pg_class
-- JOIN pg_namespace ON pg_namespace.oid = pg_class.relnamespace
-- WHERE pg_namespace.nspname = 'public'
--   AND relname IN (
--     'v_qa_notifications',
--     'v_qa_health_metrics',
--     'v_qa_detection_run_summary',
--     'v_store_fractional_hc'
--   );
-- Expected: reloptions contains 'security_invoker=true' for all four.
-- Note: vw_open_vacancies_by_store is excluded from Phase 1 (OHM2026_0066).
--
--
-- V4 — Confirm HA/SA can still query account_request scope tables via RPC:
--
-- SELECT * FROM public.get_approval_queue();  -- run as SA or HA authenticated session
-- Expected: approval queue rows returned (DEFINER RPC bypasses RLS — unaffected).
--
--
-- V5 — Confirm scoped user (non-SA/HA) cannot direct-select account_request scopes:
--
-- SELECT count(*) FROM public.account_request_account_scopes;  -- run as HRCO/OM/Encoder
-- Expected: 0 rows returned (RLS policy blocks non-full-access callers).
-- SELECT count(*) FROM public.account_request_group_scopes;    -- same
-- Expected: 0 rows returned.
--
--
-- V6 — Confirm HA/SA can still direct-select account_request scopes:
--
-- SELECT count(*) FROM public.account_request_account_scopes;  -- run as SA/HA
-- Expected: actual row count (i_have_full_access() = true for SA/HA).
--
--
-- V7 — Confirm QA views still return data for SA/HA:
--
-- SELECT count(*) FROM public.v_qa_notifications;         -- as SA/HA
-- SELECT count(*) FROM public.v_qa_health_metrics;        -- as SA/HA
-- SELECT count(*) FROM public.v_qa_detection_run_summary; -- as SA/HA
-- Expected: same row counts as before (base RLS already restricts to SA/HA).
--
--
-- V8 — Confirm EXCLUDED objects were NOT modified:
--
-- SELECT relname, reloptions
-- FROM pg_class
-- JOIN pg_namespace ON pg_namespace.oid = pg_class.relnamespace
-- WHERE pg_namespace.nspname = 'public'
--   AND relname IN (
--     'vw_open_vacancies_by_store',
--     'vw_vacancy_list',
--     'transfer_requests',
--     'vw_ready_to_plantilla',
--     'vw_plantilla_status_counts',
--     'team_performance_summary',
--     'hr_emploc_store_links',
--     'plantilla_store_links',
--     'v_hr_emploc_sla_flags'
--   );
-- Expected: reloptions IS NULL for all (no security_invoker added).
-- vw_open_vacancies_by_store deferred to a later phase per OHM2026_0066.
-- For tables: relrowsecurity = false for hr_emploc_store_links and plantilla_store_links.
--
--
-- V9 — Confirm no active Flutter workflow is broken (smoke-test checklist):
--   □ Vacancy Open tab loads with correct counts (uses vw_vacancy_list — untouched)
--   □ HR Emploc Pending/Ready lists load (uses hr_emploc + v_hr_emploc_sla_flags — untouched)
--   □ Plantilla list and per-store detail load (uses v_plantilla_safe + plantilla_store_links — untouched)
--   □ Transfer screen insert and list work (uses transfer_requests — untouched)
--   □ CENCOM KPI loads (uses v_cencom_allocation_kpi — untouched)
--   □ HC/Account Request approve RPC succeeds as SA/HA (DEFINER path — unaffected by RLS)
--
-- ============================================================
-- END OF DRAFT MIGRATION — DO NOT APPLY WITHOUT APPROVAL
-- ============================================================
