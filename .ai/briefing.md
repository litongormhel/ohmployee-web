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
1. **ohm#l7b2m8c4**: UI Standard & Motion System — Loop 7B: Approvals Cards & Modals Alignment (Standardized all 10 approval cards with canonical design tokens; wrapped 20 single approval and rejection dialogs in canonical `Modal` with `disableBackdropClick={isBusy}`, `isSubmitting={isBusy}`, dirty-Esc handling, and `maxWidthClass="max-w-md"`; eliminated all raw color literals across all 10 approval cards down to 0, bringing the entire Approvals module across `src/components/approvals/` and `src/app/(dashboard)/approvals/` to 0 color literals; preserved ADR-001/ADR-002 invariants; ESLint clean with 0 errors; `npx tsc --noEmit` green with 0 errors)
2. **ohm#l7a01n2v**: UI Standard & Motion System — Loop 7A: Approvals Navigation & Data Tables Alignment (Standardized category navigation, queue review pane, and all 11 approval data tables; wrapped 44 approval/rejection dialogs in canonical `Modal` with `disableBackdropClick={isBusy}`, `isSubmitting={isBusy}`, and dirty-Esc handling; enforced typography floor >= 14px (`text-sm`); eliminated all color literals across 13 files down to 0; preserved ADR-001/ADR-002 invariants; ESLint clean with 0 errors; `npx tsc --noEmit` green with 0 errors)
3. **ohm#l6cl0s9e**: Loop 6 Closeout Reverts & Rollout Queue Gate Upgrade (Reverted non-styling `onUpdated` drawer refresh callback from `PoolReviewQueueDrawer.tsx` and `MosesHqPoolView.tsx`; verified 0 query/RPC/RBAC alterations in Loop 6; disclosed DB query and row capability derivation for HR Emploc pending queue buttons; created `docs/architecture/ui-rollout-queue.md` with 9 continuous items; upgraded `.agents/scripts/gate.py` to completion gate with offline font-fetch resilience; Next.js 16.2.4 Turbopack build and ESLint passed with 0 errors)
4. **ohm#l6c3w8m2**: UI Standard & Motion System — Loop 6C: Plantilla Analytics & Moses Pool Views Alignment (Standardized `MosesHqPoolView.tsx` and `WorkforceAnalyticsView.tsx` with canonical design tokens; eliminated all 198 color literals down to 0, completing 100% elimination of all 1,031 baseline literals across the entire Plantilla module [Loop 6A: 442, Loop 6B: 391, Loop 6C: 198]; aligned SVG charts/donuts and progress bars with semantic tokens `--pct-*` and `--danger-*`; added `onUpdated` parity to `PoolReviewQueueDrawer`; ESLint clean with 0 errors; full Turbopack `npm run build` clean with 19/19 static routes on `main`)
5. **ohm#l6b2n7k4**: UI Standard & Motion System — Loop 6B: Plantilla Modals & Forms Alignment (Standardized all 8 Plantilla lifecycle modals with canonical `Modal` at `z-[60]` over `DetailDrawer` at `z-50`; hardened `isSubmitting`, `isDirty`, and backdrop guards; eliminated all 391 color literals across 8 modals down to 0; preserved `--danger` strictly for validation error alerts and destructive actions [`InitiateSeparationModal`]; ESLint clean with 0 errors; full Turbopack `npm run build` clean with 19/19 static routes on `main`)

> Older entries trimmed 2026-10-26 (`ohm#l6c3w8m2`) to keep this list to 5 — dropped `ohm#r7m2k9w5` and earlier entries — see git history for that and earlier entries in full.
