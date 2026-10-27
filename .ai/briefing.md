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
1. **ohm#4x7n2k9w (Phase 4 — Part 0 Rename, Part 1 Step 3 Stop Report, Part 2 Rule 4 Drift, Part 3 Step 6 Plan)**: Migration Filename Sync, Step 3 Classification Coupling Stop Report, Rule 4 Drift Audit & Step 6 Slot Resurrection Plan (Part 0: renamed local migration `20261027190000_...sql` to `20261027091040_fix_plantilla_summary_slot_counts_and_emploc_deleted_filter.sql` via `git mv` with content unchanged and updated all doc/handoff references; Part 1: simulated narrowed Step 3 on staging `qqiiznmqxfoamqytjica` across all 6 smoke accounts and stopped per explicit STOP conditions because changing `hc_filled` to `active_plantilla_count` while keeping the Open-tab predicate `(s.hc_filled < s.hc_total OR lower(s.pipeline_status) = 'open')` and `derived_status` unchanged causes 5 `Hired`/`Pipeline` vacancies [`ACT-G5-002`, `ACT-G5-006`, `ACT-G5-008`, `VCBPIG1_0183`, `CPSAJV27`] to flip into the Open tab, inflates `total_open` across 4 accounts, and causes `CPRVJV13` to display `1/1` while remaining `Open`, plus documented all web/mobile `hc_filled` consumers with line refs; Part 2: reported ADR-001 Rule 4 drift across `models.dart`, `vacancy_screen.dart`, `dashboard_screen.dart` vs `v_dashboard_*` views and `ohm#plan09` commit/approval audit; Part 3: delivered Step 6 plan for `fn_set_slot_status` and `fn_sync_vacancy_slot_open_pipeline`, audited 15 other slot-picking functions lacking `closed_at IS NULL`, and designed `fn_set_slot_status`-only cleanup for `VCAG5_0056` Ord 1–2; local commit on main)
2. **ohm#4x7n2k9w (Phase 3 — Step 2a & Step 3 Recon)**: `v_account_allocation_kpi` Closed-Slot Filter & Vacancy Views/RPCs Recon (Completed Part 0 migration bookkeeping audit on staging `qqiiznmqxfoamqytjica`: Step 1 migration applied via MCP `apply_migration` recorded `version = 20261027091040` [renamed in Phase 4 Part 0 to `20261027091040_...sql`]; implemented Part 1 Step 2a via `20261027092200_fix_account_allocation_kpi_closed_slot_filter.sql`, adding `ps.closed_at IS NULL` to `slot_vacant_non_roving` and `slot_vacant_roving` in `public.v_account_allocation_kpi` while preserving all locked formulas, column types, `security_invoker = true`, and GRANTs; verified before/after smoke tests across all 6 accounts: only `ACTISERVE` changed [`required_hc: 14.0000 -> 12.0000`, `slot_vacant_hc: 10.0000 -> 8.0000`, matching `get_web_plantilla_summary` 1:1], while `ALTURAS`, `THREE`, `FOREVER OFFICE`, `BANKO`, and `Moses HQ` remained 100% unchanged; completed Part 2 Step 3 read-only recon on `20261027170000` / `20261027180000`, `hc_filled` origin [`ohm#q7w1k9b3` migration `20262606000050`], Rule 2 + Rule 4 vacancy view/RPC plan, consumer inventory, and root cause of `VCAG5_0056` Ord 1–2 closed-slot resurrection [`fn_set_slot_status` not clearing `closed_at` on `reopened` + `20262606000049` §2.2 + `fn_sync_vacancy_slot_open_pipeline`]; local commit on main)
3. **ohm#4x7n2k9w (Phase 2 — Step 1)**: ACTISERVE Plantilla — Slot-Based Summary RPC & HR Emploc Golden Rule Fix (Step 1A + 1B, Staging) (Created and applied migration `20261027091040_fix_plantilla_summary_slot_counts_and_emploc_deleted_filter.sql` on staging `qqiiznmqxfoamqytjica`; Step 1A moved `h.deleted_at IS NULL` outside the `COALESCE(v_role_level, 0) >= 90 OR (...)` bypass in `get_web_hr_emploc_summary` and `list_web_hr_emplocs`, eliminating all 11 soft-deleted test rows from Super Admin ACTISERVE queue counts [`15 -> 4 pending, 0 correction/review/ready`] and list results [`25 -> 5`]; Step 1B updated `get_web_plantilla_summary` and `list_web_plantilla_store_staffing` to exclude pool/non-quota vacancies [`COALESCE(is_pool_vacancy,false)=false AND COALESCE(affects_required_hc,true)=true`] in both `onboarding_pipeline_count` and `open_headcount_count` and replaced `SUM(vacancies.required_headcount)` with slot-based vacant counts across `plantilla_slots` [`slot_status IN ('open','pipeline') AND closed_at IS NULL`, stationary + `1/N` roving, suppressing active Coverage Group stores] + `coverage_slots` [`slot_status = 'open'`], de-duplicating slots already counted in `hr_emploc`; verified before/after smoke tests on staging across `ACTISERVE` [`17 -> 12`: `1` actual + `3` hrProcess + `8` vacant], `ALTURAS` [`753 -> 753` unchanged], `THREE` [Coverage Group `7 -> 4`, matching `v_account_allocation_kpi`], `FOREVER OFFICE` [`10 -> 9`, matching `v_account_allocation_kpi.slot_vacant_hc = 4`], `BANKO` [`12 -> 11`], and `Moses HQ` [`3` active unchanged]; local commit on main)
4. **ohm#4x7n2k9w**: ACTISERVE Plantilla — Why Required = 17? Slot-Based Count Investigation (READ-ONLY, Phase 1) (Completed read-only investigation on staging `qqiiznmqxfoamqytjica` using 3 parallel sub-agents [DB Auditor, Formula Tracer, ADR-001 Verifier]; proved exact arithmetic of `Required = 17` in `get_web_plantilla_summary` + `normalizeSummary` [`1` active on `VAC-MNL-099` + `4` `hr_emploc` pending rows + `12` raw `SUM(vacancies.required_headcount)` across 5 open vacancies]; proved double-counting of `ACT-G5-002` [+2], `ACT-G5-006` [+2], and Moses HQ pool leak `BUN-GHQ-00015` [+2]; identified unapplied staging migration `20261027180000` causing `vw_vacancy_list.hc_filled` to count `'New'` applicants as filled [`ACT-G5-008` `2/2`, `VCAG5_0056` `2/7`] plus ADR-001 Rule 2 violation counting `Confirmed Onboard` instead of `plantilla.status = 'Active'`; uncovered `VCAG5_0056` having 8 `plantilla_slots` [Ord 1 & 2 with `closed_at IS NOT NULL` / `QA_RESET` resurrected to `'pipeline'`] vs `hc_needed = 7`; uncovered Golden Rule violation in `get_web_hr_emploc_summary` / `list_web_hr_emploc` where `v_role_level >= 90` bypasses `h.deleted_at IS NULL` [surfacing 11 soft-deleted June 2026 test rows to reach 15]; delivered reconciliation table, ranked root causes, slot-based target numbers [`Required = 12`: `1` Active + `3` HR Processing + `8` Vacant], implementation plan, and regression assessment; awaiting Ohm's explicit approval)
5. **ohm#plan10**: Plantilla Headcount Slot Capacity & MFR Reconciliation Parity (Resolved discrepancy where account e.g. ACTISERVE showed Required = 17 and 6.0% MFR while raw visible records totaled 6 [1 active + 5 vacancies]; added `getVacancyRemainingCapacity` in `plantilla/page.tsx` evaluating `v.hcTotal - v.hcFilled`; introduced `openVacanciesSlots`, `pipelineVacanciesSlots`, and `totalVacanciesSlots` to aggregate authorized slot capacity; updated Card 1 MFR denominator to evaluate `activeCount + effectiveVacancySlots` aligning with `summaryData.required`; updated Card 3 [Open Vacancies] and Card 4 [HR Pipeline] to display headcount slot capacity with secondary requisition count subtitles; enhanced Tab 3 [Vacancy] button and sub-filters to display both requisition count and total slot capacity; replaced hardcoded `1 Vacant` badge in `StoreVacancyTable` with dynamic capacity `${remainingCapacity} Vacant (${hcFilled}/${hcTotal})`; updated `storeVacancyCountMap` in Store View to sum slot capacity; verified via ESLint clean and Next.js build 19/19 routes green; local commit on main)

> Older entries trimmed 2026-10-27 (`ohm#4x7n2k9w Phase 4`) to keep this list to 5 — see git history for earlier entries in full.
