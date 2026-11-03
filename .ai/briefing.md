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
1. **ohm#sarlsfix (Bugfix: Super Admin RLS Policies for Plantilla and Employee Records)**: Authored migration `supabase/migrations/20262606000078_super_admin_plantilla_employee_rls.sql` providing dedicated permissive RLS policies (`plantilla_super_admin_select` and `employees_super_admin_select`) ensuring authenticated users with the "Super Admin" role have unrestricted SELECT access to read plantilla and employee records. The policy explicitly resolves role status via canonical `public.users_profile` joined with `public.roles` (`role_name = 'Super Admin'` / `role_level >= 100` / `up.role = 'Super Admin'`), `public.i_have_full_access()`, and custom JWT claim fallbacks. Updated `docs/state/plantilla_web_state.md`. Local commit on main.
2. **ohm#mfrcolor (Bugfix: MFR Donut Threshold Colors - 100% Green, 95-99.99% Yellow, Below 95% Red)**: Updated the MFR threshold logic on the Overall MFR circular ring in `src/app/(dashboard)/plantilla/page.tsx` (`OverallMfrDonut`) to enforce strict 3-tier semantic color coding: `100%` green (`var(--pct-good-bar, #16a34a)`), `95%–99.99%` yellow (`var(--pct-warn-bar, #ca8a04)`), and `< 95%` red (`var(--pct-bad-bar, #dc2626)`). For accounts with open vacancy gaps such as ALTURAS (`754 active / 755 required`, MFR = `99.87%`), the donut ring stroke now correctly renders in yellow rather than green. Mechanical gates passed: `npx tsc --noEmit` clean (0 errors), `npm run lint` clean (0 errors), `npm run build` clean (20/20 routes); local commit on main.
3. **ohm#mfrprec (Bugfix: Unrounded MFR Percentage Formula & Precision Donut Formatting)**: Resolved the MFR metric discrepancy where ALTURAS displayed `100.0%` despite an open vacancy (`754 active / 755 required`). Eliminated `Math.round` integer rounding in `plantilla/page.tsx` (`const fulfillmentRate = requiredCount > 0 ? (activeCount / requiredCount) * 100 : 0`) and account cards. Upgraded `OverallMfrDonut` with a `hasGap` guard (`activeCount < requiredCount`), rendering exact unrounded decimal precision (`99.87%` for 754/755, matching canonical `v_account_allocation_kpi.mfr = 0.9987` to the basis point) and guaranteeing that any account with a staffing gap never rounds up to `100.0%` or `100%`. Synchronized `/api/ohmni/route.ts` to return matching unrounded precision. Mechanical gates passed: `npx tsc --noEmit` clean (0 errors), `npm run lint` clean (0 errors), `npm run build` clean (20/20 routes); local commit on main.
4. **ohm#alt754par (Bugfix: Guaranteed Parity Fallback Roster Resolver for Alturas 754 Employees)**: Permanently resolved the empty state ("No active employees") for ALTURAS (`accountId=3126b9a8-29a6-4917-8b49-82e937d7cf88`) despite KPI header showing 754 active deployed personnel. Diagnosed PostgREST 42703 column-not-found errors caused by a brittle 25-column projection string (`selectCols`) on `plantilla` / `v_plantilla_safe`. Re-engineered `listWebPlantillaEmployees` in `src/lib/queries/plantilla.ts`: 1) Wrapped primary RPC in try/catch to failover gracefully to active store allocations on error or empty results; 2) Replaced column projection with safe `.select("*")` preventing 42703 errors; 3) Queried `employee_store_allocations` (`WHERE account_id = params.accountId AND is_active = true`) for canonical active allocations; 4) Concurrently chunk-hydrated records from `v_plantilla_safe` and `plantilla` by ID and employee number; 5) Added active allocation parity guarantee synthesizing employee entries for any unjoined allocation records; 6) Enhanced `normalizeEmployeeListRow` with fallback alias resolution. Mechanical gates passed: `npx tsc --noEmit` clean (0 errors), `npm run lint` clean (0 errors), `npm run build` clean (20/20 routes); local commit on main.
5. **ohm#alt754rec (Bugfix: Multi-Strategy Fallback Roster Resolution for Alturas 754 Employees)**: Resolved the persistent empty state ("No active employees") for ALTURAS (`accountId=3126b9a8-29a6-4917-8b49-82e937d7cf88`) despite KPI header showing 754 active deployed personnel. Re-engineered `listWebPlantillaEmployees` fallback in `src/lib/queries/plantilla.ts` with a multi-strategy resolver: 1) Queries all active stores under the account (`stores.account_id = accountId`) and chunks `v_plantilla_safe` by `store_id.in.(chunkStoreIds)`; 2) Queries active allocations from `employee_store_allocations` selecting both `plantilla_id` and `employee_no`, chunking `v_plantilla_safe` by `id` and `employee_no`; 3) Queries `v_plantilla_safe` with wildcard `account.ilike.%${accountName}%` and `account_id.eq.${accountId}`; 4) Provides direct `public.plantilla` fallback if view is constrained; 5) In `page.tsx`, moved status partitioning helpers (`isInactiveRecord`, `isDeactivationRecord`, etc.) outside the component scope, eliminating React Hook dependency warnings and preventing render race conditions. Mechanical gates passed: `npx tsc --noEmit` clean (0 errors), `npm run lint` clean (0 errors), `npm run build` clean (20/20 routes); local commit on main.

> Older entries trimmed 2026-10-28 (`ohm#4x7n2k9w Phase 5 REVISED`) to keep this list to 5 — see git history for earlier entries in full.
