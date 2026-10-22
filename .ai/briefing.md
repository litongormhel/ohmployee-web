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
1. **ohm#d8m4x2w9**: Deep-Dive Data Source & Metric Harmonization (SQL RPC Migration, Mobile Inversion & OM Scope Fix, Mock Purge & Viewport Polish)
2. **ohm#q8v2n4k7**: Add Missing Group 3 & Group 4 to Scope Selector & Dynamic Scope Mapping
3. **ohm#x7m2p9w4**: Polish Web Admin Command Center (Right-Rail Viewport Clearance, Live CENCOM Group Bindings, & Dynamic Approvals Wiring)
4. **ohm#k4r9w2m8**: Refactor Web Admin Command Center (Super Admin & Head Admin Desktop View, Semantic Urgency, Approvals Reconciliation, & MIKA Sync)
5. **ohm#p8r4m2k9**: Consolidate Candidate Pipeline Stages to 6 Target Workflow Options & Execute Safe DB Migration

> Older entries trimmed 2026-10-22 (`ohm#d8m4x2w9`) to keep this list to 5 — dropped `ohm#s4b8r2x1` and earlier entries — see git history for that and earlier entries in full.
