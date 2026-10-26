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
1. **ohm#arch01**: QA Reset Soft-Archive & 72-Hour Rollback System (Implemented 100% soft-archive sweep of operational, telemetry, and request tables while preserving User Accounts, Roles/Permissions, and Account Sign-Ups; added `is_archived`, `archived_at`, `archive_batch_id`, and `suppressed_by_batch_id` via dynamic inspection across target operational tables; implemented `resolve_audit_actor_id` to dynamically resolve actor IDs to the exact foreign key referenced table on `audit_logs`, permanently fixing the `audit_logs_actor_id_fkey` rollback violation; created `execute_qa_reset_archive` and `rollback_archive_batch` RPCs with dual write to canonical `archive_batches` and `system_archive_batches`; updated `fn_dashboard_metrics`, `fn_dashboard_operational_analytics`, and `fn_cencom_deployment_summary` RPCs in migration `20261026000002_qa_reset_soft_archive_and_atomic_rollback.sql`; synchronized read queries across requests, hr_emploc, cencom, and dashboard; wired global query cache invalidation on archive and rollback; ESLint clean, Next.js build 19/19 routes green; zero database mutation performed)
2. **ohm#uifix03**: UI Staging Pass — Table Headers, Zero-HC Display, Title-Casing, Scrim & Button Contrast (Unified table headers to 14px sentence case [text-sm font-semibold whitespace-nowrap text-text-secondary] preserving uppercase acronyms VCODE, HRCO, HC, SLA, MFR across all tables; gated Plantilla, Dashboard matrix, and CENCOM group zero-headcount displays to hide Warning chip, show "—", and render neutral track when required HC = 0; implemented displayText.ts formatter title-casing names, positions, accounts, and stores while preserving allowlist and alphanumeric identifiers with 15 verified tests; registered --surface-overlay [45% light, 65% dark] and missing color tokens in @theme inline resolving invisible scrims; humanized Vacancy drawer aging brackets and pool/pipeline enums; aligned Dashboard Open Vacancies card fill rate percentage color to fill_rate scale; eliminated washed-out disabled buttons across 14 modals using high-contrast surface-muted/text-secondary; scoped sidebar active outline to focus-visible only; extended audit_component_contrast.py verifying 100 @theme tokens with zero unregistered semantic color tokens; zero DB access performed; ESLint clean, Next.js build 19/19 routes green, gate.py blocking production ref; local commit on main)
3. **ohm#rbac01**: Drawer Actions & Mutations RBAC Matrix Full Synchronization & Enforced Guards (Implemented and enforced the authoritative 55-item Drawer Actions & Mutations RBAC Matrix across all 11 role levels [Super Admin 100 to Viewer 10]; created database migration `supabase/migrations/20261026000001_update_drawer_actions_rbac.sql` with `role_permission_definitions_compat` matrix seed, definition catalog insertion in `role_permission_definitions`, and deny-fill across roles; added `src/types/rbac.ts` with typed action literals; updated `src/lib/rbac.ts` with `DRAWER_ACTION_RULES`, `canPerformDrawerAction`, and 33 granular action checkers; aligned `getAllowedApprovalCategories` to matrix items 35-42; created `src/hooks/useRolePermissions.tsx` hook and `<RoleGuard>` component; integrated strict UI action gates across `VacancyDetailDrawer`, `EditApplicantModal`, `PoolEmployeeDetailDrawer`, `UserDetailDrawer`, and `Approvals`; documented Flutter/Dart model and BLoC parity in handoff; zero direct DB mutations performed; clean ESLint, Next.js build 19/19 routes green, gate.py blocking production ref; local commit on main)
4. **ohm#uifix02**: Governance Ref Reconciliation, Stricter Production Gate, Tab Alignment, Sentence Case Conversion & Full-Repo Contrast Audit (Corrected authoritative Supabase environment refs: production = `rwxelulyapjgaarlwkus`, staging = `qqiiznmqxfoamqytjica`; confirmed `migration_history_prod.txt` was exported from production `rwxelulyapjgaarlwkus` by Ohm; added strict governance rule in briefing and host-only gate check in `.agents/scripts/gate.py` halting with "local env points to production" whenever `.env.local` points to `rwxelulyapjgaarlwkus` without reading keys; audited `scripts/` identifying `verify-full-system-health.mjs` live DB queries and added `scratch/` to `.gitignore`; compiled verified code-derived tab inventory across all 13 modules correcting handoff inaccuracies; completed full sentence-case conversion across 95 files eliminating all 469 UI `uppercase` classes while strictly preserving uppercase acronyms HC, MFR, SLA, VCODE, HRCO, ADR, CENCOM; unified card selection tokens to `bg-surface-selected` and `border-brand-primary`; extended `scripts/audit_component_contrast.py` across all 183 `.tsx` files in `src/` achieving 100% WCAG AA compliance with 0 failures and confirmed PlantillaImportModal "Approve & Apply" button 6.65:1 contrast; zero DB access performed; ESLint clean, Next.js build 19/19 routes green, gate.py blocking production ref; local commit on main)
5. **ohm#uifix01**: Manual Test UI Fix Pass — Dark Mode Active Pills, Contrast & Typography Alignment (Resolved P0 unreadable active tabs and white buttons in dark mode via token trio `--tab-active-bg`, `--tab-active-text`, `--tab-active-border` across globals.css, SegmentedTabs, page tabs, filter chips, and modals; converted Team Directory avatar background to `var(--brand-button)` providing 6.73:1 contrast against white text in both themes; updated selected option cards across modals to brand-soft `--surface-selected` with >= 6.30:1 contrast; eliminated monospace on non-identifiers including Actual/Required counts, Aging, Approvals dates, and duration counters in favor of sans tabular-nums; converted breadcrumbs, stat-card labels, section headings, and table headers to sentence case with 12px/14px floors, reducing uppercase/tracking tokens from 868 to 811; neutralized Plantilla account card Warning chip, CENCOM deployment summary dots, and notification card borders; removed clipped graphic in Reports hub banner and relocated Dashboard toast to bottom-center; reported host part of NEXT_PUBLIC_SUPABASE_URL as production ref `rwxelulyapjgaarlwkus`; added `scripts/audit_component_contrast.py` reporting 100% WCAG AA compliance across shared components; zero database access performed; clean lint, build, and gate.py allow)

> Older entries trimmed 2026-10-26 (`ohm#lmorb8h3`) to keep this list to 5 — see git history for earlier entries in full.
