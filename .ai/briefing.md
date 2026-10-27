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
1. **ohm#plan09**: Multi-Headcount Vacancy & Plantilla Slot Retention Parity (Resolved bug where multi-headcount allocations e.g. HC = 2 prematurely disappeared from the Open tab when candidates entered pipeline screening; in Flutter mobile `models.dart`, `vacancy_screen.dart`, and `dashboard_screen.dart`, updated `remainingOpenCount` and `_isOpenVacancy` to prevent subtracting `displayPipelineCount` from available open capacity so unfilled quota `hc_needed - hired_count > 0` governs Open membership; in PostgreSQL migration `20261027180000_fix_vacancy_open_pipeline_status_precedence.sql`, recreated `vw_vacancy_list`, `vw_vacancy_detail`, `list_web_vacancies`, and `get_web_vacancy_summary` to restore `hc_filled` to strictly count `confirmed_onboard_count` and prioritize `derived_status = 'Pipeline'` when `active_applicant_count > 0` before falling back to `'Open'`; raised `v_limit` and `MAX_PAGE_SIZE` to 5000 and requested `pageSize: 2000` in `plantilla/page.tsx` with capacity protection `v.hcFilled < v.hcTotal`; ESLint clean, Next.js build 19/19 routes green; local commit on main)
2. **ohm#plan08**: Plantilla Roster Retention, Stage Renaming & Vacancy Sourcing Pipeline Parity (Resolved active employee truncation where 752 records were capped at 100 by increasing `MAX_PAGE_SIZE` to 5000 in `plantilla.ts`, requesting `pageSize: 2000` in `plantilla/page.tsx`, and adding concurrent chunked fetching in `listWebPlantillaEmployees` to load all 752 active personnel; created migration `20261027170000_increase_plantilla_list_limit.sql` raising `v_limit` ceiling to 5000; aligned `isHrPipelineWorkflowStage` to strictly target HR Emploc onboarding stages so ATS candidate sourcing `Vacancy - Pipeline` [e.g. Tejada, Elizabeth on `VCBPIG1_0183`] correctly reflects under `Open / Unassigned` [`1`] and not `HR Pipeline (For Emploc)` [`0`]; synchronized KPI cards to Open Vacancies = 1 and HR Pipeline = 0; renamed table header from `Status` to `Stage`; verified with mechanical loop gate: ESLint clean, Next.js build 19/19 routes green; local commit on main)
3. **ohm#plan07**: Plantilla Vacancy Workflow Stage Mapping & Onboarding Transition Parity (Implemented strict 6-stage vacancy workflow labeling across Plantilla Vacancy: Open/Unassigned [`Vacancy - Open`] and HR Pipeline [`Vacancy - Pipeline`, `HR Emploc - Pending`, `HR Emploc - Correction`, `HR Emploc - Ready`, `HR Emploc - Review`] with semantic badges; synchronized sub-filter counts and KPI card counts to evaluate canonical stages; implemented reactive transition so candidates completing onboarding/moving to Plantilla automatically disappear from Plantilla Vacancy and populate Plantilla Active; cross-referenced active Plantilla occupants in `listVacancies` and `allVacancies`; extended cache invalidations across `useMoveToPlantilla`, `useBulkMoveToPlantilla`, `useApproveEmplocDeletion`, `invalidatePlantillaCaches`, `TagDeficiencyModal`, and `PlantillaImportModal` for `["plantilla"]` and `["vacancy-list"]`; added migration `20261027160000_fix_vacancy_transition_on_move_to_plantilla.sql` for vacancy status closure parity across Open/Pipeline/For Sourcing; ESLint clean, Next.js build 19/19 routes green; local commit on main)
4. **ohm#plan06**: Fix Vacancy Slot Disappearance After Candidate Assignment/Import (Plantilla Vacancy All/Open/Pipeline Alignment) (Resolved bug where vacancy slot `VCBPIG1_0183` and assigned slots disappeared with "No vacant slots" while tab counter showed 1 by removing restrictive `status: "open"` from `vacancyListQuery` in `plantilla/page.tsx`, allowing `list_web_vacancies` to return all active slots [both open and in-pipeline]; added `openVacanciesCount` and `pipelineVacanciesCount` live counters on Plantilla sub-filter buttons and KPI cards; updated `VacancyDetailDrawer.onClose` to trigger reactive refetches of `vacancyListQuery` and `summaryQuery`; hardened applicant candidate VCODE lookup in `listVacancies` with case-insensitive whitespace-trimmed keying; extended candidate mutation hooks `useEndorseApplicant`, `useUpdateApplicantPipeline`, `useConfirmApplicantOnboard`, and `useFailBackoutApplicant` in `vacancy.ts` to invalidate `["plantilla"]` cache; ESLint clean, Next.js build 19/19 routes green; local commit on main)
5. **ohm#plan05**: Integration of Separation Statuses (`Resigned`, `AWOL`, `Terminated`) into Employment Status Modal & Attrition Pipeline (Integrated separation options `Resigned`, `AWOL`, `Terminated` into `UpdateEmploymentStatusModal.tsx` organized into Operational Duty Status vs Personnel Separation groups; added mandatory Effective Separation Date picker and ADR-001 slot vacation notice; extended `EmploymentStatusTarget` type and wired `updatePlantillaEmploymentStatus()` to route separation targets to `updatePlantillaSeparation` RPC, triggering reactive slot reopening `fn_sync_slot_to_open()` and archiving to Tab 6 `[ Inactive ]`; added `row.separation_status` and `row.date_of_separation` normalization fallbacks in `normalizeEmployeeListRow`; created migration `20261027150000_allow_terminated_separation_status.sql` updating `plantilla_separation_status_check` to include `'Terminated'` and `'End of Contract'`; ESLint clean, Next.js build 19/19 routes green; local commit on main)

> Older entries trimmed 2026-10-27 (`ohm#arch03`) to keep this list to 5 — see git history for earlier entries in full.
