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
1. **ohm#f4w9q1mt (Approvals Rollback Queue: Streamline Action Buttons & Vertical Reason Note Layout)**: Applied targeted UI refinements to `RollbackDataTable.tsx`: (1) Actions Simplification: removed the redundant `View` button and eye icon from the Actions column (retaining native row click to open full batch detail modal); (2) Action Labeling: omitted `& Execute` from the approval button label, simplifying it to clean `Approve` with danger solid fill (`bg-[var(--danger-button)] hover:bg-[var(--danger-button-hover)] text-white shadow-2xs`) alongside `Reject`; (3) Layout Alignment: stacked the rollback reason code badge on top and the custom note/justification text directly below it in a vertical flex container; (4) Quality Gates: `npm run lint` clean (0 errors), `npm run build` clean (20/20 static routes generated).
2. **ohm#k2v8m4sp (Approvals HR Emploc Deletions: Resolve Missing Group & Account Scope)**: Fixed empty/dash Group and Account display in the HR Emploc Deletions queue (`/approvals`): (1) Root Cause: `fetchEmplocDeletionRequests` in `hr_emploc.ts` hardcoded `accountName: null, groupName: null` and omitted `account` and `account_id` from the Supabase select projection; (2) Data Resolution: added `account` to `hr_emploc_deletion_requests` select and `account, account_id` to joined `hr_emploc`; performed primary batch lookup against `accounts` (with `groups(group_name)`) by `account_id` and `account_name`, and secondary fallback lookup against `vacancies` by `vcode` (`accounts(groups(group_name))` and `groups(group_name)`), ensuring locator and vacancy records (e.g., `VCY61_0001`) resolve to their operational Group and Account; (3) Search Filtering: updated `filteredDeletionRequests` in `ActiveQueueReviewPane.tsx` and `AllRequestsUnifiedQueue.tsx` to search against `req.groupName` and `req.accountName`; (4) Modal Detail: displayed resolved `Scope (Group / Account)` in the Single Approve modal summary; (5) Quality Gates: `npm run lint` clean (0 errors), `npm run build` clean (20/20 static routes generated).
3. **ohm#r7b3x9mq (Approvals Module: Add Rollback Review Queue Tab for Import Batch Reversals)**: Integrated a dedicated "Rollbacks" category tab into `/approvals`: (1) Queries & State (`requests.ts`): added `"rollbacks"` to `RequestCategoryKey`, configured category metadata and dual-table pending count aggregator across `plantilla_import_batches` and `vacancy_import_batches`; built `fetchRollbackApprovalRequests`, `fetchRollbackApprovalCounts`, `useRollbackApprovalRequests`, `useRollbackApprovalCounts`, `useApproveRollbackRequest`, and `useRejectRollbackRequest`; (2) RBAC Gatekeeper (`rbac.ts`): granted access to Super Admin (`level >= 100` / `isOwner`) and Head Admin (`level === 90`) in `getAllowedApprovalCategories`; (3) Table & Detail Modal (`RollbackDataTable.tsx`): created full queue table with status tabs (`Pending`, `Approved`, `Rejected`), detailed batch cards, governance window countdowns, reusable `<Pagination />` (10/25/50 items), batch details modal, solid danger button confirmation for `Approve & Execute Rollback`, and reviewer rejection justification modal; (4) Approvals Integration (`ActiveQueueReviewPane.tsx`, `AllRequestsUnifiedQueue.tsx`, `RequestCategoryNavigation.tsx`, `page.tsx`): wired category navigation icon (`RotateCcw`), dynamic search filter, and parallel execution in Unified All Requests Command Center; (5) Quality Gates: `npm run lint` clean (0 errors), `npm run build` clean (20/20 static routes generated).
4. **ohm#t5k9w2rn (Plantilla Import Batch Detail Modal: Fix Solid Danger Button Styling & Light/Dark Theme Tokens)**: Remediated modal action button visibility and theming in `PlantillaImportModal.tsx` and `globals.css`: (1) Root Cause: `bg-[var(--danger)]` referenced an undefined CSS variable, rendering the `Approve & Execute Rollback` button with an empty/transparent background, causing white text on a white modal to be 100% invisible in light mode and bare text without a container in dark mode; (2) Button Styling: replaced `bg-[var(--danger)]` across all 5 modal and sub-modal buttons (`Approve & Execute Rollback`, `Emergency Rollback Override`, `Submit Request`, `Approve & Execute`, and `Execute Override`) with solid `bg-[var(--danger-button)] hover:bg-[var(--danger-button-hover)] text-white shadow-2xs`; (3) Compatibility Token Aliases: added `--danger: var(--danger-text);` to both light and dark mode token mappings in `src/app/globals.css`; (4) Quality Gates: `npm run lint` clean (0 errors), `tsc --noEmit` clean, and `npm run build` clean (20/20 static routes generated).
5. **ohm#p8m4v7xw (Plantilla Import History: Modular Pagination & Modal Batch Detail View)**: Refactored the `Import History` table in `PlantillaImportModal.tsx`: (1) Modal Detail View: replaced inline bottom-of-page rendering with a dedicated `<Modal />` component (`max-w-4xl`) opened upon clicking any history table row (e.g., `Batch #6cc4d720`), displaying full Failure Audit & Error Log (for `validation_failed` / `rejected`) with field error badges and interactive row breakdown, or Rollback Governance (for approved / rolled back batches) with countdown window, rollback block reasons, and governance action controls; (2) Reusable Pagination: built and exported reusable `<Pagination />` and `usePagination` hook (`src/components/shared/Pagination.tsx` and `src/hooks/usePagination.ts`), featuring Next/Prev controls, page numbers with ellipsis handling, items-per-page selector (10/25/50), range label ("Showing X–Y of Z records"), and modular `{ page, limit, offset }` params for cross-module reuse; (3) Quality Gates: `npm run lint` clean (0 errors), `tsc --noEmit` clean, and `npm run build` clean (20/20 routes passing).

> Older entries trimmed 2026-10-28 (`ohm#4x7n2k9w Phase 5 REVISED`) to keep this list to 5 — see git history for earlier entries in full.
