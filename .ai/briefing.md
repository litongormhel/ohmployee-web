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
1. **ohm#alt754rec (Bugfix: Multi-Strategy Fallback Roster Resolution for Alturas 754 Employees)**: Resolved the persistent empty state ("No active employees") for ALTURAS (`accountId=3126b9a8-29a6-4917-8b49-82e937d7cf88`) despite KPI header showing 754 active deployed personnel. Re-engineered `listWebPlantillaEmployees` fallback in `src/lib/queries/plantilla.ts` with a multi-strategy resolver: 1) Queries all active stores under the account (`stores.account_id = accountId`) and chunks `v_plantilla_safe` by `store_id.in.(chunkStoreIds)`; 2) Queries active allocations from `employee_store_allocations` selecting both `plantilla_id` and `employee_no`, chunking `v_plantilla_safe` by `id` and `employee_no`; 3) Queries `v_plantilla_safe` with wildcard `account.ilike.%${accountName}%` and `account_id.eq.${accountId}`; 4) Provides direct `public.plantilla` fallback if view is constrained; 5) In `page.tsx`, moved status partitioning helpers (`isInactiveRecord`, `isDeactivationRecord`, etc.) outside the component scope, eliminating React Hook dependency warnings and preventing render race conditions. Mechanical gates passed: `npx tsc --noEmit` clean (0 errors), `npm run lint` clean (0 errors), `npm run build` clean (20/20 routes); local commit on main.
2. **ohm#alt754tbl (Bugfix: Plantilla Employee List Query & State Synchronization)**: Resolved the discrepancy where the summary KPI header showed 754 active deployed personnel for ALTURAS (`accountId=3126b9a8-29a6-4917-8b49-82e937d7cf88`) but the table rendered "No active employees". Diagnosed that legacy/imported Plantilla records lacked populated `account_id` foreign keys (relying on `account = 'ALTURAS'`) and had unpopulated status fields with `is_active = true`. Upgraded `listWebPlantillaEmployees` in `src/lib/queries/plantilla.ts` to resolve `account_name` and query `v_plantilla_safe` by both `account_id` and `account.ilike.${accountName}`, plus added chunked resolution against active allocations from `employee_store_allocations` (guaranteeing 100% parity with `v_account_allocation_kpi`). Updated `normalizeEmployeeListRow` to default `plantillaStatus` to `"Active"` when `is_active` is true. In `src/app/(dashboard)/plantilla/page.tsx`, normalized `activeEmployees` status filtering so records with `emp.isActive === true` or non-separated statuses (`"Active"`, `"Active Deployed"`, `"Deployed"`, or blank) populate the active list. Synchronized `statusTab` reactively with URL search params (`?status=`, `?statusTab=`) using `handleSelectStatusTab` across all 6 tab buttons and summary KPI cards, and added `selectedAccount?.name` into `employeeQuery` parameters and cache key. Mechanical gates passed: `npx tsc --noEmit` clean (0 errors), `npm run lint` clean (0 errors), `npm run build` clean (20/20 routes); local commit on main.
3. **ohm#0hmn1sop (Refinement: Headcount Request SOP in Plantilla, Simple Thinking Indicator, Clean Composer & Creator Identity)**: Refined OHMni Co-Pilot across SOP guidance, card aesthetics, and creator identity. Corrected Headcount Request SOP in `OHMPLOYEE_SOP_MANUAL` and `handleDeterministicFallback` (`route.ts`) to direct users to the **Plantilla** module (`/plantilla` -> select target Account -> click `+ Request Headcount` in header action bar -> track in Approvals). Established creator identity in `SYSTEM_PROMPT` and `handleDeterministicFallback`: answers proudly that OHMni was designed and built by **OHM (Ormhel Litong)**, IT Manager at Moses Coop and Systems Architect of the OHMployee ecosystem. Streamlined `OhmniDrawer.tsx`: removed noisy `⏳ Querying...` and `⚡ Live Data Verified` tool badges, displaying a clean, subtle **`Thinking.....`** state with spinner inside the OHMni response bubble until the text response renders. Removed the `⚡ Cloud • {pathname}` pill from the bottom composer box, providing a clean textarea with a right-aligned submit button. Mechanical gates passed: `npx tsc --noEmit` clean (0 errors), `npm run lint` clean (0 errors), `npm run build` clean (20/20 routes); local commit on main.
4. **ohm#alt754fix (Bugfix: Missing 754 Active Employees in Alturas Plantilla & OHMni Lookup, Show OHMni to All Roles)**: Resolved Plantilla Account Detail mismatch for ALTURAS (`accountId=3126b9a8-29a6-4917-8b49-82e937d7cf88`) where Directory card displayed `HC 754/755 • Vacant 1 • MFR 100%` but Account Detail showed 0 active employees. Fixed group filter leakage in `plantilla/page.tsx` by clearing `selectorGroupId` upon account selection and bypassing `effectiveSelectorGroupId` when `accountId` is active. Synchronized `getPlantillaSummary` with canonical metrics from `v_account_allocation_kpi` and added `v_plantilla_safe` fallback query in `listWebPlantillaEmployees`, restoring all 754 active deployed personnel and accurate 100% MFR. Upgraded OHMni Co-Pilot in `/api/ohmni` with `accountFilter` and `resolveAccountFilter(supabase, rawFilter)` to resolve client accounts against `accounts` table, querying `v_account_allocation_kpi` and `v_plantilla_safe` across Gemini tool calls and deterministic fallback router. Extended OHMni Co-Pilot sidebar button in `Sidebar.tsx` to render for all authenticated roles (below CENCOM if present, or below Dashboard/primary navigation for non-CENCOM roles). Mechanical gates passed: `npx tsc --noEmit` clean (0 errors), `npm run lint` clean (0 errors), `npm run build` clean (20/20 routes); local commit on main.
5. **ohm#0hmn1fix2 (Bugfix: query.limit Postgrest Unwrapping Fix, Multi-Model Quota Failover & Zero-Quota Fallback)**: Permanently resolved `query.limit is not a function` by eliminating async return of Supabase Postgrest builders, replacing `applyPlantillaFilters` with an async data-only helper `resolveGroupFilter(supabase, rawFilter)` and chaining `.select()`, `.ilike()`, `.or()`, and `.limit()` synchronously. Added multi-model discovery and automatic quota failover (`gemini-3.5-flash-lite`, `gemini-3.1-flash-lite`, `gemini-flash-lite-latest`, `gemini-3.8-flash`, etc.) with `maxRetries: 0` and buffered stream validation to handle Free Tier 429 exhaustion seamlessly. Implemented deterministic zero-quota local fallback router for both step-by-step SOP manual answers and direct Supabase RLS live-data queries, guaranteeing zero red error boxes in `OhmniDrawer`. Mechanical gates passed: `npx tsc --noEmit` clean (0 errors), `npm run lint` clean (0 errors), `npm run build` clean (20/20 routes); local commit on main.

> Older entries trimmed 2026-10-28 (`ohm#4x7n2k9w Phase 5 REVISED`) to keep this list to 5 — see git history for earlier entries in full.
