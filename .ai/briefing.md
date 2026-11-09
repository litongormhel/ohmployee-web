# AI Briefing

## Mandatory Workflow Rules (apply to EVERY prompt, even if the prompt body does not mention them)

### Approval & Regression Gate
Before writing any code, schema change, or migration: present a short implementation plan
plus a regression risk assessment (what could break, what's untouched). STOP and WAIT for
explicit user approval. Do not implement in the same turn the plan is presented. This applies
even when the prompt already describes the approach in detail.
*Standing UI Standard Loop Override:* The UI Standard loop (`ohm#l0u8s2d9` onward) runs WITHOUT an approval gate. The loop pauses only on the stop conditions in `docs/architecture/ui-standard-briefing.md` section 10 or when verification fails. This overrides the generic "stop and wait" rule for this project only. Do not ask for approval again unless a stop condition triggers.

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
1. **ohm#darkmode-contrast-fix (Design System & UI — Dark Mode Contrast Fix for Action Buttons, Overflow Badges, Role Pills, and Pagination)**: Resolved dark mode contrast and solid white background washout issues across Vacancy Management (`/vacancy`) and User Management (`/users`): (1) In `src/components/vacancy/VacancyTable.tsx`, styled the `+ Applicant` button with dark surface and contrast borders (`dark:bg-zinc-800 dark:hover:bg-zinc-700 dark:text-zinc-100 dark:border-zinc-700`) and the Pipeline and Closure `Approve` buttons with semantic emerald dark styling (`dark:bg-emerald-500/15 dark:text-emerald-400 dark:border-emerald-500/30 dark:hover:bg-emerald-500/25`); (2) In `VacancyTable.tsx` and `src/components/hr-emploc/useInheritedHrco.tsx`, styled outlet and HRCO overflow count badges (`+X` / `+3`) with muted dark badge tokens (`dark:bg-zinc-800 dark:text-zinc-300 dark:border-zinc-700`) and added multi-HRCO overflow formatting; (3) In `src/components/users/UsersTable.tsx`, updated the `Scoped` and `Global` role badges, main role badge, and avatar initials with high-contrast dark mode surface and border tokens (`dark:bg-zinc-800 dark:text-zinc-300 dark:border-zinc-700`); (4) In `src/components/shared/TablePagination.tsx`, `src/app/(dashboard)/vacancy/page.tsx`, and `src/app/(dashboard)/users/page.tsx`, explicitly set dark mode text color (`dark:text-zinc-950 font-semibold`) on active page number and active tab counter badges to prevent washout against white button surfaces. Verified clean linting (0 errors) and successful Next.js production build (20/20 routes passing).
2. **ohm#q3v8n2kd (HR Emploc — Stage 2b-Web (For Emploc tab, Ops docs upload, preview, Add Emploc flow) + 2b-DB closure on STAGING)**: Completed Stage 2b-Web implementation and closed all 2b-DB review evidence gaps against Staging (`qqiiznmqxfoamqytjica`) while Production (`rwxelulyapjgaarlwkus`) remains frozen read-only: (1) In `src/lib/queries/hr_emploc.ts`, added `for_emploc` queue, `For Emploc` status, `for_emploc_count` in summary, capability & attachment types, mutation hooks for authorize/storage upload/register/remove docs, `submit_hr_emploc_requirements`, and short-TTL signed URLs; removed obsolete `moveToPlantilla` / `fetchAvailableSlotsForVcode` and direct table-insert fallbacks; created remarks normalizer with `ops_remarks` top precedence; (2) Created standardized error mapper `src/lib/utils/hr_emploc_errors.ts` prioritizing Postgres DETAIL `code` first, message token prefix second, and SQLSTATE third; verified 12/12 unit tests pass; (3) Created client-side Canvas image compression (`src/lib/utils/image_compression.ts`) for JPEG/PNG/WEBP (max 1600px, 0.75 quality, PDF passthrough); (4) Built `UploadDocsModal.tsx` (sequential authorize -> upload -> idempotent register pipeline with unverified doc removal and "Submit & Move to For Emploc" / "Submit Correction" buttons); (5) Built `DocumentPreviewModal.tsx` (multi-file switcher, image zoom/rotate, PDF iframe, download); (6) Built `AddEmplocModal.tsx` (atomic single-RPC assignment with interactive confirmation sub-dialog for rehire/duplicate/middle-name reuse); (7) In `HrEmplocTable.tsx`, fixed horizontal clipping with sticky right Actions column; implemented per-tab columns and 100% capability-driven actions; (8) Deleted 5 obsolete modals; (9) Closed 2b-DB gaps on Staging: full rehearsal (rollback 84 -> rollback 83 -> apply 83 -> apply 84 -> smoke test -> 31-test suite 100% pass), overload audit (23/23 count 1), schema_migrations alignment report (PROD at 82, Staging at 84), PROD dry run (93 rows), storage orphan report (8 on Staging: 0 orphans; 18 on PROD: 16 orphans from May 15), purge executor audit (`process_storage_cleanup_queue` on `*/15 * * * *` cron), and missing test suite (5/5 pass). Mechanical gates clean: `npm run lint` clean (0 errors), `npm run build` clean (20/20 routes compiled).
3. **ohm#fix-approval-queues-root-cause (Approvals Module — Permanent Root-Cause Fix for All Approval Queues & Active Tab Auto-Scroll)**: Resolved the underlying PostgREST column and filter mismatches across failing approval tabs (`HR Emploc Deletions`, `New Stores`, `Vacancy Closures`, and `Headcount`) and resolved Next.js runtime issues: (1) In `src/lib/queries/hr_emploc.ts`, removed non-existent `account_name` join on `hr_emploc` and removed synthetic `.or("is_archived.is.null...").is("suppressed_by_batch_id", null)` filters from `fetchEmplocDeletionRequests`; (2) In `src/lib/queries/requests.ts`, stripped non-existent `suppressed_by_batch_id` from `fetchNewStoreRequests` and `countPromises` (retaining `is_archived = false`); stripped non-existent `is_archived` and `suppressed_by_batch_id` from `fetchVacancyClosureRequests` and `countPromises` to match canonical status lifecycle; stripped non-existent `suppressed_by_batch_id` from `fetchHeadcountRequests` and `countPromises`; (3) In `src/components/approvals/RequestCategoryNavigation.tsx`, implemented active tab auto-scroll (`activeTabRef.current.scrollIntoView`) to ensure active tab pill is always visible; (4) Verified 100% of approval queries pass schema compilation, verified clean TypeScript typecheck (`tsc --noEmit`), zero ESLint errors, and 20/20 Next.js routes passing in `npm run build`.
4. **ohm#fix-approval-queries-remove-plantilla (Approvals Module — Fix PostgREST Query Errors Across All Approval Tabs & Remove Plantilla Placements)**: Fixed PostgREST schema and filter errors across remaining approval tabs and completely excised obsolete "Plantilla Placements" tab across navigation, review pane, unified queue, routing, and RBAC: (1) In `src/lib/queries/requests.ts`, stripped invalid `.eq("is_archived", false).is("suppressed_by_batch_id", null)` filters from `fetchAccountGroupTransfers` and count queries; stripped invalid filters from `fetchCoverageRequests` to match canonical `.is("archived_at", null)`; fixed foreign key joins for accounts, groups, and coverage groups; and removed `plantilla_approvals` from category key unions and category counts; (2) Excised `plantilla_approvals` from `RequestCategoryNavigation.tsx`, `page.tsx` (`VALID_CATEGORIES` and default count state), and `src/lib/rbac.ts` (`getAllowedApprovalCategories` across all roles); (3) Removed `PlantillaApprovalDataTable`, hooks, and UI view blocks from `ActiveQueueReviewPane.tsx` and `AllRequestsUnifiedQueue.tsx`; (4) Verified zero TypeScript errors (`tsc --noEmit`), zero ESLint errors (`npm run lint`), and 20/20 routes passing in Next.js production build (`npm run build`).
5. **ohm#approvals-unified-and-query-fix (Approvals Module — Audit & Fix All Approval Tab Queries + Implement "All Requests" Unified Command Hub)**: Audited and resolved all row-fetching failures across `/approvals` queues and implemented the unified "All Requests" default command hub: (1) Fixed PostgREST schema and filter errors across 7 queues: removed non-existent `suppressed_by_batch_id` filter from `v_deactivation_requests` (fixing Deactivations queue), removed non-existent `is_archived` / `suppressed_by_batch_id` filters from `vw_amr_list` (fixing Applicant Movements queue), and corrected aliased relation join syntax for `groups!group_id`, `accounts!account_id`, `coverage_groups!target_coverage_group_id`, `vacancies!vacancy_vcode`, and `hr_emploc!hr_emploc_id` (fixing Account Group Transfers, Coverage, New Stores, Vacancy Closures, and HR Emploc Deletions); (2) Created `AllRequestsUnifiedQueue.tsx` as the default landing view on `/approvals` with a badge reflecting total pending requests across all categories; (3) Added resilient parallel data fetching via `Promise.allSettled()` across all categories, smart accordion section cards dynamically sorted with non-empty categories on top and empty ones collapsed at the bottom, 5-item preview cap with expand toggle, global search across all categories, and direct in-line row action execution (Approve / Reject / Review modals) with automatic query cache invalidation; (4) Added header `"Open Tab ->"` quick-switch buttons for each category; (5) Verified clean TypeScript typecheck (`tsc --noEmit`), zero ESLint errors, and clean Next.js production build (`npm run build` 20/20 routes passing).

> Older entries trimmed 2026-10-28 (`ohm#4x7n2k9w Phase 5 REVISED`) to keep this list to 5 — see git history for earlier entries in full.
