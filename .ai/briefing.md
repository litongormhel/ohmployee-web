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
1. **ohm#e8m3p0o3 (Bug Fixes & UI Adjustments: HR Emploc Overhaul & Compliance Cleanup)**: Fixed PostgreSQL schema mapping errors: corrected ecosystem uniqueness check in `check_ecosystem_employee_id_unique` to join `auth.users` on `raw_user_meta_data` instead of querying non-existent `users_profile.metadata`; fixed `revert_hr_emploc_to_pending` by removing `deleted_at` reference on `plantilla` (which uses boolean `is_deleted`); applied updated functions to staging database `qqiiznmqxfoamqytjica`; cleaned up onboarding compliance in `TagDeficiencyModal` by removing NBI Clearance and PSA Birth Certificate (leaving SSS, Pag-IBIG, PhilHealth) and enforcing that an individual note or overall remarks is strictly required before submission; updated Deployed tab in `HrEmplocTable` to display Emploc ID beside applicant name, added Hired Date column right before Actions across all queues, and converted Edit Emploc button to an icon-only button; verified with `npm run lint` (0 errors) and `npm run build` clean; local commit on main.
2. **ohm#e8m3p0o2 (Bug Fix: HR Emploc Deployed Tab & Summary Counter Sync)**: Resolved bug where assigning an Employee ID (+ Add Emploc) to SANTOS, JAYSON MENDEZ moved record out of Pending but Deployed tab showed 0 and "No recruits found". Applied updated migration `20261028150500_hr_emploc_overhaul_and_deployment_sync.sql` to staging database `qqiiznmqxfoamqytjica` updating `get_web_hr_emploc_summary` and `list_web_hr_emplocs` to fully match all deployed criteria (`status IN ('Moved to Plantilla', 'Deployed', 'Employee No Assigned', 'Ready for Plantilla') OR hr_status IN ('Transferred', 'Ready', 'Deployed', 'Complete') OR moved_to_plantilla_at IS NOT NULL OR (employee_no IS NOT NULL AND btrim(employee_no) <> '')`) with strict soft-deletion exclusion (`deleted_at IS NULL` and `status <> 'Backout'`); exposed `can_edit_emploc` and `can_revert_to_pending` in `row_capabilities`; updated `AssignEmployeeNoModal` success toast handling in `page.tsx`; verified `SANTOS, JAYSON MENDEZ` (`2026-32656`) returned in `list_web_hr_emplocs(p_queue => 'deployed')` with total count 6; verified `npm run lint` (0 errors) and `npm run build` clean; local commit on main.
3. **ohm#e8m3p0o1 (HR Emploc Module Overhaul, Auto-Plantilla Deployment, Inherited HRCO Mapping & Audit Trail Refactor)**: Complete overhaul of HR Emploc module (`/hr-emploc`): renamed 4th tab to `Deployed` (historical queue for assigned and deployed records, SLA timer frozen with `Completed in X days`); added search filter and CSV/Excel export indexing for `Employee ID`; resolved blank `--` HRCO column via inherited HRCO matrix from User Management based on `Group / Account` scope (single full name, `+N` badge with tooltip, `No HRCO in Group` badge); implemented notification matrix to all assigned HRCOs on correction; row actions in `Pending` tab (`+ Add Emploc` for Super Admin, Data Team, and HR Personnel/OM/HRCO, `! For Correction` hidden from Data Team; auto-locked with `For Deletion` badge if pending deletion request); `+ Add Emploc` modal with global ecosystem-wide uniqueness check (`hr_emploc`, `plantilla`, `users_profile`) and auto-Plantilla sync; `Edit Emploc` modal in `Deployed` tab supporting typo correction and `Revert to Pending` (clears employee ID, unlinks from Plantilla, reconciles vacancy fulfillment, resumes SLA); right drawer redesign enforcing exact 8-section top-to-bottom layout, completely removed Onboarding Requirements checklist, implemented human-readable event-specific Activity History Trail, and scoped Available Actions strictly to Deletion Request / Withdraw workflow for Ops/Super Admin; verified with clean `npm run lint` and `npm run build`; local commit on main.
4. **ohm#u9p2a1c0 (Format Account Names in CAPSLOCK)**: Updated `formatAccountName` in `src/lib/utils/displayText.ts` to format account names strictly in CAPSLOCK (uppercase) per design specification (e.g., `MOSES HQ`, `ACTISERVE`, `FOREVER OFFICE`). Updated Plantilla page breadcrumbs (`MOSES HQ Pool Management`, `{formatAccountName(selectedAccountName)}`) and VacancyFilterToolbar dropdown to render account names in uppercase. Added test suite coverage in `scripts/test_display_text.mjs` (21/21 passing); updated `docs/state/web_design_tokens.md`; verified lint clean; local commit on main.
5. **ohm#4x7n2k9w (Phase 11 — Prove Part C, D4 Reset via Option A, ESA Path Recon, PROD Promotion List, Step 4 Inventory, D6 Plan, D7 Plan)**: Staging Quota Reset & Recon Hardening (Part A: executed Option A simulation + real transaction on staging `qqiiznmqxfoamqytjica`, reopening Ord 2 `79e510b4...` via `fn_set_slot_status` with `HC_READD` and calling `revise_vcode_headcount_quota('VCAG5_0056', 1)`, reducing Ord 3–8 to `hc_reduced` and leaving Ord 2 as the single live open slot with `required_headcount = 1`; ACTISERVE summary & KPI both reconciled to 7/7 [1 active + 3 hrProcess + 3 vacant]; Ord 2 retains `qa_archive_batch_id` and is immune to QA rollback; Part B: proved Phase 10 Part C migration `20261028033431` is a functional no-op; applicant insert bug clobbering `hr_processing` was already resolved Oct 20 in `20262606000047`; cited `fn_set_slot_status` transition matrix lines and resolved `'import_rejected'` action code; Part C: confirmed active ALTURAS ESA rows `c406c477...`/`e496ae21...` created by `approve_plantilla_import_batch` under batch `600ddff6...`, tested `fn_sync_employee_store_allocations` & `fn_recompute_employee_allocation_hc` [both no-ops], proposed one-off audited SQL per environment, cataloged 13 ESA writers and designed canonical occupancy guard; Part D: cataloged all 8 migrations since `20261027091040`, assessed dependencies/trigger impacts/staging assumptions, defined promotion sequence and drafted read-only PROD pre-checks; Part E: itemized 8 frontend defect areas in Step 4 inventory with line citations, compared ACTISERVE before/after, and segregated D6 dependencies; Part F: D6 Plan Only for On-Leave in Plantilla MFR, status counts, RPC proposals, fallback handling, 116-account impact, and regression risks; Part G: D7 Plan Only for hard-blocking inactive/archived employee imports, identified re-hire blocker flow, designed pre-commit & validation guards; local commit on main).

> Older entries trimmed 2026-10-28 (`ohm#4x7n2k9w Phase 5 REVISED`) to keep this list to 5 — see git history for earlier entries in full.
