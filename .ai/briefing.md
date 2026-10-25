# AI Briefing

## Mandatory Workflow Rules (apply to EVERY prompt, even if the prompt body does not mention them)

### Approval & Regression Gate
Before writing any code, schema change, or migration: present a short implementation plan
plus a regression risk assessment (what could break, what's untouched). STOP and WAIT for
explicit user approval. Do not implement in the same turn the plan is presented. This applies
even when the prompt already describes the approach in detail.
*Standing UI Standard Loop Override:* The UI Standard loop (`ohm#l0u8s2d9` onward) runs WITHOUT an approval gate. The loop pauses only on the stop conditions in `docs/architecture/ui-standard-briefing.md` section 10 or when verification fails. This overrides the generic "stop and wait" rule for this project only. Do not ask for approval again unless a stop condition triggers.

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
1. **ohm#l4v9k2x1**: UI Standard & Motion System — Color-Use Audit & Loop 4 Vacancy Align (Recorded Ohm local build verification [19/19 routes, green, 0 errors] and clarified sandbox offline font-fetch tsc fallback; completed Color-Use Audit [Blueprint Section 3, Rule 3 & 4: color strictly reserved for percentages], fixing non-percentage color violations on counts, aging, statuses, and modals in Dashboard and CENCOM; added audit table to per-loop checklist; completed Loop 4 Vacancy alignment dropping 450+ color literals to 0 across page, table, drawer, toolbar, and all 9 modals; wrapped all 9 Vacancy modals in shared `Modal` and verified `DetailDrawer` with 100% preservation of form logic, mutations, and hooks; 0 lint/type errors on `main`)
2. **ohm#l3c8m1q5**: UI Standard & Motion System — Gate Hardening & Loop 3 CENCOM Align (Fixed shared `Toast` contract and conditional-render usage in `dashboard/page.tsx`; confirmed all shared components and `KpiCard` backward compatibility; resolved `npm run build` to 100% green with 0 errors across 19 static routes; upgraded `.agents/scripts/gate.py` removing baseline-red allowance, auto-deriving touched modules from `git diff`, and adding explicit offline font-fetch tsc fallback reporting; corrected Loop 2 build-red records; completed Loop 3 CENCOM alignment dropping color literals from 237 to 0 across 5 files and adopting shared `HeroCard`, `KpiCard`, `ScopeDropdown`, `SegmentedTabs`, `PercentageBar`, and `NeutralChip`; 0 lint/build errors on `main`)
3. **ohm#l2d7k8w1**: UI Standard & Motion System — Loop 2 Dashboard (Full tokenization and shared component adoption for Dashboard module; resolved Loop 1 fixes: WCAG AA contrast ratio table in ui-standard.md, cutoffs-only threshold spec, color gate proof output; refactored `dashboard/page.tsx` and `MikaSyncModal.tsx` dropping color literals from 313 to 0; adopted shared `KpiCard`, `AnimatedNumber`, `PercentageBar`, `SegmentedTabs`, `ScopeDropdown`, `NeutralChip`, `Toast`, `Modal`; 0 lint errors on `main`; *Correction: earlier 'gate: allow' claim was made against a red build due to ToastProps.isOpen mismatch, resolved in ohm#l3c8m1q5*)
4. **ohm#l1f9w2s4**: UI Standard & Motion System — Loop 1 Foundation (Delivered authoritative `ui-standard.md`, centralized percentage thresholds in `src/lib/utils/thresholds.ts`, implemented 7a dark navy token values, migrated hero to brand blue, preserved DM Sans font, delivered 15-component shared UI catalog, enhanced mechanical gate with build baseline & 0-color literal check; 0 lint errors on `main`)
5. **ohm#l0u8s2d9**: UI Standard & Motion System — Loop 0 Discovery & Closed Loop Gate (Delivered comprehensive Loop 0 audit answering all 10 briefing questions across tokens, dependencies, layouts, modals, fonts, routes, color literals, tables, thresholds, and CENCOM reusability; resolved all 8 Claude-decision items; configured Antigravity-native closed-loop mechanical gate in `.agents/hooks.json` & `.agents/scripts/gate.py`; authored `docs/architecture/ui-standard-briefing.md`; 0 project code/schema changes on `main`)

> Older entries trimmed 2026-10-25 (`ohm#l4v9k2x1`) to keep this list to 5 — dropped `ohm#s8k4e9l2` and earlier entries — see git history for that and earlier entries in full.
