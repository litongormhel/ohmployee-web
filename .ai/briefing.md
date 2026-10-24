# AI Briefing

## Mandatory Workflow Rules (apply to EVERY prompt, even if the prompt body does not mention them)

### Approval & Regression Gate
Before writing any code, schema change, or migration: present a short implementation plan
plus a regression risk assessment (what could break, what's untouched). STOP and WAIT for
explicit user approval. Do not implement in the same turn the plan is presented. This applies
even when the prompt already describes the approach in detail.

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
1. **ohm#6c3q8wzn**: CENCOM Overview UI Refresh & Group Scope Dropdown (Added Group 1–5 Scope Dropdown at Rightmost Tab Bar Opposite Overview with Scoped Roles Integration and Stale Fallback; Refactored Overview with 2-Row Overall MFR Sweep Ring Gauge Hero Card, 4 Neutral 44px KPI Cards with Network Coverage Progress Bar, and Dot-Indicator Deployment Summary; Introduced 6 Semantic Hero Theme Tokens in `globals.css` with &ge;4.5:1 Contrast; Zero Backend Schema Changes; 0 Lint/Build Errors on `main`)
2. **ohm#c3m8w9k4**: Vacancy Detail Audit Action Enum Coercion & Graceful Fallback (Migration `20262606000063` Applied to Live Staging; Added `'DELETE'` to `public.audit_action` Enum and Coerced `al.action::text` in `get_web_vacancy_detail` RPC to Fix Postgres 22P02 Invalid Input Value Error; Hardened `getVacancyDetail` in `src/lib/queries/vacancy.ts` to Gracefully Fall Back to Direct Table/Applicant Reads; 0 Lint/Build Errors on `main`)
3. **ohm#v2k9w4r8**: Vacancy Account & Group Linkage Propagation, Import RPC Hardening & Orphan Backfill (Migration `20262606000062` Applied to Live Staging; Fixed `directImportVacancy` Querying Invalid Column `hrco_name` on `accounts`; Hardened `approve_plantilla_import_batch` & `approve_vacancy_import` to Strictly Propagate `account_id`, `group_id`, `store_id`, and Account Name; Updated `vw_vacancy_detail` & `get_web_vacancy_detail` with Relational Fallbacks; Backfilled `CPRVJV13` to FOREVER OFFICE / Group 1 and Repaired 30 Stores and 16 Slots; Cleaned `VacancyDetailDrawer` Header & Fields; 0 Lint/Build Errors on `main`)
4. **ohm#m3k8w2r7**: MIKA Import Processor Store Name Column Removal, Review Queue Reject & History Color Fix (Removed "Store Name" from Template Headers, Sample Rows, Validation Guide, and Ingestion Parser; Added Review Queue "Reject" Action with `rejectMikaImport` DB Audit Mutation; Corrected Import History "Rejected" Status Badge to Red; 0 Lint Errors on `main`)
5. **ohm#b7k2w9m5**: Plantilla Baseline Import Batch Summary Column Fix & Error Surfacing Hardening (Migration `20262606000061` Applied to Staging & Prod, Fixed Column Name from Non-Existent `summary_json` to `error_summary` in `submit_plantilla_baseline_import`, Preserved Batch Counters & Timestamp, Hardened Client RPC Error Propagation in `dataControl.ts` and `PlantillaImportModal.tsx`, 0 Lint/Build Errors on `main`)

> Older entries trimmed 2026-10-24 (`ohm#6c3q8wzn`) to keep this list to 5 — dropped `ohm#x4m9w2k7` and earlier entries — see git history for that and earlier entries in full.
