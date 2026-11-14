-- ============================================================
-- ohm#3xk7m2wq — RLS InitPlan-wrapping fix, Phase 1 (5 tables)
-- Migration: 20260818014618_wrap_rls_scope_checks_phase1_initplan.sql
-- ============================================================
-- Context
-- -------
-- Follow-up to ohm#7wq3n9km Part A (RLS-performance timeout root
-- cause) and ohm#3xk7m2wq Part B (full policy inventory: 0/179
-- scope-check RLS policy calls across 114 tables use `(select ...)`
-- InitPlan wrapping) and Part C (6 scope/role-check functions marked
-- STABLE via ALTER FUNCTION — a verified prerequisite for this wrap
-- to have any effect, since only STABLE/IMMUTABLE calls are eligible
-- for InitPlan single-evaluation caching).
--
-- This migration is Phase 1 of the wrapping fix itself: the 5
-- highest-risk tables from the Part B inventory by live row count
-- (stores 4,136 / slot_history 4,050 / plantilla 3,979 /
-- plantilla_slots 1,710 / vacancies 257 — the last being the
-- already-confirmed ohm#7wq3n9km incident table). Remaining ~35
-- lower-risk tables from the inventory are explicitly deferred to a
-- later phase.
--
-- Scope of the change, precisely
-- -------------------------------
-- Every bare (unwrapped) call to i_have_full_access(),
-- get_my_allowed_accounts(), get_my_allowed_account_ids(), or
-- get_my_role() inside these 5 tables' policy qual/with_check text is
-- rewritten as `(select fn())`. These 4 are the only functions in
-- this migration's function-family scope that are (a) zero-argument,
-- (b) uncorrelated to the current row, and (c) STABLE — the exact
-- precondition for `(select ...)` to actually cause Postgres to cache
-- a single per-statement evaluation instead of re-running per row.
--
-- IMPORTANT gotcha found and fixed during pre-apply verification:
-- `get_my_allowed_accounts()` (returns text[]) and
-- `get_my_allowed_account_ids()` (returns uuid[]) are both used as
-- `col = ANY(fn())`. Naively wrapping as `col = ANY((select fn()))`
-- is a DIFFERENT Postgres grammar production than intended — a bare
-- `(SELECT ...)` immediately inside `ANY(...)` is parsed as the
-- scalar-subquery form of ANY (one column, N rows), not the array
-- form, and since the subquery returns a single row containing one
-- array value, this throws `operator does not exist: text = text[]`
-- (or silently misbehaves for other types). Confirmed via direct
-- repro before writing this migration. Fix: an explicit cast outside
-- the subquery — `col = ANY((select fn())::text[])` /
-- `::uuid[]` — forces the parenthesized expression to be read as a
-- cast (an array_expression), not a bare select, restoring correct
-- ANY-over-array semantics. Verified byte-identical row output vs.
-- the un-cast bare-call form before use in any policy below.
--
-- SECOND gotcha found and fixed during pre-apply verification: the
-- correctness-equivalence test (below) initially caught a real
-- regression — OM's visible `vacancies` row count jumped from a
-- scoped 15 to the full 257 after a first draft of this migration.
-- Root cause: `vacancies_block_hr_personnel` is a RESTRICTIVE policy
-- on the live table (`pg_policies.permissive = 'RESTRICTIVE'`,
-- confirmed via direct query) — RESTRICTIVE policies AND-narrow
-- alongside PERMISSIVE ones, rather than OR-broadening them. `DROP
-- POLICY` + a bare `CREATE POLICY` (no `AS RESTRICTIVE` clause)
-- defaults to PERMISSIVE, which silently flips this policy's effect:
-- its near-universally-true condition (`role <> 'HR Personnel'`) then
-- gets OR'd into `vacancies_select_secure` instead of AND-narrowing
-- it, opening full row visibility to any non-HR-Personnel role. Fixed
-- by adding `AS RESTRICTIVE` to this one CREATE POLICY statement.
-- Re-verified via a fresh full 3-role test after the fix — see
-- .ai/handoff.md for the complete before/after result log, including
-- this caught-and-fixed discrepancy. Confirmed via direct pg_policies
-- query that all other 10 policies in this migration are already
-- PERMISSIVE on the live table (the default this migration's other
-- CREATE POLICY statements correctly rely on) — this was the only
-- RESTRICTIVE policy among the 11.
--
-- Explicitly NOT wrapped, by design:
--   - i_am_assigned_to_vacancy(id) (vacancies_select_secure) takes
--     the row's own `id` as an argument — it is correlated to the
--     current row, not a statement-constant. Wrapping a correlated
--     call provides no caching benefit and would force Postgres into
--     a per-row correlated SubPlan instead of a plain function call —
--     pure overhead, no gain. Left bare deliberately.
--   - get_my_role_level(), i_can_view_plantilla(),
--     i_can_act_on_plantilla(), i_am_hrco_only(),
--     i_have_hrco_global_visibility(), i_am_recruitment(),
--     i_am_hr_dept() all appear bare in these policies too but are
--     outside this migration's authorized function scope — untouched.
--   - get_my_scoped_accounts(), get_effective_role(),
--     get_effective_account_ids(), get_effective_group_ids() do not
--     appear directly in any policy on these 5 tables — nothing to
--     wrap.
--   - plantilla_delete_blocked / vacancies_delete_blocked
--     (qual = `false`, no function calls) are untouched.
--
-- This is a text-only rewrite of policy qual/with_check expressions.
-- No function body is touched (that was Part C, already applied). No
-- semantic/authorization change — `(select fn())`/`(select fn())::ty[]`
-- and `fn()` are required to evaluate to the identical value within
-- one statement once fn() is STABLE (verified live in Part C) and the
-- ANY-over-array cast gotcha above is respected. Only latency should
-- change.
--
-- Correctness-equivalence verification performed BEFORE this
-- migration was applied (see conversation log / .ai/handoff.md,
-- ohm#3xk7m2wq): rolled-back-transaction row-id-set diffs for SA/OM/
-- HRCO test identities across all 5 tables, plus with_check accept/
-- reject parity checks for the 6 policies below that carry a
-- with_check clause, plus an explicit plantilla_read_scoped HRCO-
-- assignment-boundary check. All reported byte-identical before this
-- migration was applied — see handoff for the full result log.
--
-- Migration mechanism matches this codebase's existing convention for
-- RLS-policy-only changes (e.g. 20260810000003_fix_vacancies_select_
-- data_team_pool_scope.sql, which last touched vacancies_select_
-- secure): DROP POLICY IF EXISTS + CREATE POLICY, preserving each
-- policy's FOR/TO/roles exactly as currently defined. Postgres has no
-- CREATE OR REPLACE POLICY.
-- ============================================================

-- ── stores ──────────────────────────────────────────────────────

DROP POLICY IF EXISTS "stores_read_scoped" ON public.stores;
CREATE POLICY "stores_read_scoped" ON public.stores
FOR SELECT TO authenticated
USING (
  (is_active = true)
  AND (
    (select i_have_full_access())
    OR (account_id IN (
      SELECT a.id FROM public.accounts a
      WHERE (a.account_name = ANY ((select get_my_allowed_accounts())::text[]))
    ))
  )
);

DROP POLICY IF EXISTS "stores_write_admin" ON public.stores;
CREATE POLICY "stores_write_admin" ON public.stores
FOR ALL TO authenticated
USING ((select i_have_full_access()))
WITH CHECK ((select i_have_full_access()));

-- ── plantilla ───────────────────────────────────────────────────

DROP POLICY IF EXISTS "plantilla_insert_scoped" ON public.plantilla;
CREATE POLICY "plantilla_insert_scoped" ON public.plantilla
FOR INSERT TO public
WITH CHECK (
  (select i_have_full_access())
  OR (
    (NOT i_am_recruitment())
    AND (NOT i_am_hr_dept())
    AND (account = ANY ((select get_my_allowed_accounts())::text[]))
  )
);

DROP POLICY IF EXISTS "plantilla_read_scoped" ON public.plantilla;
CREATE POLICY "plantilla_read_scoped" ON public.plantilla
FOR SELECT TO public
USING (
  i_can_view_plantilla()
  AND (
    (select i_have_full_access())
    OR (
      (NOT i_am_hrco_only())
      AND (
        (account = ANY ((select get_my_allowed_accounts())::text[]))
        OR (
          (is_pool_employee = true)
          AND (
            (get_my_role_level() = 20)
            OR (get_my_role_level() = 30)
            OR (get_my_role_level() >= 90)
            OR ((get_my_role_level() >= 40) AND (get_my_role_level() <= 70))
          )
        )
      )
    )
    OR (
      i_am_hrco_only()
      AND (
        (i_have_hrco_global_visibility() AND (account = ANY ((select get_my_allowed_accounts())::text[])))
        OR (EXISTS (
          SELECT 1 FROM public.plantilla_hrco_assignments pha
          WHERE (pha.plantilla_id = plantilla.id)
            AND (pha.hrco_user_id = auth.uid())
            AND pha.is_active
        ))
      )
    )
  )
  AND (COALESCE(is_deleted, false) = false)
  AND ((deactivated_visible_until IS NULL) OR (deactivated_visible_until > now()))
);

DROP POLICY IF EXISTS "plantilla_update_scoped" ON public.plantilla;
CREATE POLICY "plantilla_update_scoped" ON public.plantilla
FOR UPDATE TO public
USING (
  (select i_have_full_access())
  OR (i_can_act_on_plantilla() AND (account = ANY ((select get_my_allowed_accounts())::text[])))
)
WITH CHECK (
  (select i_have_full_access())
  OR (i_can_act_on_plantilla() AND (account = ANY ((select get_my_allowed_accounts())::text[])))
);

-- ── plantilla_slots ─────────────────────────────────────────────

DROP POLICY IF EXISTS "plantilla_slots_read_scoped" ON public.plantilla_slots;
CREATE POLICY "plantilla_slots_read_scoped" ON public.plantilla_slots
FOR SELECT TO authenticated
USING (
  (select i_have_full_access())
  OR (account_id = ANY ((select get_my_allowed_account_ids())::uuid[]))
);

-- ── slot_history ────────────────────────────────────────────────

DROP POLICY IF EXISTS "slot_history_read_scoped" ON public.slot_history;
CREATE POLICY "slot_history_read_scoped" ON public.slot_history
FOR SELECT TO authenticated
USING (
  (select i_have_full_access())
  OR (account_id = ANY ((select get_my_allowed_account_ids())::uuid[]))
);

-- ── vacancies ───────────────────────────────────────────────────

DROP POLICY IF EXISTS "vacancies_block_hr_personnel" ON public.vacancies;
CREATE POLICY "vacancies_block_hr_personnel" ON public.vacancies
AS RESTRICTIVE
FOR ALL TO authenticated
USING (COALESCE((select get_my_role()), '') <> 'HR Personnel')
WITH CHECK (COALESCE((select get_my_role()), '') <> 'HR Personnel');

DROP POLICY IF EXISTS "vacancies_insert_admin_only" ON public.vacancies;
CREATE POLICY "vacancies_insert_admin_only" ON public.vacancies
FOR INSERT TO authenticated
WITH CHECK ((select i_have_full_access()));

DROP POLICY IF EXISTS "vacancies_select_secure" ON public.vacancies;
CREATE POLICY "vacancies_select_secure" ON public.vacancies
FOR SELECT TO authenticated
USING (
  ((deleted_at IS NULL) OR (select i_have_full_access()))
  AND (
    (select i_have_full_access())
    OR (account_id = ANY ((select get_my_allowed_account_ids())::uuid[]))
    OR i_am_assigned_to_vacancy(id)
    OR (get_my_role_level() = ANY (ARRAY[100, 90, 30]))
  )
);

DROP POLICY IF EXISTS "vacancies_update_admin_only" ON public.vacancies;
CREATE POLICY "vacancies_update_admin_only" ON public.vacancies
FOR UPDATE TO authenticated
USING ((select i_have_full_access()))
WITH CHECK ((select i_have_full_access()));
