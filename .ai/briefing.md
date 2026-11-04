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
1. **ohm#approvals-unified-and-query-fix (Approvals Module — Audit & Fix All Approval Tab Queries + Implement "All Requests" Unified Command Hub)**: Audited and resolved all row-fetching failures across `/approvals` queues and implemented the unified "All Requests" default command hub: (1) Fixed PostgREST schema and filter errors across 7 queues: removed non-existent `suppressed_by_batch_id` filter from `v_deactivation_requests` (fixing Deactivations queue), removed non-existent `is_archived` / `suppressed_by_batch_id` filters from `vw_amr_list` (fixing Applicant Movements queue), and corrected aliased relation join syntax for `groups!group_id`, `accounts!account_id`, `coverage_groups!target_coverage_group_id`, `vacancies!vacancy_vcode`, and `hr_emploc!hr_emploc_id` (fixing Account Group Transfers, Coverage, New Stores, Vacancy Closures, and HR Emploc Deletions); (2) Created `AllRequestsUnifiedQueue.tsx` as the default landing view on `/approvals` with a badge reflecting total pending requests across all categories; (3) Added resilient parallel data fetching via `Promise.allSettled()` across all categories, smart accordion section cards dynamically sorted with non-empty categories on top and empty ones collapsed at the bottom, 5-item preview cap with expand toggle, global search across all categories, and direct in-line row action execution (Approve / Reject / Review modals) with automatic query cache invalidation; (4) Added header `"Open Tab ->"` quick-switch buttons for each category; (5) Verified clean TypeScript typecheck (`tsc --noEmit`), zero ESLint errors, and clean Next.js production build (`npm run build` 20/20 routes passing).
2. **ohm#obsidian-contrast-button-fix (Design System — High-Contrast Readability & Button Visibility Fix for Obsidian Dark Mode)**: Resolved dark mode readability and invisible button text across `OHMployee_web`: (1) Fixed white-on-white button text on primary action buttons (`.bg-brand-button`, `.bg-brand-primary`, `.bg-primary`) by enforcing `#09090B` text and icons on off-white (`#FAFAFA`) fills in Dark Mode with `#E4E4E7` hover; (2) Replaced dark navy brand blue (`#2240b0`) with vibrant light sky blue (`#93c5fd` / `#8aa4ff`) for `.text-brand-600` and `.text-brand-500` in Dark Mode, making "Inspect Vacancy →" links, phone numbers, and email links crystal clear; (3) Elevated text hierarchy to WCAG AAA contrast: `--text-secondary` to `#D4D4D8` (13.5:1 contrast) and `--text-muted` to `#A1A1AA` (8.3:1 contrast), curing low-contrast notification texts, timestamps, and table metadata; (4) Set `--surface-base` and `--surface-card` to `#111113` (Dark Zinc) over `#0A0A0A` canvas to establish clear visual depth and separation; (5) Refactored `StatusBadge.tsx` to render semantic variant classes directly without badge component cascade overrides. Verified clean `npm run lint` and `npm run build` (20/20 routes passing).
3. **ohm#antigravity-obsidian-dark-mode (Design System — Antigravity-Inspired Obsidian Dark Mode, Theme Switcher (Light Default), and Font Choices)**: Implemented high-contrast, zero-shadow, hairline-border Obsidian Dark Mode inspired by Google Antigravity and Linear UI across `OHMployee_web`, keeping Light Mode strictly as the default theme for new sessions: (1) Standardized theme tokens in `src/app/globals.css` (.dark: Canvas `#0A0A0A`, Panels/Modals `#111113`, Hover `#18181B`, Hairline Borders `1px solid #222225`, Monospace Pills `#16181D` with border `#262930`, Action Buttons off-white `#FAFAFA` and secondary `#18181B` border `#27272A`, low-opacity tinted status badges, and stripped blurry box shadows via zero-shadow elevation rules); (2) Added seamless theme switching (Light / Dark / System) with zero flicker across `PreferencesTab.tsx`, `Sidebar.tsx` footer, and `AdminTopbar.tsx` mobile header; (3) Refactored `OhmniDrawer.tsx` floating overlay to consume semantic surface tokens (`#111113`, `#222225`, zero shadow); (4) Expanded Font Family options in `PreferencesTab.tsx` with `Inter` and `Geist Sans`, paired with `JetBrains Mono` and `Roboto Mono` via `.tech-token` / `.mono-pill` containers and dynamic `data-font` DOM synchronization; (5) Verified clean `npm run lint` (0 errors) and Next.js production build (`npm run build` 20/20 routes passing).
4. **ohm#vac-ui-refinements (Vacancy Module UI/UX & Data-Mapping Refinements + Global Required Asterisk)**: Implemented 4 UI/UX and data-mapping refinements across Vacancy module and system-wide forms: (1) Standardized global required field indicator `*` in Red (`#EF4444` / `text-red-500`) via new component `src/components/shared/RequiredAsterisk.tsx` and `.required-asterisk` utility across all Vacancy modals (`AddApplicantModal`, `MarkHiredModal`, `AdvancePipelineModal`, `EditApplicantModal`, `EditHiredDateModal`, `RequestVacancyClosureModal`, `FailBackoutModal`, `ReopenVacancyModal`, `SavedViewsModal`) and application form modals; (2) In `MarkHiredModal`, locked candidate identity fields (`Last Name`, `First Name`, `Middle Name`, `Contact Number`) as read-only/disabled with grayed-out styling, and converted `Endorsed By Deployer` into a searchable select populated by `useUsersList()` scoped to vacancy group/account users, defaulting to the candidate's initial endorsement; (3) Restyled `Closure Clearance In-Flight` notice container, clock icon, and top/inline `Pending Clearance` status badges with cohesive Red/Rose theme (`#FEF2F2`, `#FECACA`, `#991B1B`, `#DC2626`) and white subtle-border `Withdraw Closure Request` button; (4) Resolved HRCO column in Vacancy module across all 5 tabs (`Open`, `Pipeline`, `Hired`, `Closure`, `Failed / Backout`) and CSV exports via canonical view `public.vw_vacancy_list`, rendering clean `Unassigned` badges consistently when unassigned.
5. **ohm#q3v8n2kd (HR Emploc — Stage 2b-DB on STAGING (For Emploc status, scoped Ops docs, private Storage, 3-day purge queue, cross-module pipeline fixes) + Migration History Hygiene (20262606000083 & 20262606000084))**: Implemented Stage 2b-DB on STAGING (`qqiiznmqxfoamqytjica`); PROD (`rwxelulyapjgaarlwkus`) frozen read-only awaiting single coordinated release (`…83` + `…84` + web + mobile). Restored `20262606000081` and `…82` to exact `bb2e31f` blobs (verified MD5s); generated delta migration `20262606000083_hr_emploc_phase2a_fix_delta.sql` with verified 100% no-op on STAGING and dry-run against PROD; authored and applied `20262606000084_hr_emploc_for_emploc_and_scoped_docs.sql` and `supabase/rollbacks/rollback_20262606000084.sql`. Verified 100% rollback match (all 21 modified objects identical to pre-84 definitions) and 100% re-apply idempotency. Configured private bucket `hr-corrections`, scoped doc authorization, `storage_cleanup_queue` with 3-day TTL via pg_net and cron, and report-only orphan sweeper. Proven 100% pending deletion locks (13/13 blocked), 100% scope parity and dashboard metric invariance, real Storage API purge with signed URL 404, and 31/31 comprehensive test suite cases passing on Staging.

> Older entries trimmed 2026-10-28 (`ohm#4x7n2k9w Phase 5 REVISED`) to keep this list to 5 — see git history for earlier entries in full.
