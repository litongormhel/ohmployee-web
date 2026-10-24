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
1. **ohm#t3m8w1k5**: Plantilla Detail Drawer Auto Tenure, Plantilla Type Removal & Human-Readable Action Buttons (Dynamic `computeTenure` from Date Deployed, Plantilla Type Removed from Employment Grid & Header Badge, Clean Action Toolbar with Human-Readable Labels & Role Authorization, 0 Build/Lint Regressions on `main`)
2. **ohm#f7m2w9x4**: Plantilla Import Field Inheritance & Mobile Parity, Vacancy Tab Store Name Exclusion & Detail Drawer Resolution (Deterministic Helper Functions `safe_parse_numeric`/`safe_parse_date`, Phase B2 Inheritance of Primary Store, Date Hired, Rate, and Address, Migration `20262606000059` Applied to Staging, Detail Drawer & Table VCode Fallback, Occupied Store Name Suppression from Vacancies, 0 Build/Lint Errors on `main`)
3. **ohm#s8k2w7m3**: Strict Vacancy Occupancy Filter for Missing Store Provisioning & Direct Import Guard (Strict Store Exclusion from "Stores without Active Vacancies" / "Missing from Vacancies" When Occupied in `plantilla_slots`, `plantilla`, or `employee_store_allocations`, Authoritative Occupancy Guard in `directImportVacancy`, `occupiedStoresQuery` Integration in Vacancy Tab, 0 Build/Lint Errors on `main`)
4. **ohm#v2k8w4m9**: Plantilla Import Completeness, Vacancy Tab Aging/Action & Direct Import, Conditional HRCO Badge & Details Drawer Cleanup (Migration `20262606000058` Applied to Staging, Vacancy Tab Non-Clickable to HC Request & Wired to Inspect Drawer, Aging Badge Column, Direct 1-Click Vacancy Import Action & Missing Store Detection, Conditional `NEEDS HRCO` Badge Hidden When Account/Row Assigned, Details Drawer Spacing & Redundancy Consolidation, 0 Build/Lint Errors on `main`)
5. **ohm#m4k9w2x8**: Plantilla Import Roving Slot Occupancy, Rejection Status Expansion & Review Queue Scope Fix (Store-Scoped `uq_plantilla_slots_active_occupant`, 3-Step Idempotent Phase B2 Slot Assignment, Rejection RPC State Expansion, Staging Cleanup `#8ba83c7f` Reset)

> Older entries trimmed 2026-10-24 (`ohm#s8k2w7m3`) to keep this list to 5 — dropped `ohm#b4k9w2x7` and earlier entries — see git history for that and earlier entries in full.
