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
1. **ohm#4x7n2k9w (Phase 10 — Closed-Slot Trigger Fix, VCAG5_0056 Restoration, Trigger & KPI Guards, D4 Reset Smoke STOP GATE)**: Staging Database Hardening & Quota STOP GATE (Part A: applied migration `20261028033015_fix_sync_closed_slot_to_vacancy_multi_slot_guard.sql`, updating previously unversioned function `fn_sync_closed_slot_to_vacancy` to close vacancy ONLY when no OTHER live slot remains, verified 4/4 smoke scenarios; Part B: verified no sanctioned reopen path exists for Closed non-archived vacancies, executed simulated + real audited UPDATE restoring `VCAG5_0056.status = 'Open'`, verified capacity 7 in `/vacancy` Open tab, ACTISERVE `total_open = 1`, summary & KPI both 12/12; Part C: applied migration `20261028033431_fix_sync_vacancy_slot_open_pipeline_exclude_occupied_slots.sql` excluding `hr_processing`/`occupied`/`filled` from claim/release loops, passed all smoke scenarios and Step 6 smokes, repaired `ACT-G5-010` slot `8eb14b17...` to `hr_processing`, ACTISERVE stayed 12/12; Part D: applied migration `20261028033655_fix_account_allocation_kpi_actual_hc_active_plantilla_guard.sql`, 116-account gate verified sole diff ALTURAS 754->752, ACTISERVE 12/12, FOREVER OFFICE actual_hc 5; Part E STOP GATE: simulated `revise_vcode_headcount_quota('VCAG5_0056', 1)` in `BEGIN...ROLLBACK` where `v_delta = 1 - 7 = -6` reduced all 6 open slots leaving 0 live slots [expected 1 live slot] and dropping ACTISERVE to 6/6 [expected 7/7], STOPPED per gate instructions without applying mutation; Part F: confirmed correct ESA UUIDs `c406c477...`/`e496ae21...`, cataloged all 13 `employee_store_allocations` writing functions from `pg_proc`, and subagent delivered D7 Import guard report recommending Option 1 hard-block; local commit on main).
2. **ohm#4x7n2k9w (Phase 9 — Part 0 total_open Root Cause & STOP GATE, Parts 1–4 Reports & Smokes)**: Total Open Investigation, Trigger Guard Recon & Smoke, Allocation KPI Guard Simulation, ESA Import Audit & D6 Prerequisites (Part 0 STOP GATE: identified root cause of ACTISERVE `total_open = 0` as unintended execution of unversioned database trigger `trg_sync_closed_slot_to_vacancy` -> `fn_sync_closed_slot_to_vacancy()` which unconditionally executed `UPDATE vacancies SET status = 'Closed'` when Phase 7 Part 1b re-closed Ord 1, causing `derived_status = 'Archived'` and exclusion from `scoped` CTE; proved `20261028015509` and `20261028005821` did not cause the flip; STOPPED per STOP GATE instructions and presented minimal trigger guard fix; Part 1: audited callers of `fn_set_slot_status(..., 'pipeline', ...)`, drafted `fn_sync_vacancy_slot_open_pipeline` exclusion guard, verified ACT-G5-010 slot `8eb14b17...` and live Pending Emploc `33da0ac2...`, confirmed all Part 1 smoke tests and Step 6 smokes passed in `BEGIN...ROLLBACK`; Part 2: re-simulated 116-account gate on `v_account_allocation_kpi` actual_hc guard where ALTURAS 754->752 was the sole diff, verified dependent views resolve and ACTISERVE/FOREVER OFFICE unchanged; Part 3: subagent audited exact lines 435–440 & 465–482 in `approve_plantilla_import_batch`, proposed lifecycle status guard without account-equality, proved why rejected rows must be hard-blocked errors, cataloged all 11 ESA-modifying functions, and recommended one-off audited data fix for ALTURAS; Part 4: subagent cataloged all TS/TSX consumers, migrations, and architectural impact of "On-Leave counts as filled" in Plantilla MFR; zero database writes; local commit on main).
3. **ohm#4x7n2k9w (Phase 7 — D4-independent execution + trigger/KPI recon)**: Vacancy `derived_status` Active Plantilla Precedence Fix, VCAG5_0056 Slots Re-close, Migration File Hygiene & Recon (Part 1a: applied migration `20261028015509_fix_derived_status_active_plantilla_precedence.sql` on staging `qqiiznmqxfoamqytjica`, updating `derived_status` in both `vw_vacancy_list` and `vw_vacancy_detail` to check `active_plantilla_count >= required_headcount` alongside `confirmed_onboard_count >= required_headcount` or `status = 'Filled'`, pre-simulated on all 20 live vacancies where only CPRVJV13 flipped Open->Hired and FOREVER OFFICE Open dropped 4->3, verified all 6 smoke accounts on `get_web_vacancy_summary`, ACTISERVE stayed 12/12; Part 1b: re-closed VCAG5_0056 Ord 1-2 slots `bee89108...` and `79e510b4...` via `fn_set_slot_status(..., 'closed', 'QA_RESET')` with verified Super Admin profile `b865eef6...`, verified `qa_archive_batch_id` untouched and ACTISERVE stayed 12/12; Part 1c: moved `20261027180000_*` to `docs/archive/` as `.superseded`, diffed `20261027170000_*` base function body vs staging `list_web_plantilla_employees` and re-timestamped to `20261028020000_*` leaving unapplied; Part 2: audited 7 unapplied migrations [4 archive, 3 needs-Ohm-decision]; Part 3: audited slot-sync trigger bug clobbering `hr_processing` to `pipeline` on ACT-G5-010 and proposed guards/repair; Part 4: audited ESA/KPI Golden Rule leak on ALTURAS [2 inactive MARIZ parents] and proposed guard/repair; Part 5: verified ADR-001 has no citation for On-Leave KPI vs Plantilla divergence; local commit on main).
4. **ohm#4x7n2k9w (Phase 6 — Hygiene Recon + VCAG5_0056 Plan; Plan Only)**: Migration Hygiene Recon (audited 489 local files vs 555 DB migrations, confirmed 9 unapplied, proved `20261027180000` reverts Rule 2 `hc_filled` to `confirmed_onboard_count` and proposed archive move + new timestamp for `20261027170000`, verified `ai-finish.ps1`/`finish.js` has no `db push` and drafted `--no-db-push` guard diff); ACT-G5-010 Slot ID & Early Archive Recon (proved correct UUID `8eb14b17-b2e2-42c5-8aba-4b93782c08a3`, proved `confirm_applicant_onboard` placed slot in `hr_processing` at 07:20:31 but 2nd applicant ROMERO at 07:22:10 fired `trg_applicant_insert_slot_sync` clobbering slot to `pipeline`, and proved `mark_vacancy_filled` called by UAT Test 3 at 07:22:26 triggered `handle_vacancy_filled_archive`); CPRVJV13 Recon & Simulation (explained Rule 2 `hc_filled` [active Plantilla] vs `derived_status` [confirmed onboards], proposed minimal `derived_status` fix and simulated on all live vacancies where only CPRVJV13 flips `Open -> Hired`); Actual-Count Divergence Recon (proved FOREVER OFFICE 4 vs 5 is by design because ANTONIO is `On Leave` in Plantilla but retains active ESA, while ALTURAS 752 vs 754 is an import artifact from 2026-10-27 batch `600ddff6` assigning inactive MARIZ employees to ALTURAS ESA); VCAG5_0056 Plan (sanctioned flow steps via `revise_vcode_headcount_quota` and `fn_set_slot_status` for reset to 1 / keep 7 / close with applicant handling, expected ACTISERVE numbers, re-closing Ord 1-2 with `QA_RESET`, and rollback plan); ADR-001 note draft for mobile repo. Plan only — zero DB mutations).
5. **ohm#4x7n2k9w (Phase 5 REVISED — Step 3 + Plantilla-scoped web fix; Step 6 code fix)**: Vacancy Rule 2/Rule 4 + Pool Exclusion, Plantilla Web Slot-Vacant Capacity & Slot Reopen/Sync Hardening (Part 1: applied `20261028005821_fix_vacancy_views_rpcs_rule2_rule4_and_pool_filter.sql` on staging `qqiiznmqxfoamqytjica`, setting `hc_filled`/`hc_display` to active Plantilla per VCode [Rule 2], appending `hr_processing_count`, `is_pool_vacancy`, `affects_required_hc` at end of `vw_vacancy_list` and `vw_vacancy_detail`, enforcing pool exclusion for regular accounts in `list_web_vacancies` and `get_web_vacancy_summary` while keeping Moses HQ unchanged, and replacing only the `hc_filled < hc_total` Open-tab disjunct with explicit Rule 4 `(hc_total - active_plantilla_count - pipeline_count - hr_processing_count) > 0`; Part 2: updated `src/lib/queries/vacancy.ts` to expose `hrProcessingCount` and stop re-deriving `/vacancy` Open tab from `hcFilled < hcTotal`, and updated `getVacancyRemainingCapacity` in `plantilla/page.tsx` to `max(0, hcTotal - hcFilled - hrProcessingCount)` per D2 while confirming `allVacancies` fetches `status: undefined` [Open ∪ Pipeline]; Part 3: applied `20261028005902_fix_slot_status_reopen_clear_closed_and_sync_closed_filter.sql` on staging so `fn_set_slot_status` clears `closed_at`, `closed_by`, `closure_reason_code` on `p_new_status = 'open'` [leaving `qa_archive_batch_id` intact per grep gate] and `fn_sync_vacancy_slot_open_pipeline` enforces `closed_at IS NULL` + deterministic `ORDER BY slot_ordinal, created_at, id`; Part 4: reported `20261210000002` [`OHM2026_1136 §3`] reasoning and `ACT-G5-010` Golden Rule status; local commit on main).

> Older entries trimmed 2026-10-28 (`ohm#4x7n2k9w Phase 5 REVISED`) to keep this list to 5 — see git history for earlier entries in full.
