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
1. **ohm#y8k4w2m9**: Flexible Plantilla Import Approval for Flagged Rows & HRCO Auto-Tagging Fallback (Pre-Commit Blocked-Only Guard, Account HRCO Auto-Tagging, Detailed Error String Propagation, Staging Live Applied)
2. **ohm#m2x7k9w4**: Fix Plantilla Import Batch Commit Failure & Vacancies Not-Null Constraints (Pre-Commit Flagged Rows Guard, Vacancies Shadow Sync, Robust Exception Propagation, Staging Live Applied)
3. **ohm#t8k2m7w4**: Plantilla Review & History Table Typography & Responsive Layout Polish (Primary Identifiers at `text-sm`, Metadata & Error Guidance at `text-xs leading-tight`, Compact Badges, Horizontal Scrolling & Truncation with Tooltips)
4. **ohm#e7m4x9w2**: ExcelJS ADR-002 Plantilla Import Template Generator (Required Header Highlighting `#FFC7CE` / `#9C0006`, Native Excel Dropdowns for `SCHEDULE_DAYS`, `SCHEDULE_TIME`, `DAYOFF`, and 15-Rule Validation Guide Sheet)
5. **ohm#p9x2w8m4**: Implement ADR-002 Plantilla Import, Store Identity, Headcount Governance & 72h Rollback Architecture (Database Migration `20262606000053`, Staging Live Apply, Excel Parser & Template Standardization, Ops Schedule & Dayoff Controls, Zero-Edit Lock)

> Older entries trimmed 2026-10-23 (`ohm#y8k4w2m9`) to keep this list to 5 — dropped `ohm#a7k2m9x4` and earlier entries — see git history for that and earlier entries in full.
