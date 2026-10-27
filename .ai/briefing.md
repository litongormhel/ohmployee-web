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
1. **ohm#plan02**: Account Plantilla View Refactor (Employee & Store Views, 5 Status Tabs, MFR Donut & Reliever/Store Assignment Flows) (Refactored Account Plantilla page with segmented top-right toggle `[ 👥 Employee View | 🏬 Store View ]`; replaced legacy quota elements and horizontal leadership bar with 5 centered KPI & Leadership cards: CENCOM-style SVG MFR donut ring with dynamic status coloring `<75%` red, `75%–89.9%` amber, `>=90%` emerald and centered %, Active Deployed, Open Vacancies, HR Pipeline, and Leadership Team with conditional omission of unassigned TL/ATL rows; implemented hierarchical Area → City store dropdown; structured Employee View across 5 Status Sub-Tabs [Active, On-Leave, Vacancy, Floating, Deactivation] with live badges; integrated Reliever Moses HQ coverage workflow with AssignRelieverModal and ReturnToActiveModal auto-release; added AssignStoreModal for floating personnel; implemented Store View with Capacity Table; replaced Quota terminology with Required across plantilla module drawers and modals; verified clean database RPC bindings; ESLint clean, Next.js build 19/19 routes green; local commit on main)
2. **ohm#plan01**: Plantilla Navigation Streamlining & Moses HQ Workforce Analytics Integration (Removed top tab switcher from Plantilla views in favor of direct Store Plantilla default view with pinned Moses HQ grid card routing to Moses HQ Pool; added one-click breadcrumb return in AdminPageHeader; integrated Workforce Analytics as top-right action toolbar button in MosesHqPoolView rendering 7-tab analytics dashboard in full-width Modal [max-w-7xl] while strictly isolating pool table state and query caches; ESLint clean, Next.js build 19/19 routes green; local commit on main)
3. **ohm#uifix04**: MFR Progress Bar Color Logic & Styling Across Plantilla & CENCOM (Defined CSS tokens `--pct-good-bar`, `--pct-warn-bar`, `--pct-bad-bar` in `:root` and `.dark` [Light: `#059669` green, `#ca8a04` yellow, `#dc2626` red; Dark: `#34d399` green, `#facc15` yellow, `#f87171` red] registered in `@theme inline`; updated MFR thresholds across `thresholds.ts`, `cencom.ts`, `plantilla/page.tsx`, and `StoreStaffingOverviewDrawer.tsx` to exact specs: 100% Green, 95% to 99.99% Yellow, <95% Red; aligned CENCOM health status mapping to 95% cutoff; styled progress bar tracks with recessed `bg-surface-muted border border-border-subtle/50` preventing background washout and blending in both themes; ESLint clean, Next.js build 19/19 routes green; local commit on main)
4. **ohm#arch03**: Migration File Production Hardening & Dry-Run Sanity Verification (Applied production hardening to migration `20261026000002_qa_reset_soft_archive_and_atomic_rollback.sql`; corrected target tables array to live Moses HQ pool tables `workforce_pool_slots`, `workforce_pool_requests`, and `workforce_pool_request_items`; hardened `resolve_audit_actor_id` to strictly verify actor UUIDs against `auth.users` via `INNER JOIN auth.users au ON au.id = up.auth_user_id`, eliminating orphaned profile FK errors and safely returning NULL; aligned `public.audit_logs` inserts in `execute_qa_reset_archive` and `rollback_archive_batch` to match live schema `(actor_id, module, action, record_id, new_data, timestamp)` with valid `audit_action` enums `SOFT_DELETE` and `UPDATE`; executed transactional end-to-end dry-run verification against staging DB `qqiiznmqxfoamqytjica` confirming clean parsing, column creation, and 0 FK errors; ESLint clean, Next.js build 19/19 routes green; local commit on main)
5. **ohm#arch02**: Data Archival & Rollback Backend Sanity Check & FK Resolver Verification (Executed comprehensive staging DB sanity audit via Supabase Management API; verified migration `20261026000002_qa_reset_soft_archive_and_atomic_rollback.sql` is currently unapplied on remote staging DB `qqiiznmqxfoamqytjica`; identified schema differences in target tables including `workforce_pool_slots` vs `workforce_pools`; detected 32/41 orphaned `users_profile` rows causing `audit_logs_actor_id_fkey` violations unless verified against `auth.users`; identified `audit_logs` column and `audit_action` enum mismatch in migration; validated simulation of hardened actor resolver across 5 edge cases with 0 FK errors; audited live row counts across 4,005 plantilla, 283 vacancies, 96 hr_emploc, 83 moses pool slots, 265 pending operational requests, 41 preserved user profiles, and 29 preserved account sign-up requests; zero DB schema mutations performed)

> Older entries trimmed 2026-10-27 (`ohm#arch01`) to keep this list to 5 — see git history for earlier entries in full.
