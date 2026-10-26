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
1. **ohm#lfix9v2d**: UI Standard & Motion System — Final Fix Pass Verification and Parity (Executed final fix pass across 8 core directives; restored HrEmploc canAssignEmployeeNo and canTagDeficiency gates to original behavior with zero business-rule changes; documented exact DB scratch queries and Supabase host rwxelulyapjgaarlwkus; recomputed all semantic token contrast pairs to strictly >= 4.5:1 with zero AA Large exceptions on 14px text; tuned dark muted, brand/danger solid buttons, and light danger tokens in globals.css; audited and implemented motion system with live AnimatedNumber tweens on Dashboard scope, CENCOM scope, and Vacancy tabs, confirmed absence of DashboardMetricsCards.tsx, declared real page-enter CSS keyframes in globals.css, and verified Settings 3-state motion control with weak-device auto-default; added dirty-Esc modal guards across Approvals, Payroll, BatchDetails, UserDetailDrawer, and SecurityTab; resolved getRoleTint to var(--brand-primary) and added structural RoleIconBadge to Team Directory; cited Flutter mobile ADR locks; verified 0 imports of uncommitted @ai-sdk/ai/zod; ESLint 0 errors, Turbopack build 19/19 static routes green, gate.py allow)
2. **ohm#lfix9v2c**: UI Standard & Motion System — Verification & Correction Audit Fixes (Conducted rigorous verification and correction pass; code-derived modal guard audit for all 99 dialogs/drawers; converted policy/warning notices for Emergency Override, Recruitment Freeze, Safety Floor, Permission Drift, and Edit Lock from `--danger` to neutral/info styles; traced and resolved HR Emploc pre-Loop-5A root cause and code dating to migration `20262606000043` and commit `8ee3d49`; reconciled color literals to 0 across all 12 modules; strengthened `gate.py` with multi-regex checks for raw palettes, hex, `bg-white`, `bg-black`, `text-black`, `rgb(`, `rgba(`, `hsl(`, `hsla(`, inline color styles, and named CSS colors; audited motion system across value tweens, page transitions, and full/lite/off modes; verified `key={pathname}` layout isolation; elevated all table cells to 14px floor with 0 remaining sub-14px `<td` elements; computed full WCAG contrast ratios; clean lint, build, and completion gate allow)
3. **ohm#lfin9z1a**: UI Standard & Motion System — Final Sweep & Full Queue Completion (Upgraded `.agents/scripts/gate.py` to completion gate requiring 100% queue completion, zero color literals across entire `src/`, 0 lint errors, and clean Next.js build; added app-wide subtle route transition and page-enter sequence in `DashboardAuthShell.tsx`; tokenized all remaining shared/global components and modals; achieved exactly 0 raw color literals across entire `src/`; ESLint clean with 0 errors; Turbopack `npm run build` green across all 19 static routes; completion gate returned decision allow)
4. **ohm#lmorb8h3**: UI Standard & Motion System — Loop 7H: More B Import Centers & QA Alignment (Standardized all 9 import centers, data control hubs, recovery suites, and QA screens in More B; wrapped root wizards and 10 nested action sub-dialogs in canonical `Modal` with `disableBackdropClick={isBusy}`, `isSubmitting={isBusy}`, dirty tracking, and Esc handling; enforced typography floor >= 14px (`text-sm`); eliminated over 1,400 baseline color literals down to exactly 0; ESLint clean with 0 errors; Next.js 16.2.4 Turbopack build green with 0 errors)
5. **ohm#lmora7g2**: UI Standard & Motion System — Loop 7G: More A Governance & Security Alignment (Standardized all 13 governance and security screens in More A; wrapped root and sub-modals in canonical `Modal` with `disableBackdropClick={isBusy}`, `isSubmitting={isBusy}`, dirty tracking, and Esc handling; enforced typography floor >= 14px (`text-sm`); eliminated over 1,200 baseline color literals down to exactly 0; ESLint clean with 0 errors; Next.js 16.2.4 Turbopack build green with 0 errors)

> Older entries trimmed 2026-10-26 (`ohm#l6c3w8m2`) to keep this list to 5 — dropped `ohm#r7m2k9w5` and earlier entries — see git history for that and earlier entries in full.
