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
1. **ohm#b7k2w9m5**: Plantilla Baseline Import Batch Summary Column Fix & Error Surfacing Hardening (Migration `20262606000061` Applied to Staging & Prod, Fixed Column Name from Non-Existent `summary_json` to `error_summary` in `submit_plantilla_baseline_import`, Preserved Batch Counters & Timestamp, Hardened Client RPC Error Propagation in `dataControl.ts` and `PlantillaImportModal.tsx`, 0 Lint/Build Errors on `main`)
2. **ohm#x4m9w2k7**: Plantilla Import Template Generator Schedule Columns Free-Form Text Update (Removed ExcelJS Data Validation Dropdown Lists from `SCHEDULE_DAYS`, `SCHEDULE_TIME`, and `DAYOFF`, Enabling Unrestricted Free-Form Text Entry while Preserving Sample Values, Column Widths, and ADR-002 Invariants, 0 Lint Errors on `main`)
3. **ohm#p8m2w6k9**: HR Emploc Bulk XLSX Import Modal Shell Refactor & More Dashboard Integration (Replaced Full-Page Wizard with Centered Purple Modal Overlay `HrEmplocImportModal` Matching Plantilla/Vacancy/MIKA/Payroll, Underlined Tabs `#7C3AED` with "Review Queue" Nomenclature, Purple Dropzone & Badges, Mobile Parity Footer Bar, ADR-001 Validation & Group Selector Preserved, Legacy `/hr-emploc/import` Route Redirected, 0 Lint/Build Errors on `main`)
4. **ohm#n2k7w9m4**: Plantilla Needs HRCO Tab Visibility Guard & Active Employee Resolution (Migration `20262606000060` Applied to Staging, "Needs HRCO" Tab Only Rendered When Account Lacks HRCO `!accountHasAssignedHrco`, Returns All Active Employees Under Account When No HRCO Assigned, Derived `effectiveTab` Sync, 0 Build/Lint Errors on `main`)
5. **ohm#e4w9k2m7**: Plantilla Detail Drawer Web-Optimized Desktop Layout, 4-Tab Navigation & MIKA Sync (Desktop Drawer with Deep Blue Header Banner, Initials Avatar & 4-Tab System: Profile with 2-Column Grid & Schedule Time, Benefits with Eye Mask Toggle & MIKA Sync RPC, Stores Allocation & Activity Logs, 0 Build/Lint Errors on `main`)

> Older entries trimmed 2026-10-24 (`ohm#b7k2w9m5`) to keep this list to 5 — dropped `ohm#t3m8w1k5` and earlier entries — see git history for that and earlier entries in full.
