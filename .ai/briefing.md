# AI Briefing

## Mandatory Workflow Rules (apply to EVERY prompt, even if the prompt body does not mention them)

### Approval & Regression Gate
Before writing any code, schema change, or migration: present a short implementation plan
plus a regression risk assessment (what could break, what's untouched). STOP and WAIT for
explicit user approval. Do not implement in the same turn the plan is presented. This applies
even when the prompt already describes the approach in detail.
*Standing UI Standard Loop Override:* The UI Standard loop (`ohm#l0u8s2d9` onward) runs WITHOUT an approval gate. The loop pauses only on the stop conditions in `docs/architecture/ui-standard-briefing.md` section 10 or when verification fails. This overrides the generic "stop and wait" rule for this project only. Do not ask for approval again unless a stop condition triggers.
*Scope-Expansion Rule:* If any later test or investigation shows a change is needed outside an approved plan (any function, table, file or migration not listed), STOP and present an amended plan. Do not extend scope.
*Post-Migration Live Diff Rule:* After applying any migration to staging, diff live `pg_get_functiondef` vs the committed file for every touched function.
*REPORTING INTEGRITY:* every table, count, SQL result, timestamp, assertion list and code excerpt in a report or handoff must be copied from a tool output of the current task, with the query or file and line shown. Never reconstruct, round, summarize from memory or fill in a result you did not obtain. If a check was not run, write NOT RUN. If a value is unknown, write NOT VERIFIED.

### ADR Architecture Lock Reference
ADR-001 location (read-only from mobile repo): `/Users/armanjr/Projects/OHMployee/OHMployee/.ai/architecture_locks/adr_001_coverage_architecture_v2.md`.
Do not edit the ADR from this web repo. If a loop requires an ADR update, log it in handoff under "ADR updates needed (Ohm applies in mobile repo)". In every loop report, state "ADR basis: <file + sections>".

### Branch Policy
Work on `main` only. Never create a branch unless the prompt explicitly says "create a branch".
Never merge, push, or delete a branch on your own initiative. If the session environment
created a branch (e.g. remote/cloud task isolation), report it in the handoff entry; Ohm
verifies, merges to `main`, and deletes it.

### Database Access & Modification Rule
No DDL, function execution, or writes against any Supabase project without Ohm's explicit instruction in that prompt, and NEVER from a UI loop. All database access for UI work is strictly prohibited.

### Supabase Environments & Project References
- **Production:** `rwxelulyapjgaarlwkus`
- **Staging:** `qqiiznmqxfoamqytjica`
- Agent sessions and localhost must use staging (`qqiiznmqxfoamqytjica`).
- NEVER connect to the production ref (`rwxelulyapjgaarlwkus`).

### After Every Completed Prompt (mandatory, in this order)
1. `.ai/briefing.md` — prepend PROMPT ID + title to "Last Completed Tasks" (keep only 5)
2. `.ai/handoff.md` — prepend full handoff entry
3. `docs/state/<module>_state.md` — surgical update if behavior changed
4. Local commit (see "Local Commit Rule" below)
5. Branch close-out — if a branch exists, Ohm verifies (`npm run lint` / `npm run build` /
   manual test), merges into `main`, then deletes the branch. AI only reports the branch.

### Local Commit Rule (every prompt, after items 1-3)
- Commit LOCALLY on `main`. NEVER `git push`, merge, rebase, amend, reset, or delete anything.
- Stage ONLY the files this prompt changed, by explicit path. Never `git add .` or `git add -A`.
- Include the doc files updated in items 1-3 (briefing.md, handoff.md, state file) and any new
  migration file this prompt created. Committing a migration file does NOT apply it.
- Before committing, run `git status`. If a file this prompt touched already had uncommitted
  changes from before this prompt started, do NOT stage it. Report it and skip the commit.
- Commit only if verification passed: `npm run lint` clean for any code change (docs-only
  prompts need no lint). If verification fails, do not commit; report the failure.
- Commit only if on `main`. If on any other branch, do not commit; report it.
- Message format: `<PROMPT ID>: <PROMPT TITLE>`.
- After committing, report the commit hash and the exact files included.

State files = current stable behavior only. handoff.md = active sprint continuity only.
Archive obsolete logs to `docs/archive/`.

## Last Completed Tasks
1. **ohm#p8m4v7xw (Plantilla Import History: Modular Pagination & Modal Batch Detail View)**: Refactored the `Import History` table in `PlantillaImportModal.tsx`: (1) Modal Detail View: replaced inline bottom-of-page rendering with a dedicated `<Modal />` component (`max-w-4xl`) opened upon clicking any history table row (e.g., `Batch #6cc4d720`), displaying full Failure Audit & Error Log (for `validation_failed` / `rejected`) with field error badges and interactive row breakdown, or Rollback Governance (for approved / rolled back batches) with countdown window, rollback block reasons, and governance action controls; (2) Reusable Pagination: built and exported reusable `<Pagination />` and `usePagination` hook (`src/components/shared/Pagination.tsx` and `src/hooks/usePagination.ts`), featuring Next/Prev controls, page numbers with ellipsis handling, items-per-page selector (10/25/50), range label ("Showing X–Y of Z records"), and modular `{ page, limit, offset }` params for cross-module reuse; (3) Quality Gates: `npm run lint` clean (0 errors), `tsc --noEmit` clean, and `npm run build` clean (20/20 routes passing).
2. **ohm#u3s8m2ql (User Management: Responsive Natural Scroll, Bottom Pagination, Group Filter, Table Kebab Actions, Role Edit Modal & Conversational Audit Log)**: Completed full module redesign across `src/app/(dashboard)/users/page.tsx`, `src/components/users/UsersTable.tsx`, and `src/components/users/UserDetailDrawer.tsx`: (1) Layout & Scrolling: removed fixed `h-screen` and locked overflows, enabling natural vertical document scrolling; (2) Header Tabs: replaced large KPI cards with compact unified `SegmentedTabs` (`All Users (${totalCount})` | `Active (${activeCount})` | `Inactive (${inactiveCount})`); (3) Action Buttons: prioritized "Create User" (brand fill, SA only) and deprioritized "Temporary Overrides" and "Account Requests" with subtle bordered surfaces; (4) Unified Filters: aligned Search Bar, Role Dropdown, and new Group Dropdown on a single row above the table; (5) Table Specifications: compact row padding (`px-4 py-2.5`), circular initials avatar + full name + email, role pill with italicized scoped/global subtext, plain text Group/Account, kebab menu (`...`) with status toggle, password reset, and soft archive modals, plus standard bottom `TablePagination` with 10/25/50 row selector; (6) Detail Drawer: replaced inline role `<select>` with read-only text, SA/HA lock note, and an explicit `EditRoleConfirmationModal` with diff preview; matched Danger Zone to kebab actions; translated raw audit logs into human-friendly conversational sentences with actor initials avatar; (7) Quality Gates: 0 color literals in `users` module, `npm run lint` clean (0 errors), `tsc --noEmit` clean, and `npm run build` clean (20/20 static routes generated).
3. **ohm#r4t7y2bn (Phase 2: Plantilla Import — Rollback Lineage Reset, Executor Lockdown & Protected Occupant Guard)**: Applied migration `20262606000087_reset_incomplete_plantilla_rollback_lineage_and_lock_executor.sql` on Staging (`qqiiznmqxfoamqytjica`): (1) Reset `rollback_ready = false` for legacy approved batch `1dcb71eb-742d-4fbc-83a0-703cb57f64b5` lacking allocation insert/slot snapshots, strictly preserving vacant-only and valid 086-approved batches; (2) Revoked EXECUTE on `rollback_plantilla_import_batch` from PUBLIC, anon, authenticated (direct PostgREST RPC hard-denied 42501), granting only to `service_role` while SECURITY DEFINER wrappers execute as postgres; (3) Hardened `rollback_plantilla_import_batch` with protected occupant guard (`ROLLBACK_BLOCKED_PROTECTED_OCCUPANT`), preventing orphan deletions when batch-created slots are occupied by external employees; (4) Verified normalized diff between live `pg_get_functiondef` and migration file; (5) Extended self-rolling-back test harness `scripts/tests/plantilla_import_regression.sql` covering vacant-only immunity, direct execution denial, protected occupant abort, and full 6-table post-rollback baseline comparison (`ALL_ASSERTIONS_PASSED`).
4. **ohm#r4t7y2bn (Plantilla Import — Fix Rollback Readiness & Store Closure Cascade Vacancies Trigger)**: Completed investigation and remediation on Staging (`qqiiznmqxfoamqytjica`): (1) Root-caused `rollback_ready` remaining `false`: migration `20262606000059_fix_plantilla_field_inheritance_and_mapping.sql` (`ohm#f7m2w9x4`) replaced `approve_plantilla_import_batch` with a function template omitting `rollback_ready = true` (and `committed_stores`/`committed_employees`), carried forward through `062` and `064`. Before 086, snapshots existed for store, plantilla and Phase B1 vacant slots. allocation (insert) snapshots and Phase B2 slot snapshots (occupied or claimed) were first written by 086. Legacy batches have allocation (update) snapshots only; (2) Root-caused store closure trigger error: migration `20262606000057_route_store_deletion_to_closure_tab.sql` from mobile repo introduced `fn_trg_store_closure_cascade_vacancies()` referencing `vacancies.closed_at`, which was never added to the schema in either repository; (3) Created and applied migration `20262606000086_fix_plantilla_import_rollback_ready_and_store_closure_trigger.sql` on Staging: added `closed_at timestamptz` to `public.vacancies`, re-asserted safe `fn_trg_store_closure_cascade_vacancies()` setting `status = 'Closed'` and `is_archived = true`, updated `approve_plantilla_import_batch()` to record commit snapshots for stores, plantilla, Phase B1 vacant slots, allocations, and Phase B2 slots/vacancies while asserting `rollback_ready = true`, updated `rollback_plantilla_import_batch()` to safely restore/deactivate allocations and close/restore slots, and backfilled approved batches; (4) Enhanced and executed self-rolling-back test harness `scripts/tests/plantilla_import_regression.sql` verifying stationary evaluation, roving submission (`pending_approval`, 0 flagged), approval, rollback execution (100% restoration to baseline active plantilla and allocations), blocked file rejection (`BATCH_BLOCKED`), and batch rejection with audit trail (`ALL_ASSERTIONS_PASSED`); (5) Quality gates clean: `npm run lint` clean (0 errors), `npm run build` clean (20/20 routes passing).
5. **ohm#k6w3n8qd (Plantilla Import — Staging Audit, Cleanup Script, Idempotency & SQL Regression Test Harness)**: Completed cleanup audit and test harness tasks: (1) Performed exhaustive read-only audit of staging database (`qqiiznmqxfoamqytjica`) vs baseline for Group 4 / APEX across stores, plantilla, slots, allocations, links, vacancies, views, summaries, and batches; (2) Authored non-executed FK-ordered cleanup script `scripts/staging_cleanup_ohm_k6w3n8qd.sql` targeting explicit IDs, documented how it safely bypasses broken trigger `fn_trg_store_closure_cascade_vacancies` by avoiding UPDATEs on stores; (3) Measured live idempotency inside atomic DO block with 100% rollback (`idem_stores_persisted = 0`): re-submitting and re-approving identical 14 roving rows detects 14 existing stores, 0 new stores, and yields identical counts (14 stores, 14 slots, 14 allocations, 4 plantilla employees, 14 links); (4) Authored self-rolling-back PostgreSQL regression test harness `scripts/tests/plantilla_import_regression.sql` (deleted obsolete `.mjs` script), asserting stationary valid, roving valid (14 rows, 0 flagged, batch `pending_approval`), approve execution, server-side blocking (`BATCH_BLOCKED: ...`), and rejection audit trail with forced rollback; (5) Documented regression suite in `docs/state/plantilla_web_state.md`, updated handoff notes with mobile follow-up and orchestrator corrections; (6) Verified mechanical quality gates: `tsc --noEmit` clean, `npm run lint` clean (0 errors), `npm run build` clean (20/20 routes passing).

> Older entries trimmed 2026-10-28 (`ohm#4x7n2k9w Phase 5 REVISED`) to keep this list to 5 — see git history for earlier entries in full.
