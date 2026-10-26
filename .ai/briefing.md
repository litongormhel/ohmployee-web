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
1. **ohm#lmorb8h3**: UI Standard & Motion System — Loop 7H: More B Import Centers & QA Alignment (Standardized all 9 import centers, data control hubs, recovery suites, and QA screens in More B: `HrEmplocImportModal`, `PayrollImportModal`, `PayrollReviewCenterModal`, `MikaImportModal`, `QaCenterModal`, `GlobalStoreTransferModal`, `DataArchivalCenterModal`, `PlantillaImportModal`, and `VacancyImportModal`; wrapped root wizards and 10 nested action sub-dialogs in canonical `Modal` with `disableBackdropClick={isBusy}`, `isSubmitting={isBusy}`, dirty tracking, and Esc handling; enforced typography floor >= 14px (`text-sm`) across all preview tables, review drawers, archived repositories, and audit logs; eliminated over 1,400 baseline color literals down to exactly 0; preserved `--danger` strictly for rejections, hard validation conflicts, destructive bulk archives, rollback confirmations, and emergency overrides; ESLint clean with 0 errors; Next.js 16.2.4 Turbopack build green with 0 errors)
2. **ohm#lmora7g2**: UI Standard & Motion System — Loop 7G: More A Governance & Security Alignment (Standardized all 13 governance and security screens in More A: `more/page.tsx`, `AuditLogsModal`, `SecurityEventsModal`, `RolePermissionsModal`, `PermissionMatrixModal`, `SwitchRoleModal`, `PermissionDriftModal`, `RovingCoverageGroupsModal`, `EditLockControlModal`, `AccountRequestsModal`, `AccessControlCenterModal`, `OhmsSafespaceModal`, and `TempPermissionModal`; wrapped root and sub-modals in canonical `Modal` with `disableBackdropClick={isBusy}`, `isSubmitting={isBusy}`, dirty tracking, and Esc handling; enforced typography floor >= 14px (`text-sm`) across all matrices, audit logs, and streams; eliminated over 1,200 baseline color literals down to exactly 0; preserved `--danger` strictly for rejections, freezes, gaps, breaches, and critical incidents; ESLint clean with 0 errors; Next.js 16.2.4 Turbopack build green with 0 errors)
3. **ohm#lset6f8p**: UI Standard & Motion System — Loop 7F: Settings & System Governance Alignment (Standardized all 6 settings files: `settings/page.tsx`, `ProfileTab`, `PreferencesTab`, `SecurityTab`, `DiagnosticsTab`, and `ChangePasswordModal`; wrapped `ChangePasswordModal` and 2 session revocation dialogs in canonical `Modal` with `disableBackdropClick={isBusy}`, `isSubmitting={isBusy}`, and dirty tracking; eliminated all 267 baseline color literals down to exactly 0; preserved `--danger` strictly for session revocation, emergency freeze locks, and fatal probe alerts; ESLint clean with 0 errors; Next.js 16.2.4 Turbopack build green with 0 errors)
4. **ohm#lrpt5m1k**: UI Standard & Motion System — Loop 7E: Reports Hub Alignment (Standardized all 10 reports views and drilldown dialogs: `ReportsCatalogTab`, `FloatingStaffTab`, `TeamPerformanceTab`, `DataIntegrityTab`, `CustomReportTab`, `ReportDetailView`, `TeamPerformanceIssuesModal`, `DataIntegrityDetailModal`, `AttritionDrilldownModal`, and `reports/page.tsx`; wrapped all drilldown modals in canonical `Modal` with `disableBackdropClick={isBusy}`, `isSubmitting={isBusy}`, and dirty-Esc handling; enforced typography floor >= 14px (`text-sm`) across all report data tables; eliminated all 400+ raw color literals down to exactly 0; preserved `--danger` strictly for SLA breaches, ghost occupancy, and critical audit findings; ESLint clean with 0 errors; Turbopack `npm run build` green with 0 errors)
5. **ohm#lntf4k2w**: UI Standard & Motion System — Loop 7D: Notifications Activity Center Alignment (Standardized notifications stream, category tabs, card tone categorization, and empty state illustrations; eliminated all 44 color literals down to 0; preserved `--danger` strictly for SLA breaches and rejections; preserved realtime subscription and deep linking; ESLint clean with 0 errors; `npx tsc --noEmit` green with 0 errors)

> Older entries trimmed 2026-10-26 (`ohm#l6c3w8m2`) to keep this list to 5 — dropped `ohm#r7m2k9w5` and earlier entries — see git history for that and earlier entries in full.
