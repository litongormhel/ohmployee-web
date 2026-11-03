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
1. **ohm#7k4w9xqn (HR Emploc (Web) — Emploc ID on Approve Correction + Remarks column blank in Review tab)**: Required mandatory Emploc ID (Employee Number) on Review Approve Correction with format regex (`/^[A-Za-z0-9._-]+$/`), async ecosystem uniqueness pre-check via `checkEcosystemEmployeeIdUnique`, and atomic backend transaction via `_assign_hr_emploc_number_core` setting `employee_no`/`emploc_no`, `status = 'Ready for Plantilla'`, `hr_status = 'Complete'`, clearing deficiencies, and logging timeline entry. Preserved Head Admin (role level 90) approve capability. Fixed Review tab Remarks column by projecting `ops_remarks` in `list_web_hr_emplocs` `row_capabilities` and prioritizing Ops correction remarks in web fallback. Staging migration `20262606000080` applied with 14/14 smoke tests passing. Mechanical gates passed: `npx tsc --noEmit` clean (0 errors), `npm run lint` clean (0 errors), `next build` clean (0 errors); local commit on main.
2. **ohm#9b5t3c7e (Plantilla: Remove "Import Plantilla" Button and Stray Import Component Mounts (Fix Broken Inline Render))**: Removed the "Import Plantilla" header action button, unused `UploadCloud` icon, `PlantillaImportModal` import, state `isPlantillaImportOpen`, and inline `<PlantillaImportModal>` mount from `src/app/(dashboard)/plantilla/page.tsx`. Resolves broken inline overlay on Plantilla content following the batch imports full-page conversion. Plantilla batch import lives exclusively under More → Data Control → Batch Imports. Mechanical gates passed: `npx tsc --noEmit` clean (0 errors), `npm run lint` clean (0 errors); local commit on main.
3. **ohm#4d8w2n6p (BatchImportPageShell: Fix Duplicate Back Arrow)**: Removed the literal "←" character from the back button label text in `src/components/more/BatchImportPageShell.tsx`, leaving the `ArrowLeft` icon alongside "Back to Batch Imports". Presentation-only fix across all 5 full-page batch import flows. Mechanical gates passed: `npx tsc --noEmit` clean (0 errors), `npm run lint` clean (0 errors); local commit on main.
4. **ohm#7k3q9x2m (More → Data Control → Batch Imports: Convert Import Modals to Full-Page Views (All 5 Imports))**: Converted all 5 batch import flows (HR Emploc, Plantilla, Vacancy, MIKA, Payroll) from clipped `<Modal>` containers into URL-driven full-page views (`/more?tab=data_control&subtab=batch_imports&import=<plantilla|hr_emploc|vacancy|mika|payroll>`) using a unified `BatchImportPageShell` with full-width/full-height layout, "← Back to Batch Imports" navigation, sticky action footers, and unclipped preview tables. Retained all internal sub-dialogs, staging pipelines, and ADR-001 slot validation rules. Updated `src/app/(dashboard)/hr-emploc/import/page.tsx` redirect and `docs/state/more_state.md`. Mechanical gates passed: `npx tsc --noEmit` clean (0 errors), `npm run lint` clean (0 errors), Next.js build clean (0 errors); local commit on main.
5. **ohm#userscopefix (Bugfix: User Management Scope Assignment & Friendly Error Mapping)**: Resolved the false-positive "at least one active Super Admin must remain" error when updating user scopes in User Management. In `src/lib/queries/users.ts`, decoupled generic PostgreSQL SQLSTATE `22023` (`invalid_parameter_value`) from the Super Admin restriction check in `friendlyUserError` and added clear error mapping for mismatched accounts (`"do not belong to selected groups"`). In `src/components/users/UserDetailDrawer.tsx` and `src/components/users/CreateUserModal.tsx`, added account-to-group tracking (`accountGroupRef`) to automatically prune accounts from deselected groups and sanitized `accountIds` prior to mutation submission, preventing database Guard (c) violations. Updated `docs/state/web_auth_rbac_state.md`. Mechanical gates passed: `npx tsc --noEmit` clean (0 errors), `npm run lint` clean (0 errors); local commit on main.

> Older entries trimmed 2026-10-28 (`ohm#4x7n2k9w Phase 5 REVISED`) to keep this list to 5 — see git history for earlier entries in full.
