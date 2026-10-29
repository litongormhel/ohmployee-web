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
1. **ohm#9d3t5hq2 (Phase 2B-1 Round 3 Implementation: Account Requests Union, Vacancy Batching & Scope Verification)**: Implemented Option A in `public.fn_get_recent_activity` on staging (`qqiiznmqxfoamqytjica`), unifying approved `account_requests` into the recent activity feed strictly for Data Team roles (Super Admin, Head Admin, Encoder). Enforced privacy constraints (exposes only `full_name` and `target_role`; null `approved_by` renders as `"System:"`; zero email/PII). Hardened vacancy batch samples to separate `vcode`, `position`, and `store_name` without placing position in "name", updating formatter to render active sentences (`<Actor>: opened N vacancies for <position> at <store> [<account>]`). Proved scope isolation with re-run tests under caller impersonation across OM, HRCO, Recruitment, HR Personnel, and Back Office (0 User Management rows and 0 cross-scope leaks). Investigated open vacancy breakdown in Group Matrix: proved pool vacancies (`is_pool_vacancy = true`, `affects_required_hc = false`) and unbudgeted slots are excluded from matrix capacity by design. Documented staging-to-production migration audit (versions 60-77) and exact Hotfix A production apply and rollback procedures. Documented that `account_requests` events do not appear in the Audit Logs viewer.
2. **ohm#9d3t5hq2 (Phase 2B-1 Round 3 Review: Parity, Regression & Vacancy Breakdown Audit)**: Reconciled 20 open vacancies on staging (`qqiiznmqxfoamqytjica`): proved via raw timestamps all 20 existed prior to Oct 27 (0 created on/after Oct 28), definitively disproving earlier claims of "3 new vacancies" or "16 unassigned / 4 assigned". Breakdown confirms exactly 12 legacy ghost slots in Groups 1/2 (all unassigned, normalized via actual >= required), 7 real unassigned slots (G4, G5, Moses HQ), and 1 real assigned slot (`VCAG5_0056` to Selena Gomez in G5). Proved `account_requests` approval schema and proposed integration design without touching `approve_account_request_v2`. Re-ran comprehensive multi-role regression testing across SA, HA, Encoder, OM, HRCO (account scope), HRCO (no scopes), Recruitment, HR Personnel, Back Office, forged scopes, and Moses HQ pool account; verified strict scope isolation and zero cross-account leakage. Documented fixed 5-minute clock-aligned `date_bin` bucket behavior and boundary effects in state file. Verified 100% character-for-character parity between staging and production for `get_web_current_user_context` and `i_have_full_access`. Documented migration prerequisites (66-71 non-existent; 72-75 not prerequisites for 76/77) and deployment options with `supabase db push --include-all`.
3. **ohm#9d3t5hq2 (Phase 2B-1 Follow-up: Recent Activity Batching, Formatter Parity, and Dashboard Cleanups)**: Implemented 5-minute pre-limit sliding window batching (`date_bin`) in `public.fn_get_recent_activity` on staging (`qqiiznmqxfoamqytjica`), collapsing identical-actor/action/account bursts (e.g. 10 "UAT Test 3 -> PERFECT SM" transfers) into single summary rows with `batch_count` and up to 3 `samples` (name + employee_no). Established subject-first sentences (`Actor: Subject [no] transferred to Plantilla [account]`) with bold actor and colon, and batched rows (`Actor: transferred N employees to Plantilla [account]`) with an expandable sample disclosure. Relocated `RecentActivityFeed` to full-width section beneath matrix and attention rows with max 8 compact rows and right-aligned relative time. Applied dashboard cleanups: removed "CENCOM Triage" text link and aging placeholder from SLA Breaches card, rendered "19 unassigned to HRCO" pill once on Open Vacancies card (removed duplicate lines), resolved "Includes 2coverage" spacing typo, and thickened Workforce Coverage segmented bar to a prominent ~8-10px. Clarified vacancy mismatch: confirmed 16 vs 19 comes from the same live source (`fn_dashboard_metrics`), where 19 represents the current live count of unassigned open vacancies. Lint clean (0 errors), build clean (19 routes); local commit on main.
4. **ohm#9d3t5hq2 (Phase 2B-1 Round 2 Review & Production Parity Audit)**: Refined `fn_get_recent_activity` on staging (`qqiiznmqxfoamqytjica`) with transaction-level entity deduplication (`priority ASC, module preference ASC`), collapsing multi-table collisions (e.g. plantilla INSERT + hr_emploc 'Moved to Plantilla') into a single event with complete employee details. Confirmed `idx_audit_logs_account_ts` in migration file and verified parity with `pg_get_functiondef` on staging. Traced User Management approvals: proved `approve_account_request_v2` does not write to `audit_logs`, established unambiguous rule separating approvals from `CREATE_USER` (`user_created`) and `UPDATE_USER_ROLE` (`user_role_updated`). Restricted role updates & archives strictly to SA/HA (`v_is_admin`); verified Encoder (GROUP ONE) receives 0 User Management rows. Proved 5 real `vacancies` `APPROVAL` rows represent genuine `Open` → `Filled` transitions. Upgraded actor display to show human names with active grammar and `System:` only when null. Audited production parity via SELECT-only queries (`rwxelulyapjgaarlwkus`), confirming schema prerequisites and documenting unapplied migrations. Lint clean (0 errors), build clean (19 routes); local commit on main.
5. **ohm#u8b2m5p1 (Fix Import Plantilla Light/Dark Mode Contrast & Dropdown Glare)**: Resolved Light Mode submit button invisibility and Dark Mode dropdown menu solid white glare in `PlantillaImportModal.tsx` (and `VacancyImportModal.tsx`). Corrected "Submit Batch for HA/SA Review" button styling from unmapped `bg-[var(--primary)]` (which rendered transparent background with white text on white canvas) to canonical design tokens `bg-brand-button hover:bg-brand-button-hover text-white shadow-xs cursor-pointer`. Resolved Dark Mode dropdown popup glare by establishing root fallback aliases (`--card: var(--surface-card)`, `--primary: var(--brand-button)`), assigning `<select>` inputs `bg-surface-card border-border-default text-text-primary`, applying explicit option styling (`select option { background-color: var(--surface-card); color: var(--text-primary); }`), and enforcing `color-scheme: dark` under dark mode selectors. UI/styling-only; 0 database changes; `npm run lint` clean (0 errors) and `npm run build` (all 19 routes) clean; local commit on main.

> Older entries trimmed 2026-10-28 (`ohm#4x7n2k9w Phase 5 REVISED`) to keep this list to 5 — see git history for earlier entries in full.
