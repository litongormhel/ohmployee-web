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
1. **ohm#plan06**: Fix Vacancy Slot Disappearance After Candidate Assignment/Import (Plantilla Vacancy All/Open/Pipeline Alignment) (Resolved bug where vacancy slot `VCBPIG1_0183` and assigned slots disappeared with "No vacant slots" while tab counter showed 1 by removing restrictive `status: "open"` from `vacancyListQuery` in `plantilla/page.tsx`, allowing `list_web_vacancies` to return all active slots [both open and in-pipeline]; added `openVacanciesCount` and `pipelineVacanciesCount` live counters on Plantilla sub-filter buttons and KPI cards; updated `VacancyDetailDrawer.onClose` to trigger reactive refetches of `vacancyListQuery` and `summaryQuery`; hardened applicant candidate VCODE lookup in `listVacancies` with case-insensitive whitespace-trimmed keying; extended candidate mutation hooks `useEndorseApplicant`, `useUpdateApplicantPipeline`, `useConfirmApplicantOnboard`, and `useFailBackoutApplicant` in `vacancy.ts` to invalidate `["plantilla"]` cache; ESLint clean, Next.js build 19/19 routes green; local commit on main)
2. **ohm#plan05**: Integration of Separation Statuses (`Resigned`, `AWOL`, `Terminated`) into Employment Status Modal & Attrition Pipeline (Integrated separation options `Resigned`, `AWOL`, `Terminated` into `UpdateEmploymentStatusModal.tsx` organized into Operational Duty Status vs Personnel Separation groups; added mandatory Effective Separation Date picker and ADR-001 slot vacation notice; extended `EmploymentStatusTarget` type and wired `updatePlantillaEmploymentStatus()` to route separation targets to `updatePlantillaSeparation` RPC, triggering reactive slot reopening `fn_sync_slot_to_open()` and archiving to Tab 6 `[ Inactive ]`; added `row.separation_status` and `row.date_of_separation` normalization fallbacks in `normalizeEmployeeListRow`; created migration `20261027150000_allow_terminated_separation_status.sql` updating `plantilla_separation_status_check` to include `'Terminated'` and `'End of Contract'`; ESLint clean, Next.js build 19/19 routes green; local commit on main)
3. **ohm#plan04**: Plantilla SSOT Architecture, Vacancy Tab 9-Column Refactor, HR Emploc Pipeline & Inactive Tab (Implemented strict Single Source of Truth [SSOT] architecture across Plantilla, Vacancy, and HR Emploc; added 6th main tab `[ Inactive ]` for historical attrition tracking [Resigned, AWOL, Terminated] with 8-column layout and reactive slot opening upon separation; refactored `StoreVacancyTable` to strict 1-to-1 slot granularity with 9-column sequence [VCode/CGCode, Store Branch, Area & City, Applicant, Status, Aging, Position, Slot 1 Vacant, Remarks] and deleted the Actions column and Details button; added Vacancy sub-filters [All, Open, HR Pipeline] wired to top KPI cards [Open Vacancies, HR Pipeline]; added editable Effective Vacancy Date [vacantDate] with reactive aging recalculation in `VacancyDetailDrawer`; integrated `Import Plantilla` action in header and verified zero database DDL; ESLint clean, Next.js build 19/19 routes green; local commit on main)
4. **ohm#hremploc02**: Fix SQLSTATE 42P13 in HR Emploc Correction RPC Migration (`get_web_hr_emploc_detail` Return Type & Drop Guard Parity) (Resolved PostgreSQL SQLSTATE 42P13 'cannot change return type of existing function' in `20261027120000_fix_hrco_all_scope_hr_emploc_correction_rpc.sql` by synchronizing `public.get_web_hr_emploc_detail` with the canonical 48-column `RETURNS TABLE` signature and body from `20262606000043` while retaining HRCO All Scope and global visibility bypasses; added `DROP FUNCTION IF EXISTS` statements before all 4 functions in the migration to guarantee clean idempotent execution; staged renamed `20261013000001` migration file resolving duplicate timestamp collision; ESLint clean; local commit on main)
5. **ohm#plan03**: Fix HRCO Scope Bypass Bug in Plantilla Module (Strict Group & Account Scoping) (Resolved scope bypass where HRCO and scoped roles could view all Plantilla groups and accounts; created centralized `fetchPlantillaScopedAccounts` query in `plantilla.ts` enforcing `group_id` and `account_id` boundaries; updated `auth.ts` to only elevate to global scope for users with explicit "All Scope" / "Global HQ" permissions; hardened `plantilla/page.tsx` so `uniqueGroups` and the group dropdown filter only to assigned groups for scoped users, and direct URL access to unauthorized accounts is rejected with `DataState kind="access_denied"`; hardened Workforce Analytics and Plantilla modals; ESLint clean, Next.js build 19/19 routes green; local commit on main)

> Older entries trimmed 2026-10-27 (`ohm#arch03`) to keep this list to 5 — see git history for earlier entries in full.
